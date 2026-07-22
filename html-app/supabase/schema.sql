-- ============================================================
-- Digital Pulse - Supabase full installation schema
-- Run this in the Supabase SQL editor of a fresh project.
-- ============================================================

-- ---------- Cleanup (safe re-run after a failed install) ----------
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user, public.my_role, public.is_pm_or_tt,
  public.touch_updated_at, public.notify_pm_tt, public.on_idea_insert,
  public.on_idea_stage_change, public.qualify_idea, public.convert_to_project,
  public.can_read_project_deliverables, public.can_manage_project_deliverable,
  public.can_manage_document_version, public.prevent_project_lead_document_approval,
  public.update_project_description, public.set_project_update_revision,
  public.on_project_update_insert, public.review_project_update cascade;
drop table if exists public.notifications, public.activity, public.document_versions,
  public.decisions, public.business_cases, public.project_charters, public.projects,
  public.ideas, public.profiles cascade;
drop sequence if exists public.idea_seq, public.bc_seq, public.charter_seq, public.decision_seq;

-- ---------- Profiles (extends auth.users) ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email text not null default '',
  role text not null default 'requester'
    check (role in ('requester','program_manager','transformation_team','project_lead')),
  function text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email);
  return new;
end; $$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Role helper (security definer avoids RLS recursion)
create or replace function public.my_role()
returns text language sql security definer stable set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_pm_or_tt()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select role in ('program_manager','transformation_team')
                   from public.profiles where id = auth.uid()), false)
$$;

-- ---------- Sequences for human-readable IDs ----------
create sequence public.idea_seq;
create sequence public.bc_seq;
create sequence public.charter_seq;
create sequence public.decision_seq;

