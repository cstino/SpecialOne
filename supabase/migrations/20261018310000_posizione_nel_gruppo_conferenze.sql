-- ============================================================
--  POSIZIONE IN CLASSIFICA NELLE LEGHE A CONFERENZE (18 ottobre 2026).
--  Il morale (voce "vittorie") e la tolleranza dei rinnovi usano la posizione normalizzata sul numero di squadre
--  della lega (24 in Serie F), ma le classifiche sono due da 12 (Eastern/Western): la prima prendeva il massimo e
--  l'ultima (12a) restava a +0,02, quindi nessuno riceveva mai una penalita' per la classifica (morale gonfiato).
--  Ora si normalizza sulla dimensione del proprio gruppo (la conferenza). Nelle leghe senza conferenze non cambia nulla.
--  Funzioni riscritte dalla definizione viva: morale_giornaliero, applica_morale_checkpoint, offri_rinnovo, offri_promozione.
-- ============================================================
begin;

create or replace function private.squadre_nel_gruppo(p_season_id bigint, p_team_id bigint)
returns integer language sql stable security definer set search_path = '' as $f$
  select case when exists (select 1 from public.standings s where s.season_id = p_season_id and s.conferenza is not null)
    then (select count(*)::integer from public.standings s
           where s.season_id = p_season_id
             and s.conferenza is not distinct from (select s2.conferenza from public.standings s2 where s2.season_id = p_season_id and s2.team_id = p_team_id))
    else null end
