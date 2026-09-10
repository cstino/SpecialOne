-- ============================================================
--  BADGE DI CRESCITA ANCHE PER I PROSPETTI IN VIVAIO
--
--  Richiesta dell'utente il 9 settembre 2026, come seguito diretto del
--  badge gia' aggiunto alla rosa vera (20260909100000): i prospetti in
--  cantera crescono davvero (cresci_vivaio_checkpoint, ogni trimestre di
--  stagione) ma quella crescita non si vedeva da nessuna parte.
--
--  DIFFERENZA CHIAVE rispetto alla rosa vera
--  player_instances ha una propria colonna overall_corrente: il valore
--  cresce li', il catalogo public.players resta intatto. I prospetti
--  vivaio invece non hanno una riga propria con l'overall — leggono
--  direttamente players.overall, e cresci_vivaio_checkpoint MUTA quella
--  riga sul catalogo. E' sicuro solo perche' un prospetto vivaio
--  (origine_vivaio) appartiene sempre e solo a una lega, mai condiviso
--  (vedi 20260901070000_vivaio_mercato_under.sql) — ma significa anche che
--  non esiste alcuno storico: una volta cresciuto, il valore di partenza
--  e' perso per sempre, a meno di conservarlo a parte.
--
--  Stessa soluzione della rosa vera, stessa forma: due trigger, nessuna
--  funzione esistente riscritta.
--    1. Alla creazione del prospetto (vinta l'asta UNDER), si registra
--       l'overall di quel momento.
--    2. Alla nascita di una stagione, si riazzera per tutti i prospetti
--       ancora in cantera. Riuso il trigger seasons_azzera_overall_inizio
--       gia' esistente, estendendo la funzione che richiama invece di
--       aggiungerne uno nuovo: e' letteralmente lo stesso evento
--       ("la stagione X e' appena nata"), stesso significato per la rosa
--       vera e per il vivaio.
--
--  BACKFILL
--  Non ricostruibile con la stessa esattezza della rosa vera. La rosa vera
--  ha un catalogo che NON viene toccato da chi gioca (solo da
--  applica_progressione_trimestrale sulle istanze), quindi il valore
--  originale sopravvive fino al primo checkpoint. Qui invece il catalogo
--  stesso e' il valore mutato: se un checkpoint e' gia' passato, il dato
--  di partenza non esiste piu' da nessuna parte. Verificato: in Serie F 6
--  prospetti su 8 sono nati prima del checkpoint del 6 settembre, quindi
--  gia' cresciuti almeno una volta.
--  Si prende quindi l'unica strada onesta, la stessa gia' usata per i
--  giocatori di origine vivaio nella migrazione della rosa vera: si parte
--  da oggi. Il badge sara' silenzioso finche' non arriva il prossimo
--  checkpoint, poi esatto per sempre in avanti.
-- ============================================================

begin;

alter table public.vivaio_prospetti
  add column overall_inizio_stagione smallint;

comment on column public.vivaio_prospetti.overall_inizio_stagione is
  'Overall del prospetto (letto da players.overall) al momento in cui e'' entrato in '
  'cantera, o all''inizio della stagione corrente se gia'' presente. Serve al badge di '
  'crescita, stessa logica di player_instances.overall_inizio_stagione. Riportato al '
  'valore corrente alla nascita di ogni stagione dallo stesso trigger su seasons.';

-- ------------------------------------------------------------
--  1. Ogni nuovo prospetto nasce con il proprio riferimento.
-- ------------------------------------------------------------
create or replace function private.imposta_overall_inizio_vivaio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.overall_inizio_stagione is null then
    select overall into new.overall_inizio_stagione
    from public.players where id = new.player_id;
  end if;
  return new;
end;
$$;

create trigger vivaio_prospetti_overall_inizio
before insert on public.vivaio_prospetti
for each row execute function private.imposta_overall_inizio_vivaio();

-- ------------------------------------------------------------
--  2. A ogni nuova stagione il riferimento riparte da zero, per i
--     prospetti come per la rosa vera. Si estende la funzione gia'
--     agganciata a seasons, non se ne aggiunge una seconda: e' lo stesso
--     evento con lo stesso significato per entrambe le tabelle.
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

  update public.vivaio_prospetti vp
  set overall_inizio_stagione = p.overall
  from public.players p
  where p.id = vp.player_id
    and vp.league_id = new.league_id
    and vp.overall_inizio_stagione is distinct from p.overall;

  return new;
end;
$$;

-- ------------------------------------------------------------
--  3. Backfill: si parte da oggi, per il motivo spiegato in testa al file.
-- ------------------------------------------------------------
update public.vivaio_prospetti vp
set overall_inizio_stagione = p.overall
from public.players p
where p.id = vp.player_id
  and vp.overall_inizio_stagione is null;

alter table public.vivaio_prospetti
  alter column overall_inizio_stagione set not null;

commit;
