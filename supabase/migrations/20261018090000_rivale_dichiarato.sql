-- ============================================================
--  Rivale dichiarato (docs/decisioni-conferenze-stampa.md): ogni allenatore sceglie la squadra con cui ha
--  la rivalita' piu' sentita. Quella coppia e' sempre derby (grado minimo 91, il derby scatta oltre 90),
--  anche se e' l'altra squadra ad aver scelto. Si puo' cambiare una volta a stagione. Le altre rivalita'
--  salgono e scendono come prima. Solo nelle leghe con conferenze_stampa.
-- ============================================================

begin;

alter table public.teams
  add column rivale_id bigint references public.teams(id) on delete set null,
  add column rivale_stagione smallint;

create or replace function public.scegli_rivale(p_team_id bigint, p_rivale_id bigint)
returns void language plpgsql security definer set search_path = '' as $f$
declare
  v_t record;
  v_r record;
  v_stagione smallint;
begin
  select t.id, t.league_id, t.user_id, t.rivale_id, t.rivale_stagione, l.conferenze_stampa, l.stagione_corrente
    into v_t from public.teams t join public.leagues l on l.id = t.league_id where t.id = p_team_id;
  if not found or v_t.user_id is distinct from (select auth.uid()) then raise exception 'Non è la tua squadra.'; end if;
  if not v_t.conferenze_stampa then raise exception 'Le rivalità non sono attive in questa lega.'; end if;
  select id, league_id into v_r from public.teams where id = p_rivale_id;
  if not found or v_r.league_id <> v_t.league_id or v_r.id = v_t.id then raise exception 'Squadra rivale non valida.'; end if;
  v_stagione := v_t.stagione_corrente;
  if v_t.rivale_id is not null and v_t.rivale_stagione = v_stagione and v_t.rivale_id <> p_rivale_id then
    raise exception 'Hai già scelto il rivale in questa stagione: potrai cambiarlo dalla prossima.';
  end if;
  update public.teams set rivale_id = p_rivale_id, rivale_stagione = v_stagione where id = p_team_id;
  perform private.sposta_rivalita(v_t.league_id, p_team_id, p_rivale_id, 91);
end $f$;
revoke all on function public.scegli_rivale(bigint, bigint) from public, anon;
grant execute on function public.scegli_rivale(bigint, bigint) to authenticated;

CREATE OR REPLACE FUNCTION private.sposta_rivalita(p_league_id bigint, p_t1 bigint, p_t2 bigint, p_delta numeric)
 RETURNS numeric
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into public.rivalita (league_id, team_a, team_b, grado)
  values (p_league_id, least(p_t1, p_t2), greatest(p_t1, p_t2), greatest((case when exists (select 1 from public.teams t where (t.id = least(p_t1, p_t2) and t.rivale_id = greatest(p_t1, p_t2)) or (t.id = greatest(p_t1, p_t2) and t.rivale_id = least(p_t1, p_t2))) then 91 else 0 end), least(100, p_delta)))
  on conflict (team_a, team_b) do update
    set grado = greatest((case when exists (select 1 from public.teams t where (t.id = public.rivalita.team_a and t.rivale_id = public.rivalita.team_b) or (t.id = public.rivalita.team_b and t.rivale_id = public.rivalita.team_a)) then 91 else 0 end), least(100, public.rivalita.grado + p_delta)), aggiornata_il = now()
  returning grado
$function$;

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
                 where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione
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
    v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_lega.n_squadre - 1)))
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

commit;