-- ---------- Ideas ----------
create table public.ideas (
  id uuid primary key default gen_random_uuid(),
  idea_id text unique not null default 'IDEA-' || lpad(nextval('public.idea_seq')::text, 4, '0'),
  title text not null,
  requester_id uuid not null references public.profiles(id),
  submitted_date timestamptz not null default now(),
  stage text not null default 'L0 Submitted'
    check (stage in ('L0 Submitted','L0 Triage','L1 Qualified','L2 BC/Charter','G1 Approval','Converted','Rejected','Hold')),
  digital_pillar text,
  opportunity text not null,
  business_benefits text not null,
  e3_environment boolean not null default false,
  e3_economy boolean not null default false,
  e3_engagement boolean not null default false,
  impacted_functions text[] not null default '{}',
  expected_value_types text[] not null default '{}',
  estimated_value text,
  urgency text check (urgency in ('Low','Medium','High')),
  risks_challenges text,
  interface_systems text,
  data_availability text check (data_availability in ('Unknown','Low','Medium','High')),
  resources_effort text check (resources_effort in ('Low','Medium','High')),
  cost_effort text check (cost_effort in ('Low','Medium','High')),
  change_effort text check (change_effort in ('Low','Medium','High')),
  technical_effort text check (technical_effort in ('Low','Medium','High')),
  owner_id uuid references public.profiles(id),
  provisional_sponsor text,
  quick_win boolean not null default false,
  priority boolean not null default false,
  duplicate_of uuid references public.ideas(id),
  duplicate_note text,
  triage_notes text,
  status_reason text,
  linked_project_id text,
  committee_target text check (committee_target in ('Pillar SteerCo','Digitalization SteerCo')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Business Cases ----------
create table public.business_cases (
  id uuid primary key default gen_random_uuid(),
  business_case_id text unique not null default 'BC-' || lpad(nextval('public.bc_seq')::text, 4, '0'),
  idea_id uuid references public.ideas(id) on delete cascade,
  project_ref uuid,
  version text not null default 'v0',
  status text not null default 'Draft'
    check (status in ('Draft','In Review','Ready for Gate','Approved','Rework')),
  problem_statement text,
  proposed_solution text,
  strategic_alignment text,
  e3_impact_summary text,
  expected_benefits text,
  value_types text[] not null default '{}',
  estimated_value text,
  assumptions text,
  cost_estimate text,
  resource_needs text,
  risks text,
  dependencies text,
  success_metrics text,
  recommendation text check (recommendation in ('Go','No-Go','Rework','Hold')),
  committee_target text check (committee_target in ('Pillar SteerCo','Digitalization SteerCo')),
  owner_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Version snapshots (append-only history)
create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  doc_type text not null check (doc_type in ('business_case','charter','project_description')),
  doc_id uuid not null,
  version_label text not null,
  snapshot jsonb not null,
  saved_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- ---------- Project Charters ----------
create table public.project_charters (
  id uuid primary key default gen_random_uuid(),
  charter_id text unique not null default 'CH-' || lpad(nextval('public.charter_seq')::text, 4, '0'),
  idea_id uuid references public.ideas(id) on delete cascade,
  project_ref uuid,
  version text not null default 'v0',
  status text not null default 'Draft'
    check (status in ('Draft','In Review','Ready for Gate','Approved','Rework')),
  initiative_title text,
  sponsor text,
  business_owner text,
  project_lead text,
  objectives text,
  scope_in text,
  scope_out text,
  deliverables text,
  high_level_timeline text,
  stakeholders text,
  dependencies text,
  governance_path text,
  smartsheet_project_id text,
  owner_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Decisions ----------
create table public.decisions (
  id uuid primary key default gen_random_uuid(),
  decision_id text unique not null default 'DEC-' || lpad(nextval('public.decision_seq')::text, 4, '0'),
  title text not null,
  related_type text not null check (related_type in ('Idea','Business Case','Charter','Project')),
  related_id text not null,
  owner_id uuid references public.profiles(id),
  committee_target text not null default 'Pillar SteerCo'
    check (committee_target in ('Pillar SteerCo','Digitalization SteerCo','Project Meeting')),
  due_date date,
  recommendation text check (recommendation in ('Go','No-Go','Rework','Hold')),
  impact text,
  status text not null default 'To Decide'
    check (status in ('To Decide','Decided','Blocked','Deferred','Escalated')),
  outcome text check (outcome in ('Go','No-Go','Rework','Hold')),
  decision_date date,
  decision_notes text,
  action_owner_id uuid references public.profiles(id),
  next_action text,
  next_steerco boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Projects (SmartSheet mirror) ----------
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  project_id text unique not null,
  project_name text not null,
  project_category text,
  current_stage text,
  digital_pillar text,
  key_benefiting_functions text,
  execution_phase text,
  pillar_sponsor text,
  project_description text,
  project_lead text,
  project_manager_id uuid references public.profiles(id),
  pwt_it_lead text,
  integrator_consultants text,
  charter_status text,
  charter_file text,
  it_demand_status text,
  ar_status text,
  ar_file text,
  capex_keur numeric,
  current_year_budget numeric,
  cost_center_internal_order text,
  planned_start_date date,
  planned_end_date date,
  linked_initiative_id text,
  needs_attention text,
  source_file text,
  imported_at timestamptz,
  description_version integer not null default 1,
  description_sync_status text not null default 'synced'
    check (description_sync_status in ('synced','pending_push','conflict')),
  description_updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

alter table public.business_cases
  add constraint business_cases_project_ref_fkey foreign key (project_ref) references public.projects(id) on delete cascade,
  add constraint business_cases_parent_check check (idea_id is not null or project_ref is not null);
alter table public.project_charters
  add constraint project_charters_project_ref_fkey foreign key (project_ref) references public.projects(id) on delete cascade,
  add constraint project_charters_parent_check check (idea_id is not null or project_ref is not null);

create table public.project_work_items (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(project_id) on delete cascade,
  smartsheet_id text not null,
  parent_initiative_id text,
  parent_milestone_id text,
  item_type text not null check (item_type in ('initiative','milestone','activity')),
  sort_order integer not null default 0,
  name text not null,
  description text,
  owner_email text,
  accountability text,
  workstream text,
  sub_workstream text,
  stage text,
  status text,
  progress_percent integer check (progress_percent between 0 and 100),
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
  source_origin text not null default 'smartsheet' check (source_origin in ('smartsheet','digital_pulse')),
  sync_status text not null default 'synced' check (sync_status in ('synced','pending_push','pending_review','conflict')),
  smartsheet_row_id text,
  last_modified_by uuid references public.profiles(id),
  imported_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(project_id, smartsheet_id)
);

create table public.project_updates (
  id uuid primary key default gen_random_uuid(),
  project_ref uuid not null references public.projects(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  update_week date not null,
  health_status text not null check (health_status in ('Green','Amber','Red')),
  progress_summary text not null,
  blockers text,
  next_actions text,
  support_needed text,
  system_health_status text check (system_health_status in ('Green','Amber','Red')),
  system_progress_percent integer check (system_progress_percent between 0 and 100),
  system_health_reasons text[] not null default '{}',
  current_milestone text,
  current_milestone_date date,
  rag_override_reason text,
  blocker_owner text,
  blocker_due_date date,
  action_owner text,
  action_due_date date,
  support_recipient text check (support_recipient in ('Program Manager','Digital Transformation Team')),
  support_due_date date,
  decision_required boolean not null default false,
  review_status text not null default 'Submitted'
    check (review_status in ('Submitted','Reviewed','Action required','Escalated')),
  review_note text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  escalated_decision_id uuid references public.decisions(id),
  revision integer not null default 1,
  supersedes_update_id uuid references public.project_updates(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_ref, update_week, revision)
);

-- ---------- Notifications ----------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  related_type text,
  related_id text,
  message text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- Activity log (comments + events) ----------
create table public.activity (
  id uuid primary key default gen_random_uuid(),
  related_type text not null,
  related_id uuid not null,
  user_id uuid references public.profiles(id),
  kind text not null default 'event' check (kind in ('event','comment')),
  message text not null,
  created_at timestamptz not null default now()
);

-- ---------- updated_at triggers ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create trigger t_ideas_touch before update on public.ideas for each row execute function public.touch_updated_at();
create trigger t_bc_touch before update on public.business_cases for each row execute function public.touch_updated_at();
create trigger t_ch_touch before update on public.project_charters for each row execute function public.touch_updated_at();
create trigger t_dec_touch before update on public.decisions for each row execute function public.touch_updated_at();
create trigger t_projects_touch before update on public.projects for each row execute function public.touch_updated_at();
create trigger t_project_work_items_touch before update on public.project_work_items for each row execute function public.touch_updated_at();
create trigger t_project_updates_touch before update on public.project_updates for each row execute function public.touch_updated_at();

create or replace function public.set_project_update_revision()
returns trigger language plpgsql set search_path = public as $$
declare
  v_previous uuid;
begin
  select id into v_previous
  from public.project_updates
  where project_ref = new.project_ref and update_week = new.update_week
  order by revision desc, created_at desc
  limit 1;
  new.revision := coalesce((select max(revision) + 1 from public.project_updates
    where project_ref = new.project_ref and update_week = new.update_week), 1);
  new.supersedes_update_id := coalesce(new.supersedes_update_id, v_previous);
  return new;
end; $$;
create trigger t_project_updates_revision before insert on public.project_updates
  for each row execute function public.set_project_update_revision();

-- ---------- Notify PM/TT helper ----------
create or replace function public.notify_pm_tt(p_type text, p_related_type text, p_related_id text, p_message text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (recipient_id, type, related_type, related_id, message)
  select id, p_type, p_related_type, p_related_id, p_message
  from public.profiles
  where role in ('program_manager','transformation_team') and active;
end; $$;

create or replace function public.on_project_update_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_project public.projects%rowtype;
begin
  select * into v_project from public.projects where id = new.project_ref;
  if new.health_status in ('Amber','Red')
     or nullif(new.support_needed, '') is not null
     or new.decision_required then
    perform public.notify_pm_tt('Weekly Pulse', 'Project', v_project.project_id,
      v_project.project_name || ': ' || new.health_status ||
      case when new.decision_required then ' - decision requested'
           when nullif(new.support_needed, '') is not null then ' - support requested'
           else '' end);
  end if;
  return new;
end; $$;
create trigger t_project_updates_notify after insert on public.project_updates
  for each row execute function public.on_project_update_insert();

create or replace function public.review_project_update(
  p_update uuid,
  p_action text,
  p_note text default null,
  p_create_decision boolean default false,
  p_decision_title text default null,
  p_committee text default 'Project Meeting',
  p_due_date date default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_update public.project_updates%rowtype;
  v_project public.projects%rowtype;
  v_review_status text;
  v_decision uuid;
begin
  if not public.is_pm_or_tt() then
    raise exception 'Only Program Manager / Digital Transformation Team can review Weekly Pulses';
  end if;
  if p_action not in ('Acknowledge','Recovery required','Escalate') then
    raise exception 'Unsupported review action: %', p_action;
  end if;
  select * into v_update from public.project_updates where id = p_update for update;
  if not found then raise exception 'Weekly Pulse not found'; end if;
  select * into v_project from public.projects where id = v_update.project_ref;
  v_review_status := case p_action
    when 'Acknowledge' then 'Reviewed'
    when 'Recovery required' then 'Action required'
    else 'Escalated'
  end;
  if p_create_decision or p_action = 'Escalate' then
    if p_committee not in ('Pillar SteerCo','Digitalization SteerCo','Project Meeting') then
      raise exception 'Unsupported committee: %', p_committee;
    end if;
    insert into public.decisions (title, related_type, related_id, owner_id, committee_target,
      due_date, impact, status, next_action, next_steerco)
    values (coalesce(nullif(p_decision_title, ''), 'Resolve Weekly Pulse escalation - ' || v_project.project_id),
      'Project', v_project.project_id, auth.uid(), p_committee, p_due_date,
      concat_ws(E'\n', nullif(v_update.blockers, ''), nullif(v_update.support_needed, '')),
      'Escalated', coalesce(nullif(p_note, ''), 'Review and resolve the Weekly Pulse escalation.'), true)
    returning id into v_decision;
  end if;
  update public.project_updates
  set review_status = v_review_status, review_note = nullif(p_note, ''),
      reviewed_by = auth.uid(), reviewed_at = now(),
      escalated_decision_id = coalesce(v_decision, escalated_decision_id)
  where id = p_update;
  insert into public.activity (related_type, related_id, user_id, message)
  values ('Project', v_project.id, auth.uid(),
    'Weekly Pulse ' || p_action || coalesce(': ' || nullif(p_note, ''), ''));
  if v_update.author_id <> auth.uid() then
    insert into public.notifications (recipient_id, type, related_type, related_id, message)
    values (v_update.author_id, 'Weekly Pulse review', 'Project', v_project.project_id,
      v_project.project_name || ': ' || v_review_status || coalesce(' - ' || nullif(p_note, ''), ''));
  end if;
  return jsonb_build_object('update_id', p_update, 'review_status', v_review_status, 'decision_id', v_decision);
end; $$;

revoke all on function public.review_project_update(uuid, text, text, boolean, text, text, date) from public;
grant execute on function public.review_project_update(uuid, text, text, boolean, text, text, date) to authenticated;

-- New idea -> notify PM/TT + activity event
create or replace function public.on_idea_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_pm_tt('New idea', 'Idea', new.idea_id,
    'New idea submitted: ' || new.idea_id || ' - ' || new.title);
  insert into public.activity (related_type, related_id, user_id, message)
  values ('Idea', new.id, new.requester_id, 'Idea submitted');
  return new;
end; $$;
create trigger t_idea_insert after insert on public.ideas
  for each row execute function public.on_idea_insert();

-- Stage change -> activity event
create or replace function public.on_idea_stage_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.stage is distinct from old.stage then
    insert into public.activity (related_type, related_id, user_id, message)
    values ('Idea', new.id, auth.uid(), 'Stage changed: ' || old.stage || ' -> ' || new.stage);
  end if;
  return new;
end; $$;
create trigger t_idea_stage after update on public.ideas
  for each row execute function public.on_idea_stage_change();

-- ---------- RPC: qualify idea (L0 Triage -> L1 Qualified) ----------
-- Atomically: set stage, create BC v0 + Charter v0, initial decision, notifications.
create or replace function public.qualify_idea(p_idea uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
  v_bc uuid; v_ch uuid; v_dec uuid;
begin
  if not public.is_pm_or_tt() then
    raise exception 'Only Program Manager / Digital Team can qualify ideas';
  end if;
  select * into v_idea from public.ideas where id = p_idea for update;
  if not found then raise exception 'Idea not found'; end if;
  if v_idea.stage not in ('L0 Submitted','L0 Triage') then
    raise exception 'Idea must be in L0 to qualify (current: %)', v_idea.stage;
  end if;

  update public.ideas set stage = 'L1 Qualified', owner_id = coalesce(owner_id, auth.uid())
  where id = p_idea;

  insert into public.business_cases (idea_id, problem_statement, expected_benefits, value_types,
    estimated_value, e3_impact_summary, risks, dependencies, owner_id)
  values (p_idea, v_idea.opportunity, v_idea.business_benefits, v_idea.expected_value_types,
    v_idea.estimated_value,
    concat_ws(', ',
      case when v_idea.e3_environment then 'Environment' end,
      case when v_idea.e3_economy then 'Economy' end,
      case when v_idea.e3_engagement then 'Engagement' end),
    v_idea.risks_challenges, v_idea.interface_systems, auth.uid())
  returning id into v_bc;

  insert into public.project_charters (idea_id, initiative_title, sponsor, objectives, dependencies, owner_id)
  values (p_idea, v_idea.title, v_idea.provisional_sponsor, v_idea.business_benefits,
    v_idea.interface_systems, auth.uid())
  returning id into v_ch;

  insert into public.decisions (title, related_type, related_id, owner_id, committee_target, status)
  values ('Qualify idea for business case and charter preparation: ' || v_idea.idea_id,
    'Idea', v_idea.idea_id, auth.uid(), coalesce(v_idea.committee_target,'Pillar SteerCo'), 'Decided')
  returning id into v_dec;
  update public.decisions set outcome='Go', decision_date=current_date where id = v_dec;

  insert into public.activity (related_type, related_id, user_id, message)
  values ('Idea', p_idea, auth.uid(), 'Idea qualified (L1). Business Case v0 and Project Charter v0 created.');

  perform public.notify_pm_tt('Gate readiness','Idea', v_idea.idea_id,
    'Business Case v0 and Project Charter v0 created for ' || v_idea.idea_id);

  return jsonb_build_object('business_case_id', v_bc, 'charter_id', v_ch, 'decision_id', v_dec);
end; $$;

-- ---------- RPC: convert initiative to project (post G1 Go) ----------
create or replace function public.convert_to_project(p_idea uuid, p_project_id text, p_project_lead text)
returns void language plpgsql security definer set search_path = public as $$
declare v_idea public.ideas%rowtype;
begin
  if public.my_role() <> 'program_manager' then
    raise exception 'Only the Program Manager can convert an initiative to a project';
  end if;
  select * into v_idea from public.ideas where id = p_idea for update;
  if not found then raise exception 'Idea not found'; end if;
  if v_idea.stage <> 'G1 Approval' then
    raise exception 'Idea must be at G1 Approval to convert (current: %)', v_idea.stage;
  end if;
  if exists (select 1 from public.projects where project_id = p_project_id) then
    raise exception 'Project ID % already exists', p_project_id;
  end if;

  insert into public.projects (project_id, project_name, project_category, current_stage,
    digital_pillar, project_description, project_lead, linked_initiative_id, updated_at)
  values (p_project_id, v_idea.title, 'Digitalization', 'S1 (Scoping)',
    v_idea.digital_pillar, v_idea.opportunity, p_project_lead, v_idea.idea_id, now());

  update public.ideas set stage='Converted', linked_project_id = p_project_id where id = p_idea;
  update public.project_charters set smartsheet_project_id = p_project_id where idea_id = p_idea;

  insert into public.activity (related_type, related_id, user_id, message)
  values ('Idea', p_idea, auth.uid(), 'Converted to project ' || p_project_id);

  perform public.notify_pm_tt('Converted','Project', p_project_id,
    'Initiative ' || v_idea.idea_id || ' converted to project ' || p_project_id);
end; $$;

create or replace function public.can_read_project_deliverables(p_idea uuid, p_smartsheet_project_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    public.my_role() = 'project_lead'
    and exists (
      select 1 from public.projects p
      left join public.ideas i on i.idea_id = p.linked_initiative_id
      where (p.project_manager_id = auth.uid()
        or p.project_lead = (select name from public.profiles where id = auth.uid())
        or p.project_lead = (select email from public.profiles where id = auth.uid()))
        and (i.id = p_idea or p.project_id = p_smartsheet_project_id)
    ), false
  )
$$;
revoke all on function public.can_read_project_deliverables(uuid, text) from public;
grant execute on function public.can_read_project_deliverables(uuid, text) to authenticated;

create or replace function public.can_manage_project_deliverable(
  p_idea uuid, p_smartsheet_project_id text, p_project_ref uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    public.is_pm_or_tt()
    or (
      public.my_role() = 'project_lead'
      and exists (
        select 1 from public.projects p
        left join public.ideas i on i.idea_id = p.linked_initiative_id
        where (p.project_manager_id = auth.uid()
          or p.project_lead = (select name from public.profiles where id = auth.uid())
          or p.project_lead = (select email from public.profiles where id = auth.uid()))
          and (p.id = p_project_ref or p.project_id = p_smartsheet_project_id or i.id = p_idea)
      )
    ), false
  )
$$;
revoke all on function public.can_manage_project_deliverable(uuid, text, uuid) from public;
grant execute on function public.can_manage_project_deliverable(uuid, text, uuid) to authenticated;

create or replace function public.can_manage_document_version(p_doc_type text, p_doc_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    public.is_pm_or_tt()
    or case p_doc_type
      when 'project_description' then exists (
        select 1 from public.projects p where p.id = p_doc_id
          and public.can_manage_project_deliverable(null, p.project_id, p.id))
      when 'business_case' then exists (
        select 1 from public.business_cases bc where bc.id = p_doc_id
          and public.can_manage_project_deliverable(bc.idea_id, null, bc.project_ref))
      when 'charter' then exists (
        select 1 from public.project_charters ch where ch.id = p_doc_id
          and public.can_manage_project_deliverable(ch.idea_id, ch.smartsheet_project_id, ch.project_ref))
      else false
    end, false
  )
$$;
revoke all on function public.can_manage_document_version(text, uuid) from public;
grant execute on function public.can_manage_document_version(text, uuid) to authenticated;

create or replace function public.prevent_project_lead_document_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() = 'project_lead' and new.status is distinct from old.status then
    raise exception 'Only Program Manager / Digital Transformation Team can change governance status';
  end if;
  return new;
end; $$;
create trigger t_bc_project_lead_status before update on public.business_cases
for each row execute function public.prevent_project_lead_document_approval();
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
  if coalesce(v_project.project_description, '') = coalesce(p_description, '') then return v_project; end if;
  insert into public.document_versions (doc_type, doc_id, version_label, snapshot, saved_by)
  values ('project_description', v_project.id, 'v' || v_project.description_version,
    jsonb_build_object('project_description', v_project.project_description,
      'description_sync_status', v_project.description_sync_status, 'updated_at', v_project.updated_at), auth.uid());
  update public.projects
  set project_description = nullif(trim(p_description), ''),
      description_version = description_version + 1,
      description_sync_status = 'pending_push',
      description_updated_by = auth.uid()
  where id = p_project returning * into v_project;
  return v_project;
end; $$;
revoke all on function public.update_project_description(uuid, text) from public;
grant execute on function public.update_project_description(uuid, text) to authenticated;

-- ============================================================
-- Row Level Security (permission matrix from the spec)
-- ============================================================
alter table public.profiles enable row level security;
alter table public.ideas enable row level security;
alter table public.business_cases enable row level security;
alter table public.project_charters enable row level security;
alter table public.decisions enable row level security;
alter table public.projects enable row level security;
alter table public.project_work_items enable row level security;
alter table public.project_updates enable row level security;
alter table public.notifications enable row level security;
alter table public.activity enable row level security;
alter table public.document_versions enable row level security;

-- Profiles: everyone authenticated can read (names needed across app);
-- users update own profile except role; PM manages roles.
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_insert_own on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and role = (select role from public.profiles where id = auth.uid()));
create policy profiles_pm_update on public.profiles for update to authenticated
  using (public.my_role() = 'program_manager') with check (true);

-- Ideas
create policy ideas_insert on public.ideas for insert to authenticated
  with check (requester_id = auth.uid());
create policy ideas_select on public.ideas for select to authenticated
  using (requester_id = auth.uid() or owner_id = auth.uid() or public.is_pm_or_tt()
         or public.my_role() = 'project_lead' and owner_id = auth.uid());
create policy ideas_update_pm_tt on public.ideas for update to authenticated
  using (public.is_pm_or_tt());
create policy ideas_update_own_before_triage on public.ideas for update to authenticated
  using (requester_id = auth.uid() and stage = 'L0 Submitted')
  with check (requester_id = auth.uid() and stage in ('L0 Submitted'));
create policy ideas_project_lead_select on public.ideas for select to authenticated
  using (public.can_read_project_deliverables(id, null));

-- Business cases / charters: PM + TT full; assigned Project Manager maintains project documents.
create policy bc_all_pm_tt on public.business_cases for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
create policy bc_lead on public.business_cases for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = business_cases.idea_id and i.owner_id = auth.uid()));
create policy bc_project_lead_select on public.business_cases for select to authenticated
  using (public.can_manage_project_deliverable(idea_id, null, project_ref));
create policy bc_project_lead_insert on public.business_cases for insert to authenticated
  with check (public.can_manage_project_deliverable(idea_id, null, project_ref));
create policy bc_project_lead_update on public.business_cases for update to authenticated
  using (public.can_manage_project_deliverable(idea_id, null, project_ref))
  with check (public.can_manage_project_deliverable(idea_id, null, project_ref));
create policy ch_all_pm_tt on public.project_charters for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
create policy ch_lead on public.project_charters for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = project_charters.idea_id and i.owner_id = auth.uid()));
create policy ch_project_lead_select on public.project_charters for select to authenticated
  using (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));
create policy ch_project_lead_insert on public.project_charters for insert to authenticated
  with check (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));
create policy ch_project_lead_update on public.project_charters for update to authenticated
  using (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref))
  with check (public.can_manage_project_deliverable(idea_id, smartsheet_project_id, project_ref));

-- Decisions: PM + TT full; owner / action owner read+update
create policy dec_all_pm_tt on public.decisions for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
create policy dec_owner_select on public.decisions for select to authenticated
  using (owner_id = auth.uid() or action_owner_id = auth.uid());
create policy dec_owner_update on public.decisions for update to authenticated
  using (owner_id = auth.uid() or action_owner_id = auth.uid());

-- Projects: PM + TT full; project leads read assigned projects
create policy prj_all_pm_tt on public.projects for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
create policy prj_lead_select on public.projects for select to authenticated
  using (
    public.my_role() = 'project_lead'
    and (
      project_manager_id = auth.uid()
      or project_lead = (select name from public.profiles where id = auth.uid())
      or project_lead = (select email from public.profiles where id = auth.uid())
    )
  );

-- Project work items / updates: PM + TT full; project leads manage assigned delivery plans and submit updates
create policy pwi_all_pm_tt on public.project_work_items for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
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
create policy pu_all_pm_tt on public.project_updates for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
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

-- Notifications: recipient only
create policy notif_select on public.notifications for select to authenticated
  using (recipient_id = auth.uid());
create policy notif_update on public.notifications for update to authenticated
  using (recipient_id = auth.uid());

-- Activity: visible if the parent idea is visible; insert by any authenticated (comments)
create policy act_select on public.activity for select to authenticated using (true);
create policy act_insert on public.activity for insert to authenticated
  with check (user_id = auth.uid());

-- Document versions: PM/TT
create policy dv_all_pm_tt on public.document_versions for all to authenticated
  using (public.is_pm_or_tt()) with check (public.is_pm_or_tt());
create policy dv_project_lead_select on public.document_versions for select to authenticated
  using (public.can_manage_document_version(doc_type, doc_id));
create policy dv_project_lead_insert on public.document_versions for insert to authenticated
  with check (public.can_manage_document_version(doc_type, doc_id));

-- ============================================================
-- Bootstrap: after your first signup, promote yourself:
-- update public.profiles set role='program_manager' where email='you@company.com';
-- ============================================================

-- ============================================================
-- Idea Owner document visibility + field-level audit log (migration 2, folded in)
-- ============================================================

-- 1) The Idea Owner can read the BC / Charter; Digital Transformation Team owns document updates.
drop policy if exists bc_requester_select on public.business_cases;
drop policy if exists bc_requester_update on public.business_cases;
drop policy if exists ch_requester_select on public.project_charters;
drop policy if exists ch_requester_update on public.project_charters;
create policy bc_requester_select on public.business_cases for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = business_cases.idea_id and i.requester_id = auth.uid()));
create policy ch_requester_select on public.project_charters for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = project_charters.idea_id and i.requester_id = auth.uid()));

