# Voucher Theme activation hook

The production shell already loads `assets/js/pressed-feedback.js` on every portal page through `backend-config.js`. For the incremental Theme rollout, that shared client hook is used only to bootstrap `assets/js/voucher-theme-integration.js` when the current path is `voucher-engine.html` or `voucher.html`.

The bootstrap is path-gated, idempotent, versioned with `EVOLUTION_ASSET_VERSION`, and does not call Supabase. All existing pressed-feedback behavior remains unchanged.

This keeps the activation frontend-only and avoids touching Voucher schema, RPCs, RLS, or Production data.
