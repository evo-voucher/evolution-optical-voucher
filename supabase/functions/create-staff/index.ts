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

    const { data: manager } = await admin
      .from("staff_users")
      .select("id,user_id,branch_id,staff_name,role,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();

    const isAdmin = !!adminRow;
    const managerRole = String(manager?.role || "").toLowerCase();
    const isManager = managerRole === "manager" || managerRole === "all_branch_manager";
    if (!isAdmin && !isManager) return json({ success: false, error: "Admin or Manager access required" }, 403);

    const body = await req.json();
    const staff_name = typeof body.staff_name === "string" ? body.staff_name.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const requestedBranchId = typeof body.branch_id === "string" ? body.branch_id.trim() : "";
    const requestedRole = typeof body.role === "string" ? body.role.trim().toLowerCase() : "staff";

    if (!staff_name || !email || !password) return json({ success: false, error: "Missing required fields" }, 400);
    if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
    if (password.length < 6) return json({ success: false, error: "Password must be at least 6 characters" }, 400);

    let finalRole = "staff";
    let finalBranchId: string | null = null;

    if (isAdmin || managerRole === "all_branch_manager") {
      if (!["staff", "manager"].includes(requestedRole)) {
        return json({ success: false, error: "Allowed roles: staff, manager" }, 400);
      }
      if (!requestedBranchId) return json({ success: false, error: "Please select a branch" }, 400);
      const { data: branch } = await admin.from("branches").select("id,status").eq("id", requestedBranchId).eq("status", "active").maybeSingle();
      if (!branch) return json({ success: false, error: "Invalid or inactive branch" }, 400);
      finalRole = requestedRole;
      finalBranchId = branch.id;
    } else {
      if (requestedRole !== "staff") return json({ success: false, error: "Branch Manager can only create Staff accounts" }, 403);
      if (!manager?.branch_id) return json({ success: false, error: "Manager has no assigned branch" }, 400);
      finalRole = "staff";
      finalBranchId = manager.branch_id;
    }

    const { data: newUserData, error: createUserError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    const newUser = newUserData?.user;
    if (createUserError || !newUser) return json({ success: false, error: "Failed to create Staff login", details: createUserError?.message }, 400);

    const { data: staffRow, error: staffError } = await admin
      .from("staff_users")
      .insert({ user_id: newUser.id, branch_id: finalBranchId, staff_name, role: finalRole, status: "active" })
      .select("id,user_id,branch_id,staff_name,role,status")
      .single();

    if (staffError || !staffRow) {
      try { await admin.auth.admin.deleteUser(newUser.id); } catch (_) {}
      return json({ success: false, error: "Failed to create Staff profile", details: staffError?.message }, 500);
    }

    await admin.from("admin_audit_log").insert({
      actor_user_id: caller.id,
      actor_name: adminRow?.display_name || manager?.staff_name || "Manager",
      action_type: "staff_account_created",
      entity_type: "staff_users",
      entity_id: staffRow.id,
      after_data: { staff_name, branch_id: finalBranchId, role: finalRole, status: "active" },
      metadata: { login_email: email, secret_material_logged: false },
    });

    return json({ success: true, staff: staffRow }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
