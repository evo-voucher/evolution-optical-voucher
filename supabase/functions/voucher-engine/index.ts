import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "Method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1];
    if (!jwt) return json({ success: false, error: "Unauthorized" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !service) return json({ success: false, error: "Server configuration error" }, 500);

    const admin = createClient(url, service, { auth: { persistSession: false } });
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const caller = userData?.user;
    if (userError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: adminRow } = await admin
      .from("admin_users")
      .select("user_id,display_name,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();

    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";

    const audit = async (actionType: string, entityType: string, entityId: string | null, afterData: unknown, metadata: unknown = {}) => {
      await admin.from("admin_audit_log").insert({
        actor_user_id: caller.id,
        actor_name: adminRow.display_name || "Admin",
        action_type: actionType,
        entity_type: entityType,
        entity_id: entityId,
        after_data: afterData,
        metadata,
      });
    };

    if (action === "allocate" || action === "allocate_all") {
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const quantity = Number(body.quantity);
      if (!versionId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid version_id and positive quantity are required" }, 400);
      }

      const { data: version } = await admin
        .from("voucher_versions")
        .select("id,template_id,status")
        .eq("id", versionId)
        .maybeSingle();
      if (!version || version.status !== "active") return json({ success: false, error: "Active Voucher Version not found" }, 404);

      let partnerIds: string[] = [];
      if (action === "allocate_all") {
        const { data: rows, error } = await admin.from("partners").select("id").eq("status", "active");
        if (error) return json({ success: false, error: "Unable to load active Partners", details: error.message }, 500);
        partnerIds = (rows || []).map((r: { id: string }) => r.id);
      } else {
        const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
        if (!partnerId) return json({ success: false, error: "partner_id is required" }, 400);
        const { data: partner } = await admin.from("partners").select("id,status").eq("id", partnerId).maybeSingle();
        if (!partner || partner.status !== "active") return json({ success: false, error: "Active Partner not found" }, 404);
        partnerIds = [partnerId];
      }

      let allocatedCount = 0;
      for (const partnerId of partnerIds) {
        const { data: current } = await admin
          .from("partner_voucher_allocations")
          .select("id,quantity_allocated,quantity_revoked,status")
          .eq("partner_id", partnerId)
          .eq("version_id", versionId)
          .eq("status", "active")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        let allocationId: string;
        if (current) {
          const nextQty = Number(current.quantity_allocated || 0) + quantity;
          const { data: updated, error } = await admin
            .from("partner_voucher_allocations")
            .update({ quantity_allocated: nextQty, updated_at: new Date().toISOString() })
            .eq("id", current.id)
            .select("id")
            .single();
          if (error || !updated) return json({ success: false, error: "Failed to increase allocation", details: error?.message }, 500);
          allocationId = updated.id;
        } else {
          const { data: created, error } = await admin
            .from("partner_voucher_allocations")
            .insert({
              partner_id: partnerId,
              version_id: versionId,
              quantity_allocated: quantity,
              quantity_revoked: 0,
              status: "active",
              created_by: caller.id,
            })
            .select("id")
            .single();
          if (error || !created) return json({ success: false, error: "Failed to create allocation", details: error?.message }, 500);
          allocationId = created.id;
        }

        await admin.from("partner_voucher_access").upsert({
          partner_id: partnerId,
          template_id: version.template_id,
          status: "active",
          quota_type: "allocation",
          created_by: caller.id,
          updated_at: new Date().toISOString(),
        }, { onConflict: "partner_id,template_id" });

        await admin.from("voucher_allocation_events").insert({
          allocation_id: allocationId,
          partner_id: partnerId,
          version_id: versionId,
          event_type: current ? "increased" : "allocated",
          quantity,
          actor_user_id: caller.id,
        });
        allocatedCount++;
      }

      await audit("voucher_allocation_changed", "voucher_version", versionId, { partners_allocated: allocatedCount, quantity_each: quantity, mode: action });
      return json({ success: true, result: { partners_allocated: allocatedCount, quantity_each: quantity } });
    }

    if (action === "revoke_unissued") {
      const allocationId = typeof body.allocation_id === "string" ? body.allocation_id.trim() : "";
      const quantity = Number(body.quantity);
      const reason = typeof body.reason === "string" ? body.reason.trim() : null;
      if (!allocationId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid allocation_id and positive quantity are required" }, 400);
      }

      const { data: allocation } = await admin
        .from("partner_voucher_allocations")
        .select("id,partner_id,version_id,quantity_allocated,quantity_revoked,status")
        .eq("id", allocationId)
        .maybeSingle();
      if (!allocation || allocation.status !== "active") return json({ success: false, error: "Active allocation not found" }, 404);

      const { count: issuedCount, error: countError } = await admin
        .from("vouchers")
        .select("id", { count: "exact", head: true })
        .eq("allocation_id", allocationId);
      if (countError) return json({ success: false, error: "Unable to count issued vouchers", details: countError.message }, 500);

      const issued = issuedCount ?? 0;
      const remainingUnissued = Number(allocation.quantity_allocated) - Number(allocation.quantity_revoked) - issued;
      if (quantity > remainingUnissued) {
        return json({ success: false, error: "Cannot revoke more than remaining unissued quantity", remaining_unissued: remainingUnissued }, 409);
      }

      const nextRevoked = Number(allocation.quantity_revoked) + quantity;
      const { error: updateError } = await admin
        .from("partner_voucher_allocations")
        .update({ quantity_revoked: nextRevoked, updated_at: new Date().toISOString() })
        .eq("id", allocationId);
      if (updateError) return json({ success: false, error: "Failed to revoke allocation", details: updateError.message }, 500);

      await admin.from("voucher_allocation_events").insert({
        allocation_id: allocationId,
        partner_id: allocation.partner_id,
        version_id: allocation.version_id,
        event_type: "revoked",
        quantity,
        reason,
        actor_user_id: caller.id,
      });

      const left = remainingUnissued - quantity;
      await audit("voucher_allocation_revoked", "voucher_allocation", allocationId, { quantity, remaining_unissued: left }, { reason });
      return json({ success: true, result: { revoked_unissued: quantity, remaining_unissued: left } });
    }

    if (action === "retire_version") {
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const reason = typeof body.reason === "string" ? body.reason.trim() : null;
      if (!versionId) return json({ success: false, error: "version_id is required" }, 400);

      const { data: version } = await admin.from("voucher_versions").select("id,status").eq("id", versionId).maybeSingle();
      if (!version) return json({ success: false, error: "Voucher Version not found" }, 404);
      if (version.status !== "active") return json({ success: false, error: "Only active Voucher Versions can be retired" }, 409);

      const { error } = await admin.from("voucher_versions").update({ status: "inactive" }).eq("id", versionId);
      if (error) return json({ success: false, error: "Failed to retire Voucher Version", details: error.message }, 500);

      await admin.from("partner_voucher_allocations").update({ status: "closed", updated_at: new Date().toISOString() }).eq("version_id", versionId).eq("status", "active");
      await audit("voucher_version_retired", "voucher_version", versionId, { status: "inactive" }, { reason });
      return json({ success: true, result: { version_id: versionId, status: "inactive" } });
    }

    return json({ success: false, error: "Unsupported action" }, 400);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