$f$;

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

  -- Il pubblico vive i risultati: poco e lentamente (vittoria +1,5, pareggio -0,5, sconfitta
  -- -2,5; in trasferta la meta'). Sopra 80 il bonus casa e' gia' pieno, quindi una serie
  -- negativa lunga serve per toccarlo. Il grosso lo muovono le conferenze stampa.
  update public.teams t
     set pubblico = greatest(0, least(100, t.pubblico + x.delta))
    from (
      select q.team_id, sum(q.delta) as delta
      from (
        select f.home_team_id as team_id,
               case when m.gol_home > m.gol_away then 1.5 when m.gol_home < m.gol_away then -2.5 else -0.5 end as delta
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
        union all
        select f.away_team_id,
               case when m.gol_away > m.gol_home then 0.75 when m.gol_away < m.gol_home then -1.25 else -0.25 end
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
      ) q
      group by q.team_id
    ) x
   where t.id = x.team_id;

  -- Le rivalita': negli scontri diretti fra squadre rivali chi vince guadagna un po' di morale
  -- e chi perde ne perde (fino a +-4 a rivalita' 100%, in proporzione al grado), e il pubblico
  -- vive la partita di piu' (+2 / -3 al grado pieno). Poi la rivalita' si raffredda di 1 punto a
  -- giornata. Una sola applicazione per giornata (la guardia e' sopra).
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
    select vincente as team_id, 4 * grado / 100.0 as morale, 2 * grado / 100.0 as pubblico from esiti
    union all
    select perdente, -4 * grado / 100.0, -3 * grado / 100.0 from esiti
  ), pubblico_agg as (
    update public.teams t set pubblico = greatest(0, least(100, t.pubblico + e.pubblico))
      from (select team_id, sum(pubblico) as pubblico from effetti group by team_id) e
     where t.id = e.team_id
    returning t.id
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
    -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
    --    delude piu' di quanto giocare tanto gratifichi.
    -- Dall'arrivo in squadra, solo stagione corrente, senza le partite da
    -- assente; con meno di 3 partite giocabili la voce non pesa.
    v_delta_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
      ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
        - case when v_giocatore.tattiche
            then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
            else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
      ) * 30
    )) end;

    -- Promessa trattata e non mantenuta: pesa il 50% in piu'
    -- (docs/decisioni-minutaggio.md, punto 4).
    if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_delta_min < 0 then
      v_delta_min := greatest(-18, v_delta_min * 1.5);
    end if;

    -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
    v_delta_eco := greatest(-10, least(6,
      ((v_giocatore.ingaggio::numeric
        / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
    )) * (v_giocatore.mentalita_economia / 33.0);

    -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
    v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_giocatore.n_gruppo - 1)))
      * 16 * (v_giocatore.mentalita_vittorie / 33.0);

    -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
    --    Un bandiera 60 assorbe il 30% del malcontento.
    v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

    -- 5. Il capitano. In Football Manager la fascia agisce sullo spogliatoio
    --    nel tempo, non sui novanta minuti: e' qui che deve pesare, non nel
    --    motore. Un trascinatore assorbe fino al 30% del malcontento dei
    --    compagni; un capitano scontento lo peggiora, perche' la qualita' va
    --    anche sotto zero. Si moltiplica con l'attenuazione da bandiera
    --    invece di sommarsi: sono due modi diversi di reggere lo stesso colpo,
    --    e sommandoli un bandiera capitano sarebbe diventato immune.
    v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);

    v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
    v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit))
                  * v_attenuazione * v_att_capitano;

    -- Ogni giornata si applica solo 1/L del delta di un quarto (L = giornate di un quarto):
    -- il totale a stagione e' quello di sempre, ma il morale scorre invece di saltare.
    -- Il morale e' un intero: l'arrotondamento a sorte conserva il valore medio, senza
    -- far sparire i delta piccoli.
    v_esatto := v_giocatore.morale + (v_positivi + v_negativi) / v_quarto;
    v_nuovo := greatest(0, least(100,
      floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;

    update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
    v_aggiornati := v_aggiornati + 1;
  end loop;

  return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', v_aggiornati);
end;
$function$;

CREATE OR REPLACE FUNCTION public.applica_morale_checkpoint(p_league_id bigint, p_giornata smallint)
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
  v_applicato smallint := null;
  v_aggiornati integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_nuovo smallint;
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;

  -- Leghe con il morale a ogni giornata (conferenze_stampa): niente quarti.
  if (select l.conferenze_stampa from public.leagues l where l.id = p_league_id) then
    return private.morale_giornaliero(p_league_id, p_giornata) || jsonb_build_object('checkpoint_applicato', null);
  end if;

  -- Stessa scansione della progressione overall: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_morale_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_stagione_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    for v_giocatore in
      select
        pi.id,
        pi.morale,
        pi.ingaggio,
        pi.overall_corrente,
        pi.eta_corrente,
        pi.team_id,
        -- Capitano effettivo: quello designato oppure, nelle leghe con il capitano a requisiti
        -- (conferenze_stampa), il piu' idoneo. Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
        -- un capitano, o se il capitano e' quello che si sta valutando: chi
        -- porta la fascia non consola se stesso.
        case when coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) is null or coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) = pi.id then 0
             when not l.tattiche_attive then 0
             else private.qualita_capitano(coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end)) end as forza_capitano,
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
      join public.leagues l on l.id = pi.league_id
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      -- Dall'arrivo in squadra, solo stagione corrente, senza le partite da
      -- assente; con meno di 3 partite giocabili la voce non pesa.
      v_delta_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - case when v_giocatore.tattiche
              then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
              else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
        ) * 30
      )) end;

      -- Promessa trattata e non mantenuta: pesa il 50% in piu'
      -- (docs/decisioni-minutaggio.md, punto 4).
      if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_delta_min < 0 then
        v_delta_min := greatest(-18, v_delta_min * 1.5);
      end if;

      -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
      v_delta_eco := greatest(-10, least(6,
        ((v_giocatore.ingaggio::numeric
          / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
      )) * (v_giocatore.mentalita_economia / 33.0);

      -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
      v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_giocatore.n_gruppo - 1)))
        * 16 * (v_giocatore.mentalita_vittorie / 33.0);

      -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
      --    Un bandiera 60 assorbe il 30% del malcontento.
      v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

      -- 5. Il capitano. In Football Manager la fascia agisce sullo spogliatoio
      --    nel tempo, non sui novanta minuti: e' qui che deve pesare, non nel
      --    motore. Un trascinatore assorbe fino al 30% del malcontento dei
      --    compagni; un capitano scontento lo peggiora, perche' la qualita' va
      --    anche sotto zero. Si moltiplica con l'attenuazione da bandiera
      --    invece di sommarsi: sono due modi diversi di reggere lo stesso colpo,
      --    e sommandoli un bandiera capitano sarebbe diventato immune.
      v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);

      v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
      v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit))
                    * v_attenuazione * v_att_capitano;

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;

