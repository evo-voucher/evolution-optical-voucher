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
      .select("user_id,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";

    if (action === "allocate") {
      const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const quantity = Number(body.quantity);
      if (!partnerId || !versionId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid partner_id, version_id and positive quantity are required" }, 400);
      }
      const { data, error } = await admin.rpc("admin_engine_allocate", {
        p_partner_id: partnerId,
        p_version_id: versionId,
        p_quantity: quantity,
        p_actor_user_id: caller.id,
      });
      if (error) return json({ success: false, error: error.message }, 409);
      return json({ success: true, result: data });
    }

    if (action === "allocate_all") {
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const quantity = Number(body.quantity);
      if (!versionId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid version_id and positive quantity are required" }, 400);
      }
      const { data, error } = await admin.rpc("admin_engine_allocate_all", {
        p_version_id: versionId,
        p_quantity: quantity,
        p_actor_user_id: caller.id,
      });
      if (error) return json({ success: false, error: error.message }, 409);
      return json({ success: true, result: data });
    }

    if (action === "revoke_unissued") {
      const allocationId = typeof body.allocation_id === "string" ? body.allocation_id.trim() : "";
      const quantity = Number(body.quantity);
      const reason = typeof body.reason === "string" ? body.reason.trim() : null;
      if (!allocationId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid allocation_id and positive quantity are required" }, 400);
      }
      const { data, error } = await admin.rpc("admin_engine_revoke_unissued", {
        p_allocation_id: allocationId,
        p_quantity: quantity,
        p_reason: reason,
        p_actor_user_id: caller.id,
      });
      if (error) return json({ success: false, error: error.message }, 409);
      return json({ success: true, result: data });
    }

    if (action === "retire_version") {
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const reason = typeof body.reason === "string" ? body.reason.trim() : null;
      if (!versionId) return json({ success: false, error: "version_id is required" }, 400);
      const { data, error } = await admin.rpc("admin_engine_retire_version", {
        p_version_id: versionId,
        p_reason: reason,
        p_actor_user_id: caller.id,
      });
      if (error) return json({ success: false, error: error.message }, 409);
      return json({ success: true, result: data });
    }

    return json({ success: false, error: "Unsupported action" }, 400);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
