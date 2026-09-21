-- ============================================================
--  IL BIENNIO 15-16 ANNI NON DEVE ESSERE UNA ZONA MORTA
--
--  Segnalato dall'utente: "i giovani promossi dal vivaio non crescono piu'
--  come quando erano nel vivaio?". Misurato: e' vero, e il caso peggiore e'
--  proprio quello che capita sempre.
--
--  I promossi hanno tutti quindici anni, e per loro il moltiplicatore era
--  bloccato a 1.0. Il risultato, sui giocatori veri di Serie F:
--
--      giocatore        margine   da promosso   se fosse nel vivaio
--      Ren Mendes            39         0,390                0,764
--      Rayan Greco           35         0,350                0,627
--      Pablo Hansen          34         0,340                0,595
--      Amir Yamamoto         36         0,360                0,660
--                                       (punti di overall al giorno)
--
--  Pablo Hansen cresceva al 57% di quanto avrebbe fatto restando in cantera:
--  +10,2 a stagione invece di +17,9. Promuovere un prodigio era un
--  declassamento della crescita.
--
--  E non era colpa del minutaggio. Sotto i 17 anni il moltiplicatore e' fisso,
--  quindi Hansen a zero minuti cresce come se giocasse tutte le partite: non
--  veniva punito per non giocare, ma non poteva nemmeno essere premiato. Era
--  piu' lento del vivaio E piu' lento di un diciassettenne che gioca.
--
--  IL NUMERO. Frazione del margine chiusa in una stagione, prospetto con
--  margine 30:
--
--      nel vivaio                      +14,3     (tasso 0,475)
--      promosso 17+, gioca sempre      +12,6     (0,30 x 1,40)
--      promosso sotto i 17, PRIMA       +9,0     (0,30 x 1,00)
--      promosso sotto i 17, ADESSO     +11,7     (0,30 x 1,30)
--      promosso 17+, panchina           +7,7     (0,30 x 0,85)
--
--  1.3 e non di piu': il vivaio resta il posto dove si cresce piu' in fretta
--  finche' il margine e' grande, ed e' giusto che sia cosi' — e' una scelta
--  fra crescere in fretta e avere il giocatore in rosa. Ma la differenza torna
--  a essere un prezzo ragionevole invece di una punizione.
--
--  SUL LUNGO PERIODO NON CAMBIA IL VERDETTO, e va detto: il tasso del vivaio
--  scala col margine e quindi DECELERA man mano che il ragazzo si avvicina al
--  potenziale, mentre il promosso tiene una frazione fissa. Dalla terza
--  stagione chi gioca sorpassa comunque. Qui si corregge solo il biennio
--  iniziale, che era l'unico tratto in cui promuovere non aveva nessun senso.
--
--  Definizione ripresa integralmente dal database vivo (pg_get_functiondef):
--  cambia una riga, il resto e' quello che gira adesso.
-- ============================================================

