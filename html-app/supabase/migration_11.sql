-- Harmonized BC / Project Charter visibility and ownership.
-- Run after migration_10.sql.

create or replace function public.can_read_project_deliverables(p_idea uuid, p_smartsheet_project_id text)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
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
      and (i.id = p_idea or p.project_id = p_smartsheet_project_id)
    ), false
  )
$$;

revoke all on function public.can_read_project_deliverables(uuid, text) from public;
grant execute on function public.can_read_project_deliverables(uuid, text) to authenticated;

drop policy if exists ideas_project_lead_select on public.ideas;
create policy ideas_project_lead_select on public.ideas for select to authenticated
  using (public.can_read_project_deliverables(id, null));

drop policy if exists bc_project_lead_select on public.business_cases;
create policy bc_project_lead_select on public.business_cases for select to authenticated
  using (public.can_read_project_deliverables(idea_id, null));

drop policy if exists ch_project_lead_select on public.project_charters;
create policy ch_project_lead_select on public.project_charters for select to authenticated
  using (public.can_read_project_deliverables(idea_id, smartsheet_project_id));

-- Idea Owners retain visibility but the Digital Transformation Team owns these governance documents.
drop policy if exists bc_requester_update on public.business_cases;
drop policy if exists ch_requester_update on public.project_charters;

-- The Digital Transformation Team prepares the decision kit. Idea Owners are
-- informed and consulted, but are no longer instructed to author governance documents.
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
