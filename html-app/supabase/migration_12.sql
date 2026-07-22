-- Editable, versioned project description and project-linked governance documents.
-- Run after migration_11.sql.

alter table public.projects
  add column if not exists description_version integer not null default 1,
  add column if not exists description_sync_status text not null default 'synced'
    check (description_sync_status in ('synced','pending_push','conflict')),
  add column if not exists description_updated_by uuid references public.profiles(id);

alter table public.business_cases
  alter column idea_id drop not null,
  add column if not exists project_ref uuid references public.projects(id) on delete cascade;

alter table public.project_charters
  alter column idea_id drop not null,
  add column if not exists project_ref uuid references public.projects(id) on delete cascade;

alter table public.business_cases drop constraint if exists business_cases_parent_check;
alter table public.business_cases add constraint business_cases_parent_check
  check (idea_id is not null or project_ref is not null);
alter table public.project_charters drop constraint if exists project_charters_parent_check;
alter table public.project_charters add constraint project_charters_parent_check
  check (idea_id is not null or project_ref is not null);

alter table public.document_versions drop constraint if exists document_versions_doc_type_check;
alter table public.document_versions add constraint document_versions_doc_type_check
  check (doc_type in ('business_case','charter','project_description'));

-- Attach existing idea documents to converted/imported projects where possible.
update public.business_cases bc
set project_ref = p.id
from public.ideas i
join public.projects p on p.linked_initiative_id = i.idea_id
where bc.idea_id = i.id and bc.project_ref is null;

update public.project_charters ch
set project_ref = p.id
from public.ideas i
join public.projects p on p.linked_initiative_id = i.idea_id
where ch.idea_id = i.id and ch.project_ref is null;

update public.project_charters ch
set project_ref = p.id
from public.projects p
where ch.smartsheet_project_id = p.project_id and ch.project_ref is null;

drop trigger if exists t_projects_touch on public.projects;
create trigger t_projects_touch before update on public.projects
for each row execute function public.touch_updated_at();

create or replace function public.can_manage_project_deliverable(
  p_idea uuid, p_smartsheet_project_id text, p_project_ref uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    public.is_pm_or_tt()
    or (
      public.my_role() = 'project_lead'
      and exists (
        select 1
        from public.projects p
        left join public.ideas i on i.idea_id = p.linked_initiative_id
        where (
          p.project_manager_id = auth.uid()
          or p.project_lead = (select name from public.profiles where id = auth.uid())
          or p.project_lead = (select email from public.profiles where id = auth.uid())
        )
        and (p.id = p_project_ref or p.project_id = p_smartsheet_project_id or i.id = p_idea)
      )
    ), false
  )
$$;

revoke all on function public.can_manage_project_deliverable(uuid, text, uuid) from public;
grant execute on function public.can_manage_project_deliverable(uuid, text, uuid) to authenticated;

drop policy if exists bc_project_lead_select on public.business_cases;
drop policy if exists bc_project_lead_manage on public.business_cases;
drop policy if exists bc_project_lead_insert on public.business_cases;
drop policy if exists bc_project_lead_update on public.business_cases;
create policy bc_project_lead_select on public.business_cases for select to authenticated
  using (public.can_manage_project_deliverable(idea_id, null, project_ref));
create policy bc_project_lead_insert on public.business_cases for insert to authenticated
  with check (public.can_manage_project_deliverable(idea_id, null, project_ref));
create policy bc_project_lead_update on public.business_cases for update to authenticated
  using (public.can_manage_project_deliverable(idea_id, null, project_ref))
  with check (public.can_manage_project_deliverable(idea_id, null, project_ref));

drop policy if exists ch_project_lead_select on public.project_charters;
drop policy if exists ch_project_lead_manage on public.project_charters;
drop policy if exists ch_project_lead_insert on public.project_charters;
drop policy if exists ch_project_lead_update on public.project_charters;
create policy ch_project_lead_select on public.project_charters for select to authenticated
  using (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));
create policy ch_project_lead_insert on public.project_charters for insert to authenticated
  with check (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));
create policy ch_project_lead_update on public.project_charters for update to authenticated
  using (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref))
  with check (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));

