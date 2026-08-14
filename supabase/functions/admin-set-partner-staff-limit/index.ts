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
    const url = Deno.env.get("SUPABASE_URL");
    const publishable = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !publishable) return json({ success: false, error: "Server configuration error" }, 500);

    const db = createClient(url, publishable, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const body = await req.json();
    const partnerId = typeof body.partner_id === "string" ? body.partner_id.trim() : "";
    const staffLimit = Number(body.staff_limit);
    if (!partnerId || !Number.isInteger(staffLimit)) return json({ success: false, error: "Invalid input" }, 400);

    const { data, error } = await db.rpc("admin_set_partner_staff_limit", {
      p_partner_id: partnerId,
      p_staff_limit: staffLimit,
    });

    if (error) return json({ success: false, error: error.message }, 400);
    return json(data ?? { success: true });
  } catch (e) {
    return json({ success: false, error: "Unexpected error", details: e instanceof Error ? e.message : String(e) }, 500);
  }
});
