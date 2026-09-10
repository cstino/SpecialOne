-- ============================================================
--  RIFERIMENTO DI INIZIO STAGIONE ANCHE PER GLI SVINCOLATI DEL POOL
--
--  Terzo e ultimo pezzo del badge di crescita, dopo la rosa
--  (20260909100000) e il vivaio (20260910100000). Serve alla pagina Draft:
--  i giocatori del pool non sono in nessuna rosa, quindi il loro overall
--  vero vive in free_agent_progression, che finora non conservava alcun
--  valore di partenza.
--
--  Stesso schema delle altre due tabelle, per non inventare un terzo modo:
--    - un trigger alla creazione della riga registra l'overall del momento;
--    - il trigger gia' agganciato a public.seasons (che azzerava rosa e
--      vivaio) viene esteso a questa terza tabella. E' sempre lo stesso
--      evento — "la stagione X e' appena nata" — e tenerlo in un solo punto
--      evita di doversi ricordare, alla prossima tabella, che i punti da
--      aggiornare erano tre.
--
--  BACKFILL, ricostruito dove e' esatto. In una lega alla prima stagione
--  free_agent_progression parte da players.overall e da li' evolve, mentre
--  il catalogo resta fermo (lo modifica solo la crescita del vivaio, e solo
--  per i giocatori origine_vivaio). Per quelle leghe, quindi,
--  players.overall E' il valore d'inizio stagione, non una stima. Per le
--  altre si parte da oggi, come gia' fatto per rosa e vivaio.
-- ============================================================

begin;

alter table public.free_agent_progression
  add column overall_inizio_stagione smallint;

comment on column public.free_agent_progression.overall_inizio_stagione is
  'Overall dello svincolato all''inizio della stagione corrente. Serve al badge di '
  'crescita nella pagina Draft, stessa logica di player_instances e vivaio_prospetti.';

-- ------------------------------------------------------------
--  1. Ogni nuova riga nasce con il proprio riferimento.
-- ------------------------------------------------------------
create or replace function private.imposta_overall_inizio_pool()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.overall_inizio_stagione is null then
    new.overall_inizio_stagione := new.overall_corrente;
  end if;
  return new;
end;
$$;

create trigger free_agent_progression_overall_inizio
before insert on public.free_agent_progression
for each row execute function private.imposta_overall_inizio_pool();

-- ------------------------------------------------------------
--  2. Azzeramento a inizio stagione: si estende il trigger unico.
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

  update public.free_agent_progression
  set overall_inizio_stagione = overall_corrente
  where league_id = new.league_id
    and overall_inizio_stagione is distinct from overall_corrente;

  return new;
end;
$$;

-- ------------------------------------------------------------
--  3. Backfill.
-- ------------------------------------------------------------
update public.free_agent_progression fap
set overall_inizio_stagione = p.overall
from public.players p, public.leagues l
where p.id = fap.player_id
  and l.id = fap.league_id
  and fap.overall_inizio_stagione is null
  and l.stagione_corrente = 1
  and not p.origine_vivaio;

update public.free_agent_progression
set overall_inizio_stagione = overall_corrente
where overall_inizio_stagione is null;

alter table public.free_agent_progression
  alter column overall_inizio_stagione set not null;

commit;
