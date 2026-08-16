-- OPERATIONAL LINEAGE MARKER ONLY — NO-OP ON REBUILD.
--
-- Production migration 20260816023940 created a temporary, isolated recovery schema
-- named reset_recovery_20260816 immediately before the 2026-08-16 Factory Reset.
-- It captured the business rows that were about to be removed from production.
--
-- This migration file intentionally does NOT recreate that snapshot on a fresh rebuild:
-- a fresh environment has no historical production customer/business data to preserve,
-- and replaying an operational recovery snapshot would create unnecessary residue.
--
-- Production recovery schema status:
--   temporary; not used by Portal/RPC runtime.
--   remove only after Eric accepts the post-reset system and the recovery window is closed.
--
-- Source-of-truth rule:
--   this file aligns GitHub migration lineage with the already-applied production migration
--   without pretending the historical snapshot data belongs in canonical rebuild source.

select 1;
