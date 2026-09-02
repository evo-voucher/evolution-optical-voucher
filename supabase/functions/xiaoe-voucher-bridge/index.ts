import { createClient } from "npm:@supabase/supabase-js@2";

const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8" };
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

const READ_TABLES = new Set([
  "partners","branches","partner_users","staff_users","partner_claim_settings",
  "partner_claim_branches","vouchers","voucher_branches","redemptions",
  "voucher_templates","voucher_versions","voucher_version_branches","voucher_rules",
  "partner_voucher_access","partner_voucher_allocations","voucher_allocation_events",
  "operational_identity_realms","partner_voucher_allocation_branches","partner_customers",
  "system_customer_field_settings","customer_districts"
]);

const MANAGE_TABLES = new Set([
  "partners","branches","partner_claim_settings","partner_claim_branches",
  "voucher_templates","voucher_versions","voucher_version_branches","voucher_rules",
  "partner_voucher_access","partner_voucher_allocations",
  "partner_voucher_allocation_branches","system_customer_field_settings","customer_districts"
]);

function cleanLimit(raw: unknown) {
  const n = Number(raw ?? 20);
  if (!Number.isFinite(n)) return 20;
  return Math.max(1, Math.min(Math.floor(n), 100));
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const expectedToken = Deno.env.get("XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN")?.trim() ?? "";
  const suppliedToken = req.headers.get("X-XiaoE-Voucher-Token")?.trim() ?? "";
  if (!expectedToken || !suppliedToken || suppliedToken !== expectedToken) {
    return reply(401, { error: "unauthorized_bridge_caller" });
  }

  const baseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!baseUrl || !serviceRoleKey) {
    return reply(500, { error: "server_configuration_error" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "invalid_json" });
  }

  const admin = createClient(baseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const action = typeof body.action === "string" ? body.action : "health";

  if (action === "health") {
    const { error } = await admin.from("partners").select("id", { count: "exact", head: true });
    if (error) return reply(502, { ok: false, error: "voucher_db_unreachable" });
    return reply(200, {
      ok: true,
      bridge: "xiaoe-voucher-bridge",
      project_ref: "tagusbcluzoxueixjmwh",
      mode: "controlled_admin",
      auth: "dedicated_stage_bridge_token"
    });
  }

  if (action === "read") {
    const table = typeof body.table === "string" ? body.table : "";
    if (!READ_TABLES.has(table)) return reply(403, { error: "table_not_allowed" });
    const limit = cleanLimit(body.limit);
    const { data, error } = await admin.from(table).select("*").limit(limit);
    if (error) return reply(502, { error: "read_failed", code: error.code });
    return reply(200, { ok: true, table, rows: data ?? [] });
  }

  if (action === "insert") {
    const table = typeof body.table === "string" ? body.table : "";
    if (!MANAGE_TABLES.has(table)) return reply(403, { error: "table_not_manageable" });
    if (!body.row || typeof body.row !== "object" || Array.isArray(body.row)) {
      return reply(400, { error: "row_required" });
    }
    const { data, error } = await admin.from(table).insert(body.row as Record<string, unknown>).select();
    if (error) return reply(502, { error: "insert_failed", code: error.code });
    return reply(200, { ok: true, table, rows: data ?? [] });
  }

  if (action === "update") {
    const table = typeof body.table === "string" ? body.table : "";
    if (!MANAGE_TABLES.has(table)) return reply(403, { error: "table_not_manageable" });
    const id = typeof body.id === "string" ? body.id : "";
    if (!id) return reply(400, { error: "id_required" });
    if (!body.patch || typeof body.patch !== "object" || Array.isArray(body.patch)) {
      return reply(400, { error: "patch_required" });
    }
    const { data, error } = await admin.from(table)
      .update(body.patch as Record<string, unknown>)
      .eq("id", id)
      .select();
    if (error) return reply(502, { error: "update_failed", code: error.code });
    return reply(200, { ok: true, table, rows: data ?? [] });
  }

  return reply(400, { error: "unsupported_action" });
});
