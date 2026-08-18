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

function generateTemporaryPassword(length = 16) {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%*-_";
  const all = upper + lower + digits + symbols;
  const bytes = new Uint32Array(length);
  crypto.getRandomValues(bytes);
  const chars = [
    upper[bytes[0] % upper.length],
    lower[bytes[1] % lower.length],
    digits[bytes[2] % digits.length],
    symbols[bytes[3] % symbols.length],
  ];
  for (let i = 4; i < length; i++) chars.push(all[bytes[i] % all.length]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = bytes[i] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
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

    const { data: adminRow, error: adminLookupError } = await callerClient
      .from("admin_users")
      .select("user_id,display_name,status")
      .eq("user_id", caller.id)
      .eq("status", "active")
      .maybeSingle();
    if (adminLookupError) return json({ success: false, error: "Admin authorization check failed" }, 500);
    if (!adminRow) return json({ success: false, error: "Admin access required" }, 403);

    const body = await req.json();
    const partner_code = typeof body.partner_code === "string" ? body.partner_code.trim().toUpperCase() : "";
    const partner_name = typeof body.partner_name === "string" ? body.partner_name.trim() : "";
    const contact_person = typeof body.contact_person === "string" ? body.contact_person.trim() : null;
    const contact_phone = typeof body.contact_phone === "string" ? body.contact_phone.trim() : null;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const staff_limit = Number(body.staff_limit ?? 0);
    const all_branches = body.all_branches === true;
    const branch_codes = Array.isArray(body.branch_codes)
      ? [...new Set(body.branch_codes.map((v: unknown) => String(v || "").trim().toUpperCase()).filter(Boolean))]
      : [];
    const rawAllocations = Array.isArray(body.allocations)
      ? body.allocations
      : (body.version_id ? [{ version_id: body.version_id, quantity: body.quantity, validity_anchor: body.validity_anchor, validity_value: body.validity_value, validity_unit: body.validity_unit }] : []);
    const allocations = rawAllocations.map((item: any) => ({
      version_id: typeof item?.version_id === "string" ? item.version_id.trim() : "",
      quantity: Number(item?.quantity ?? 0),
      validity_anchor: typeof item?.validity_anchor === "string" ? item.validity_anchor.trim().toLowerCase() : "issue",
      validity_value: Number(item?.validity_value ?? 0),
      validity_unit: typeof item?.validity_unit === "string" ? item.validity_unit.trim().toLowerCase() : "",
    }));

    if (!partner_code || !partner_name || !email) return json({ success: false, error: "Missing required fields" }, 400);
    if (!/^[A-Z0-9_-]+$/.test(partner_code)) return json({ success: false, error: "Invalid partner code" }, 400);
    if (!email.includes("@")) return json({ success: false, error: "Invalid email" }, 400);
    if (!Number.isInteger(staff_limit) || staff_limit < 0 || staff_limit > 1000) return json({ success: false, error: "Invalid Staff Limit" }, 400);
    if (!allocations.length) return json({ success: false, error: "Select at least one Initial Voucher" }, 400);
    if (allocations.some((x: any) => !x.version_id || !Number.isInteger(x.quantity) || x.quantity < 1)) return json({ success: false, error: "Each Initial Voucher needs a valid whole-number quantity of at least 1" }, 400);
    if (allocations.some((x: any) => !["issue", "allocation"].includes(x.validity_anchor))) return json({ success: false, error: "Validity Start must be Issue Date or Allocation Date" }, 400);
    if (allocations.some((x: any) => !Number.isInteger(x.validity_value) || x.validity_value < 1)) return json({ success: false, error: "Each Voucher validity value must be a whole number of at least 1" }, 400);
    if (allocations.some((x: any) => !["days", "months"].includes(x.validity_unit))) return json({ success: false, error: "Validity Unit must be Days or Months" }, 400);
    if (new Set(allocations.map((x: any) => x.version_id)).size !== allocations.length) return json({ success: false, error: "Duplicate Initial Voucher selected" }, 400);
    if (!all_branches && branch_codes.length < 1) return json({ success: false, error: "Select at least one claim branch" }, 400);

    const temporaryPassword = generateTemporaryPassword();
    const { data: createdUserData, error: createUserError } = await server.auth.admin.createUser({ email, password: temporaryPassword, email_confirm: true });
    const newUser = createdUserData?.user;
    if (createUserError || !newUser) return json({ success: false, error: "Failed to create Partner login", details: createUserError?.message }, 400);

    const { data: provisioned, error: provisionError } = await server.rpc("admin_provision_partner_with_initial_allocations", {
      p_partner_code: partner_code,
      p_partner_name: partner_name,
      p_contact_person: contact_person,
      p_contact_phone: contact_phone,
      p_staff_limit: staff_limit,
      p_new_user_id: newUser.id,
      p_login_email: email,
      p_actor_user_id: caller.id,
      p_allocations: allocations,
      p_all_branches: all_branches,
      p_branch_codes: branch_codes,
    });

    if (provisionError || !provisioned?.success) {
      try { await server.auth.admin.deleteUser(newUser.id); } catch (_) {}
      const message = provisionError?.message || provisioned?.error || "Partner provisioning failed";
      const status = /duplicate|unique|already exists/i.test(message) ? 409 : 500;
      return json({ success: false, error: "Failed to provision Partner", details: message }, status);
    }

    return json({ success: true, partner: provisioned.partner, user_id: newUser.id, temporary_password: temporaryPassword, initial_allocations: provisioned.initial_allocations, claim_all_branches: provisioned.claim_all_branches, claim_branch_codes: provisioned.claim_branch_codes }, 201);
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
