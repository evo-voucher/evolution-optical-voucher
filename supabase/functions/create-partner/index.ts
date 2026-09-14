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

function createTemporaryPassword() {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);
  const token = Array.from(bytes, b => b.toString(36).padStart(2, "0")).join("").slice(0, 20);
  return `Ev!${token}9`;
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
    if (realmError) return json({ success: false, error: "Admin authorization check failed", details: realmError.message }, 500);
    if (realm?.realm !== "admin") return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    let partner_code = typeof body.partner_code === "string" && body.partner_code.trim()
      ? body.partner_code.trim().toUpperCase()
      : "AUTO";
    const partner_name = typeof body.partner_name === "string" ? body.partner_name.trim() : "";
    const contact_person = typeof body.contact_person === "string" ? body.contact_person.trim() : null;
    const contact_phone = typeof body.contact_phone === "string" ? body.contact_phone.trim() : null;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const staff_limit = Number(body.staff_limit ?? 0);
    const suppliedPassword = typeof body.initial_password === "string" ? body.initial_password.trim() : "";

    if (!partner_name || !email) return json({ success: false, error: "Missing required fields" }, 400);
    if (partner_code !== "AUTO" && !/^[A-Z0-9_-]+$/.test(partner_code)) return json({ success: false, error: "Invalid partner code" }, 400);
    if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
    if (!Number.isInteger(staff_limit) || staff_limit < 0 || staff_limit > 1000) return json({ success: false, error: "Invalid Staff Limit" }, 400);
    if (suppliedPassword && suppliedPassword.length < 8) return json({ success: false, error: "Initial Password must be at least 8 characters" }, 400);

    if (partner_code === "AUTO") {
      const { data: generatedCode, error: codeError } = await callerClient.rpc("admin_next_partner_code", { p_partner_name: partner_name });
      if (codeError || typeof generatedCode !== "string" || !/^[A-Z][0-9]{3}$/.test(generatedCode)) {
        return json({ success: false, error: "Unable to generate Partner Code", details: codeError?.message }, 500);
      }
      partner_code = generatedCode;
    }

    const temporaryPassword = suppliedPassword || createTemporaryPassword();
    const { data: createdUserData, error: createUserError } = await server.auth.admin.createUser({
      email,
      password: temporaryPassword,
      email_confirm: true,
    });
    const newUser = createdUserData?.user;
    if (createUserError || !newUser) {
      return json({ success: false, error: "Failed to create Partner login", details: createUserError?.message }, 400);
    }

    const { data: provisioned, error: provisionError } = await server.rpc("admin_provision_partner_without_allocation", {
      p_partner_code: partner_code,
      p_partner_name: partner_name,
      p_contact_person: contact_person,
      p_contact_phone: contact_phone,
      p_staff_limit: staff_limit,
      p_new_user_id: newUser.id,
      p_login_email: email,
      p_actor_user_id: caller.id,
      p_all_branches: true,
      p_branch_codes: [],
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
      const message = provisionError?.message || provisioned?.error || "Partner provisioning failed";
      const status = /duplicate|unique|already exists/i.test(message) ? 409 : 500;
      return json({ success: false, error: "Failed to provision Partner", details: message }, status);
    }

    return json({
      success: true,
      partner: provisioned.partner,
      user_id: newUser.id,
      temporary_password: temporaryPassword,
      claim_all_branches: provisioned.claim_all_branches,
      claim_branch_codes: provisioned.claim_branch_codes,
      allocation_required: false,
    }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
