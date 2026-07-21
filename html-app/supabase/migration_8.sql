-- ============================================================
-- Migration 8 - project manager assignments
-- Idempotent: safe to run on an existing Supabase project.
-- ============================================================

alter table public.projects
  add column if not exists project_manager_id uuid references public.profiles(id);

drop policy if exists prj_lead_select on public.projects;
create policy prj_lead_select on public.projects for select to authenticated
  using (
    public.my_role() = 'project_lead'
    and (
      project_manager_id = auth.uid()
      or project_lead = (select name from public.profiles where id = auth.uid())
      or project_lead = (select email from public.profiles where id = auth.uid())
    )
  );

