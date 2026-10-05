-- ============================================================
--  STELLE: UNA PER OGNI TITLE PLAYOFF VINTO
--  Richiesta del committente il 5 ottobre 2026: sopra lo stemma di chi vince
--  il Title Playoff compare una stella dorata, una per ogni titolo, come le
--  stelle della Juventus. Per evitare spoiler la stella si assegna solo
--  quando la lega ENTRA IN OFF-SEASON, cioe' a playoff chiusi: prima di quel
--  momento nessuno la vede, nemmeno chi ha gia' visto il risultato.
--
--  teams.titoli_title e' un contatore derivato: si ricalcola da zero dai
--  tabelloni 'title' conclusi (ogni volta lo stesso risultato, nessun rischio
--  di conteggi doppi). Conta le stagioni fino a quella appena giocata
--  (stagione_corrente in off-season, la precedente a stagione avviata).
-- ============================================================

alter table public.teams
  add column if not exists titoli_title smallint not null default 0;
comment on column public.teams.titoli_title is
  'Title Playoff vinti, assegnati all''ingresso in off-season (stelle sullo stemma). Derivato da brackets.';

create or replace function private.assegna_stelle_title(p_league_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_fino_a smallint;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then return; end if;
  v_fino_a := case when v_lega.fase_carriera = 'offseason'
                   then v_lega.stagione_corrente
                   else v_lega.stagione_corrente - 1 end;

  update public.teams t
  set titoli_title = coalesce((
    select count(*) from public.brackets b
    join public.seasons s on s.id = b.season_id
    where b.league_id = p_league_id and b.tipo = 'title' and b.stato = 'concluso'
      and b.vincitore_team_id = t.id and s.numero <= v_fino_a
  ), 0)
  where t.league_id = p_league_id;
end;
$$;

revoke all on function private.assegna_stelle_title(bigint) from public, anon, authenticated;

-- All'ingresso in off-season. Un errore qui non deve mai impedire di aprirla.
create or replace function private.stelle_all_ingresso_in_offseason()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform private.assegna_stelle_title(new.id);
  exception when others then
    raise warning 'stelle title: lega % non aggiornata: % (%)', new.id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

drop trigger if exists leagues_assegna_stelle on public.leagues;
create trigger leagues_assegna_stelle
  after update of fase_carriera on public.leagues
  for each row
  when (new.fase_carriera = 'offseason' and old.fase_carriera is distinct from 'offseason')
  execute function private.stelle_all_ingresso_in_offseason();

-- Recupero: le leghe gia' in off-season e quelle con stagioni passate.
do $$
declare v_id bigint;
begin
  for v_id in select id from public.leagues loop
    perform private.assegna_stelle_title(v_id);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