create or replace function public.can_manage_document_version(p_doc_type text, p_doc_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    public.is_pm_or_tt()
    or case p_doc_type
      when 'project_description' then exists (
        select 1 from public.projects p
        where p.id = p_doc_id and public.can_manage_project_deliverable(null, p.project_id, p.id)
      )
      when 'business_case' then exists (
        select 1 from public.business_cases bc
        where bc.id = p_doc_id and public.can_manage_project_deliverable(bc.idea_id, null, bc.project_ref)
      )
      when 'charter' then exists (
        select 1 from public.project_charters ch
        where ch.id = p_doc_id and public.can_manage_project_deliverable(ch.idea_id, ch.smartsheet_project_id, ch.project_ref)
      )
      else false
    end, false
  )
$$;

revoke all on function public.can_manage_document_version(text, uuid) from public;
grant execute on function public.can_manage_document_version(text, uuid) to authenticated;

drop policy if exists dv_project_lead_manage on public.document_versions;
drop policy if exists dv_project_lead_select on public.document_versions;
drop policy if exists dv_project_lead_insert on public.document_versions;
create policy dv_project_lead_select on public.document_versions for select to authenticated
  using (public.can_manage_document_version(doc_type, doc_id));
create policy dv_project_lead_insert on public.document_versions for insert to authenticated
  with check (public.can_manage_document_version(doc_type, doc_id));

create or replace function public.prevent_project_lead_document_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() = 'project_lead' and new.status is distinct from old.status then
    raise exception 'Only Program Manager / Digital Transformation Team can change governance status';
  end if;
  return new;
end; $$;

drop trigger if exists t_bc_project_lead_status on public.business_cases;
create trigger t_bc_project_lead_status before update on public.business_cases
for each row execute function public.prevent_project_lead_document_approval();
drop trigger if exists t_ch_project_lead_status on public.project_charters;
create trigger t_ch_project_lead_status before update on public.project_charters
for each row execute function public.prevent_project_lead_document_approval();

create or replace function public.update_project_description(p_project uuid, p_description text)
returns public.projects language plpgsql security definer set search_path = public as $$
declare
  v_project public.projects%rowtype;
begin
  select * into v_project from public.projects where id = p_project for update;
  if not found then raise exception 'Project not found'; end if;
  if not public.can_manage_project_deliverable(null, v_project.project_id, v_project.id) then
    raise exception 'You are not assigned to edit this project';
  end if;
  if coalesce(v_project.project_description, '') = coalesce(p_description, '') then
    return v_project;
  end if;

  insert into public.document_versions (doc_type, doc_id, version_label, snapshot, saved_by)
  values ('project_description', v_project.id, 'v' || v_project.description_version,
    jsonb_build_object(
      'project_description', v_project.project_description,
      'description_sync_status', v_project.description_sync_status,
      'updated_at', v_project.updated_at
    ), auth.uid());

  update public.projects
  set project_description = nullif(trim(p_description), ''),
      description_version = description_version + 1,
      description_sync_status = 'pending_push',
      description_updated_by = auth.uid()
  where id = p_project
  returning * into v_project;
  return v_project;
end; $$;

revoke all on function public.update_project_description(uuid, text) from public;
grant execute on function public.update_project_description(uuid, text) to authenticated;

-- Keep activity logging valid for documents created directly from a legacy/imported project.
create or replace function public.log_changes()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  changed text[];
  rid uuid;
  related_type text := TG_ARGV[0];
begin
  select array_agg(n.key) into changed
  from jsonb_each(to_jsonb(new)) n
  join jsonb_each(to_jsonb(old)) o on n.key = o.key
  where n.value is distinct from o.value
    and n.key not in ('updated_at','created_at');
  if TG_TABLE_NAME = 'ideas' then changed := array_remove(changed, 'stage'); end if;
  if changed is null or array_length(changed, 1) is null then return new; end if;
  if TG_TABLE_NAME in ('business_cases','project_charters') then
    rid := coalesce(new.idea_id, new.project_ref);
    if new.idea_id is null then related_type := 'Project'; end if;
  else
    rid := new.id;
  end if;
  insert into public.activity (related_type, related_id, user_id, kind, message)
  values (related_type, rid, auth.uid(), 'event', TG_ARGV[1] || ' updated: ' || array_to_string(changed, ', '));
  return new;
end; $$;
