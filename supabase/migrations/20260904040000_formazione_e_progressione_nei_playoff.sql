-- ============================================================
--  PLAYOFF BLOCCATI: "Giornata non valida per questa lega".
--
--  Segnalato dall'utente su LegaBot, arrivata ai playoff: salvando la
--  formazione compariva "Giornata non valida per questa lega".
--
--  Causa: playoff e playout vivono a giornate OLTRE la stagione
--  regolare. Con 16 squadre la regolare arriva alla 30 e i playoff
--  stanno alla 31 e alla 32, ma due funzioni rifiutavano per principio
--  qualunque giornata maggiore di leagues.giornate_totali:
--
--  1) public.salva_formazione — il bug visibile: impossibile schierare
--     la squadra proprio nelle partite decisive. Ora accetta anche una
--     giornata piu' alta, a patto che esista davvero come turno della
--     stagione in corso (quindi niente giornate inventate).
--
--  2) public.applica_progressione_trimestrale — molto piu' grave, e non
--     ancora visibile: il cron notturno la chiama a OGNI giornata
--     simulata, playoff compresi, e l'edge function propaga l'errore.
--     Verificato chiamandola davvero con la giornata 31 di LegaBot:
--     "Giornata non valida per la progressione overall". La simulazione
--     della prima giornata di playoff sarebbe fallita stanotte, dopo
--     aver gia' registrato le partite. Qui il limite superiore si toglie
--     del tutto: i quattro checkpoint sono ancorati a frazioni della
--     stagione regolare, quindi oltre la 30 il ciclo li trova gia'
--     applicati e non fa nulla — che e' il comportamento corretto.
--
--  Perche' non era mai emerso: nella stagione 2 di LegaBot i playoff
--  cadevano alle giornate 15-19, sotto il valore di leagues.giornate_totali
--  in vigore allora. La stagione 3 e' la prima in cui la regolare occupa
--  per intero le giornate disponibili e i playoff le superano.
--
--  Corpi ri-fetchati dal vivo con pg_get_functiondef; in entrambi cambia
--  solo il controllo sulla giornata.
-- ============================================================

begin;

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_all bigint[];
  v_convocati bigint[];
  v_rosa_count integer;
  v_unique_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare la formazione.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La stagione non e'' ancora iniziata.';
  end if;
  -- Playoff e playout vivono a giornate OLTRE la stagione regolare (con 16
  -- squadre: regolare fino alla 30, playoff 31 e 32), quindi il confronto
  -- con giornate_totali da solo rendeva impossibile schierare la formazione
  -- proprio nelle partite decisive. Si accetta anche una giornata piu' alta,
  -- purche' esista davvero come turno di questa stagione.
  if p_giornata < 1 or (
    p_giornata > v_league.giornate_totali
    and not exists (
      select 1
      from public.fixtures f
      join public.seasons s on s.id = f.season_id
      where s.league_id = p_league_id
        and s.numero = v_league.stagione_corrente
        and f.giornata = p_giornata
    )
  ) then
    raise exception using errcode = '22023', message = 'Giornata non valida per questa lega.';
  end if;
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_gioco = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  if coalesce(cardinality(p_titolari), 0) <> 11 then
    raise exception using errcode = '22023', message = 'Servono esattamente 11 titolari.';
  end if;
  if coalesce(cardinality(p_panchina), 0) > 9 then
    raise exception using errcode = '22023', message = 'La panchina puo'' contenere al massimo 9 giocatori.';
  end if;
  if p_titolari[1] is null then
    raise exception using errcode = '22023', message = 'Il primo slot deve contenere il portiere, anche se di movimento.';
  end if;
  if array_position(p_titolari, null) is not null
     or array_position(p_panchina, null) is not null
     or array_position(p_tribuna, null) is not null then
    raise exception using errcode = '22023', message = 'La formazione contiene uno slot vuoto non valido.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  v_all := p_titolari || coalesce(p_panchina, '{}'::bigint[]) || coalesce(p_tribuna, '{}'::bigint[]);
  v_unique_count := (select count(distinct id)::integer from unnest(v_all) as u(id));
  if v_unique_count <> cardinality(v_all) then
    raise exception using errcode = '22023', message = 'Lo stesso giocatore compare piu'' volte nella formazione.';
  end if;

  select count(*) into v_rosa_count
  from public.player_instances
  where league_id = p_league_id and team_id = v_team.id and id = any(v_all);
  if v_rosa_count <> cardinality(v_all) then
    raise exception using errcode = '42501', message = 'La formazione contiene un giocatore fuori dalla tua rosa.';
  end if;

  v_convocati := p_titolari || coalesce(p_panchina, '{}'::bigint[]);
  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and team_id = v_team.id
      and id = any(v_convocati) and infortunato_fino_a > 0
  ) then
    raise exception using errcode = '22023', message = 'Un giocatore infortunato non puo'' essere titolare o andare in panchina. Spostalo in tribuna.';
  end if;

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now()
  )
  on conflict (team_id, giornata) do update set
    modulo = excluded.modulo,
    titolari = excluded.titolari,
    panchina = excluded.panchina,
    tribuna = excluded.tribuna,
    stile_gioco = excluded.stile_gioco,
    automatica = false,
    salvata_il = now();

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', v_team.id,
    'giornata', p_giornata,
    'modulo', p_modulo,
    'stile_gioco', p_stile_gioco,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.applica_progressione_trimestrale(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Le giornate di playoff/playout stanno OLTRE la stagione regolare (con
  -- 16 squadre: regolare fino alla 30, playoff 31 e 32). Il cron notturno
  -- chiama questa funzione a ogni giornata simulata, playoff compresi:
  -- rifiutarle faceva fallire per intero la simulazione della prima
  -- giornata di playoff. I quattro checkpoint restano ancorati alla
  -- stagione regolare (le soglie sono frazioni di giornate_totali), quindi
  -- a giornata 31 il ciclo trova il 4o checkpoint gia' applicato e non fa
  -- nulla: e' corretto, la progressione e' gia' completa.
  if p_giornata < 1 then
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
$function$

;

commit;
