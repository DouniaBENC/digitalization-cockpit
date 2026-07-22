-- Weekly Pulse governance workflow.
-- Run after migration_12.sql.

alter table public.project_updates
  add column if not exists system_health_status text
    check (system_health_status in ('Green','Amber','Red')),
  add column if not exists system_progress_percent integer
    check (system_progress_percent between 0 and 100),
  add column if not exists system_health_reasons text[] not null default '{}',
  add column if not exists current_milestone text,
  add column if not exists current_milestone_date date,
  add column if not exists rag_override_reason text,
  add column if not exists blocker_owner text,
  add column if not exists blocker_due_date date,
  add column if not exists action_owner text,
  add column if not exists action_due_date date,
  add column if not exists support_recipient text
    check (support_recipient in ('Program Manager','Digital Transformation Team')),
  add column if not exists support_due_date date,
  add column if not exists decision_required boolean not null default false,
  add column if not exists review_status text not null default 'Submitted'
    check (review_status in ('Submitted','Reviewed','Action required','Escalated')),
  add column if not exists review_note text,
  add column if not exists reviewed_by uuid references public.profiles(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists escalated_decision_id uuid references public.decisions(id),
  add column if not exists revision integer,
  add column if not exists supersedes_update_id uuid references public.project_updates(id);

with ranked as (
  select id,
    row_number() over (
      partition by project_ref, update_week
      order by created_at, id
    ) as revision_number
  from public.project_updates
)
update public.project_updates u
set revision = ranked.revision_number
from ranked
where ranked.id = u.id and u.revision is null;

alter table public.project_updates alter column revision set default 1;
alter table public.project_updates alter column revision set not null;

create unique index if not exists project_updates_week_revision_uidx
  on public.project_updates(project_ref, update_week, revision);

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

  new.revision := coalesce((
    select max(revision) + 1
    from public.project_updates
    where project_ref = new.project_ref and update_week = new.update_week
  ), 1);
  new.supersedes_update_id := coalesce(new.supersedes_update_id, v_previous);
  return new;
end; $$;

drop trigger if exists t_project_updates_revision on public.project_updates;
create trigger t_project_updates_revision
  before insert on public.project_updates
  for each row execute function public.set_project_update_revision();

create or replace function public.on_project_update_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_project public.projects%rowtype;
begin
  select * into v_project from public.projects where id = new.project_ref;
  if new.health_status in ('Amber','Red')
     or nullif(new.support_needed, '') is not null
     or new.decision_required then
    perform public.notify_pm_tt(
      'Weekly Pulse', 'Project', v_project.project_id,
      v_project.project_name || ': ' || new.health_status ||
      case when new.decision_required then ' - decision requested'
           when nullif(new.support_needed, '') is not null then ' - support requested'
           else '' end
    );
  end if;
  return new;
end; $$;

drop trigger if exists t_project_updates_notify on public.project_updates;
create trigger t_project_updates_notify
  after insert on public.project_updates
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
    insert into public.decisions (
      title, related_type, related_id, owner_id, committee_target,
      due_date, impact, status, next_action, next_steerco
    ) values (
      coalesce(nullif(p_decision_title, ''), 'Resolve Weekly Pulse escalation - ' || v_project.project_id),
      'Project', v_project.project_id, auth.uid(), p_committee,
      p_due_date,
      concat_ws(E'\n', nullif(v_update.blockers, ''), nullif(v_update.support_needed, '')),
      'Escalated', coalesce(nullif(p_note, ''), 'Review and resolve the Weekly Pulse escalation.'), true
    ) returning id into v_decision;
  end if;

  update public.project_updates
  set review_status = v_review_status,
      review_note = nullif(p_note, ''),
      reviewed_by = auth.uid(),
      reviewed_at = now(),
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

  return jsonb_build_object(
    'update_id', p_update,
    'review_status', v_review_status,
    'decision_id', v_decision
  );
end; $$;

revoke all on function public.review_project_update(uuid, text, text, boolean, text, text, date) from public;
grant execute on function public.review_project_update(uuid, text, text, boolean, text, text, date) to authenticated;
