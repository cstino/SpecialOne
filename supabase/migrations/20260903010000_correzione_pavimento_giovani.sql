-- ============================================================
--  CORREZIONE AL PAVIMENTO MINUTAGGIO PER I GIOVANI (2 settembre 2026,
--  20260903000000_crescita_vivaio_e_pavimento_giovani.sql): 0.95 era
--  troppo generoso, un giovane in panchina non deve crescere "quasi come
--  chi gioca" — il minutaggio deve continuare a pesare davvero.
--
--  Corretto con l'utente:
--   - pavimento generale <=22 anni: torna giu' a 0.85 (tetto invariato
--     1.4x, quindi la formula e' 0.85 + 0.55*quota).
--   - eccezione: chi viene dal vivaio (players.origine_vivaio, un flag
--     permanente sulla riga anche dopo la promozione) e non ha ancora
--     17 anni ha un moltiplicatore fisso 1.0x, a prescindere dal
--     minutaggio — appena usciti dall'academy restano "al massimo" al
--     ritmo pieno, ne' premiati ne' penalizzati dal tempo giocato,
--     finche' non compiono 17 anni: da li' in poi rientrano nella regola
--     generale <=22 (0.85-1.4x).
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

    for v_player in
      select
        pi.id, pi.overall_corrente, pi.eta_corrente, pi.progressione_residuo, p.potential, p.origine_vivaio,
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
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

      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.player_instances
      set overall_corrente = v_ovr, progressione_residuo = v_residuo
      where id = v_player.id;
      v_giocatori_aggiornati := v_giocatori_aggiornati + 1;
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
