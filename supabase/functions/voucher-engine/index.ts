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
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anon || !service) return json({ success: false, error: "Server configuration error" }, 500);

    const callerClient = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false },
    });
    const server = createClient(url, service, { auth: { persistSession: false } });

    const { data: userData, error: userError } = await callerClient.auth.getUser(jwt);
    const caller = userData?.user;
    if (userError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: realm, error: realmError } = await callerClient.rpc("current_operational_realm");
    if (realmError) return json({ success: false, error: "Admin authorization check failed" }, 500);
    if (!realm || realm.authenticated !== true || realm.realm !== "admin") {
      return json({ success: false, error: "Admin access required" }, 403);
    }

    const body = await req.json();
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";

    if (action === "allocate") {
      const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
      const versionId = typeof body.version_id === "string" ? body.version_id.trim() : "";
      const quantity = Number(body.quantity);
      const allBranches = body.all_branches !== false;
      const branchCodes = Array.isArray(body.branch_codes)
        ? body.branch_codes.filter((x: unknown) => typeof x === "string").map((x: string) => x.trim().toUpperCase()).filter(Boolean)
        : [];
      const validityAnchor = typeof body.validity_anchor === "string" ? body.validity_anchor.trim().toLowerCase() : "issue";
      const allocationValidDays = body.allocation_valid_days == null ? null : Number(body.allocation_valid_days);

      if (!partnerId || !versionId || !Number.isInteger(quantity) || quantity <= 0) {
        return json({ success: false, error: "Valid partner_id, version_id and positive quantity are required" }, 400);
      }
      if (!allBranches && branchCodes.length === 0) {
        return json({ success: false, error: "Select at least one Allocation branch" }, 400);
      }
      if (validityAnchor === "allocation" && (!Number.isInteger(allocationValidDays) || Number(allocationValidDays) < 1)) {
        return json({ success: false, error: "Allocation validity days must be at least 1" }, 400);
      }

      const { data, error } = await server.rpc("admin_engine_allocate_v3", {
        p_partner_id: partnerId,
        p_version_id: versionId,
        p_quantity: quantity,
        p_validity_anchor: validityAnchor,
        p_allocation_valid_days: allocationValidDays,
        p_all_branches: allBranches,
        p_branch_codes: allBranches ? [] : branchCodes,
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
      const { data, error } = await server.rpc("admin_engine_allocate_all", {
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
      const { data, error } = await server.rpc("admin_engine_revoke_unissued", {
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
      const { data, error } = await server.rpc("admin_engine_retire_version", {
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
