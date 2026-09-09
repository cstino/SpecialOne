-- ============================================================
--  DELTA DI CRESCITA STAGIONALE DEL GIOCATORE
--
--  Richiesta dei partecipanti, riportata dall'utente il 9 settembre 2026:
--  nella rosa, accanto all'overall, un numeretto verde o rosso che dica di
--  quanto il giocatore e' migliorato o peggiorato DA INIZIO STAGIONE. Si
--  azzera a ogni nuova stagione, e se non c'e' variazione non si mostra
--  nulla.
--
--  Il dato non esisteva: applica_progressione_trimestrale sovrascrive
--  overall_corrente e nessuna tabella conserva il valore di partenza. Serve
--  quindi una colonna, riportata al valore corrente all'inizio di ogni
--  stagione.
--
--  QUANDO VIENE SCRITTA — due trigger, nessuna funzione riscritta
--  1. Alla creazione di ogni istanza. Trigger invece dell'elenco delle
--     INSERT perche' i punti che creano un player_instances sono molti
--     (draft, aste svincolati, promozione dal vivaio, completamento rose in
--     off-season, scambi) e dimenticarne uno avrebbe lasciato istanze senza
--     riferimento, con il badge muto e nessun errore a segnalarlo.
--  2. Alla nascita di una stagione, agganciandosi all'INSERT su
--     public.seasons. Il punto naturale sarebbe private.inizializza_stagione,
--     dove gia' si azzera giornata_acquisizione, ma quella funzione e' lunga
--     7500 caratteri e contiene il ciclo sui gironi e tutto il blocco del
--     mercato a scelte: riscriverla per aggiungere due righe significa
--     rischiare di perderne pezzi (e' successo il 3 settembre con
--     applica_progressione_trimestrale). Il trigger ottiene lo stesso
--     risultato — la riga in seasons nasce li' dentro, subito dopo la
--     creazione della stagione — senza toccarne una riga.
--
--  Per chi arriva a stagione in corso il riferimento e' l'overall al momento
--  dell'acquisto, non quello di inizio stagione: al primo giorno il delta e'
--  zero e il badge non compare, poi cresce col giocatore. E' l'unica lettura
--  sensata — un acquisto di gennaio non ha un "inizio stagione" in quella
--  squadra — e non richiede spiegazioni all'utente.
--
--  BACKFILL DELLA STAGIONE IN CORSO
--  Non e' una stima. Serie F e Real Fampionato sono in stagione 1 e hanno
--  applicato UN SOLO checkpoint di progressione (Serie F il 6 settembre alle
--  23:07). Per ogni istanza creata PRIMA di quel momento l'overall di
--  partenza e' ancora esattamente quello del catalogo players.overall: prima
--  del primo checkpoint nulla aveva ancora modificato ne' overall_corrente
--  ne' free_agent_progression. Per quelle istanze il riferimento e' quindi
--  ricostruito con precisione, non stimato.
--
--  Restano fuori, e partono da oggi con delta zero:
--    - le leghe oltre la prima stagione (LegaBot e' alla terza): li' il
--      catalogo non dice piu' nulla sul valore d'inizio stagione;
--    - i giocatori di origine vivaio, perche' cresci_vivaio_checkpoint muta
--      direttamente players.overall e il catalogo si e' gia' spostato;
--    - le istanze create dopo il primo checkpoint.
--  Per loro il badge misura da adesso ed e' esatto dalla stagione successiva.
-- ============================================================

begin;

alter table public.player_instances
  add column overall_inizio_stagione smallint;

comment on column public.player_instances.overall_inizio_stagione is
  'Overall del giocatore all''inizio della stagione corrente (o al suo acquisto, '
  'se e'' arrivato a stagione in corso). Serve al badge di crescita nella rosa. '
  'Riportato a overall_corrente alla nascita di ogni stagione dal trigger su seasons.';

-- ------------------------------------------------------------
--  1. Ogni nuova istanza nasce con il proprio riferimento.
-- ------------------------------------------------------------
create or replace function private.imposta_overall_inizio_stagione()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Solo se chi inserisce non l'ha gia' valorizzata di proposito.
  if new.overall_inizio_stagione is null then
    new.overall_inizio_stagione := new.overall_corrente;
  end if;
  return new;
end;
$$;

create trigger player_instances_overall_inizio
before insert on public.player_instances
for each row execute function private.imposta_overall_inizio_stagione();

-- ------------------------------------------------------------
--  2. A ogni nuova stagione il riferimento riparte da zero.
-- ------------------------------------------------------------
create or replace function private.azzera_overall_inizio_stagione()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.player_instances
  set overall_inizio_stagione = overall_corrente
  where league_id = new.league_id
    and overall_inizio_stagione is distinct from overall_corrente;
  return new;
end;
$$;

create trigger seasons_azzera_overall_inizio
after insert on public.seasons
for each row execute function private.azzera_overall_inizio_stagione();

-- ------------------------------------------------------------
--  3. Backfill, solo dove e' ricostruibile con esattezza.
-- ------------------------------------------------------------
with primo_checkpoint as (
  select s.league_id, min(c.applicato_il) as applicato_il
  from public.season_progression_checkpoints c
  join public.seasons s on s.id = c.season_id
  group by s.league_id
)
update public.player_instances pi
set overall_inizio_stagione = p.overall
from public.players p, public.leagues l
left join primo_checkpoint pc on pc.league_id = l.id
where p.id = pi.player_id
  and l.id = pi.league_id
  and pi.overall_inizio_stagione is null
  and l.stagione_corrente = 1
  and not p.origine_vivaio
  and (pc.applicato_il is null or pi.creata_il < pc.applicato_il);

-- Tutto il resto parte da oggi: nessun delta finche' non cresce davvero.
update public.player_instances
set overall_inizio_stagione = overall_corrente
where overall_inizio_stagione is null;

alter table public.player_instances
  alter column overall_inizio_stagione set not null;

commit;
