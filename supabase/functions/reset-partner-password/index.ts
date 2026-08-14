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
    const { data: callerData, error: callerError } = await admin.auth.getUser(jwt);
    const caller = callerData?.user;
    if (callerError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: adminRow } = await admin
      .from("admin_users")
      .select("user_id,display_name,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
    const newPassword = typeof body.new_password === "string" ? body.new_password : "";
    if (!partnerId) return json({ success: false, error: "partner_id is required" }, 400);
    if (newPassword.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);

    const { data: partner } = await admin
      .from("partners")
      .select("id,partner_code,partner_name,status")
      .eq("id", partnerId)
      .maybeSingle();
    if (!partner) return json({ success: false, error: "Partner not found" }, 404);

    const { data: partnerAdmin } = await admin
      .from("partner_users")
      .select("id,user_id,staff_name,login_email,status,removed_at")
      .eq("partner_id", partner.id)
      .eq("role", "partner_admin")
      .is("removed_at", null)
      .maybeSingle();
    if (!partnerAdmin) return json({ success: false, error: "Partner Admin account not found" }, 404);

    const { data: updated, error: updateError } = await admin.auth.admin.updateUserById(
      partnerAdmin.user_id,
      { password: newPassword },
    );
    if (updateError || !updated?.user) {
      return json({ success: false, error: "Unable to reset Partner password", details: updateError?.message }, 500);
    }

    try { await admin.auth.admin.signOut(partnerAdmin.user_id, "global"); } catch (_) {}

    await admin.from("admin_audit_log").insert({
      actor_user_id: caller.id,
      actor_name: adminRow.display_name || "Admin",
      action_type: "partner_password_reset",
      entity_type: "partner_user",
      entity_id: partnerAdmin.id,
      partner_id: partner.id,
      after_data: { partner_code: partner.partner_code, login_email: partnerAdmin.login_email },
      metadata: { secret_material_logged: false, sessions_signed_out: true },
    });

    return json({
      success: true,
      partner_id: partner.id,
      partner_name: partner.partner_name,
      message: "Partner password reset successfully. Existing sessions were signed out.",
    });
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
