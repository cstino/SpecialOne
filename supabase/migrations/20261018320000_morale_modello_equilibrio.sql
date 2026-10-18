-- ============================================================
--  MORALE A MORALE D'EQUILIBRIO (18 ottobre 2026, deciso con il committente, dopo il caso Mandas: un giocatore con
--  tutti i fattori a favore ci metteva ~17 giornate a risalire perche' il morale era una somma cumulata senza memoria
--  della propria distanza). Ogni giornata si misura quanto ogni fattore e' rispettato adesso (minuti, stipendio,
--  vittorie, contratto), si calcola un morale d'equilibrio (40-100, neutro 70 come nel motore) e il morale ne recupera un quarto della distanza.
--  Vale solo nelle leghe con le novita' (applica_morale_checkpoint -> private.morale_giornaliero). Riscritta dalla
--  definizione viva; il resto della funzione (pubblico, rivalita', scontri) e' invariato.
-- ============================================================
begin;

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
  v_raw_min numeric;
  v_raw_eco numeric;
  v_f_min numeric;
  v_f_eco numeric;
  v_f_vit numeric;
  v_f_con numeric;
  v_w_eco numeric;
  v_w_vit numeric;
  v_w_con numeric;
  v_s numeric;
  v_target numeric;
  v_anni numeric;
  c_base constant numeric := 70;       -- morale di un giocatore con tutti i fattori neutri (= MORALE_NEUTRO del motore)
  c_ampiezza constant numeric := 30;   -- da 40 (tutto contro) a 100 (tutto a favore)
  c_quota constant numeric := 0.25;    -- quota della distanza dal morale d'equilibrio recuperata a ogni giornata
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
    -- MODELLO A MORALE D'EQUILIBRIO (18 ottobre 2026, deciso con il committente). Ogni giornata si guarda quanto ogni
    -- fattore e' rispettato ADESSO, da -1 (molto contro) a +1 (molto a favore), pesato dal carattere del giocatore; ne
    -- esce un morale d'equilibrio (40-100, neutro 70 come nel motore) e il morale vero ne recupera una quota fissa a ogni giornata. Chi ha tutto
    -- per stare bene risale in fretta, chi perde cio' che voleva scende; gli effetti di conferenze e richieste (che
    -- aggiungono morale subito) svaniscono piano piano.

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

    v_s := (1.0 * v_f_min + v_w_eco * v_f_eco + v_w_vit * v_f_vit + v_w_con * v_f_con)
           / greatest(0.01, 1.0 + v_w_eco + v_w_vit + v_w_con);
    v_target := greatest(0, least(100, c_base + c_ampiezza * v_s));

    -- Il morale ne recupera una quota; l'arrotondamento a sorte conserva la media (come prima).
    v_esatto := v_giocatore.morale + (v_target - v_giocatore.morale) * c_quota;
    v_nuovo := greatest(0, least(100,
      floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;

    update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
    v_aggiornati := v_aggiornati + 1;
  end loop;

  return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', v_aggiornati);
end;
$function$;

commit;
