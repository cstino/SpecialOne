-- ============================================================
--  RIPRISTINO: progressione svincolati e bonus TRAINING cancellati per
--  errore il 3 settembre 2026.
--
--  Le migrazioni 20260903000000 e 20260903010000 (pavimento minutaggio
--  giovani + eccezione vivaio<17) hanno riscritto applica_progressione_
--  trimestrale ripartendo da una versione PRECEDENTE al 30 agosto e al
--  1 settembre, senza ri-fetchare il corpo live prima di sostituirlo —
--  esattamente l'errore che la pratica di questa sessione dovrebbe
--  evitare. Il risultato, scoperto indagando una segnalazione
--  sull'overall degli svincolati nel mercato:
--
--  1) Il blocco che fa evolvere free_agent_progression (chi non e' mai
--     stato scelto in questa lega, aggiunto il 30 agosto) e' sparito.
--     Verificato: max(aggiornato_il) su TUTTA la tabella, tutte le
--     leghe, e' fermo al 3 settembre 06:08 UTC — la progressione degli
--     svincolati e' congelata ovunque da quel momento.
--  2) Il join "join public.teams t on t.id = pi.team_id and t.attiva"
--     e' ricomparso sulla query di player_instances: uno svincolato
--     REALE (player_instances con team_id nullo) smette di evolvere,
--     esattamente il problema che il 30 agosto era stato tolto apposta.
--  3) Il bonus del reparto TRAINING (moltiplicatore_crescita, aggiunto
--     il 1 settembre) e' sparito dalla crescita di player_instances.
--
--  Questa migrazione rimette tutti e tre, mantenendo le due correzioni
--  legittime del 3 settembre (pavimento 0.85 invece di 0.8 per i <=22,
--  eccezione vivaio<17 a moltiplicatore 1.0 fisso).
-- ============================================================

create or replace function public.applica_progressione_trimestrale(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_player record;
  v_delta numeric;
  v_moltiplicatore numeric;
  v_valore numeric;
  v_ovr smallint;
  v_residuo numeric;
  v_checkpoint_applicati smallint[] := array[]::smallint[];
  v_giocatori_aggiornati integer := 0;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    raise exception using errcode = '55000', message = 'Non esiste una stagione in corso per la progressione overall.';
  end if;
  if p_giornata < 1 or p_giornata > v_lega.giornate_totali then
    raise exception using errcode = '22023', message = 'Giornata non valida per la progressione overall.';
  end if;
  v_stagione_id := v_lega.season_id;

  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_progression_checkpoints(league_id, season_id, checkpoint, giornata)
    values (p_league_id, v_stagione_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;
    if not found then
      continue;
    end if;

    -- Chi ha (o ha avuto) una squadra: player_instances. NESSUN join sulla
    -- squadra attiva (deciso il 30 agosto 2026): uno svincolato reale
    -- (team_id nullo) evolve esattamente come chi gioca, solo al ritmo
    -- minimo perche' minuti_giocati resta 0. Uno svincolato non ha un
    -- moltiplicatore_training (nessuna squadra): coalesce a 1.
    for v_player in
      select
        pi.id, pi.overall_corrente, pi.eta_corrente, pi.progressione_residuo, p.potential, p.origine_vivaio,
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate,
        coalesce((
          select (private.effetti_ramo('training', tr.livello_training)->>'moltiplicatore_crescita')::numeric
          from public.team_risorse tr
          where tr.team_id = pi.team_id
        ), 1) as moltiplicatore_training
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- Pavimento standard: 0.8x a zero minuti, 1.4x a minutaggio pieno.
      v_moltiplicatore := 0.8 + 0.6 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));

      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / 4.0;
        if v_player.origine_vivaio and v_player.eta_corrente < 17 then
          -- Appena usciti dall'academy: ritmo pieno fisso, ne' premiato ne'
          -- penalizzato dal minutaggio, finche' non compiono 17 anni.
          v_moltiplicatore := 1.0;
        else
          -- <=22 anni ma non piu' "appena usciti dal vivaio" (o mai stati
          -- in vivaio): pavimento 0.85, non 0.8 — il minutaggio conta
          -- ancora davvero, solo un po' meno spietato per chi e' in
          -- panchina dietro un titolare fisso.
          v_moltiplicatore := 0.85 + 0.55 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));
        end if;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_delta := v_delta * v_moltiplicatore;

      -- TRAINING allena, non fa invecchiare piu' in fretta: il bonus vale
      -- solo sulla crescita vera, mai sul declino.
      if v_delta > 0 then
        v_delta := v_delta * v_player.moltiplicatore_training;
      end if;

      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.player_instances
      set overall_corrente = v_ovr, progressione_residuo = v_residuo
      where id = v_player.id;
      v_giocatori_aggiornati := v_giocatori_aggiornati + 1;
    end loop;

    -- Chi non e' mai stato scelto in questa lega: free_agent_progression.
    -- Stessa formula per fascia d'eta' e stesso residuo frazionario di
    -- player_instances (senza, un delta minuscolo arrotondava a zero ogni
    -- trimestre e andava perso). Moltiplicatore fisso al minimo (0.8): non
    -- hanno mai la possibilita' di giocare un minuto, quindi restano
    -- sempre alla velocita' piu' bassa della curva, mai a zero. Nessun
    -- bonus TRAINING: non hanno una squadra.
    for v_player in
      select fap.league_id, fap.player_id, fap.overall_corrente, fap.eta_corrente,
             fap.progressione_residuo, p.potential
      from public.free_agent_progression fap
      join public.players p on p.id = fap.player_id
      where fap.league_id = p_league_id
      for update of fap
    loop
      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / 4.0;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_delta := v_delta * 0.8;
      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.free_agent_progression
      set overall_corrente = v_ovr, progressione_residuo = v_residuo, aggiornato_il = now()
      where league_id = v_player.league_id and player_id = v_player.player_id;
    end loop;

    v_checkpoint_applicati := array_append(v_checkpoint_applicati, v_step);
    exit;
  end loop;

  return jsonb_build_object(
    'checkpoint_applicati', v_checkpoint_applicati,
    'giocatori_aggiornati', v_giocatori_aggiornati
  );
end;
$$;
