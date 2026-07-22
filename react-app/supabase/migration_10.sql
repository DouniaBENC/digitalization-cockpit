-- Editable delivery plan, stable SmartSheet order and sync metadata.
-- Run after migration_9.sql.

alter table public.project_work_items
  add column if not exists sort_order integer not null default 0,
  add column if not exists progress_percent integer check (progress_percent between 0 and 100),
  add column if not exists source_origin text not null default 'smartsheet'
    check (source_origin in ('smartsheet','digital_pulse')),
  add column if not exists sync_status text not null default 'synced'
    check (sync_status in ('synced','pending_push','pending_review','conflict')),
  add column if not exists smartsheet_row_id text,
  add column if not exists last_modified_by uuid references public.profiles(id);

drop policy if exists pwi_lead_select on public.project_work_items;
drop policy if exists pwi_lead_manage on public.project_work_items;
create policy pwi_lead_manage on public.project_work_items for all to authenticated
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
  )
  with check (
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
