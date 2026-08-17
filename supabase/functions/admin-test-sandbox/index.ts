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

  const createdUsers: string[] = [];
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

    // The platform gateway already enforces verify_jwt=true. Authorize the caller
    // through Postgres auth.uid() + the canonical operational realm instead of
    // auth.getUser(jwt), which incorrectly depends on a live Auth session row.
    const { data: realm, error: realmError } = await callerClient.rpc("current_operational_realm");
    const callerId = typeof realm?.user_id === "string" ? realm.user_id : "";
    if (realmError || realm?.authenticated !== true || realm.realm !== "admin" || !callerId) {
      return json({ success: false, error: "Active Admin access required" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = typeof body?.action === "string" ? body.action.trim().toLowerCase() : "status";

    if (action === "status") {
      const { data, error } = await callerClient.rpc("admin_test_sandbox_status");
      if (error) return json({ success: false, error: "Unable to read Test Sandbox status", details: error.message }, 500);
      return json({ success: true, sandbox: data });
    }

    if (action === "reset") {
      const { data, error } = await callerClient.rpc("admin_reset_test_sandbox");
      if (error) return json({ success: false, error: "Test Sandbox reset failed", details: error.message }, 409);
      return json({ success: true, reset: data });
    }

    if (action !== "setup") return json({ success: false, error: "Unsupported action" }, 400);

    const password = typeof body?.password === "string" ? body.password : "";
    if (password.length < 8) return json({ success: false, error: "Test password must be at least 8 characters" }, 400);

    const { data: statusData, error: statusError } = await callerClient.rpc("admin_test_sandbox_status");
    if (statusError) return json({ success: false, error: "Unable to read Test Sandbox status", details: statusError.message }, 500);
    if (statusData?.configured === true) return json({ success: false, error: "Test Sandbox is already initialized" }, 409);

    const partnerEmail = "test.partner@evolution-optical.test";
    const partnerStaffEmail = "test.partner.staff@evolution-optical.test";
    const evolutionStaffEmail = "test.evolution.staff@evolution-optical.test";

    async function createUser(email: string) {
      const { data, error } = await server.auth.admin.createUser({ email, password, email_confirm: true });
      if (error || !data?.user) throw new Error(`Unable to create ${email}: ${error?.message || "unknown error"}`);
      createdUsers.push(data.user.id);
      return data.user;
    }

    const partnerUser = await createUser(partnerEmail);
    const partnerStaffUser = await createUser(partnerStaffEmail);
    const evolutionStaffUser = await createUser(evolutionStaffEmail);

    const { data: initialized, error: initError } = await server.rpc("service_initialize_test_sandbox", {
      p_partner_admin_user_id: partnerUser.id,
      p_partner_admin_email: partnerEmail,
      p_partner_staff_user_id: partnerStaffUser.id,
      p_partner_staff_email: partnerStaffEmail,
      p_evolution_staff_user_id: evolutionStaffUser.id,
      p_evolution_staff_email: evolutionStaffEmail,
      p_actor_user_id: callerId,
      p_template_code: "UAT_RM60",
      p_branch_code: "MINES",
    });

    if (initError || !initialized?.success) {
      throw new Error(initError?.message || "Atomic Test Sandbox initialization failed");
    }

    return json({
      success: true,
      sandbox: {
        partner_id: initialized.partner_id,
        partner_email: partnerEmail,
        partner_staff_email: partnerStaffEmail,
        evolution_staff_email: evolutionStaffEmail,
        branch_code: initialized.branch_code,
        template_code: initialized.template_code,
        version_id: initialized.version_id,
        baseline_quantity: initialized.baseline_quantity,
      },
      message: "Test Sandbox initialized. The test password is not stored in the Sandbox registry.",
    }, 201);
  } catch (e) {
    try {
      const url = Deno.env.get("SUPABASE_URL");
      const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (url && service && createdUsers.length) {
        const server = createClient(url, service, { auth: { persistSession: false } });
        for (const id of createdUsers.reverse()) {
          try { await server.auth.admin.deleteUser(id); } catch (_) {}
        }
      }
    } catch (_) {}
    return json({ success: false, error: "Test Sandbox setup failed", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});