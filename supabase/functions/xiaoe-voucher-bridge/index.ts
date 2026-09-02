import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

const ALLOWED_ACTIONS = new Set(["health", "read", "insert", "update"]);

function parseAllowedTables(): Set<string> {
  const raw = Deno.env.get("XIAOE_VOUCHER_BRIDGE_ALLOWED_TABLES") ?? "";
  return new Set(
    raw
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

function validIdentifier(value: string): boolean {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const expectedToken = Deno.env.get("XIAOE_VOUCHER_BRIDGE_TOKEN")?.trim();
  const suppliedToken = req.headers.get("X-XiaoE-Voucher-Token")?.trim();

  if (!expectedToken) return reply(500, { error: "bridge_token_not_configured" });
  if (!suppliedToken || suppliedToken !== expectedToken) {
    return reply(403, { error: "forbidden" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return reply(500, { error: "server_configuration_error" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "invalid_json" });
  }

  const action = typeof body.action === "string" ? body.action : "health";
  if (!ALLOWED_ACTIONS.has(action)) {
    return reply(400, { error: "unsupported_action" });
  }

  if (action === "health") {
    return reply(200, {
      ok: true,
      service: "xiaoe-voucher-bridge",
      project_ref: new URL(supabaseUrl).hostname.split(".")[0],
      allowed_actions: [...ALLOWED_ACTIONS],
    });
  }

  const table = typeof body.table === "string" ? body.table.trim() : "";
  if (!table || !validIdentifier(table)) {
    return reply(400, { error: "invalid_table" });
  }

  const allowedTables = parseAllowedTables();
  if (!allowedTables.has(table)) {
    return reply(403, { error: "table_not_allowed" });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (action === "read") {
    const requestedLimit = Number(body.limit ?? 20);
    const limit = Math.max(1, Math.min(Number.isFinite(requestedLimit) ? requestedLimit : 20, 100));
    const { data, error } = await client.from(table).select("*").limit(limit);
    if (error) return reply(400, { error: "read_failed", detail: error.message });
    return reply(200, { ok: true, action, table, data });
  }

  if (action === "insert") {
    if (!body.row || typeof body.row !== "object" || Array.isArray(body.row)) {
      return reply(400, { error: "invalid_row" });
    }
    const { data, error } = await client
      .from(table)
      .insert(body.row as Record<string, unknown>)
      .select()
      .limit(1);
    if (error) return reply(400, { error: "insert_failed", detail: error.message });
    return reply(200, { ok: true, action, table, data });
  }

  const rowId = typeof body.id === "string" ? body.id.trim() : "";
  if (!rowId) return reply(400, { error: "missing_id" });
  if (!body.patch || typeof body.patch !== "object" || Array.isArray(body.patch)) {
    return reply(400, { error: "invalid_patch" });
  }

  const { data, error } = await client
    .from(table)
    .update(body.patch as Record<string, unknown>)
    .eq("id", rowId)
    .select()
    .limit(1);
  if (error) return reply(400, { error: "update_failed", detail: error.message });

  return reply(200, { ok: true, action, table, data });
});