CREATE OR REPLACE FUNCTION public.applica_progressione_trimestrale(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_stagione_id bigint;
  v_player record;
  v_delta numeric;
  v_moltiplicatore numeric;
  v_valore numeric;
  v_ovr smallint;
  v_residuo numeric;
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
  if p_giornata < 1 then
    raise exception using errcode = '22023', message = 'Giornata non valida per la progressione overall.';
  end if;
  v_stagione_id := v_lega.season_id;

  -- 10 settembre 2026, richiesta dell'utente: da qui non si aggiorna piu'
  -- una volta a quarto di stagione ma una volta per ogni giornata REALE
  -- (giornate_totali quote invece di 4), cosi' il badge di crescita nella
  -- rosa si muove sera dopo sera invece che a scatti ogni ~7-8 giornate.
  -- La formula annuale e le fasce d'eta' restano identiche: cambia solo il
  -- denominatore, da 4.0 a giornate_totali, e la cadenza con cui viene
  -- consumata. La tabella dei checkpoint resta la stessa
  -- (season_progression_checkpoints): la chiave "checkpoint" prima era il
  -- numero del quarto (1-4), ora e' il numero della giornata. Nessuna
  -- collisione possibile con i quarti gia' registrati per le stagioni in
  -- corso: la UNIQUE e' per (season_id, checkpoint), e una giornata gia'
  -- passata (dove viveva un vecchio "1", "2", "3" o "4") non torna mai
  -- indietro. Le prime giornate di ogni stagione gia' avviata hanno quindi
  -- ricevuto la crescita del vecchio schema in un'unica soluzione grossa
  -- (al raggiungimento del quarto), quelle successive la ricevono a fette
  -- quotidiane: e' una cucitura visibile una tantum nel passaggio, non un
  -- bug — la stagione non riparte e non raddoppia nulla.
  --
  -- Le giornate di playoff/playout stanno OLTRE la stagione regolare: la
  -- crescita annua e' distribuita per intero sulle giornate_totali della
  -- stagione regolare, quindi oltre quel punto non c'e' piu' nulla da
  -- applicare (senza questo controllo, il cron notturno che chiama questa
  -- funzione anche in playoff avrebbe provato a scrivere un checkpoint per
  -- giornate che non esistono nel monte crescita della stagione).
  if p_giornata > v_lega.giornate_totali then
    return jsonb_build_object('checkpoint_applicati', array[]::smallint[], 'giocatori_aggiornati', 0);
  end if;

  insert into public.season_progression_checkpoints(league_id, season_id, checkpoint, giornata)
  values (p_league_id, v_stagione_id, p_giornata, p_giornata)
  on conflict (season_id, checkpoint) do nothing;
  if not found then
    -- Questa giornata ha gia' ricevuto la sua crescita: il cron puo'
    -- rientrare piu' volte sullo stesso invio (ritentativi), qui si ferma
    -- senza rifare nulla.
    return jsonb_build_object('checkpoint_applicati', array[]::smallint[], 'giocatori_aggiornati', 0);
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
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / v_lega.giornate_totali::numeric;
        if v_player.origine_vivaio and v_player.eta_corrente < 17 then
          -- Appena usciti dall'academy: ritmo fisso, ne' premiato ne'
          -- penalizzato dal minutaggio, finche' non compiono 17 anni. A
          -- quindici anni non si gioca, e misurare un ragazzino sui minuti
          -- sarebbe solo un modo elaborato di punirlo.
          --
          -- 1.3 e NON 1.0, che era il valore precedente. Con 1.0 il biennio
          -- 15-16 anni era una zona morta: si cresceva meno che nel vivaio E
          -- meno di un diciassettenne che gioca. Misurato su Pablo Hansen
          -- (Serie F, 15 anni, margine 34): 0,340 punti al giorno da promosso
          -- contro 0,595 che avrebbe avuto restando in cantera — il 57%.
          -- Promuovere un prodigio era un declassamento della crescita, il che
          -- e' esattamente il contrario di quello che deve essere.
          --
          -- 1.3 chiude quasi tutto il divario col vivaio senza superarlo: il
          -- vivaio resta il posto dove si cresce piu' in fretta finche' il
          -- margine e' grande, ed e' giusto cosi'. Vedi la nota in fondo alla
          -- migrazione per i numeri.
          v_moltiplicatore := 1.3;
        else
          -- <=22 anni ma non piu' "appena usciti dal vivaio" (o mai stati
          -- in vivaio): pavimento 0.85, non 0.8 — il minutaggio conta
          -- ancora davvero, solo un po' meno spietato per chi e' in
          -- panchina dietro un titolare fisso.
          v_moltiplicatore := 0.85 + 0.55 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));
        end if;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / v_lega.giornate_totali::numeric;
      else
        v_delta := -(1.5 + random() * 2.5) / v_lega.giornate_totali::numeric;
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
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / v_lega.giornate_totali::numeric;
      else
        v_delta := -(1.5 + random() * 2.5) / v_lega.giornate_totali::numeric;
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

  return jsonb_build_object(
    'checkpoint_applicati', array[p_giornata],
    'giocatori_aggiornati', v_giocatori_aggiornati
  );
end;
$function$;
