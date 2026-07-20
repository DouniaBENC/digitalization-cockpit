-- ============================================================
-- Migration 3 : Lean Business Case & Project Charter templates
-- Contenu structuré en jsonb + remapping de la génération v0.
-- Ré-exécutable sans risque.
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

-- v0 générée avec la structure lean (answer-first) + kit porteur
create or replace function public.qualify_idea(p_idea uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_idea public.ideas%rowtype;
  v_bc uuid; v_ch uuid; v_dec uuid;
begin
  if not public.is_pm_or_tt() then
    raise exception 'Only Program Manager / Transformation Team can qualify ideas';
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
    'Your idea ' || v_idea.idea_id || ' has been qualified! Please complete your Business Case v0 and Project Charter v0 from the idea page.');

  return jsonb_build_object('business_case_id', v_bc, 'charter_id', v_ch, 'decision_id', v_dec);
end; $$;
