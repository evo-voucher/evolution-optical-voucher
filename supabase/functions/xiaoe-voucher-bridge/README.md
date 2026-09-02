# XiaoE Voucher Bridge

This directory is the GitHub source-of-truth for the target-side `xiaoe-voucher-bridge` Supabase Edge Function used by Voucher Stage.

## Current verified Stage deployment baseline

- Supabase project: `voucher-stage`
- Project ref: `tagusbcluzoxueixjmwh`
- Edge Function: `xiaoe-voucher-bridge`
- Verified Supabase runtime version: `3`
- Runtime status: `ACTIVE`
- Health verification: HTTP `200`, `ok: true`
- Mode: `controlled_admin`
- Authentication: dedicated Stage bridge token
- Secret name: `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN`

## Important

The secret value is intentionally **not** stored in GitHub.

Production and Stage must use separate credentials. Production is not modified by this source-tracking change.

## Rebuild procedure

1. Create or restore the target Supabase project.
2. Configure the secret `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN` with the approved Stage-only token value.
3. Deploy `supabase/functions/xiaoe-voucher-bridge/index.ts` as the Edge Function `xiaoe-voucher-bridge`.
4. Keep custom token authentication enabled in the function body.
5. Invoke with `POST` body `{ "action": "health" }` and header `X-XiaoE-Voucher-Token: <stage-token>`.
6. Confirm HTTP `200`, `ok: true`, and `project_ref: tagusbcluzoxueixjmwh`.

## Versioning rule

Supabase runtime version numbers are deployment counters, not the source version. Git commit SHA / merged PR is the authoritative source version. Every future bridge code change should be made in GitHub first, reviewed by PR, then deployed to Supabase from that exact Git revision. After deployment, update this README with the verified Supabase runtime version and deployment date.
