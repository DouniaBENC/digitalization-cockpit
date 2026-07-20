-- ============================================================
-- Migration 4 : enrichissement du pré-remplissage des BC/Charters
-- existants depuis l'idée parente (les valeurs déjà saisies gagnent).
-- Ré-exécutable sans risque.
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
