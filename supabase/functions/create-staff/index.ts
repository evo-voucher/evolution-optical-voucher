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

    const { data: realm, error: realmError } = await callerClient.rpc("current_operational_realm");
    if (realmError) return json({ success: false, error: "Authorization check failed" }, 500);

    const isAdmin = realm?.authenticated === true && realm?.realm === "admin";
    const isStaffRealm = realm?.authenticated === true && realm?.realm === "staff";
    const managerRole = isStaffRealm ? String(realm?.role || "").toLowerCase() : "";
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
      finalRole = requestedRole;
      finalBranchId = requestedBranchId;
    } else {
      if (requestedRole !== "staff") return json({ success: false, error: "Branch Manager can only create Staff accounts" }, 403);
      const managerBranchId = typeof realm?.branch_id === "string" ? realm.branch_id : "";
      if (!managerBranchId) return json({ success: false, error: "Manager has no assigned branch" }, 400);
      finalRole = "staff";
      finalBranchId = managerBranchId;
    }

    const { data: newUserData, error: createUserError } = await server.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    const newUser = newUserData?.user;
    if (createUserError || !newUser) return json({ success: false, error: "Failed to create Staff login", details: createUserError?.message }, 400);

    const { data: provisioned, error: provisionError } = await server.rpc("admin_provision_staff", {
      p_new_user_id: newUser.id,
      p_staff_name: staff_name,
      p_branch_id: finalBranchId,
      p_role: finalRole,
      p_login_email: email,
      p_actor_user_id: caller.id,
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
      return json({
        success: false,
        error: "Failed to provision Staff profile",
        details: provisionError?.message || provisioned?.error || "Unknown provisioning error",
      }, 500);
    }

    return json({ success: true, staff: provisioned.staff }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
