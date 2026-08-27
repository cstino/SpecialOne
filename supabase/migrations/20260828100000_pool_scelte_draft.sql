-- ============================================================
--  MERCATO A SCELTE SCAMBIABILI — pool di una finestra
--  docs/decisioni-draft-picks.md §6 bis (deciso il 28 agosto 2026)
--
--  Il pool non e' "tutti gli svincolati overall>75": e' un'estrazione
--  dedicata alla finestra, 10 per ruolo (GK/DEF/MID/ATT) = 40 totali,
--  fatta UNA volta quando la finestra si apre e stabile finche' non si
--  risolve — altrimenti una lista di preferenze sottomessa oggi punterebbe
--  a un pool diverso da quello con cui si risolve domani.
--
--  Solo tabella + funzione di estrazione, isolate e testabili da sole.
--  Non ancora agganciate al momento reale di apertura delle finestre
--  (giornata di meta' stagione per l'ON-Season, prepara_offseason per
--  l'OFF-Season): quell'aggancio tocca funzioni gia' live ogni notte
--  (registra_risultato_partita, prepara_offseason) e va fatto con piu'
--  margine di test, e' il passo successivo insieme al motore di
--  risoluzione delle preferenze.
-- ============================================================

create table public.scelte_pool (
  id                bigint generated always as identity primary key,
  league_id         bigint not null references public.leagues(id) on delete cascade,
  stagione          smallint not null check (stagione >= 1),
  finestra          text not null check (finestra in ('on', 'off')),
  player_id         bigint not null references public.players(id),
  ingaggio_teorico  bigint not null,
  creato_il         timestamptz not null default now(),
  unique (league_id, stagione, finestra, player_id)
);

comment on table public.scelte_pool is
  'I 40 giocatori (10 per ruolo, overall>75) estratti per una finestra ON/OFF-Season. Estrazione unica, stabile per tutta la finestra. docs/decisioni-draft-picks.md §6 bis';

create index scelte_pool_finestra_idx on public.scelte_pool(league_id, stagione, finestra);

alter table public.scelte_pool enable row level security;

create policy scelte_pool_lettura on public.scelte_pool
  for select to authenticated
  using ((select private.e_membro(league_id)));

-- ------------------------------------------------------------
--  Estrazione: stesso principio di private.estrai_svincolati_lega
--  (partizione per ruolo, ordine casuale, primi N per partizione), ma
--  overall>75 invece del flag disponibile_estrazione da solo, e senza
--  tornate: una sola estrazione per finestra. Idempotente — se la
--  finestra ha gia' il suo pool non lo tocca (on conflict do nothing +
--  controllo preventivo, cosi' il risultato riporta 0 senza generare
--  righe parziali se la finestra e' gia' popolata a meta').
-- ------------------------------------------------------------
create or replace function private.estrai_pool_scelte(
  p_league_id bigint,
  p_stagione smallint,
  p_finestra text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_creati integer := 0;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if exists (select 1 from public.scelte_pool where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra) then
    return 0;
  end if;

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.disponibile_estrazione
      and p.overall > 75
      and (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
      and private.macro_ruolo(p.posizioni) in ('GK', 'DEF', 'MID', 'ATT')
      and not exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = p.id and pi.team_id is not null
      )
      and not exists (
        select 1 from public.retired_players rp
        where rp.league_id = p_league_id and rp.player_id = p.id
      )
  ), ranked as (
    select id, macro, row_number() over (partition by macro order by random()) as rn from disponibili
  ), scelti as (
    select id from ranked where rn <= 10
  )
  insert into public.scelte_pool (league_id, stagione, finestra, player_id, ingaggio_teorico)
  select p_league_id, p_stagione, p_finestra, p.id, private.ingaggio_teorico(p.overall, p.eta)
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$$;

comment on function private.estrai_pool_scelte(bigint, smallint, text) is
  '10 giocatori per ruolo (overall>75, liberi) per il pool di una finestra ON/OFF-Season. Idempotente: non ritocca una finestra gia'' estratta.';

revoke all on function private.estrai_pool_scelte(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.estrai_pool_scelte(bigint, smallint, text) to service_role;
