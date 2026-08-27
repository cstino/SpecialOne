-- ============================================================
--  MERCATO DI EMERGENZA: L'ESTRAZIONE PESCA SOLO SOTTO 75
--  docs/decisioni-draft-picks.md §3.3 e §6 ("confine 75 overall")
--
--  Il confine era applicato da un lato solo: estrai_pool_scelte filtra
--  overall > 75 (20260828100000), ma l'estrazione giornaliera pescava
--  ancora da tutti i disponibili. I due mercati si sovrapponevano, e la
--  sovrapposizione e' dannosa in modo specifico: un giocatore sopra 75
--  poteva finire sia nel pool di una finestra sia in un'asta a busta
--  chiusa, e chi se lo aggiudicava all'asta lo sottraeva a una finestra
--  gia' aperta — con le liste di preferenze gia' sottomesse su un pool
--  che cambiava sotto ai piedi delle squadre. §6 bis vuole che il pool
--  resti stabile per tutta la finestra.
--
--  Base: la versione di 20260827170000_rimuove_spin_offseason.sql, che e'
--  quella viva (include i rilasci in coda ed elimina il riferimento a
--  offseason_spins). L'unica differenza e' la riga `p.overall <= 75`.
--
--  NOTA — i rilasci in coda NON sono filtrati, deliberatamente. Sono
--  giocatori svincolati da una squadra, garantiti in estrazione dalla
--  funzionalita' aggiunta il 27 agosto: filtrarli qui significherebbe far
--  sparire dal mercato un giocatore appena rilasciato sopra 75, e non e'
--  quello che §3.3 chiede. Se invece si vuole che anche i rilasci sopra 75
--  passino dalle finestre, e' una decisione di design da prendere e
--  scrivere, non da dedurre.
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
    select p.id, private.macro_ruolo(p.posizioni) as macro
    from public.players p
    where p.disponibile_estrazione
      -- decisioni-draft-picks §3.3: sopra 75 si passa dal mercato a scelte
      and p.overall <= 75
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
    select id, macro, row_number() over (partition by macro order by random()) as rn from disponibili
  ), scelti as (
    select id from ranked where rn <= v_per_ruolo
  )
  insert into public.free_agent_auctions
    (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
  select p_league_id, p_giorno, p.id,
         private.ingaggio_teorico(p.overall, p.eta), 'estrazione', v_tornata
  from public.players p join scelti s on s.id = p.id;

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
  'Estrazione giornaliera del mercato di emergenza. Il sorteggio pesca solo overall <= 75: sopra quella soglia si passa dal mercato a scelte (docs/decisioni-draft-picks.md §3.3). I rilasci in coda entrano comunque, a qualunque overall.';

revoke all on function private.estrai_svincolati_lega(bigint, date) from public, anon, authenticated;
grant execute on function private.estrai_svincolati_lega(bigint, date) to service_role;