-- 2) Audit log générique : chaque modification est tracée (date, utilisateur, champs modifiés)
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
  if TG_TABLE_NAME = 'ideas' then
    changed := array_remove(changed, 'stage'); -- déjà loggé par le trigger dédié avec un message plus lisible
  end if;
  if changed is null or array_length(changed, 1) is null then return new; end if;
  if TG_TABLE_NAME in ('business_cases','project_charters') then
    rid := coalesce(new.idea_id, new.project_ref);
    if new.idea_id is null then related_type := 'Project'; end if;
  else rid := new.id; end if;
  insert into public.activity (related_type, related_id, user_id, kind, message)
  values (related_type, rid, auth.uid(), 'event', TG_ARGV[1] || ' updated: ' || array_to_string(changed, ', '));
  return new;
end; $$;

drop trigger if exists t_log_ideas on public.ideas;
drop trigger if exists t_log_bc on public.business_cases;
drop trigger if exists t_log_ch on public.project_charters;
drop trigger if exists t_log_dec on public.decisions;
drop trigger if exists t_log_prj on public.projects;
create trigger t_log_ideas after update on public.ideas for each row execute function public.log_changes('Idea','Idea');
create trigger t_log_bc after update on public.business_cases for each row execute function public.log_changes('Idea','Business Case');
create trigger t_log_ch after update on public.project_charters for each row execute function public.log_changes('Idea','Charter');
create trigger t_log_dec after update on public.decisions for each row execute function public.log_changes('Decision','Decision');
create trigger t_log_prj after update on public.projects for each row execute function public.log_changes('Project','Project');

