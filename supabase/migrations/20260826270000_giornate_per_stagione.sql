-- Ogni stagione si porta dietro il PROPRIO numero di giornate.
--
-- Segnalato dall'utente: la stagione 1 di Real Fampionato si e' giocata in 8
-- squadre su 3 gironi, 21 giornate, e la 21a e' stata l'ultima. Aggiungendo
-- squadre per la stagione 2, l'app ha iniziato a dire "giornata 21 di 33" su
-- una stagione gia' finita.
--
-- La causa e' la stessa di altri tre bug corretti oggi (svincolo, scambi,
-- stipendi delle giornate di playoff): leagues.giornate_totali e' una colonna
-- GENERATA da n_squadre e n_gironi, quindi cambia retroattivamente ogni volta
-- che l'admin tocca la composizione della lega, comprese le stagioni concluse.
-- Finora ho corretto i sintomi uno a uno; questa migrazione toglie la causa.
--
-- Da qui in poi la durata di una stagione e' un dato della stagione, fissato
-- quando nasce il calendario e mai piu' ricalcolato.

alter table public.seasons
  add column if not exists giornate_totali smallint check (giornate_totali > 0);

comment on column public.seasons.giornate_totali is
  'Giornate di stagione REGOLARE, fissate alla creazione del calendario. Non usare leagues.giornate_totali per una stagione gia'' iniziata: e'' una colonna generata che cambia se la lega cambia composizione.';

-- Backfill dalle fixtures realmente generate, che sono la prova di quante
-- giornate ha avuto davvero ogni stagione. Esclude quelle dei tabelloni:
-- playoff e playout non fanno parte della stagione regolare.
update public.seasons s
set giornate_totali = x.giornate
from (
  select f.season_id, count(distinct f.giornata)::smallint as giornate
  from public.fixtures f
  where f.bracket_tie_id is null
  group by f.season_id
) x
where x.season_id = s.id and s.giornate_totali is null;

CREATE OR REPLACE FUNCTION private.inizializza_stagione(p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_scadenza timestamptz;
  v_prima_giornata timestamptz;
  v_start date;
  v_campo_neutro boolean;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  select id into v_season_id
  from public.seasons
  where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;

  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.';
  end if;

  select o.scade_il into v_scadenza
  from public.offseasons o
  where o.league_id = p_league_id and o.stagione_a = v_league.stagione_corrente
  order by o.id desc limit 1;

  v_prima_giornata := private.primo_calcio_dopo(coalesce(v_scadenza, clock_timestamp()));
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  -- Il numero di giornate viene FISSATO qui e non si tocca piu'.
  -- leagues.giornate_totali e' una colonna generata da n_squadre e n_gironi:
  -- se l'admin aggiunge squadre o cambia i gironi cambia anche per le stagioni
  -- gia' giocate, che si ritrovano "21 giornate su 33". Da qui in poi la
  -- verita' sulla durata di una stagione sta nella stagione stessa.
  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine, giornate_totali)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1), v_league.giornate_totali)
  returning id into v_season_id;

  insert into public.standings(season_id, league_id, team_id, posizione)
  select v_season_id, p_league_id, t.id,
         row_number() over(order by t.nome, t.id)::smallint
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
    v_campo_neutro := (v_league.n_gironi % 2 = 1 and v_leg = v_league.n_gironi);
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];
        if v_home is null or v_away is null then continue; end if;
        -- Il lato casa/trasferta dipende SOLO dalla parita' della giornata.
        -- Prima entrava nel conto anche l'indice della coppia: siccome nel
        -- metodo del cerchio una squadra che ruota cambia coppia di +/-1 a
        -- ogni giornata, quella somma manteneva la stessa parita' per mezzo
        -- giro e la squadra restava inchiodata in casa o in trasferta.
        -- Verificato per 4-20 squadre e 2-4 gironi: al massimo 2 partite
        -- consecutive nello stesso campo (3 a squadre dispari, per via dei
        -- turni di riposo) e bilanciamento esatto.
        if mod(v_round, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'), v_campo_neutro);
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;
  return v_season_id;
end;
$function$;
