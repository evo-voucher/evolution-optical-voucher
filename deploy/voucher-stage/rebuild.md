# Voucher Stage Rebuild Procedure

Use this procedure when recreating the Voucher Stage environment from scratch or restoring the XiaoE external bridge target.

## Preconditions

- Work only against the Voucher Stage project unless the owner explicitly approves Production work.
- Confirm the intended Stage project ref. Current baseline: `tagusbcluzoxueixjmwh`.
- Use the merged GitHub source as the canonical bridge implementation.
- Never copy secret values into GitHub, issues, PR bodies, or logs.

## Rebuild order

1. Create or restore the Supabase Stage project.
2. Apply the Voucher Stage database migrations and schema baseline before bridge verification.
3. Confirm required Stage tables exist, including the tables referenced by the bridge allowlists.
4. Create the Stage secret named `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN` with a Stage-only random value.
5. Put the same Stage token value in the XiaoE runtime under `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN`.
6. Deploy `supabase/functions/xiaoe-voucher-bridge/index.ts` to the Stage project as Edge Function `xiaoe-voucher-bridge`.
7. Keep JWT verification disabled for this target function only because the function performs its own dedicated bridge-token authentication. Do not generalize this setting to other functions.
8. Invoke the bridge health action with the `X-XiaoE-Voucher-Token` header and body `{ "action": "health" }`.
9. Accept the deployment only when health returns HTTP 200 with `ok: true` and the expected Stage project ref.
10. From the XiaoE runtime, route a health request with `target=stage` and confirm the XiaoE -> Stage bridge -> Stage DB path.

## Expected Stage health result

A healthy Stage target should report:

- `ok: true`
- `bridge: xiaoe-voucher-bridge`
- `project_ref: tagusbcluzoxueixjmwh` (or the new Stage ref if intentionally rebuilt)
- `mode: controlled_admin`
- Stage-specific bridge authentication

If a new Stage project ref is created, update all of the following together in one reviewed change:

- XiaoE Core target registry
- XiaoE runtime Stage endpoint
- this deployment manifest
- this rebuild procedure if examples become stale

## Failure handling

- HTTP 401: confirm header name and Stage token match on both caller and target.
- HTTP 502 / database unreachable: verify Stage schema/migrations and required tables before changing bridge code.
- Wrong project ref in response: stop; do not continue until the target lock is corrected.
- Any sign that a request is reaching Production while testing Stage: stop immediately and fix routing before further calls.

## Production guardrail

Production is not part of this rebuild procedure. Stage and Production must have separate token values and separate explicit target configuration.
