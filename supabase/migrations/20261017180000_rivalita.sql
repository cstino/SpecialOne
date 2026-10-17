-- ============================================================
--  RIVALITA' — fase 2 (docs/decisioni-conferenze-stampa.md §2)
--  Prova in LegaBot (interruttore leagues.conferenze_stampa).
--
--  Una riga per coppia di squadre (rivalita' RECIPROCA): grado da 0 a 100. Ognuno vede solo le
--  proprie (squadre della coppia). Cresce quando un allenatore attacca, scherna o disprezza
--  l'altra squadra in conferenza (+10), cala quando la elogia (-6); si raffredda di 1 punto a
--  giornata. Negli scontri diretti il risultato sposta un po' morale e pubblico, in proporzione
--  al grado. Chi viene attaccato (se e' umano) riceve una domanda di replica.
-- ============================================================

begin;

create table public.rivalita (
  league_id    bigint not null references public.leagues(id) on delete cascade,
  team_a       bigint not null references public.teams(id) on delete cascade,
  team_b       bigint not null references public.teams(id) on delete cascade,
  grado        numeric(4,1) not null default 0 check (grado between 0 and 100),
  aggiornata_il timestamptz not null default now(),
  primary key (team_a, team_b),
  check (team_a < team_b)
);
create index rivalita_lega_idx on public.rivalita (league_id);
create index rivalita_team_b_idx on public.rivalita (team_b);

alter table public.rivalita enable row level security;
create policy rivalita_miei on public.rivalita
  for select to authenticated
  using (exists (select 1 from public.teams t where t.user_id = (select auth.uid()) and t.id in (team_a, team_b)));

-- Sposta il grado di una coppia (crea la riga se manca), sempre fra 0 e 100.
create or replace function private.sposta_rivalita(p_league_id bigint, p_t1 bigint, p_t2 bigint, p_delta numeric)
returns numeric
language sql security definer set search_path = ''
as $$
  insert into public.rivalita (league_id, team_a, team_b, grado)
  values (p_league_id, least(p_t1, p_t2), greatest(p_t1, p_t2), greatest(0, least(100, p_delta)))
  on conflict (team_a, team_b) do update
    set grado = greatest(0, least(100, public.rivalita.grado + p_delta)), aggiornata_il = now()
  returning grado
$$;

-- Applica gli effetti di una risposta: attacco +10, elogio -6, e per chi e' attaccato
-- (se umano) crea la domanda di replica (la terza della sua ultima partita).
-- p_squadre: [{team_id, direzione}], gia' filtrate dal server (squadre della lega, non la propria).
create or replace function public.applica_rivalita(p_domanda_id bigint, p_squadre jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_d public.conferenze_domande;
  v_s record;
  v_delta numeric;
  v_grado numeric;
  v_out jsonb := '[]'::jsonb;
  v_target public.teams;
  v_match bigint;
  v_attaccante text;
  v_tipo_squadra text;
begin
  select * into v_d from public.conferenze_domande where id = p_domanda_id;
  if not found then raise exception 'Domanda % inesistente.', p_domanda_id; end if;
  select coalesce(nullif(btrim(pr.nome_allenatore), ''), t.nome), t.nome into v_attaccante, v_tipo_squadra
    from public.teams t left join public.profiles pr on pr.user_id = t.user_id where t.id = v_d.team_id;

  for v_s in
    select (x->>'team_id')::bigint as team_id, x->>'direzione' as direzione
    from jsonb_array_elements(coalesce(p_squadre, '[]'::jsonb)) x
  loop
    continue when v_s.team_id = v_d.team_id;
    select * into v_target from public.teams where id = v_s.team_id and league_id = v_d.league_id;
    continue when not found;
    v_delta := case v_s.direzione when 'attacco' then 10 when 'elogio' then -6 else 0 end;
    continue when v_delta = 0;
    v_grado := private.sposta_rivalita(v_d.league_id, v_d.team_id, v_s.team_id, v_delta);
    v_out := v_out || jsonb_build_object('team_id', v_s.team_id, 'nome', v_target.nome, 'delta', v_delta, 'grado', v_grado);

    -- Diritto di replica: solo se attaccato e umano.
    if v_delta > 0 and v_target.user_id is not null and not v_target.controllata_da_pc then
      select m.id into v_match
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      where f.league_id = v_d.league_id and v_s.team_id in (f.home_team_id, f.away_team_id)
      order by m.simulata_il desc limit 1;
      if v_match is not null then
        insert into public.conferenze_domande (league_id, match_id, team_id, ordine, giornalista, domanda)
        values (v_d.league_id, v_match, v_s.team_id, 3,
                private.social_scegli('replica' || p_domanda_id || v_s.team_id, array['Sky Sport 24', 'Radio 24', 'Sport Mediaset', 'Corriere dello Sport', 'Rai Sport', 'Tuttosport']),
                'Mister, ' || v_attaccante || ' (' || v_tipo_squadra || ') ha parlato della vostra squadra: «' || left(coalesce(v_d.risposta, ''), 220) ||
                case when char_length(coalesce(v_d.risposta, '')) > 220 then '…' else '' end || '». Cosa risponde?')
        on conflict (match_id, team_id, ordine) do nothing;
        if found then
          perform private.notifica(v_target.user_id, v_d.league_id, 'sistema', 'Diritto di replica',
            v_attaccante || ' ha parlato di te in conferenza: i giornalisti vogliono la tua risposta.',
            jsonb_build_object('conferenza_match_id', v_match));
        end if;
      end if;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.applica_rivalita(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.applica_rivalita(bigint, jsonb) to service_role;

-- Gli scontri diretti e il raffreddamento: dentro il morale giornaliero.
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

  update public.rivalita set grado = greatest(0, grado - 1), aggiornata_il = now()
   where league_id = p_league_id and grado > 0;

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
