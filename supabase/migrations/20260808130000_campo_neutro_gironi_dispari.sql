-- ============================================================
--  CAMPO NEUTRO NELL'ULTIMO GIRONE DEI CAMPIONATI A GIRONI DISPARI
--
--  Segnalato dall'utente: il fattore campo (+2 punti overall ATT/MID,
--  design.md §6.6) presuppone che ogni squadra giochi lo stesso numero di
--  partite in casa e in trasferta contro ogni avversaria nel corso della
--  stagione. Vero solo con un numero PARI di gironi. Verificato sul
--  generatore di calendario (private.inizializza_stagione): ogni girone
--  alterna casa/trasferta con la parita' di (round+pair), poi inverte di
--  nuovo se il girone e' pari — quindi i gironi dispari (1, 3, 5...) usano
--  tutti lo stesso ordine. Con un numero pari di gironi si accoppiano e si
--  bilanciano (1 vs 2, 3 vs 4...). Con un numero dispari l'ultimo girone
--  resta spaiato e ripete l'ordine del girone 1: chi era in casa nel
--  girone 1 lo e' di nuovo nell'ultimo, con una partita in casa in piu'
--  della sua avversaria in quell'accoppiamento.
--
--  Soluzione: se n_gironi e' dispari, l'ultimo girone si gioca a campo
--  neutro (nessun bonus casa per nessuna delle due squadre, vedi
--  engine/engine.js opt.campoNeutro). Applicato sia alla generazione
--  futura sia, con un backfill, alle leghe gia' in corso con l'ultimo
--  girone gia' generato ma non ancora giocato (Real Fampionato, verificato
--  su dati reali: giornate 15-21, tutte ancora 'programmata').
-- ============================================================

alter table public.fixtures
  add column campo_neutro boolean not null default false;

-- ------------------------------------------------------------
--  Generazione futura: private.inizializza_stagione
-- ------------------------------------------------------------

create or replace function private.inizializza_stagione(p_league_id bigint)
returns bigint
language plpgsql
set search_path = ''
as $function$
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
  v_leg integer;
  v_round integer;
  v_pair integer;
  v_index integer;
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
    -- Solo l'ultimo girone di un campionato a gironi dispari va a campo
    -- neutro: e' l'unico che altrimenti ripeterebbe lo squilibrio del
    -- girone 1 senza un girone gemello che lo bilanci.
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
        if mod(v_round + v_pair, 2) = 0 then
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

-- ------------------------------------------------------------
--  Backfill: leghe gia' in corso con l'ultimo girone dispari gia'
--  generato ma non ancora giocato. Non tocca nulla di gia' 'simulata'.
-- ------------------------------------------------------------

with leghe_dispari as (
  select
    l.id as league_id,
    l.n_gironi,
    -- stessa formula del generatore: v_slot_count/v_rounds
    (l.n_squadre + (l.n_squadre % 2)) - 1 as rounds
  from public.leagues l
  where l.n_gironi % 2 = 1
),
inizio_ultimo_girone as (
  select league_id, (n_gironi - 1) * rounds + 1 as prima_giornata_ultimo_girone
  from leghe_dispari
)
update public.fixtures f
set campo_neutro = true
from inizio_ultimo_girone i
where f.league_id = i.league_id
  and f.giornata >= i.prima_giornata_ultimo_girone
  and f.stato = 'programmata';
