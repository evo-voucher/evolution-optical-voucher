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

    const body = await req.json();
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";
    const requestedPartnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";

    const { data: realm, error: realmError } = await callerClient.rpc("current_operational_realm");
    if (realmError || !realm?.authenticated) return json({ success: false, error: "Authorization check failed" }, 403);

    let partnerId = "";
    if (realm.realm === "partner" && realm.role === "partner_admin") {
      partnerId = typeof realm.partner_id === "string" ? realm.partner_id : "";
      if (!partnerId) return json({ success: false, error: "Partner context unavailable" }, 403);
      if (requestedPartnerId && requestedPartnerId !== partnerId) {
        return json({ success: false, error: "Partner context access denied" }, 403);
      }
    } else if (realm.realm === "admin") {
      if (!requestedPartnerId) return json({ success: false, error: "Admin must select a Partner" }, 400);
      partnerId = requestedPartnerId;
    } else {
      return json({ success: false, error: "Partner Admin or Admin access required" }, 403);
    }

    const { data: partner, error: partnerError } = await server
      .from("partners")
      .select("id,partner_code,partner_name,status,staff_limit,staff_access_enabled")
      .eq("id", partnerId)
      .maybeSingle();
    if (partnerError || !partner || partner.status !== "active") {
      return json({ success: false, error: "Partner is not active" }, 403);
    }

    if (action === "create") {
      const staff_name = typeof body.staff_name === "string" ? body.staff_name.trim() : "";
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const password = typeof body.password === "string" ? body.password : "";
      if (!staff_name || !email || !password) return json({ success: false, error: "Missing required fields" }, 400);
      if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
      if (password.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);

      const { data: newUserData, error: createUserError } = await server.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      const newUser = newUserData?.user;
      if (createUserError || !newUser) {
        return json({ success: false, error: "Failed to create Staff login", details: createUserError?.message }, 400);
      }

      const { data: provisioned, error: provisionError } = await server.rpc("partner_provision_staff", {
        p_new_user_id: newUser.id,
        p_staff_name: staff_name,
        p_login_email: email,
        p_actor_user_id: caller.id,
        p_partner_id: partnerId,
      });
      if (provisionError || !provisioned?.success) {
        try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
        const message = provisionError?.message || provisioned?.error || "Partner Staff provisioning failed";
        const status = /limit reached/i.test(message) ? 409 : 500;
        return json({ success: false, error: "Failed to create Partner Staff profile", details: message }, status);
      }
      return json({ success: true, staff: provisioned.staff, actor_realm: provisioned.actor_realm }, 201);
    }

    const staffId = typeof body.staff_id === "string" ? body.staff_id.trim() : "";
    if (!staffId) return json({ success: false, error: "staff_id is required" }, 400);

    const { data: target, error: targetError } = await server
      .from("partner_users")
      .select("id,user_id,partner_id,role,status,staff_name,login_email,removed_at")
      .eq("id", staffId)
      .eq("partner_id", partner.id)
      .eq("role", "partner_staff")
      .maybeSingle();
    if (targetError || !target) return json({ success: false, error: "Staff account not found" }, 404);

    if (action === "reset_password") {
      if (target.removed_at || target.status === "removed") {
        return json({ success: false, error: "Removed Staff password cannot be reset" }, 409);
      }
      const newPassword = typeof body.new_password === "string" ? body.new_password : "";
      if (newPassword.length < 6) return json({ success: false, error: "New password must be at least 6 characters" }, 400);

      const { data: updatedUser, error: passwordError } = await server.auth.admin.updateUserById(target.user_id, { password: newPassword });
      if (passwordError || !updatedUser?.user) {
        return json({ success: false, error: "Unable to reset Staff password", details: passwordError?.message }, 500);
      }
      try { await server.auth.admin.signOut(target.user_id, "global"); } catch (_) {}

      const { data: recorded, error: recordError } = await server.rpc("partner_record_staff_password_reset", {
        p_staff_id: target.id,
        p_actor_user_id: caller.id,
        p_partner_id: partnerId,
      });
      if (recordError || !recorded?.success) {
        return json({ success: false, error: "Password changed but audit recording failed", details: recordError?.message }, 500);
      }
      return json({
        success: true,
        staff_id: target.id,
        staff_name: target.staff_name,
        actor_realm: recorded.actor_realm,
        message: "Staff password reset successfully. Existing Staff sessions were signed out.",
      });
    }

    if (!["rename", "suspend", "activate", "remove"].includes(action)) {
      return json({ success: false, error: "Unsupported action" }, 400);
    }
    const staffName = action === "rename" && typeof body.staff_name === "string" ? body.staff_name.trim() : null;
    if (action === "rename" && !staffName) return json({ success: false, error: "Staff name is required" }, 400);

    const { data: mutated, error: mutationError } = await server.rpc("partner_update_staff_profile", {
      p_staff_id: target.id,
      p_action: action,
      p_staff_name: staffName,
      p_actor_user_id: caller.id,
      p_partner_id: partnerId,
    });
    if (mutationError || !mutated?.success) {
      return json({ success: false, error: "Unable to update Staff", details: mutationError?.message }, 409);
    }

    if (action === "suspend" || action === "remove") {
      try { await server.auth.admin.signOut(target.user_id, "global"); } catch (_) {}
    }
    return json({ success: true, staff: mutated.staff, actor_realm: mutated.actor_realm });
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
