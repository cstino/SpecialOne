begin;

-- ============================================================
--  POOL DELLE FINESTRE (ON/OFF-Season) DA 40 A 23 GIOCATORI
--
--  Deciso il 30 agosto 2026, in conversazione con l'utente. Il pool di
--  una finestra ON/OFF-Season (docs/decisioni-draft-picks.md §6 bis) era
--  10 giocatori per ruolo (GK/DEF/MID/ATT) = 40 totali. Ora e' 5
--  portieri e 6 per ciascuno degli altri tre ruoli = 23 totali.
-- ============================================================

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
    select id from ranked
    where (macro = 'GK' and rn <= 5) or (macro <> 'GK' and rn <= 6)
  )
  insert into public.scelte_pool (league_id, stagione, finestra, player_id, ingaggio_teorico)
  select p_league_id, p_stagione, p_finestra, p.id, private.ingaggio_teorico(p.overall, p.eta)
  from public.players p join scelti s on s.id = p.id;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$$;

comment on function private.estrai_pool_scelte(bigint, smallint, text) is
  '5 portieri e 6 per ciascun altro ruolo (overall>75, liberi) per il pool di una finestra ON/OFF-Season: 23 totali. Idempotente: non ritocca una finestra gia'' estratta.';

comment on table public.scelte_pool is
  'I 23 giocatori (5 portieri, 6 per ciascun altro ruolo, overall>75) estratti per una finestra ON/OFF-Season. Estrazione unica, stabile per tutta la finestra. docs/decisioni-draft-picks.md §6 bis';

commit;
