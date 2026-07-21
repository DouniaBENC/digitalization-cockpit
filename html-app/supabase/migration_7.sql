-- ============================================================
-- Migration 7 - idea status reason compatibility
-- Idempotent: safe to run on an existing Supabase project.
-- ============================================================

alter table public.ideas
  add column if not exists status_reason text;

