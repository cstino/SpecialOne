-- ============================================================
--  LA CRESCITA DEI GIOCATORI DIVENTA GIORNALIERA, NON PIU' A QUARTI
--
--  Richiesta dell'utente il 10 settembre 2026, seguito diretto dei badge
--  di crescita aggiunti ieri (rosa: 20260909100000, vivaio: 20260910100000):
--  "possiamo mostrarli live? Cioe' giorno per giorno? Sia vivaio che
--  squadra normale".
--
--  Design doc, sezione 10.2: "L'overall viene aggiornato alla conclusione
--  di ogni quarto della stagione... Le formule annuali sotto sono
--  distribuite in quattro quote: non sono quattro progressioni complete."
--  Qui si generalizza esattamente quella frase da "quattro quote" a
--  "giornate_totali quote": la formula annuale e le fasce d'eta' restano
--  identiche, cambia solo il denominatore (da 4.0 a giornate_totali) e la
--  cadenza con cui la quota si consuma — una volta per ogni giornata reale
--  invece che una volta ogni ~7-8. design.md viene aggiornato di
--  conseguenza in questo stesso commit.
--
--  CONSEGUENZA STATISTICA DA SAPERE (non e' un difetto, e' aritmetica)
--  Il delta di ogni fascia contiene un termine casuale (es. uniform(0.15,
--  0.45) per gli under 22). Sommare 4 estrazioni indipendenti produce una
--  crescita finale piu' dispersa attorno alla media di quanto ne producano
--  30 estrazioni indipendenti piu' piccole: la varianza della somma scala
--  circa come 1/N. In pratica: gli "scatti" di fine trimestre, a volte
--  sorprendenti, lasciano il posto a una crescita quotidiana piu' liscia e
--  prevedibile. E' esattamente l'effetto "live" richiesto — il rovescio
--  della medaglia e' che il risultato di fine stagione sara' leggermente
--  meno soggetto a sorprese estreme rispetto a prima.
--
--  NESSUNA COLLISIONE CON I CHECKPOINT GIA' REGISTRATI
--  season_progression_checkpoints e season_vivaio_checkpoints hanno
--  entrambe la chiave unica su (season_id, checkpoint): il campo
--  "checkpoint" prima conteneva il numero del quarto (1-4), ora conterra'
--  il numero della giornata. Non c'e' rischio di collisione per le
--  stagioni gia' in corso, perche' la chiave e' scoperta per season_id (un
--  "1" della lega 63 e un "1" della lega 62 sono righe diverse), e perche'
--  una giornata gia' passata (dove viveva un vecchio valore 1-4) non torna
--  mai indietro nella stessa stagione. Verificato sui dati reali prima di
--  scrivere questa migrazione: Serie F ha un solo checkpoint registrato
--  (valore 1, per la giornata 8), le prossime chiamate useranno checkpoint
--  9, 10, 11... senza mai ripassare da 1.
--
--  CUCITURA VISIBILE UNA TANTUM, NON UN BUG
--  Le stagioni gia' in corso hanno ricevuto la crescita dei primi giorni
--  in una o piu' soluzioni "a scatto grosso" (schema vecchio, quando si e'
--  raggiunta la soglia del quarto) e riceveranno il resto a fette
--  quotidiane (schema nuovo) da qui in avanti. Non e' un doppio conteggio
--  ne' un buco: e' semplicemente il punto in cui la regola e' cambiata.
--
--  Scope volutamente limitato a overall (rosa vera + svincolati mai
--  scelti) e vivaio, cioe' esattamente cio' che l'utente ha chiesto.
--  Morale (applica_morale_checkpoint) e punti abilita'
--  (assegna_punti_abilita) restano a cadenza trimestrale: sono meccanismi
--  volutamente separati — "registro e funzione separati... per poter
--  correggerne uno senza toccare gli altri" (commento originale del 1
--  settembre 2026) — e nessuno ha chiesto di cambiarli.
--
--  Entrambe le funzioni sono state ottenute per sostituzione mirata sul
--  testo live (pg_get_functiondef), verificata con diff prima di
--  applicare: nessuna riga persa oltre a quelle del vecchio ciclo sui
--  quattro quarti.
-- ============================================================

begin;

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
$function$
;

CREATE OR REPLACE FUNCTION public.cresci_vivaio_checkpoint(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_applicato smallint := null;
  v_prospetto record;
  v_headroom numeric;
  v_tasso numeric;
  v_nuovo smallint;
  v_aggiornati integer := 0;
begin
  select l.id, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'prospetti_aggiornati', 0);
  end if;

  -- 10 settembre 2026: stessa richiesta e stesso schema di
  -- applica_progressione_trimestrale (vedi il commento li' per il
  -- ragionamento completo su collisioni e cucitura del passaggio). Un
  -- checkpoint per ogni giornata reale, non piu' uno a quarto: la quota
  -- annuale ora si divide per giornate_totali invece che per 4.
  if p_giornata > v_lega.giornate_totali then
    return jsonb_build_object('checkpoint_applicato', null, 'prospetti_aggiornati', 0);
  end if;

  insert into public.season_vivaio_checkpoints(season_id, league_id, checkpoint, giornata)
  values (v_lega.season_id, p_league_id, p_giornata, p_giornata)
  on conflict (season_id, checkpoint) do nothing;
  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'prospetti_aggiornati', 0);
  end if;

  v_applicato := p_giornata;

  for v_prospetto in
      select p.id, p.overall, p.potential
      from public.vivaio_prospetti vp
      join public.teams t on t.id = vp.team_id and t.attiva
      join public.players p on p.id = vp.player_id
      where vp.league_id = p_league_id
      for update of p
    loop
      v_headroom := v_prospetto.potential - v_prospetto.overall;
      if v_headroom <= 0 then
        continue;
      end if;
      -- Tasso STAGIONALE (non trimestrale): 10% a ridosso del potenziale,
      -- fino al 60% con 40+ punti di margine, +-25% di variazione casuale.
      -- Diviso per giornate_totali per ottenere il delta di questa singola giornata.
      v_tasso := (0.10 + 0.50 * least(1.0, v_headroom / 40.0)) * (0.75 + random() * 0.5);
      v_nuovo := greatest(40, least(v_prospetto.potential, round(v_prospetto.overall + v_headroom * v_tasso / v_lega.giornate_totali::numeric)))::smallint;
      update public.players set overall = v_nuovo where id = v_prospetto.id;
      v_aggiornati := v_aggiornati + 1;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'prospetti_aggiornati', v_aggiornati);
end;
$function$
;

commit;
