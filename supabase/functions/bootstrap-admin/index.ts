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

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ success: false, error: "Server configuration error" }, 500);

  const server = createClient(url, service, { auth: { persistSession: false } });

  try {
    const { data: status, error: statusError } = await server.rpc("admin_bootstrap_status");
    if (statusError) return json({ success: false, error: "Unable to verify setup state" }, 500);
    if (!status?.bootstrap_available) {
      return json({ success: false, error: "First Admin setup is not available" }, 409);
    }

    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const setupCode = typeof body.setup_code === "string" ? body.setup_code : "";

    if (!email || !email.includes("@")) return json({ success: false, error: "Valid email is required" }, 400);
    if (password.length < 8) return json({ success: false, error: "Password must be at least 8 characters" }, 400);
    if (setupCode.length < 24) return json({ success: false, error: "Valid Setup Code is required" }, 400);

    const { data: validCode, error: codeError } = await server.rpc("service_validate_admin_bootstrap_code", {
      p_setup_code: setupCode,
    });
    if (codeError || validCode !== true) {
      return json({ success: false, error: "Invalid Setup Code" }, 403);
    }

    const { data: created, error: createError } = await server.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    const user = created?.user;
    if (createError || !user) {
      return json({ success: false, error: "Unable to create Admin login", details: createError?.message }, 400);
    }

    const { data: provisioned, error: provisionError } = await server.rpc("service_bootstrap_first_admin", {
      p_user_id: user.id,
      p_display_name: "Evolution Optical Admin",
      p_setup_code: setupCode,
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(user.id); } catch (_) {}
      const message = provisionError?.message || provisioned?.error || "Admin bootstrap failed";
      const statusCode = /already complete|not enabled/i.test(message) ? 409 : /setup code/i.test(message) ? 403 : 500;
      return json({ success: false, error: message }, statusCode);
    }

    return json({ success: true, realm: "admin", email }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected setup error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
