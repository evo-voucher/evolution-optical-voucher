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

    const server = createClient(url, service, { auth: { persistSession: false } });
    const { data: userData, error: userError } = await server.auth.getUser(jwt);
    const caller = userData?.user;
    if (userError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: adminRow, error: adminError } = await server
      .from("partner_users")
      .select("user_id")
      .eq("user_id", caller.id)
      .eq("role", "admin")
      .eq("status", "active")
      .is("removed_at", null)
      .maybeSingle();
    if (adminError) return json({ success: false, error: "Admin authorization check failed" }, 500);
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const partner_code = typeof body.partner_code === "string" ? body.partner_code.trim().toUpperCase() : "";
    const partner_name = typeof body.partner_name === "string" ? body.partner_name.trim() : "";
    const contact_person = typeof body.contact_person === "string" ? body.contact_person.trim() : null;
    const contact_phone = typeof body.contact_phone === "string" ? body.contact_phone.trim() : null;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const voucher_limit = Number(body.voucher_limit ?? 0);
    const staff_limit = Number(body.staff_limit ?? 0);

    if (!partner_code || !partner_name || !email || !password) return json({ success: false, error: "Missing required fields" }, 400);
    if (!/^[A-Z0-9_-]+$/.test(partner_code)) return json({ success: false, error: "Invalid partner code" }, 400);
    if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
    if (password.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);
    if (!Number.isInteger(voucher_limit) || voucher_limit < 0 || !Number.isInteger(staff_limit) || staff_limit < 0) {
      return json({ success: false, error: "Invalid limits" }, 400);
    }

    const { data: created, error: createError } = await server.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    const newUser = created?.user;
    if (createError || !newUser) {
      return json({ success: false, error: "Failed to create Partner login", details: createError?.message }, 400);
    }

    const { data: provisioned, error: provisionError } = await server.rpc("service_provision_partner", {
      p_actor_user_id: caller.id,
      p_new_user_id: newUser.id,
      p_partner_code: partner_code,
      p_partner_name: partner_name,
      p_contact_person: contact_person,
      p_contact_phone: contact_phone,
      p_voucher_limit: voucher_limit,
      p_staff_limit: staff_limit,
      p_login_email: email,
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
      const message = provisionError?.message || provisioned?.error || "Partner provisioning failed";
      const status = /already exists|duplicate|unique/i.test(message) ? 409 : /Admin access/i.test(message) ? 403 : 500;
      return json({ success: false, error: "Failed to provision Partner", details: message }, status);
    }

    return json({ success: true, partner: provisioned.partner, user_id: newUser.id }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