-- 3) Notification au porteur quand son idée est qualifiée (kit d'accompagnement)
--    (remplace la fonction qualify_idea : ajout du bloc notification requester)
create or replace function public.qualify_idea(p_idea uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
  v_bc uuid; v_ch uuid; v_dec uuid;
begin
  if not public.is_pm_or_tt() then
    raise exception 'Only Program Manager / Digital Team can qualify ideas';
  end if;
  select * into v_idea from public.ideas where id = p_idea for update;
  if not found then raise exception 'Idea not found'; end if;
  if v_idea.stage not in ('L0 Submitted','L0 Triage') then
    raise exception 'Idea must be in L0 to qualify (current: %)', v_idea.stage;
  end if;

  update public.ideas set stage = 'L1 Qualified', owner_id = coalesce(owner_id, auth.uid())
  where id = p_idea;

  insert into public.business_cases (idea_id, problem_statement, expected_benefits, value_types,
    estimated_value, e3_impact_summary, risks, dependencies, owner_id)
  values (p_idea, v_idea.opportunity, v_idea.business_benefits, v_idea.expected_value_types,
    v_idea.estimated_value,
    concat_ws(', ',
      case when v_idea.e3_environment then 'Environment' end,
      case when v_idea.e3_economy then 'Economy' end,
      case when v_idea.e3_engagement then 'Engagement' end),
    v_idea.risks_challenges, v_idea.interface_systems, auth.uid())
  returning id into v_bc;

  insert into public.project_charters (idea_id, initiative_title, sponsor, objectives, dependencies, owner_id)
  values (p_idea, v_idea.title, v_idea.provisional_sponsor, v_idea.business_benefits,
    v_idea.interface_systems, auth.uid())
  returning id into v_ch;

  insert into public.decisions (title, related_type, related_id, owner_id, committee_target, status)
  values ('Qualify idea for business case and charter preparation: ' || v_idea.idea_id,
    'Idea', v_idea.idea_id, auth.uid(), coalesce(v_idea.committee_target,'Pillar SteerCo'), 'Decided')
  returning id into v_dec;
  update public.decisions set outcome='Go', decision_date=current_date where id = v_dec;

  insert into public.activity (related_type, related_id, user_id, message)
  values ('Idea', p_idea, auth.uid(), 'Idea qualified (L1). Business Case v0 and Project Charter v0 created.');

  perform public.notify_pm_tt('Gate readiness','Idea', v_idea.idea_id,
    'Business Case v0 and Project Charter v0 created for ' || v_idea.idea_id);

  -- Notify the Idea Owner that the Digital Team is preparing the decision kit.
  insert into public.notifications (recipient_id, type, related_type, related_id, message)
  values (v_idea.requester_id, 'Idea qualified', 'Idea', v_idea.idea_id,
    'Your idea ' || v_idea.idea_id || ' has been qualified. The Digital Transformation Team is preparing the Business Case and Project Charter and may contact you for clarification.');

  return jsonb_build_object('business_case_id', v_bc, 'charter_id', v_ch, 'decision_id', v_dec);
end; $$;

-- ============================================================
-- Lean Business Case & Project Charter templates (migration 3, folded in)
-- ============================================================

alter table public.business_cases add column if not exists content jsonb not null default '{}'::jsonb;
alter table public.project_charters add column if not exists content jsonb not null default '{}'::jsonb;

-- Reprise du contenu déjà saisi dans les anciennes sections
update public.business_cases set content = jsonb_strip_nulls(jsonb_build_object(
  'problem', problem_statement,
  'proposed_solution', proposed_solution,
  'expected_benefits', expected_benefits,
  'estimated_value', estimated_value,
  'estimated_cost', cost_estimate,
  'resources_needed', resource_needs,
  'systems_data', dependencies,
  'critical_assumption', assumptions,
  'summary', null
)) || case when risks is not null and risks <> ''
      then jsonb_build_object('risks', jsonb_build_array(jsonb_build_object('risk', risks, 'impact', '', 'mitigation', '', 'owner', '')))
      else '{}'::jsonb end
where content = '{}'::jsonb;

update public.project_charters set content = jsonb_strip_nulls(jsonb_build_object(
  'outcome', objectives,
  'in_scope', scope_in,
  'out_scope', scope_out,
  'target_dates', high_level_timeline,
  'core_contributors', stakeholders,
  'decision_path', governance_path
)) || case when deliverables is not null and deliverables <> ''
      then jsonb_build_object('deliverables', jsonb_build_array(jsonb_build_object('deliverable', deliverables, 'acceptance', '', 'owner', '', 'target', '')))
      else '{}'::jsonb end
  || case when dependencies is not null and dependencies <> ''
      then jsonb_build_object('risks_deps', jsonb_build_array(jsonb_build_object('item', dependencies, 'type', 'Dependency', 'impact_action', '', 'owner', '', 'due', '', 'status', 'Open')))
      else '{}'::jsonb end
where content = '{}'::jsonb;

-- v0 generated with the lean decision-kit structure
create or replace function public.qualify_idea(p_idea uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
  v_bc uuid; v_ch uuid; v_dec uuid;
begin
  if not public.is_pm_or_tt() then
    raise exception 'Only Program Manager / Digital Team can qualify ideas';
  end if;
  select * into v_idea from public.ideas where id = p_idea for update;
  if not found then raise exception 'Idea not found'; end if;
  if v_idea.stage not in ('L0 Submitted','L0 Triage') then
    raise exception 'Idea must be in L0 to qualify (current: %)', v_idea.stage;
  end if;

  update public.ideas set stage = 'L1 Qualified', owner_id = coalesce(owner_id, auth.uid())
  where id = p_idea;

  insert into public.business_cases (idea_id, problem_statement, expected_benefits, value_types,
    estimated_value, e3_impact_summary, risks, dependencies, owner_id, content)
  values (p_idea, v_idea.opportunity, v_idea.business_benefits, v_idea.expected_value_types,
    v_idea.estimated_value,
    concat_ws(', ',
      case when v_idea.e3_environment then 'Environment' end,
      case when v_idea.e3_economy then 'Economy' end,
      case when v_idea.e3_engagement then 'Engagement' end),
    v_idea.risks_challenges, v_idea.interface_systems, auth.uid(),
    jsonb_strip_nulls(jsonb_build_object(
      'problem', v_idea.opportunity,
      'who_affected', nullif(array_to_string(v_idea.impacted_functions, ', '), ''),
      'expected_benefits', v_idea.business_benefits,
      'estimated_value', v_idea.estimated_value,
      'systems_data', v_idea.interface_systems,
      'why_now', case when v_idea.urgency is not null then 'Urgency assessed as ' || v_idea.urgency || ' at triage. To be confirmed.' end
    )) || case when v_idea.risks_challenges is not null and v_idea.risks_challenges <> ''
          then jsonb_build_object('risks', jsonb_build_array(jsonb_build_object('risk', v_idea.risks_challenges, 'impact', '', 'mitigation', 'To be confirmed', 'owner', '')))
          else '{}'::jsonb end)
  returning id into v_bc;

  insert into public.project_charters (idea_id, initiative_title, sponsor, objectives, dependencies, owner_id, content)
  values (p_idea, v_idea.title, v_idea.provisional_sponsor, v_idea.business_benefits,
    v_idea.interface_systems, auth.uid(),
    jsonb_strip_nulls(jsonb_build_object(
      'outcome', v_idea.business_benefits,
      'problem', v_idea.opportunity,
      'roadmap', jsonb_build_array(
        jsonb_build_object('phase','Scope','outcome','Scope, value baseline and solution confirmed','target','','gate','G2','owner',''),
        jsonb_build_object('phase','Plan','outcome','Resources, plan and adoption approach confirmed','target','','gate','G3','owner',''),
        jsonb_build_object('phase','Deliver','outcome','Solution implemented and accepted','target','','gate','G4','owner',''),
        jsonb_build_object('phase','Verify','outcome','Benefits and run ownership confirmed','target','','gate','G5','owner','')
      ))))
  returning id into v_ch;

  insert into public.decisions (title, related_type, related_id, owner_id, committee_target, status)
  values ('Qualify idea for business case and charter preparation: ' || v_idea.idea_id,
    'Idea', v_idea.idea_id, auth.uid(), coalesce(v_idea.committee_target,'Pillar SteerCo'), 'Decided')
  returning id into v_dec;
  update public.decisions set outcome='Go', decision_date=current_date where id = v_dec;

  insert into public.activity (related_type, related_id, user_id, message)
  values ('Idea', p_idea, auth.uid(), 'Idea qualified (L1). Business Case v0 and Project Charter v0 created.');

  perform public.notify_pm_tt('Gate readiness','Idea', v_idea.idea_id,
    'Business Case v0 and Project Charter v0 created for ' || v_idea.idea_id);

  insert into public.notifications (recipient_id, type, related_type, related_id, message)
  values (v_idea.requester_id, 'Idea qualified', 'Idea', v_idea.idea_id,
    'Your idea ' || v_idea.idea_id || ' has been qualified. The Digital Transformation Team is preparing the Business Case and Project Charter and may contact you for clarification.');

  return jsonb_build_object('business_case_id', v_bc, 'charter_id', v_ch, 'decision_id', v_dec);
end; $$;

-- ============================================================
-- Prefill enrichment from parent idea (migration 4, folded in)
-- ============================================================

update public.business_cases bc
set content = (
  jsonb_strip_nulls(jsonb_build_object(
    'problem', i.opportunity,
    'who_affected', nullif(array_to_string(i.impacted_functions, ', '), ''),
    'why_now', case when i.urgency is not null then 'Urgency assessed as ' || i.urgency || ' at triage. To be confirmed.' end,
    'expected_benefits', i.business_benefits,
    'estimated_value', i.estimated_value,
    'systems_data', i.interface_systems
  ))
  || case when bc.content->'risks' is null and i.risks_challenges is not null and i.risks_challenges <> ''
       then jsonb_build_object('risks', jsonb_build_array(jsonb_build_object('risk', i.risks_challenges, 'impact', '', 'mitigation', 'To be confirmed', 'owner', '')))
       else '{}'::jsonb end
  || bc.content  -- les valeurs déjà saisies dans le document prévalent
)
from public.ideas i
where i.id = bc.idea_id;

update public.project_charters ch
set content = (
  jsonb_strip_nulls(jsonb_build_object(
    'purpose', 'Deliver "' || i.title || '" to address the qualified need. To be refined.',
    'outcome', i.business_benefits,
    'problem', i.opportunity
  ))
  || case when ch.content->'roadmap' is null
       then jsonb_build_object('roadmap', jsonb_build_array(
         jsonb_build_object('phase','Scope','outcome','Scope, value baseline and solution confirmed','target','','gate','G2','owner',''),
         jsonb_build_object('phase','Plan','outcome','Resources, plan and adoption approach confirmed','target','','gate','G3','owner',''),
         jsonb_build_object('phase','Deliver','outcome','Solution implemented and accepted','target','','gate','G4','owner',''),
         jsonb_build_object('phase','Verify','outcome','Benefits and run ownership confirmed','target','','gate','G5','owner','')))
       else '{}'::jsonb end
  || ch.content
)
from public.ideas i
where i.id = ch.idea_id;

-- Sponsor / business owner du charter depuis l'idée si absents
update public.project_charters ch
set sponsor = coalesce(ch.sponsor, i.provisional_sponsor),
    business_owner = coalesce(ch.business_owner, p.name)
from public.ideas i
join public.profiles p on p.id = i.requester_id
where i.id = ch.idea_id;

-- ============================================================
-- Configurable reference data + settings (migration 5, folded in)
-- ============================================================

create table if not exists public.app_reference (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('pillar','function','value_type')),
  value text not null,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (category, value)
);
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_reference enable row level security;
alter table public.app_settings enable row level security;
drop policy if exists ref_select on public.app_reference;
drop policy if exists ref_write on public.app_reference;
drop policy if exists set_select on public.app_settings;
drop policy if exists set_write on public.app_settings;
create policy ref_select on public.app_reference for select to authenticated using (true);
create policy ref_write on public.app_reference for all to authenticated
  using (public.my_role() = 'program_manager') with check (public.my_role() = 'program_manager');
create policy set_select on public.app_settings for select to authenticated using (true);
create policy set_write on public.app_settings for all to authenticated
  using (public.my_role() = 'program_manager') with check (public.my_role() = 'program_manager');

-- Seed depuis les valeurs actuelles de l'app
insert into public.app_reference (category, value, sort_order) values
  ('pillar','Smart Planning',1), ('pillar','AI-enhanced Engineering',2),
  ('pillar','Agentic AI for Engineering',3), ('pillar','CTQ & Digital Twin Innovation',4),
  ('pillar','Lean and Automated Support',5), ('pillar','Digital Thread',6), ('pillar','To Be Confirmed',7),
  ('function','Engineering',1), ('function','Manufacturing',2), ('function','Installation',3),
  ('function','Planning',4), ('function','Quality',5), ('function','HR',6), ('function','Legal',7),
  ('function','Project',8), ('function','Technical Office',9), ('function','Other',10),
  ('value_type','Cost reduction',1), ('value_type','Cycle time reduction',2),
  ('value_type','Quality improvement',3), ('value_type','Risk reduction',4),
  ('value_type','Revenue enablement',5), ('value_type','Compliance',6),
  ('value_type','User experience',7), ('value_type','Data availability',8)
on conflict (category, value) do nothing;

insert into public.app_settings (key, value) values
  ('gate_ready_threshold', '80'::jsonb), ('triage_sla_days', '7'::jsonb)
on conflict (key) do nothing;

-- Renommage avec propagation optionnelle sur l'existant
create or replace function public.rename_reference(p_category text, p_old text, p_new text, p_propagate boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() <> 'program_manager' then
    raise exception 'Only the Program Manager can rename reference data';
  end if;
  update public.app_reference set value = p_new where category = p_category and value = p_old;
  if p_propagate then
    if p_category = 'pillar' then
      update public.ideas set digital_pillar = p_new where digital_pillar = p_old;
      update public.projects set digital_pillar = p_new where digital_pillar = p_old;
    elsif p_category = 'function' then
      update public.ideas set impacted_functions = array_replace(impacted_functions, p_old, p_new)
        where p_old = any(impacted_functions);
    elsif p_category = 'value_type' then
      update public.ideas set expected_value_types = array_replace(expected_value_types, p_old, p_new)
        where p_old = any(expected_value_types);
      update public.business_cases set value_types = array_replace(value_types, p_old, p_new)
        where p_old = any(value_types);
    end if;
  end if;
end; $$;

-- ============================================================
-- Parcours porteur d'idée : notifications à chaque étape,
-- décision comité, commentaires, bienvenue (migration 6, folded in)
-- ============================================================

-- 1) Changement de stage -> activité + notification au porteur
--    ('L1 Qualified' est exclu : qualify_idea() envoie déjà la
--    notification "kit" plus détaillée)
create or replace function public.on_idea_stage_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_msg text;
begin
  if new.stage is distinct from old.stage then
    insert into public.activity (related_type, related_id, user_id, message)
    values ('Idea', new.id, auth.uid(), 'Stage changed: ' || old.stage || ' -> ' || new.stage);

    if new.stage <> 'L1 Qualified'
       and (auth.uid() is null or auth.uid() <> new.requester_id) then
      v_msg := case new.stage
        when 'L0 Triage' then
          'Your idea ' || new.idea_id || ' is now being reviewed by the Digital Team.'
        when 'L2 BC/Charter' then
          'Your idea ' || new.idea_id || ' moved to decision-kit preparation (L2). The Digital Transformation Team is preparing the Business Case and Project Charter.'
        when 'G1 Approval' then
          'Your idea ' || new.idea_id || ' is ready and will be presented for the G1 committee decision.'
        when 'Converted' then
          'Congratulations! Your idea ' || new.idea_id || ' has been approved and converted into project ' || coalesce(new.linked_project_id, 'TBD') || '.'
        when 'Rejected' then
          'Your idea ' || new.idea_id || ' was not selected.' || coalesce(' Reason: ' || nullif(new.status_reason, ''), '')
        when 'Hold' then
          'Your idea ' || new.idea_id || ' was put on hold.' || coalesce(' Reason: ' || nullif(new.status_reason, ''), '')
        else null end;
      if v_msg is not null then
        insert into public.notifications (recipient_id, type, related_type, related_id, message)
        values (new.requester_id, 'Stage update', 'Idea', new.idea_id, v_msg);
      end if;
    end if;
  end if;
  return new;
end; $$;

-- 2) Décision de comité tranchée -> notification au porteur de l'idée liée.
--    Les décisions générées par qualify_idea() ('Qualify idea…') sont
--    exclues : le porteur reçoit déjà la notification de qualification.
create or replace function public.on_decision_notify_requester()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
begin
  if new.related_type = 'Idea' and new.status = 'Decided' and new.outcome is not null
     and (TG_OP = 'INSERT' or old.status is distinct from new.status or old.outcome is distinct from new.outcome)
     and new.title not like 'Qualify idea%'
  then
    select * into v_idea from public.ideas where idea_id = new.related_id;
    if found then
      insert into public.notifications (recipient_id, type, related_type, related_id, message)
      values (v_idea.requester_id, 'Committee decision', 'Idea', v_idea.idea_id,
        'Committee decision for your idea ' || v_idea.idea_id || ': ' || new.outcome
        || coalesce(' - ' || nullif(new.decision_notes, ''), '')
        || ' (' || new.committee_target || ')');
    end if;
  end if;
  return new;
end; $$;
create or replace trigger t_dec_notify_requester after insert or update on public.decisions
  for each row execute function public.on_decision_notify_requester();

-- 3) Commentaire sur une idée -> notification au porteur et à l'owner
--    (jamais à l'auteur du commentaire, pas de doublon)
create or replace function public.on_comment_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
  v_who text;
begin
  if new.kind <> 'comment' or new.related_type <> 'Idea' then return new; end if;
  select * into v_idea from public.ideas where id = new.related_id;
  if not found then return new; end if;
  select name into v_who from public.profiles where id = new.user_id;

  if v_idea.requester_id is distinct from new.user_id then
    insert into public.notifications (recipient_id, type, related_type, related_id, message)
    values (v_idea.requester_id, 'New comment', 'Idea', v_idea.idea_id,
      coalesce(v_who, 'Someone') || ' commented on your idea ' || v_idea.idea_id || ': ' || left(new.message, 160));
  end if;
  if v_idea.owner_id is not null
     and v_idea.owner_id is distinct from new.user_id
     and v_idea.owner_id is distinct from v_idea.requester_id then
    insert into public.notifications (recipient_id, type, related_type, related_id, message)
    values (v_idea.owner_id, 'New comment', 'Idea', v_idea.idea_id,
      coalesce(v_who, 'Someone') || ' commented on idea ' || v_idea.idea_id || ': ' || left(new.message, 160));
  end if;
  return new;
end; $$;
create or replace trigger t_comment_notify after insert on public.activity
  for each row execute function public.on_comment_notify();

-- 4) Notification (et email via l'edge function) de bienvenue à l'inscription
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email);
  insert into public.notifications (recipient_id, type, message)
  values (new.id, 'Welcome',
    'Welcome to Digital Pulse! Submit your idea in about 5 minutes, then track its progress here - you will be notified at every step.');
  return new;
end; $$;
