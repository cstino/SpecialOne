-- ============================================================
--  SCHEMI: le due card restano ferme al loro posto
--  docs/decisioni-tattiche.md punto 41 (revisione del 4 ottobre 2026)
--
--  La tabella distingue lo schema ATTIVO dalla RISERVA, e quando si attiva
--  la riserva i due si scambiano: la card di sinistra mostrava sempre
--  l'attivo, quindi le card si scambiavano di posto. Il committente vuole
--  le card ferme e solo l'etichetta "Attivo" che si sposta. Serve ricordare
--  da che lato sta lo schema attivo, sul database perche' la squadra si puo'
--  aprire da un altro dispositivo. Solo estetica: il motore non lo legge.
-- ============================================================

alter table public.schemi_squadra
  add column if not exists attivo_a_destra boolean not null default false;

comment on column public.schemi_squadra.attivo_a_destra is
  'Lato della card dello schema attivo nella Formazione (false = sinistra). Solo interfaccia.';

create or replace function public.imposta_lato_schemi(p_league_id bigint, p_attivo_a_destra boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team_id bigint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per salvare gli schemi.';
  end if;
  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;
  update public.schemi_squadra
  set attivo_a_destra = coalesce(p_attivo_a_destra, false), aggiornato_il = now()
  where team_id = v_team_id;
end;
$$;

revoke all on function public.imposta_lato_schemi(bigint, boolean) from public, anon;
grant execute on function public.imposta_lato_schemi(bigint, boolean) to authenticated;
