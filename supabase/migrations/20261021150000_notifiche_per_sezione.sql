-- Notifiche per sezione (richiesta del committente): ognuno sceglie, lega per lega, se ricevere tutte le notifiche,
-- solo quelle del calcio o solo quelle di BetOne (SchedOne, CasinOne, QuizOne, Album). Le notifiche escluse non vengono
-- proprio scritte: niente push e niente campanella. Di partenza 'tutte'.
alter table public.teams add column if not exists notifiche_scelta text not null default 'tutte';
do $$ begin
  alter table public.teams add constraint teams_notifiche_scelta_check check (notifiche_scelta in ('tutte', 'calcio', 'betone'));
exception when duplicate_object then null; end $$;

-- Sezione di una notifica: BetOne se porta a una pagina di BetOne o all'Album, altrimenti calcio.
create or replace function private.notifica_sezione(p_dati jsonb) returns text language sql immutable set search_path to '' as $$
  select case when coalesce(p_dati ->> 'view', '') in ('betone', 'casinone', 'quizzone', 'album') then 'betone' else 'calcio' end
$$;

create or replace function private.notifica_filtra_sezione() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.league_id is not null and exists (
       select 1 from public.teams t
        where t.league_id = new.league_id and t.user_id = new.user_id
          and t.notifiche_scelta <> 'tutte' and t.notifiche_scelta <> private.notifica_sezione(new.dati)) then
    return null;   -- sezione esclusa dall'utente: la notifica non si scrive
  end if;
  return new;
end $$;
drop trigger if exists notifications_filtra_sezione on public.notifications;
create trigger notifications_filtra_sezione before insert on public.notifications for each row execute function private.notifica_filtra_sezione();

create or replace function public.imposta_notifiche(p_league_id bigint, p_scelta text) returns text language plpgsql security definer set search_path to '' as $$
begin
  if p_scelta not in ('tutte', 'calcio', 'betone') then raise exception using errcode = '22023', message = 'Scelta non valida.'; end if;
  update public.teams set notifiche_scelta = p_scelta where league_id = p_league_id and user_id = (select auth.uid()) and attiva;
  if not found then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  return p_scelta;
end $$;
revoke all on function public.imposta_notifiche(bigint, text) from public, anon;
grant execute on function public.imposta_notifiche(bigint, text) to authenticated;
revoke all on function private.notifica_filtra_sezione() from public, anon, authenticated;
