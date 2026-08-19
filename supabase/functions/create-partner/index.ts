import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PARTNER_INITIAL_PASSWORD = "EVO12345678";

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

    const { data: adminRow, error: adminLookupError } = await callerClient
      .from("admin_users")
      .select("user_id,display_name,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();
    if (adminLookupError) return json({ success: false, error: "Admin authorization check failed" }, 500);
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const partner_code = typeof body.partner_code === "string" ? body.partner_code.trim().toUpperCase() : "";
    const partner_name = typeof body.partner_name === "string" ? body.partner_name.trim() : "";
    const contact_person = typeof body.contact_person === "string" ? body.contact_person.trim() : null;
    const contact_phone = typeof body.contact_phone === "string" ? body.contact_phone.trim() : null;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const staff_limit = Number(body.staff_limit ?? 0);
    const rawAllocations = Array.isArray(body.allocations)
      ? body.allocations
      : (body.version_id ? [{ version_id: body.version_id, quantity: body.quantity }] : []);
    const requestedAllocations = rawAllocations.map((item: any) => ({
      version_id: typeof item?.version_id === "string" ? item.version_id.trim() : "",
      quantity: Number(item?.quantity ?? 0),
    }));

    if (!partner_code || !partner_name || !email) return json({ success: false, error: "Missing required fields" }, 400);
    if (!/^[A-Z0-9_-]+$/.test(partner_code)) return json({ success: false, error: "Invalid partner code" }, 400);
    if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
    if (!Number.isInteger(staff_limit) || staff_limit < 0 || staff_limit > 1000) return json({ success: false, error: "Invalid Staff Limit" }, 400);
    if (!requestedAllocations.length) return json({ success: false, error: "Select at least one Initial Voucher" }, 400);
    if (requestedAllocations.some((x: any) => !x.version_id || !Number.isInteger(x.quantity) || x.quantity < 1)) return json({ success: false, error: "Each Initial Voucher needs a valid whole-number quantity of at least 1" }, 400);
    if (new Set(requestedAllocations.map((x: any) => x.version_id)).size !== requestedAllocations.length) return json({ success: false, error: "Duplicate Initial Voucher selected" }, 400);

    // Read Voucher defaults through the existing admin SECURITY DEFINER RPC instead of
    // querying voucher_versions directly. Production hardening intentionally denies
    // direct table access, while the RPC is the canonical authorized read path.
    const { data: activeVersions, error: versionError } = await callerClient.rpc("admin_active_voucher_versions");
    if (versionError) return json({ success: false, error: "Unable to load Voucher validity", details: versionError.message }, 500);
    const versionIds = requestedAllocations.map((x: any) => x.version_id);
    const versionRows = (Array.isArray(activeVersions) ? activeVersions : []).filter((v: any) => versionIds.includes(v.version_id));
    if (versionRows.length !== versionIds.length) return json({ success: false, error: "One or more selected Voucher Versions are unavailable" }, 400);

    const byId = new Map(versionRows.map((v: any) => [v.version_id, v]));
    const allocations = requestedAllocations.map((item: any) => {
      const v: any = byId.get(item.version_id);
      const mode = String(v?.validity_mode || "").toLowerCase();
      const months = Number(v?.valid_months ?? 0);
      const days = Number(v?.valid_days ?? 0);
      if ((mode === "calendar_months_after_issue" || mode === "months") && Number.isInteger(months) && months > 0) {
        return { ...item, validity_anchor: "issue", validity_value: months, validity_unit: "months" };
      }
      if ((mode === "days_after_issue" || mode === "days") && Number.isInteger(days) && days > 0) {
        return { ...item, validity_anchor: "issue", validity_value: days, validity_unit: "days" };
      }
      return { ...item, validity_anchor: "", validity_value: 0, validity_unit: "" };
    });
    if (allocations.some((x: any) => !x.validity_anchor || !Number.isInteger(x.validity_value) || x.validity_value < 1 || !x.validity_unit)) {
      return json({ success: false, error: "Selected Voucher Version has no supported default validity rule" }, 400);
    }

    const temporaryPassword = PARTNER_INITIAL_PASSWORD;
    const { data: createdUserData, error: createUserError } = await server.auth.admin.createUser({ email, password: temporaryPassword, email_confirm: true });
    const newUser = createdUserData?.user;
    if (createUserError || !newUser) return json({ success: false, error: "Failed to create Partner login", details: createUserError?.message }, 400);

    const { data: provisioned, error: provisionError } = await server.rpc("admin_provision_partner_with_initial_allocations", {
      p_partner_code: partner_code,
      p_partner_name: partner_name,
      p_contact_person: contact_person,
      p_contact_phone: contact_phone,
      p_staff_limit: staff_limit,
      p_new_user_id: newUser.id,
      p_login_email: email,
      p_actor_user_id: caller.id,
      p_allocations: allocations,
      p_all_branches: true,
      p_branch_codes: [],
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
      const message = provisionError?.message || provisioned?.error || "Partner provisioning failed";
      const status = /duplicate|unique|already exists/i.test(message) ? 409 : 500;
      return json({ success: false, error: "Failed to provision Partner", details: message }, status);
    }

    return json({ success: true, partner: provisioned.partner, user_id: newUser.id, temporary_password: temporaryPassword, initial_allocations: provisioned.initial_allocations, claim_all_branches: provisioned.claim_all_branches, claim_branch_codes: provisioned.claim_branch_codes }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
