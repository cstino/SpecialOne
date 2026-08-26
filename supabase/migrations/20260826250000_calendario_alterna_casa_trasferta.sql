-- Il calendario faceva giocare a ogni squadra mezzo girone intero nello
-- stesso campo. Segnalato dall'utente sulla stagione 1 di Real Fampionato,
-- dove le sequenze casa/trasferta erano queste:
--
--   McDon's      C TTTTTTT CCCCCCC TTTTTT
--   Coccialand   CCCCCCC TTTTTTT CCCCCCC
--   Regginho FC  TCTCTCTCTCTCTCTCTCTCT   <- l'unica che alternava davvero
--
-- Causa: il lato casa/trasferta si decideva combinando la parita' della
-- giornata con l'indice della coppia. Nel metodo del cerchio una squadra che
-- ruota cambia indice di coppia di +/-1 a ogni giornata, quindi quella somma
-- manteneva la stessa parita' per mezzo giro e la squadra restava inchiodata.
-- Solo il perno, fermo alla coppia 1, alternava correttamente: e' esattamente
-- la squadra con la sequenza perfetta qui sopra.
--
-- La correzione e' di una riga: il lato dipende solo dalla parita' della
-- giornata. Il resto della funzione e' identico alla versione live.
--
-- Nessun backfill: i calendari gia' generati appartengono a stagioni
-- concluse, e quello della prossima stagione viene creato da capo da
-- finalizza_offseason, che chiama questa funzione.

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

  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1))
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
