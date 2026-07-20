-- ============================================================
-- Migration 5 : référentiels configurables + paramètres (panneau admin PM)
-- Ré-exécutable sans risque.
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
