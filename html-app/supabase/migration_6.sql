-- ============================================================
-- Migration 6 — Parcours porteur d'idée (issues GitHub #1 et #19)
-- Notifications au requester à chaque étape + décision comité +
-- commentaires + notification de bienvenue à l'inscription.
-- Idempotente : ré-exécutable sans risque sur la base existante.
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
          'Your idea ' || new.idea_id || ' is now being reviewed by the Transformation Team.'
        when 'L2 BC/Charter' then
          'Your idea ' || new.idea_id || ' moved to preparation (L2). Please complete your Business Case and Project Charter from the idea page.'
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
    'Welcome to the Digitalization Program Cockpit! Submit your idea in about 5 minutes, then track its progress here - you will be notified at every step.');
  return new;
end; $$;
