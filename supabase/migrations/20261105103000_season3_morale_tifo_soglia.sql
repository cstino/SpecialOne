-- Season 3, diario §2 e §6.
-- §2: morale e pubblico a 50 a ogni nuova stagione (in finalizza_offseason); "Titolare fisso" dal 55% al 65%.
-- §6: il pubblico segue di piu' i risultati (doppio di prima) e nei derby l'effetto raddoppia.
-- Funzioni ricostruite dalla definizione live.

-- Derby: rivalita' oltre 90 o rivale dichiarato da una delle due (stessa regola della conferenza stampa).
create or replace function private.e_derby(p_league_id bigint, p_a bigint, p_b bigint)
returns boolean
language sql
stable
set search_path to ''
as $$
  select exists (
           select 1 from public.rivalita r
           where r.league_id = p_league_id and r.team_a = least(p_a, p_b) and r.team_b = greatest(p_a, p_b) and r.grado > 90)
      or exists (
           select 1 from public.teams t
           where (t.id = p_a and t.rivale_id = p_b) or (t.id = p_b and t.rivale_id = p_a));
$$;
revoke all on function private.e_derby(bigint, bigint, bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.soglia_minutaggio(p_gradino text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select case p_gradino
    when 'titolare' then 0.65
    when 'turnover' then 0.30
    when 'sporadico' then 0.03
    when 'promessa' then 0.03
    else 0.30
  end::numeric;
$function$

;

CREATE OR REPLACE FUNCTION private.morale_giornaliero(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_stagione_id bigint;
  v_quarto numeric;
  v_aggiornati integer := 0;
  v_fuori_ruolo integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_esatto numeric;
  v_nuovo smallint;
  v_raw_min numeric;
  v_raw_eco numeric;
  v_f_min numeric;
  v_f_eco numeric;
  v_f_vit numeric;
  v_f_con numeric;
  v_w_eco numeric;
  v_w_vit numeric;
  v_w_con numeric;
  v_p numeric;
  v_n numeric;
  v_pesi numeric;
  v_anni numeric;
  c_pavimento constant numeric := 40;  -- sotto questo morale i fattori negativi non spingono piu' in giu'
  c_quota constant numeric := 0.25;    -- quota della distanza recuperata a ogni giornata
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('morale_giornaliero', false, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;
  v_quarto := greatest(1, ceil(v_lega.giornate_totali::numeric / 4.0));

  -- Una sola volta per giornata, anche se la simulazione venisse rilanciata.
  insert into private.morale_giornaliero(season_id, giornata, league_id)
  values (v_stagione_id, p_giornata, p_league_id)
  on conflict (season_id, giornata) do nothing;
  if not found then
    return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', 0);
  end if;

  -- Il pubblico vive i risultati (Season 3, diario §6): in casa vittoria +4, pareggio -1, sconfitta -4;
  -- in trasferta la meta'. Nei derby (rivalita' oltre 90 o rivale dichiarato, come nelle conferenze stampa)
  -- l'effetto raddoppia, al posto del vecchio bonus in proporzione al grado.
  update public.teams t
     set pubblico = greatest(0, least(100, t.pubblico + x.delta))
    from (
      select q.team_id, sum(q.delta * case when q.derby then 2 else 1 end) as delta
      from (
        select f.home_team_id as team_id,
               case when m.gol_home > m.gol_away then 4 when m.gol_home < m.gol_away then -4 else -1 end as delta,
               private.e_derby(f.league_id, f.home_team_id, f.away_team_id) as derby
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
        union all
        select f.away_team_id,
               case when m.gol_away > m.gol_home then 2 when m.gol_away < m.gol_home then -2 else -0.5 end,
               private.e_derby(f.league_id, f.home_team_id, f.away_team_id)
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
      ) q
      group by q.team_id
    ) x
   where t.id = x.team_id;

  -- Le rivalita': negli scontri diretti fra squadre rivali chi vince guadagna un po' di morale
  -- e chi perde ne perde (fino a +-4 a rivalita' 100%, in proporzione al grado); il pubblico dei derby
  -- e' gia' raddoppiato sopra. Poi la rivalita' si raffredda di 1 punto a giornata. Una sola
  -- applicazione per giornata (la guardia e' sopra).
  with scontri as (
    select f.home_team_id, f.away_team_id, m.gol_home, m.gol_away, r.grado
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    join public.rivalita r on r.league_id = f.league_id
     and r.team_a = least(f.home_team_id, f.away_team_id) and r.team_b = greatest(f.home_team_id, f.away_team_id)
    where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata' and r.grado > 0
  ), esiti as (
    select case when gol_home > gol_away then home_team_id else away_team_id end as vincente,
           case when gol_home > gol_away then away_team_id else home_team_id end as perdente, grado
    from scontri where gol_home <> gol_away
  ), effetti as (
    select vincente as team_id, 4 * grado / 100.0 as morale from esiti
    union all
    select perdente, -4 * grado / 100.0 from esiti
  )
  update public.player_instances pi
     set morale = greatest(0, least(100,
           floor(pi.morale + e.morale) + case when random() < (pi.morale + e.morale) - floor(pi.morale + e.morale) then 1 else 0 end))::smallint
    from (select team_id, sum(morale) as morale from effetti group by team_id) e
   where pi.team_id = e.team_id and not pi.ritirato;

  -- Scontri diretti ACCESI: la rivalita' nasce e cresce anche sul campo. Un'espulsione (rosso diretto o doppio
  -- giallo) vale +6; un gol decisivo dal 85' in poi (partita finita con un solo gol di scarto, segnato dalla
  -- vincente) vale +4; le due cose insieme +10. Vale per qualsiasi coppia di squadre, anche senza una rivalita' prima.
  perform private.sposta_rivalita(a.league_id, a.home_team_id, a.away_team_id,
            (case when a.rosso then 6 else 0 end) + (case when a.finale_decisivo then 4 else 0 end))
  from (
    select f.league_id, f.home_team_id, f.away_team_id,
           exists (select 1 from jsonb_array_elements(m.blocchi) e where e->>'tipo' = 'cartellino' and e->>'colore' in ('rosso_diretto', 'doppio_giallo')) as rosso,
           abs(m.gol_home - m.gol_away) = 1 and exists (
             select 1 from jsonb_array_elements(m.blocchi) e
              where e->>'tipo' = 'gol' and (e->>'minuto')::int >= 85
                and e->>'lato' = case when m.gol_home > m.gol_away then 'casa' else 'ospite' end) as finale_decisivo
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata' and f.campo_neutro is not true
  ) a
  where a.rosso or a.finale_decisivo;

  update public.rivalita r set grado = greatest((case when exists (select 1 from public.teams t where (t.id = r.team_a and t.rivale_id = r.team_b) or (t.id = r.team_b and t.rivale_id = r.team_a)) then 91 else 0 end), grado - 1), aggiornata_il = now()
   where r.league_id = p_league_id and r.grado > 0;

  -- Il capitano effettivo e la sua forza si calcolano UNA volta per squadra (prima erano ricalcolati tre volte per
  -- ogni giocatore: ~11 secondi in una lega da 16 squadre, oltre il limite di 8 s delle chiamate).
  for v_giocatore in
    with cap as materialized (
      select t2.id as team_id, c.cap_id,
             case when c.cap_id is null or not l2.tattiche_attive then 0 else private.qualita_capitano(c.cap_id) end as forza
        from public.teams t2
        join public.leagues l2 on l2.id = t2.league_id
        cross join lateral (select coalesce(t2.capitano, case when l2.conferenze_stampa then private.capitano_automatico(t2.id) end) as cap_id) c
       where t2.league_id = p_league_id and t2.attiva
    )
    select
      pi.id,
      pi.morale,
      pi.ingaggio,
      pi.overall_corrente,
      pi.eta_corrente,
      pi.team_id,
      pi.contratto_scadenza,
      private.stagione_contratto(pi.league_id) as stagione_contratto,
      -- Capitano effettivo: quello designato oppure, nelle leghe con il capitano a requisiti
      -- (conferenze_stampa), il piu' idoneo. Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
      -- un capitano, o se il capitano e' quello che si sta valutando: chi
      -- porta la fascia non consola se stesso.
      case when cap.cap_id is null or cap.cap_id = pi.id then 0 else cap.forza end as forza_capitano,
      p.mentalita_bandiera,
      p.mentalita_economia,
      p.mentalita_vittorie,
      pi.minutaggio_promesso,
      l.tattiche_attive as tattiche,
      -- media overall della propria rosa: e' il metro con cui il giocatore
      -- giudica quanto dovrebbe giocare
      (select avg(x.overall_corrente)
         from public.player_instances x
        where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
      -- quota di minuti effettivamente giocati sulle giornate disputate
      coalesce((select ms.minuti from private.minuti_stagione(pi.id) ms), 0) as minuti_giocati,
      coalesce((select ms.partite from private.minuti_stagione(pi.id) ms), 0) as giornate_disputate,
      coalesce((select st.posizione
                  from public.standings st
                 where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione,
        coalesce(private.squadre_nel_gruppo(v_stagione_id, pi.team_id), v_lega.n_squadre) as n_gruppo
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    join cap on cap.team_id = pi.team_id
    join public.leagues l on l.id = pi.league_id
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    -- MODELLO A FATTORI (18 ottobre 2026, deciso con il committente). Ogni giornata si guarda quanto ogni fattore e'
    -- rispettato ADESSO, da -1 (molto contro) a +1 (molto a favore), pesato dal carattere del giocatore. Il morale sale
    -- in proporzione ai fattori a favore e scende SOLO in proporzione a quelli contro.

    -- 1. Minutaggio (peso 1 per tutti). Asimmetrico di proposito: giocare meno del previsto delude piu' di quanto
    --    giocare tanto gratifichi. Con meno di 3 partite giocabili non pesa (neutro).
    v_raw_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
      ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
        - case when v_giocatore.tattiche
            then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
            else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
      ) * 30
    )) end;
    -- Promessa trattata e non mantenuta: pesa il 50% in piu' (docs/decisioni-minutaggio.md, punto 4).
    if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_raw_min < 0 then
      v_raw_min := greatest(-18, v_raw_min * 1.5);
    end if;
    v_f_min := case when v_raw_min >= 0 then v_raw_min / 8.0 else greatest(-1, v_raw_min / 12.0) end;

    -- 2. Stipendio, peso = mentalita economia / 33.
    v_raw_eco := greatest(-10, least(6,
      ((v_giocatore.ingaggio::numeric
        / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20));
    v_f_eco := case when v_raw_eco >= 0 then v_raw_eco / 6.0 else v_raw_eco / 10.0 end;
    v_w_eco := v_giocatore.mentalita_economia / 33.0;

    -- 3. Vittorie: posizione nel proprio gruppo (conferenza), 1a = +1, ultima = -1. Peso = mentalita vittorie / 33.
    v_f_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_giocatore.n_gruppo - 1))) * 2;
    v_w_vit := v_giocatore.mentalita_vittorie / 33.0;

    -- 4. Contratto: in scadenza a fine stagione = insicurezza (-0,5), un anno ancora = neutro, due o piu' = sicurezza (+0,3).
    --    Peso = mentalita bandiera / 33 (a chi tiene alla maglia la stabilita' conta di piu').
    v_anni := coalesce(v_giocatore.contratto_scadenza, v_giocatore.stagione_contratto) - coalesce(v_giocatore.stagione_contratto, 0);
    v_f_con := case when v_anni <= 0 then -0.5 when v_anni = 1 then 0 else 0.3 end;
    v_w_con := v_giocatore.mentalita_bandiera / 33.0;

    -- I fattori negativi sono attenuati dalla bandiera e dal capitano (come prima): un bandiera 60 assorbe il 30%
    -- del malcontento; un trascinatore fino al 30%, un capitano scontento lo peggiora.
    v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);
    v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);
    if v_f_min < 0 then v_f_min := v_f_min * v_attenuazione * v_att_capitano; end if;
    if v_f_eco < 0 then v_f_eco := v_f_eco * v_attenuazione * v_att_capitano; end if;
    if v_f_vit < 0 then v_f_vit := v_f_vit * v_attenuazione * v_att_capitano; end if;
    if v_f_con < 0 then v_f_con := v_f_con * v_attenuazione * v_att_capitano; end if;

    -- Quanto i fattori a favore (P) e quelli contro (N) pesano, da 0 a 1, sul totale dei pesi. Il morale SALE verso 100
    -- in proporzione a P e SCENDE verso il pavimento in proporzione a N: senza nessun fattore negativo (N = 0) non
    -- scende mai, per quanto alto sia; senza fattori a favore (P = 0) non sale. Un giocatore perde morale solo se
    -- c'e' davvero qualcosa che glielo fa perdere.
    v_pesi := greatest(0.01, 1.0 + v_w_eco + v_w_vit + v_w_con);
    v_p := (greatest(0, v_f_min) + v_w_eco * greatest(0, v_f_eco) + v_w_vit * greatest(0, v_f_vit) + v_w_con * greatest(0, v_f_con)) / v_pesi;
    v_n := (greatest(0, -v_f_min) + v_w_eco * greatest(0, -v_f_eco) + v_w_vit * greatest(0, -v_f_vit) + v_w_con * greatest(0, -v_f_con)) / v_pesi;

    -- L'arrotondamento a sorte conserva la media (come prima).
    v_esatto := v_giocatore.morale
      + c_quota * (v_p * (100 - v_giocatore.morale) - v_n * greatest(0, v_giocatore.morale - c_pavimento));
    v_nuovo := greatest(0, least(100,
      floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;

    update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
    v_aggiornati := v_aggiornati + 1;
  end loop;

  -- FUORI RUOLO (24/10/2026): titolari schierati in un reparto non loro, scesi davvero in campo in questa giornata.
  -- Reparto vicino -8, reparto lontano -25, fino a un minimo di 10 (chi e' gia' sotto 10 non risale per questo).
  with partite as (
    select f.home_team_id as team_id, f.giornata, m.titolari_home as in_campo
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
    union all
    select f.away_team_id, f.giornata, m.titolari_away
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
  ), cali as (
    select x.id as player_id,
           private.calo_morale_fuori_ruolo(coalesce(pi.posizioni_override, p.posizioni),
                                           (coalesce(l.disposizione, private.disposizione_standard(l.modulo)))[x.k]) as calo
      from partite pa
      join public.lineups l on l.team_id = pa.team_id and l.giornata = pa.giornata and l.league_id = p_league_id
      cross join lateral unnest(l.titolari) with ordinality as x(id, k)
      join public.player_instances pi on pi.id = x.id
      join public.players p on p.id = pi.player_id
     where x.k between 2 and 11 and x.id = any(pa.in_campo)
  )
  update public.player_instances pi
     set morale = least(pi.morale, greatest(10, pi.morale - c.calo))::smallint
    from cali c
   where pi.id = c.player_id and c.calo > 0;
  get diagnostics v_fuori_ruolo = row_count;

  return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', v_aggiornati, 'cali_fuori_ruolo', v_fuori_ruolo);
end;
$function$

;

CREATE OR REPLACE FUNCTION private.finalizza_offseason(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
  v_scelte_live integer;
  v_avvio_live timestamptz;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      -- In diretta le notifiche delle scelte partono alla rivelazione.
      if v_league.conferenze_attive then perform set_config('private.silenzia_scelte', '1', true); end if;
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  perform set_config('private.silenzia_scelte', '', true);

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  -- Contratti scaduti e non rinnovati: i giocatori restano senza squadra E finiscono nella coda dei rilasci, cosi' alla
  -- prima estrazione dopo la riapertura del mercato compaiono tutti fra i free agent (non solo per sorteggio).
  with liberati as (
    update public.player_instances
    set team_id = null
    where league_id = p_league_id
      and team_id is not null
      and not ritirato
      and contratto_scadenza <= v_league.stagione_corrente
    returning player_id
  )
  insert into private.rilasci_in_coda (league_id, player_id)
  select p_league_id, l.player_id from liberati l
  on conflict (league_id, player_id) do nothing;

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile sotto il tetto, si applica
    -- l'insolvenza del design: escono prima gli ingaggi piu' alti finche'
    -- restano finanziabili anche i posti mancanti al minimo di 21. Sotto
    -- il tetto questo non dovrebbe piu' accadere per una rosa costruita
    -- interamente dopo la migrazione (ogni acquisizione verifica gia' la
    -- capienza), ma resta il paracadute per le rose ereditate dal vecchio
    -- modello a cassa (v. private.capienza_residua).
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_league.tetto_ingaggi;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      insert into private.rilasci_in_coda (league_id, player_id)
      select p_league_id, pi.player_id from public.player_instances pi where pi.id = v_candidate.id
      on conflict (league_id, player_id) do nothing;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome,
             coalesce(fap.overall_corrente, p.overall) as overall, coalesce(fap.eta_corrente, p.eta) as eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      left join public.free_agent_progression fap
        on fap.league_id = p_league_id and fap.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))
          <= v_league.tetto_ingaggi - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))) asc,
               coalesce(fap.overall_corrente, p.overall) asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
        delete from public.free_agent_progression
        where league_id = p_league_id and player_id = v_candidate.player_id;
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_league.tetto_ingaggi < v_ingaggi then
      raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il tetto ingaggi.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  -- Il rilascio automatico dei prospetti non promossi in tempo non e' piu'
  -- legato alla chiusura dell'off-season (deciso con l'utente il 4
  -- settembre 2026: comprare un giovane a ridosso della fine stagione non
  -- deve costringere a promuoverlo quasi subito). Ora e' un conto alla
  -- rovescia in giornate dal momento dell'acquisto, decrementato ogni
  -- giornata simulata da public.decrementa_vivaio_giornate — qui non
  -- resta piu' nulla da fare.

  -- ON-Season della nuova stagione: l'ordine dal monte ingaggi (minore -> maggiore),
  -- misurato ora che draft e rose sono completi.
  perform private.assegna_posizioni_on_per_monte_ingaggi(p_league_id, v_off.stagione_a);

  -- Le formazioni della stagione chiusa non devono sopravvivere nella nuova: lineups non ha la stagione,
  -- quindi una riga "giornata 2" di agosto verrebbe scambiata per quella della giornata 2 di questa
  -- stagione (simulazione, promemoria, pagina Formazione). Si archiviano e si tolgono: restano solo le
  -- formazioni preparate durante l'off-season (giornata 1 salvata dopo l'apertura dell'off-season).
  insert into private.lineups_archivio
  select l.*, v_off.stagione_da::smallint
  from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);
  delete from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

  -- Season 3 (diario §2): ogni stagione riparte con morale dei giocatori e pubblico a meta'. Si fa qui, alla
  -- chiusura dell'off-season, perche' durante l'off-season il morale serve ancora ai rinnovi.
  update public.player_instances set morale = 50
  where league_id = p_league_id and not ritirato and morale <> 50;
  update public.teams set pubblico = 50
  where league_id = p_league_id and pubblico <> 50;

  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Ritiro dei mai-scelti: legge l'eta' vera tracciata in
  -- free_agent_progression (non piu' un'eta' ipotetica ricalcolata),
  -- e ripulisce la riga tracciata quando il giocatore esce dal pool.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, fap.player_id, v_off.stagione_a
  from public.free_agent_progression fap
  where fap.league_id = p_league_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = fap.player_id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = fap.player_id
    )
    and fap.eta_corrente >= 34
    and random() < private.probabilita_ritiro(fap.eta_corrente)
  on conflict do nothing;

  delete from public.free_agent_progression fap
  using public.retired_players rp
  where fap.league_id = p_league_id and rp.league_id = p_league_id and rp.player_id = fap.player_id;

  -- Con le conferenze la stagione non parte subito: prima il sorteggio East/West
  -- in diretta, e solo a sorteggio concluso nasce il calendario
  -- (private.completa_sorteggi_scaduti).
  if v_league.conferenze_attive then
    perform private.crea_sorteggio_conferenze(p_league_id, v_off.stagione_a);
    v_season := null;
    -- Draft dei giocatori in diretta (30 s a scelta) e, 3 minuti dopo l'ultima
    -- scelta, il sorteggio. Parte al minuto pieno successivo alla chiusura.
    select count(*)::integer into v_scelte_live
    from public.scelte_draft
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off' and stato in ('usata', 'vuota');
    if v_scelte_live > 0 then
      v_avvio_live := date_trunc('minute', clock_timestamp()) + interval '1 minute';
      insert into public.scelte_live (league_id, stagione, finestra, avviato_il, totale)
      values (p_league_id, v_off.stagione_da, 'off', v_avvio_live, v_scelte_live)
      on conflict (league_id, stagione, finestra) do nothing;
      update public.sorteggi_conferenze
      set avviato_il = v_avvio_live + (v_scelte_live * 30 + 180) * interval '1 second'
      where league_id = p_league_id and stagione = v_off.stagione_a and completato_il is null;
    end if;
  else
    v_season := private.inizializza_stagione(p_league_id);
  end if;

  perform private.notifica(
    t.user_id, p_league_id, 'sistema',
    case when v_league.conferenze_attive then 'Draft e sorteggio in diretta' else 'La nuova stagione e'' iniziata' end,
    case when v_league.conferenze_attive then 'Entra ora: prima il draft dei giocatori, poi il sorteggio delle conferenze Eastern e Western.'
         else 'La prima giornata si giochera'' alle 23:00. Prepara la formazione.' end,
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$function$

;
