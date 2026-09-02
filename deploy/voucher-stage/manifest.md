# Voucher Stage Deployment Manifest

## Purpose

This manifest defines the reproducible baseline for the Voucher Stage environment used by XiaoE external bridge testing and controlled management.

## Environment identity

- Environment: `stage`
- Supabase project name: `voucher-stage`
- Supabase project ref: `tagusbcluzoxueixjmwh`
- Region: `ap-southeast-1`
- Target Edge Function: `xiaoe-voucher-bridge`

## Source of truth

The canonical source is GitHub, not the currently deployed Supabase runtime copy.

- Function source: `supabase/functions/xiaoe-voucher-bridge/index.ts`
- Deployment manifest: this file
- Rebuild guidance: `deploy/voucher-stage/rebuild.md`

A deployed Supabase Edge Function version is a runtime artifact only. Rebuilds must start from the merged GitHub source.

## Required secret names

The following secret name must exist in Voucher Stage:

- `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN`

The secret value must never be committed to GitHub.

XiaoE runtime must hold the same token under the same environment variable name so the caller and target can authenticate each other.

## Verified baseline

Verified on 2026-09-02:

- Stage project ref: `tagusbcluzoxueixjmwh`
- Edge Function: `xiaoe-voucher-bridge`
- Runtime version observed: `3`
- Function status: `ACTIVE`
- Health request: HTTP `200`
- Health response included:
  - `ok: true`
  - `project_ref: tagusbcluzoxueixjmwh`
  - `mode: controlled_admin`
  - `auth: dedicated_stage_bridge_token`

## Production isolation

Voucher Stage must remain isolated from Production.

- Stage uses `XIAOE_VOUCHER_STAGE_BRIDGE_TOKEN`.
- Production uses its own Production bridge token.
- Do not copy the Stage secret value into Production.
- Do not deploy Stage-only changes to Production automatically.
- Any Production write or destructive action requires explicit owner approval.

## Allowed bridge behavior

The bridge supports controlled actions only:

- `health`
- `read`
- `insert`
- `update`

Table access is restricted by allowlists implemented in the function source.

## Change control

Any future change to the target-side bridge should follow this order:

1. Change source in GitHub.
2. Review through PR.
3. Merge approved source.
4. Deploy merged source to Voucher Stage.
5. Run health verification.
6. Record meaningful deployment changes in this manifest or release notes.

Do not treat manual edits made only in the Supabase Dashboard as permanent source changes.
