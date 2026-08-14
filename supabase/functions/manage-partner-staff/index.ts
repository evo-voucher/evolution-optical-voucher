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
    const authHeader = req.headers.get("authorization") || "";
    const jwt = authHeader.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!jwt) return json({ success: false, error: "Unauthorized" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !service) return json({ success: false, error: "Server configuration error" }, 500);

    const admin = createClient(url, service, { auth: { persistSession: false } });
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const caller = userData?.user;
    if (userError || !caller) return json({ success: false, error: "Unauthorized" }, 401);

    const { data: me, error: meError } = await admin
      .from("partner_users")
      .select("id,user_id,partner_id,role,status,removed_at,staff_name")
      .eq("user_id", caller.id)
      .eq("role", "partner_admin")
      .eq("status", "active")
      .is("removed_at", null)
      .maybeSingle();

    if (meError || !me) return json({ success: false, error: "Partner Admin access required" }, 403);

    const { data: partner, error: partnerError } = await admin
      .from("partners")
      .select("id,partner_code,partner_name,status,staff_limit,staff_access_enabled")
      .eq("id", me.partner_id)
      .maybeSingle();

    if (partnerError || !partner || partner.status !== "active") {
      return json({ success: false, error: "Partner is not active" }, 403);
    }

    const body = await req.json();
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";

    const audit = async (actionType: string, entityId: string | null, afterData: unknown, metadata: unknown = {}) => {
      await admin.from("admin_audit_log").insert({
        actor_user_id: caller.id,
        actor_name: me.staff_name || "Partner Admin",
        action_type: actionType,
        entity_type: "partner_staff",
        entity_id: entityId,
        partner_id: partner.id,
        after_data: afterData,
        metadata,
      });
    };

    if (action === "create") {
      const staff_name = typeof body.staff_name === "string" ? body.staff_name.trim() : "";
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const password = typeof body.password === "string" ? body.password : "";

      if (!staff_name || !email || !password) return json({ success: false, error: "Missing required fields" }, 400);
      if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
      if (password.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);

      const { count, error: countError } = await admin
        .from("partner_users")
        .select("id", { count: "exact", head: true })
        .eq("partner_id", partner.id)
        .eq("role", "partner_staff")
        .in("status", ["active", "suspended"])
        .is("removed_at", null);

      if (countError) return json({ success: false, error: "Unable to check Staff limit" }, 500);
      if ((count ?? 0) >= partner.staff_limit) {
        return json({ success: false, error: "Staff account limit reached", staff_limit: partner.staff_limit }, 409);
      }

      const { data: newUserData, error: createUserError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      const newUser = newUserData?.user;
      if (createUserError || !newUser) {
        return json({ success: false, error: "Failed to create Staff login", details: createUserError?.message }, 400);
      }

      const { data: staffRow, error: staffError } = await admin
        .from("partner_users")
        .insert({
          user_id: newUser.id,
          partner_id: partner.id,
          role: "partner_staff",
          status: "active",
          staff_name,
          login_email: email,
        })
        .select("id,user_id,partner_id,role,status,staff_name,login_email,created_at")
        .single();

      if (staffError) {
        try { await admin.auth.admin.deleteUser(newUser.id); } catch (_) {}
        return json({ success: false, error: "Failed to create Partner Staff profile", details: staffError.message }, 500);
      }

      await audit("partner_staff_created", staffRow.id, { staff_name, login_email: email, status: "active" });
      return json({ success: true, staff: staffRow }, 201);
    }

    const staffId = typeof body.staff_id === "string" ? body.staff_id.trim() : "";
    if (!staffId) return json({ success: false, error: "staff_id is required" }, 400);

    const { data: target, error: targetError } = await admin
      .from("partner_users")
      .select("id,user_id,partner_id,role,status,staff_name,login_email,removed_at")
      .eq("id", staffId)
      .eq("partner_id", partner.id)
      .eq("role", "partner_staff")
      .maybeSingle();

    if (targetError || !target) return json({ success: false, error: "Staff account not found" }, 404);

    if (action === "rename") {
      const staff_name = typeof body.staff_name === "string" ? body.staff_name.trim() : "";
      if (!staff_name) return json({ success: false, error: "Staff name is required" }, 400);

      const { data, error } = await admin
        .from("partner_users")
        .update({ staff_name, updated_at: new Date().toISOString() })
        .eq("id", target.id)
        .select("id,user_id,partner_id,role,status,staff_name,login_email")
        .single();

      if (error) return json({ success: false, error: "Unable to rename Staff", details: error.message }, 500);
      await audit("partner_staff_renamed", target.id, { staff_name });
      return json({ success: true, staff: data });
    }

    if (action === "reset_password") {
      if (target.removed_at || target.status === "removed") {
        return json({ success: false, error: "Removed Staff password cannot be reset" }, 409);
      }

      const newPassword = typeof body.new_password === "string" ? body.new_password : "";
      if (newPassword.length < 6) return json({ success: false, error: "New password must be at least 6 characters" }, 400);

      const { data: updatedUser, error: passwordError } = await admin.auth.admin.updateUserById(
        target.user_id,
        { password: newPassword },
      );
      if (passwordError || !updatedUser?.user) {
        return json({ success: false, error: "Unable to reset Staff password", details: passwordError?.message }, 500);
      }

      try { await admin.auth.admin.signOut(target.user_id, "global"); } catch (_) {}
      await audit("partner_staff_password_reset", target.id, { staff_name: target.staff_name });

      return json({
        success: true,
        staff_id: target.id,
        staff_name: target.staff_name,
        message: "Staff password reset successfully. Existing Staff sessions were signed out.",
      });
    }

    if (action === "suspend" || action === "activate") {
      if (target.removed_at || target.status === "removed") {
        return json({ success: false, error: "Removed Staff cannot be reactivated" }, 409);
      }

      const status = action === "activate" ? "active" : "suspended";
      const { data, error } = await admin
        .from("partner_users")
        .update({ status, updated_at: new Date().toISOString() })
        .eq("id", target.id)
        .select("id,user_id,partner_id,role,status,staff_name,login_email")
        .single();

      if (error) return json({ success: false, error: "Unable to update Staff status", details: error.message }, 500);
      if (status === "suspended") {
        try { await admin.auth.admin.signOut(target.user_id, "global"); } catch (_) {}
      }

      await audit("partner_staff_status_changed", target.id, { status });
      return json({ success: true, staff: data });
    }

    if (action === "remove") {
      const now = new Date().toISOString();
      const { data, error } = await admin
        .from("partner_users")
        .update({ status: "removed", removed_at: now, updated_at: now })
        .eq("id", target.id)
        .select("id,user_id,partner_id,role,status,staff_name,login_email,removed_at")
        .single();

      if (error) return json({ success: false, error: "Unable to remove Staff", details: error.message }, 500);
      try { await admin.auth.admin.signOut(target.user_id, "global"); } catch (_) {}

      await audit("partner_staff_removed", target.id, { status: "removed", removed_at: now });
      return json({ success: true, staff: data });
    }

    return json({ success: false, error: "Unsupported action" }, 400);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
