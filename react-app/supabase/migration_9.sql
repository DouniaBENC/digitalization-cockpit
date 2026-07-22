-- Project delivery workspace: SmartSheet hierarchy + weekly updates.
-- Run after migration_8.sql.

create table if not exists public.project_work_items (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(project_id) on delete cascade,
  smartsheet_id text not null,
  parent_initiative_id text,
  parent_milestone_id text,
  item_type text not null check (item_type in ('initiative','milestone','activity')),
  name text not null,
  description text,
  owner_email text,
  accountability text,
  workstream text,
  sub_workstream text,
  stage text,
  status text,
  current_stage text,
  planned_start_date date,
  planned_end_date date,
  deliverable text,
  capex_required text,
  digital_pillar text,
  quick_win boolean,
  priority boolean,
  stakeholder text,
  source_file text,
  imported_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(project_id, smartsheet_id)
);

create table if not exists public.project_updates (
  id uuid primary key default gen_random_uuid(),
  project_ref uuid not null references public.projects(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  update_week date not null,
  health_status text not null check (health_status in ('Green','Amber','Red')),
  progress_summary text not null,
  blockers text,
  next_actions text,
  support_needed text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists t_project_work_items_touch on public.project_work_items;
create trigger t_project_work_items_touch before update on public.project_work_items
  for each row execute function public.touch_updated_at();

drop trigger if exists t_project_updates_touch on public.project_updates;
create trigger t_project_updates_touch before update on public.project_updates
  for each row execute function public.touch_updated_at();

alter table public.project_work_items enable row level security;
alter table public.project_updates enable row level security;

drop policy if exists pwi_all_pm_tt on public.project_work_items;
create policy pwi_all_pm_tt on public.project_work_items for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());

drop policy if exists pwi_lead_select on public.project_work_items;
create policy pwi_lead_select on public.project_work_items for select to authenticated
  using (
    public.my_role() = 'project_lead'
    and exists (
      select 1 from public.projects p
      where p.project_id = project_work_items.project_id
        and (
          p.project_manager_id = auth.uid()
          or p.project_lead = (select name from public.profiles where id = auth.uid())
          or p.project_lead = (select email from public.profiles where id = auth.uid())
        )
    )
  );

drop policy if exists pu_all_pm_tt on public.project_updates;
create policy pu_all_pm_tt on public.project_updates for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());

drop policy if exists pu_lead_select on public.project_updates;
create policy pu_lead_select on public.project_updates for select to authenticated
  using (
    public.my_role() = 'project_lead'
    and exists (
      select 1 from public.projects p
      where p.id = project_updates.project_ref
        and (
          p.project_manager_id = auth.uid()
          or p.project_lead = (select name from public.profiles where id = auth.uid())
          or p.project_lead = (select email from public.profiles where id = auth.uid())
        )
    )
  );

drop policy if exists pu_lead_insert on public.project_updates;
create policy pu_lead_insert on public.project_updates for insert to authenticated
  with check (
    author_id = auth.uid()
    and (
      public.is_pm_or_tt()
      or (
        public.my_role() = 'project_lead'
        and exists (
          select 1 from public.projects p
          where p.id = project_updates.project_ref
            and (
              p.project_manager_id = auth.uid()
              or p.project_lead = (select name from public.profiles where id = auth.uid())
              or p.project_lead = (select email from public.profiles where id = auth.uid())
            )
        )
      )
    )
  );
