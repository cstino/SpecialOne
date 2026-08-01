-- ============================================================
--  AVVIO STAGIONE, CALENDARIO E CLASSIFICA INIZIALE
--
--  Il passaggio della lega da draft a stagione crea, nella stessa
--  transazione, la stagione corrente, il calendario con il metodo del
--  cerchio e una riga di classifica per ogni squadra.
-- ============================================================

create or replace function private.inizializza_stagione(
  p_league_id bigint
)
returns bigint
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next_rotation bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds_per_leg integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_start_date date;
begin
  select *
    into v_league
  from public.leagues
  where id = p_league_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Lega non trovata durante l''avvio della stagione.';
  end if;

  select id
    into v_season_id
  from public.seasons
  where league_id = p_league_id
    and numero = v_league.stagione_corrente;

  -- Una transazione fallita non lascia dati parziali. Se invece la stagione
  -- esiste gia', il retry e' intenzionalmente innocuo.
  if found then
    return v_season_id;
  end if;

  if v_league.stato <> 'stagione' then
    raise exception using
      errcode = '55000',
      message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  if exists (
    select 1
    from public.draft_team_state dts
    where dts.league_id = p_league_id
      and dts.stato <> 'concluso'
  ) then
    raise exception using
      errcode = '55000',
      message = 'Tutte le squadre devono completare il draft.';
  end if;

  select
    coalesce(
      array_agg(t.id order by t.ordine_draft nulls last, t.id),
      array[]::bigint[]
    ),
    count(*)::integer
    into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id;

  if v_team_count <> v_league.n_squadre then
    raise exception using
      errcode = '55000',
      message = 'Il numero di squadre non coincide con le impostazioni della lega.';
  end if;

  v_start_date := (clock_timestamp() at time zone 'Europe/Rome')::date + 1;

  insert into public.seasons (
    league_id,
    numero,
    stato,
    data_inizio,
    data_fine
  ) values (
    p_league_id,
    v_league.stagione_corrente,
    'in_corso',
    v_start_date,
    v_start_date + (v_league.giornate_totali - 1)
  )
  returning id into v_season_id;

  insert into public.standings (
    season_id,
    league_id,
    team_id,
    posizione
  )
  select
    v_season_id,
    p_league_id,
    t.id,
    row_number() over (order by t.nome, t.id)::smallint
  from public.teams t
  where t.league_id = p_league_id;

  -- Con un numero dispari di squadre aggiungiamo uno slot vuoto. Gli
  -- accoppiamenti che lo contengono sono i turni di riposo.
  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds_per_leg := v_slot_count - 1;

  for v_leg in 1..v_league.n_gironi loop
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;

    for v_round in 1..v_rounds_per_leg loop
      v_giornata := (v_leg - 1) * v_rounds_per_leg + v_round;

      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];

        if v_home is null or v_away is null then
          continue;
        end if;

        -- Alterniamo casa/trasferta dentro il girone e invertiamo tutto nei
        -- gironi pari, mantenendo il calendario deterministico.
        if mod(v_round + v_pair, 2) = 0 then
          v_swap := v_home;
          v_home := v_away;
          v_away := v_swap;
        end if;

        if mod(v_leg, 2) = 0 then
          v_swap := v_home;
          v_home := v_away;
          v_away := v_swap;
        end if;

        insert into public.fixtures (
          season_id,
          league_id,
          giornata,
          home_team_id,
          away_team_id,
          data_sim
        ) values (
          v_season_id,
          p_league_id,
          v_giornata,
          v_home,
          v_away,
          (v_start_date + (v_giornata - 1))::timestamp
            at time zone 'Europe/Rome'
        );
      end loop;

      -- Metodo del cerchio: il primo slot resta fermo, l'ultimo passa in
      -- seconda posizione e gli altri scorrono di uno.
      v_next_rotation := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next_rotation := array_append(v_next_rotation, v_rotation[v_index]);
      end loop;
      v_rotation := v_next_rotation;
    end loop;
  end loop;

  return v_season_id;
end;
$$;

revoke all on function private.inizializza_stagione(bigint)
  from public, anon, authenticated;
grant execute on function private.inizializza_stagione(bigint)
  to service_role;

comment on function private.inizializza_stagione(bigint) is
  'Crea in modo atomico e idempotente stagione, calendario e classifica iniziale.';

create or replace function private.avvia_stagione_al_cambio_stato()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.stato = 'stagione'
     and old.stato is distinct from new.stato then
    perform private.inizializza_stagione(new.id);
  end if;

  return new;
end;
$$;

revoke all on function private.avvia_stagione_al_cambio_stato()
  from public, anon, authenticated;

create trigger leagues_avvia_stagione
  after update of stato on public.leagues
  for each row
  execute function private.avvia_stagione_al_cambio_stato();

-- Recupera le leghe che avevano gia' terminato il draft prima di questa
-- migrazione (compresa la lega di test), senza duplicare eventuali stagioni.
do $$
declare
  v_league record;
begin
  for v_league in
    select l.id
    from public.leagues l
    where l.stato = 'stagione'
      and not exists (
        select 1
        from public.seasons s
        where s.league_id = l.id
          and s.numero = l.stagione_corrente
      )
    order by l.id
  loop
    perform private.inizializza_stagione(v_league.id);
  end loop;
end;
$$;