$function$;

CREATE OR REPLACE FUNCTION public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint, p_minutaggio text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
  v_gradino text;
  v_media numeric;
  v_rifiuto text;
  v_richiesta bigint;
  v_richiesto text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata <> 1 then
    raise exception using errcode = '22023',
      message = 'I contratti durano una stagione: il rinnovo estende di un anno.';
  end if;
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  -- Il gradino: quello offerto, o (senza sceglierlo) quello che ha gia'. Un
  -- gradino non alla sua altezza lo rifiuta senza consumare un tentativo.
  v_richiesta := v_proposta.richiesta;
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto_istanza(v_inst.id);
    v_gradino := coalesce(p_minutaggio, private.gradino_effettivo(v_inst.id));
    if p_minutaggio is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_richiesto, v_inst.eta_corrente, v_inst.overall_corrente, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_inst.rinnovo_tentativi,
          'tentativi_totali', 3,
          'messaggio', case
            when p_minutaggio = 'promessa' and v_inst.eta_corrente >= 21 then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non sono venuto qui per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
    end if;
    v_richiesta := private.richiesta_per_gradino(v_proposta.richiesta, v_gradino, v_richiesto);
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint),
    coalesce(private.squadre_nel_gruppo((select se.id from public.seasons se where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente), v_inst.team_id), v_league.n_squadre)::smallint
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    -- Le due verifiche sono sotto lo stesso lock di squadra: due rinnovi
    -- contemporanei non possono consumare la medesima capienza.
    perform 1 from public.teams where id = v_team.id for update;
    perform private.verifica_capienza(
      v_team.id, p_ingaggio - v_inst.ingaggio, v_league.stagione_corrente
    );
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente,
        -- Il gradino trattato diventa parte del contratto; senza sceglierlo
        -- resta com'era (anche automatico).
        minutaggio_promesso = case when v_league.tattiche_attive and p_minutaggio is not null
                                   then p_minutaggio else minutaggio_promesso end,
        richiamo_stagione = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_stagione end,
        richiamo_giornata = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_giornata end
    where id = v_inst.id;
    perform private.spinta_morale_rinnovo(v_inst.id);

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', 1,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'minutaggio', v_gradino,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_squadra public.teams;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_rapporto numeric;
  v_tentativi smallint;
  v_rosa integer;
  v_prossima integer;
  v_istanza public.player_instances;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;

  select * into v_squadra from public.teams where id = v_prospetto.team_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  select * into v_league from public.leagues where id = v_prospetto.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La promozione si tratta solo a stagione avviata.';
  end if;
  if v_prospetto.promozione_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: resterà in cantera finché non scade il countdown.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances where team_id = v_squadra.id and not ritirato;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'La rosa è già al completo (' || private.rosa_massima() || '): libera un posto prima di promuovere.';
  end if;

  select * into v_player from public.players where id = v_prospetto.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_squadra.id
  where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    50::smallint, coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint),
    coalesce(v_player.mentalita_vittorie, 34::smallint), coalesce(v_posizione, 1::smallint),
    coalesce(private.squadre_nel_gruppo((select se.id from public.seasons se where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente), v_squadra.id), v_league.n_squadre)::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));

    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_league.id and f.stato = 'programmata';

    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
    values
      (v_prospetto.league_id, v_prospetto.player_id, v_squadra.id,
       v_player.overall, v_player.eta, p_ingaggio, v_prossima)
    returning * into v_istanza;

    delete from public.vivaio_prospetti where id = v_prospetto.id;

    perform private.notifica(v_user_id, v_league.id, 'sistema', 'Prospetto promosso in prima squadra',
      v_player.nome || ' firma il primo contratto: ' || private.in_milioni(p_ingaggio) || ' M€ a stagione.',
      jsonb_build_object('player_instance_id', v_istanza.id));

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Non vedo l''ora di debuttare.'
    );
  end if;

  v_tentativi := (v_prospetto.promozione_tentativi + 1)::smallint;
  update public.vivaio_prospetti set promozione_tentativi = v_tentativi where id = v_prospetto.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Va bene, mister: resto in cantera e aspetto.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

commit;
