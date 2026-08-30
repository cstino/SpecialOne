begin;

-- ============================================================
--  Estrazione giornaliera degli svincolati: il sorteggio generale
--  (non i rilasci in coda, che gia' leggevano pi.overall_corrente
--  correttamente) leggeva l'overall statico del catalogo anche per un
--  giocatore con una propria istanza orfana (gia' scelto e poi
--  svincolato) o tracciato come mai scelto — ignorando qualunque
--  evoluzione maturata nel frattempo. Ora preferisce, in ordine:
--  l'istanza orfana di questa lega, poi il pool tracciato, poi il
--  catalogo statico.
-- ============================================================

create or replace function private.estrai_svincolati_lega(
  p_league_id bigint,
  p_giorno    date
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_lega       public.leagues;
  v_per_ruolo  integer;
  v_tornata    integer;
  v_creati     integer := 0;
  v_dalla_coda integer := 0;
  v_asta       record;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.free_agent_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno and a.origine = 'estrazione';
  v_per_ruolo := private.svincolati_per_ruolo(p_league_id);

  with disponibili as (
    select p.id, private.macro_ruolo(p.posizioni) as macro,
           coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) as overall_attuale,
           coalesce(oi.eta_corrente, fap.eta_corrente, p.eta) as eta_attuale
    from public.players p
    left join public.player_instances oi
      on oi.league_id = p_league_id and oi.player_id = p.id and oi.team_id is null
    left join public.free_agent_progression fap
      on fap.league_id = p_league_id and fap.player_id = p.id
    where p.disponibile_estrazione
      -- decisioni-draft-picks §3.3: sopra 75 si passa dal mercato a scelte
      and coalesce(oi.overall_corrente, fap.overall_corrente, p.overall) <= 75
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
      and not exists (
        select 1 from public.free_agent_auctions a
        where a.league_id = p_league_id and a.giorno = p_giorno and a.player_id = p.id
      )
      -- I rilasci in coda non concorrono ai posti del sorteggio: entrano
      -- extra piu' sotto, garantiti.
      and not exists (
        select 1 from private.rilasci_in_coda rc
        where rc.league_id = p_league_id and rc.player_id = p.id
      )
  ), ranked as (
    select id, macro, overall_attuale, eta_attuale,
           row_number() over (partition by macro order by random()) as rn
    from disponibili
  ), scelti as (
    select id, overall_attuale, eta_attuale from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, s.id,
         private.ingaggio_teorico(s.overall_attuale, s.eta_attuale), 'estrazione', v_tornata
  from scelti s;

  get diagnostics v_creati = row_count;

  -- Rilasci in coda: entrano nella STESSA tornata appena creata, in piu'
  -- rispetto alla quota per ruolo. Solo chi e' ancora davvero libero — nel
  -- frattempo puo' essere stato ripreso da un'asta o uno scambio.
  with liberi as (
    select rc.player_id
    from private.rilasci_in_coda rc
    join public.player_instances pi
      on pi.league_id = rc.league_id and pi.player_id = rc.player_id
    where rc.league_id = p_league_id and pi.team_id is null and not pi.ritirato
  ), inseriti as (
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
    select p_league_id, p_giorno, pi.player_id,
           private.ingaggio_teorico(pi.overall_corrente, pi.eta_corrente), 'estrazione', v_tornata
    from liberi l
    join public.player_instances pi on pi.league_id = p_league_id and pi.player_id = l.player_id
    returning player_id
  )
  delete from private.rilasci_in_coda
  where league_id = p_league_id and player_id in (select player_id from inseriti);
  get diagnostics v_dalla_coda = row_count;
  v_creati := v_creati + v_dalla_coda;

  for v_asta in
    select a.id, a.ingaggio_teorico from public.free_agent_auctions a
    where a.league_id = p_league_id and a.giorno = p_giorno
  loop
    insert into private.auction_thresholds (auction_id, soglia)
    values (v_asta.id, round(v_asta.ingaggio_teorico * (0.90 + random() * 0.20)))
    on conflict (auction_id) do nothing;
  end loop;
  return v_creati;
end;
$function$;

comment on function private.estrai_svincolati_lega(bigint, date) is
  'Estrazione giornaliera del mercato di emergenza. Il sorteggio pesca solo overall <= 75 (letto dall''istanza orfana o dal pool tracciato, se esistono): sopra quella soglia si passa dal mercato a scelte (docs/decisioni-draft-picks.md §3.3). I rilasci in coda entrano comunque, a qualunque overall.';

revoke all on function private.estrai_svincolati_lega(bigint, date) from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date) to service_role;

commit;
