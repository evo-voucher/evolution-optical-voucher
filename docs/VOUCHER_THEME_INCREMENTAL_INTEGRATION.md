# Voucher Theme Incremental Integration

This change connects the existing Voucher Theme library to the Admin Voucher Engine and the public Voucher renderer without changing the database schema or Production data.

## Scope

- Reuse `voucher-theme-system-v1.js` as the source of truth for theme options and rendering.
- Populate Voucher Engine theme selectors from the shared library rather than maintaining a short hard-coded list.
- Make the public Voucher page load and apply the shared theme library while preserving the existing safe fallback behavior.
- Keep the existing `theme_code` / `theme_config` backend contract unchanged.

## Safety

- No Supabase migration.
- No Production database mutation.
- Existing unknown theme codes fall back to `classic`.
- Existing `theme_config` accent overrides remain supported.

## Rollout

Validate the branch/UAT frontend first. Merge only after review. Production deployment remains a separate explicit step.
