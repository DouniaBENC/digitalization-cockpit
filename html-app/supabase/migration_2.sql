-- ============================================================
-- Migration 2 : kit porteur d'idée + audit log champ par champ
-- À exécuter dans le SQL Editor Supabase (une seule fois).
-- ============================================================

-- 1) Le porteur d'idée (requester) peut lire ET éditer le BC / Charter de SA propre idée
drop policy if exists bc_requester_select on public.business_cases;
drop policy if exists bc_requester_update on public.business_cases;
drop policy if exists ch_requester_select on public.project_charters;
drop policy if exists ch_requester_update on public.project_charters;
create policy bc_requester_select on public.business_cases for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = business_cases.idea_id and i.requester_id = auth.uid()));
create policy bc_requester_update on public.business_cases for update to authenticated
  using (exists (select 1 from public.ideas i where i.id = business_cases.idea_id and i.requester_id = auth.uid()));
create policy ch_requester_select on public.project_charters for select to authenticated
  using (exists (select 1 from public.ideas i where i.id = project_charters.idea_id and i.requester_id = auth.uid()));
create policy ch_requester_update on public.project_charters for update to authenticated
  using (exists (select 1 from public.ideas i where i.id = project_charters.idea_id and i.requester_id = auth.uid()));

-- 2) Audit log générique : chaque modification est tracée (date, utilisateur, champs modifiés)
create or replace function public.log_changes()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  changed text[];
  rid uuid;
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
  if TG_TABLE_NAME in ('business_cases','project_charters') then rid := new.idea_id; else rid := new.id; end if;
  insert into public.activity (related_type, related_id, user_id, kind, message)
  values (TG_ARGV[0], rid, auth.uid(), 'event', TG_ARGV[1] || ' updated: ' || array_to_string(changed, ', '));
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

  -- Kit porteur : notifier le requester qu'il peut compléter ses documents
  insert into public.notifications (recipient_id, type, related_type, related_id, message)
  values (v_idea.requester_id, 'Idea qualified', 'Idea', v_idea.idea_id,
    'Your idea ' || v_idea.idea_id || ' has been qualified! Please complete your Business Case v0 and Project Charter v0 from the idea page.');

  return jsonb_build_object('business_case_id', v_bc, 'charter_id', v_ch, 'decision_id', v_dec);
end; $$;
