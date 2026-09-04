-- ============================================================
--  IL CAMBIO RUOLO CANCELLAVA TUTTI GLI ALTRI RUOLI.
--
--  Segnalato dall'utente su K. Dembélé (LegaBot): riqualificato da RM a
--  CM, si e' ritrovato "Ruoli secondari: Nessuno". Da [RM, CAM, CM, RW]
--  era rimasto [CM].
--
--  Causa: private.completa_cambi_ruolo faceva
--    posizioni_override = array[ruolo_target]
--  cioe' SOSTITUIVA l'intero elenco invece di aggiungersi. Si perdevano
--  sia i ruoli secondari sia il vecchio ruolo primario — che e' proprio
--  quello in cui il giocatore ha giocato tutta la carriera fino a ieri.
--
--  Comportamento corretto (deciso con l'utente): il ruolo nuovo diventa
--  primario, il vecchio primario scala a secondario, gli altri secondari
--  restano. L'ordine e' significativo: posizioni[1] e' il ruolo naturale
--  per il motore (engine/engine.js, penalitaRuolo), gli altri valgono
--  come "sa giocarci" (penalita' minima). Se il ruolo target era gia'
--  fra i secondari non viene duplicato, sale soltanto in prima
--  posizione.
--
--  Backfill dei 6 cambi gia' completati (tutti su LegaBot): nessuno di
--  loro aveva un override precedente, quindi l'elenco originale e'
--  esattamente players.posizioni e la ricostruzione e' esatta, non una
--  stima.
-- ============================================================

begin;

-- Il vincolo imponeva cardinality = 1: lo schema dava per scontato che un
-- cambio ruolo collassasse il giocatore su un ruolo solo. Si allinea a
-- quello del catalogo (players_posizioni_check: da 1 a 6), cosi' l'istanza
-- puo' avere un elenco di ruoli come qualunque altro giocatore.
alter table public.player_instances
  drop constraint player_instances_posizioni_override_check;
alter table public.player_instances
  add constraint player_instances_posizioni_override_check
  check (
    posizioni_override is null
    or (cardinality(posizioni_override) between 1 and 6
        and posizioni_override <@ private.ruoli_validi())
  );

create or replace function private.completa_cambi_ruolo()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_cambio record;
  v_precedenti text[];
  v_nuove text[];
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_cambio in
      select * from public.cambi_ruolo
      where league_id = v_lega.id and completato_il is null and completa_giornata <= v_prossima
      order by id
      for update
    loop
      -- Elenco ruoli da cui si parte: l'override se il giocatore ha gia'
      -- cambiato ruolo in passato, altrimenti quello del catalogo.
      select coalesce(pi.posizioni_override, p.posizioni) into v_precedenti
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.id = v_cambio.player_instance_id;

      -- Il target va in testa (ruolo naturale), tutti gli altri lo
      -- seguono nell'ordine di prima. array_agg su zero righe torna NULL,
      -- da cui il coalesce: un giocatore con un solo ruolo resta con uno.
      -- Il taglio a 6 tiene il limite del catalogo anche dopo piu'
      -- riqualificazioni: a cadere e' sempre il ruolo piu' vecchio.
      select (array[v_cambio.ruolo_target] || coalesce(array_agg(r order by ord), '{}'::text[]))[1:6]
      into v_nuove
      from unnest(coalesce(v_precedenti, '{}'::text[])) with ordinality as u(r, ord)
      where r <> v_cambio.ruolo_target;

      update public.player_instances
      set posizioni_override = v_nuove
      where id = v_cambio.player_instance_id;

      update public.cambi_ruolo set completato_il = now() where id = v_cambio.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Riqualificazione completata',
        'Un giocatore ha completato il training: ora gioca ' || v_cambio.ruolo_target ||
        ', e conserva i ruoli precedenti come secondari.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_cambio.player_instance_id)
      )
      from public.teams t where t.id = v_cambio.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;

-- Backfill: rimette i ruoli persi ai cambi gia' completati. La condizione
-- "posizioni_override = array[ruolo_target]" identifica esattamente le
-- righe scritte dalla vecchia versione, e non tocca nulla che sia gia'
-- nella forma nuova (se il fix venisse rieseguito, non fa danni).
update public.player_instances pi
set posizioni_override = (array[cr.ruolo_target] || (
  select coalesce(array_agg(r order by ord), '{}'::text[])
  from unnest(p.posizioni) with ordinality as u(r, ord)
  where r <> cr.ruolo_target
))[1:6]
from public.cambi_ruolo cr, public.players p
where cr.player_instance_id = pi.id
  and p.id = pi.player_id
  and cr.completato_il is not null
  and pi.posizioni_override = array[cr.ruolo_target];

commit;
