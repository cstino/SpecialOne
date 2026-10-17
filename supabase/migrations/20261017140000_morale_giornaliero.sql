-- ============================================================
--  MORALE A OGNI GIORNATA (non piu' a quarti di stagione) — prova in LegaBot
--  Deciso il 17 ottobre 2026 con il committente.
--
--  Nelle leghe con leagues.conferenze_stampa il ricalcolo del morale gira a ogni
--  giornata invece che a ogni quarto: ogni volta si applica 1/L del delta (L = giornate
--  di un quarto), quindi il totale a stagione e' quello di prima ma il morale scorre.
--  Le formule (minutaggio, ingaggio, risultati, bandiera, capitano) sono quelle di sempre.
--  Si aggancia a public.applica_morale_checkpoint, che la simulazione notturna gia'
--  chiama a ogni giornata: nessuna modifica alla Edge Function.
--  Le altre leghe restano a quarti, invariate.
-- ============================================================

begin;

create table if not exists private.morale_giornaliero (
  season_id bigint not null references public.seasons(id) on delete cascade,
  giornata  smallint not null,
  league_id bigint not null references public.leagues(id) on delete cascade,
  creato_il timestamptz not null default now(),
  primary key (season_id, giornata)
);

create or replace function private.morale_giornaliero(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;

$function$;

commit;
