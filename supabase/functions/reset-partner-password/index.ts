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

    const { data: callerData, error: callerError } = await callerClient.auth.getUser(jwt);
    const caller = callerData?.user;
    if (callerError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: adminRow, error: adminError } = await callerClient
      .from("admin_users")
      .select("user_id,display_name,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();
    if (adminError) return json({ success: false, error: "Admin authorization check failed" }, 500);
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
    const newPassword = typeof body.new_password === "string" ? body.new_password : "";
    if (!partnerId) return json({ success: false, error: "partner_id is required" }, 400);
    if (newPassword.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);

    const { data: partner, error: partnerError } = await callerClient
      .from("partners")
      .select("id,partner_code,partner_name,status")
      .eq("id", partnerId)
      .maybeSingle();
    if (partnerError || !partner) return json({ success: false, error: "Partner not found" }, 404);

    const { data: partnerAdmin, error: partnerAdminError } = await callerClient
      .from("partner_users")
      .select("id,user_id,staff_name,login_email,status,removed_at")
      .eq("partner_id", partner.id)
      .eq("role", "partner_admin")
      .is("removed_at", null)
      .maybeSingle();
    if (partnerAdminError || !partnerAdmin) return json({ success: false, error: "Partner Admin account not found" }, 404);

    const { data: updated, error: updateError } = await server.auth.admin.updateUserById(
      partnerAdmin.user_id,
      { password: newPassword },
    );
    if (updateError || !updated?.user) {
      return json({ success: false, error: "Unable to reset Partner password", details: updateError?.message }, 500);
    }

    try { await server.auth.admin.signOut(partnerAdmin.user_id, "global"); } catch (_) {}

    const { data: auditResult, error: auditError } = await callerClient.rpc("admin_record_partner_password_reset", {
      p_partner_id: partner.id,
    });
    if (auditError || !auditResult?.success) {
      return json({
        success: false,
        error: "Password changed but audit recording failed",
        details: auditError?.message || auditResult?.error,
      }, 500);
    }

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
