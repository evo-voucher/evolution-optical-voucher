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

    const { data: existingPartner } = await admin.from("partners").select("id").eq("partner_code", partner_code).maybeSingle();
    if (existingPartner) return json({ success: false, error: "Partner code already exists" }, 409);

    const { data: createdUserData, error: createUserError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    const newUser = createdUserData?.user;
    if (createUserError || !newUser) return json({ success: false, error: "Failed to create Partner login", details: createUserError?.message }, 400);

    const { data: partner, error: partnerError } = await admin
      .from("partners")
      .insert({
        partner_code,
        partner_name,
        contact_person,
        contact_phone,
        voucher_limit,
        vouchers_issued: 0,
        staff_limit,
        staff_access_enabled: false,
        status: "active",
      })
      .select()
      .single();

    if (partnerError || !partner) {
      try { await admin.auth.admin.deleteUser(newUser.id); } catch (_) {}
      return json({ success: false, error: "Failed to create Partner", details: partnerError?.message }, 500);
    }

    const { error: linkError } = await admin.from("partner_users").insert({
      user_id: newUser.id,
      partner_id: partner.id,
      role: "partner_admin",
      status: "active",
      staff_name: contact_person || partner_name,
      login_email: email,
    });

    if (linkError) {
      try { await admin.from("partners").delete().eq("id", partner.id); } catch (_) {}
      try { await admin.auth.admin.deleteUser(newUser.id); } catch (_) {}
      return json({ success: false, error: "Failed to link Partner Admin", details: linkError.message }, 500);
    }

    await admin.from("partner_claim_settings").insert({ partner_id: partner.id, all_branches: false, updated_by: caller.id });
    await admin.from("admin_audit_log").insert({
      actor_user_id: caller.id,
      actor_name: adminRow.display_name || "Admin",
      action_type: "partner_created",
      entity_type: "partner",
      entity_id: partner.id,
      partner_id: partner.id,
      after_data: { partner_code, partner_name, voucher_limit, staff_limit, status: "active" },
      metadata: { login_email: email, secret_material_logged: false },
    });

    return json({ success: true, partner, user_id: newUser.id }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
