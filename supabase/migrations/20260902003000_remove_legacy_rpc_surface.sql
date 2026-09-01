-- Remove legacy/compatibility RPC overloads that exist in voucher-stage but are
-- absent from the current Production function surface.
--
-- Safety notes:
-- - Exact signatures only; no CASCADE.
-- - Dependency scan on voucher-stage found zero dependent objects for every
--   function below before this migration was authored.
-- - Production is not modified by this migration unless explicitly applied.

DROP FUNCTION IF EXISTS public.admin_engine_allocate_all(uuid, integer, uuid);
DROP FUNCTION IF EXISTS public.admin_engine_allocate_v2(uuid, uuid, integer, text, integer, uuid);
DROP FUNCTION IF EXISTS public.admin_engine_allocate_v3(uuid, uuid, integer, text, integer, boolean, text[], uuid);
DROP FUNCTION IF EXISTS public.admin_engine_allocate(uuid, uuid, integer, uuid);

DROP FUNCTION IF EXISTS public.admin_publish_voucher_version_theme(uuid, text, numeric, numeric, text, integer, integer, numeric, numeric, integer, boolean, text, integer, boolean, text);
DROP FUNCTION IF EXISTS public.admin_publish_voucher_version_v2(uuid, text, numeric, numeric, text, integer, integer, date, numeric, numeric, integer, boolean, text, integer, boolean, text, jsonb, text);
DROP FUNCTION IF EXISTS public.admin_publish_voucher_version_v3(uuid, text, numeric, numeric, text, integer, integer, date, numeric, numeric, integer, boolean, text, integer, boolean, text[], text, jsonb, text);

DROP FUNCTION IF EXISTS public.create_partner_multi_voucher_controlled(uuid, text, text);
DROP FUNCTION IF EXISTS public.create_partner_voucher_controlled(text, text, text, text, date);
DROP FUNCTION IF EXISTS public.issue_partner_voucher(text, text, text, date);
