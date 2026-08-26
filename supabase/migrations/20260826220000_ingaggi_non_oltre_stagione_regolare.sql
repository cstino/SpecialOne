-- Le giornate di playoff/playout sono numerate OLTRE giornate_totali (22, 23…
-- su una stagione da 21). Prima di questa migrazione nessuna fixture poteva
-- superare quel numero, quindi due funzioni davano per scontato che non
-- accadesse mai. Con i tabelloni non e' piu' vero:
--
-- 1. quota_ingaggio_giornata(ing, 22, 21) restituiva un'altra rata piena.
--    L'ingaggio annuale e' gia' interamente pagato alla giornata 21: le
--    partite di eliminatoria non devono costare un altro stipendio. Con un
--    ingaggio da 21 M€ erano 1 M€ di troppo per ogni giornata di tabellone,
--    per ogni giocatore in rosa.
--
-- 2. svincola_giocatore calcola la quota residua contando le giornate della
--    stagione: includendo quelle dei tabelloni, il totale saliva da 21 a 24 e
--    riappariva un residuo del 12,5% su un ingaggio gia' saldato. E' lo stesso
--    identico tipo di errore corretto il 26 agosto per giornate_totali.
--
-- Nessuna delle due modifica il comportamento delle giornate di campionato:
-- per giornata <= giornate_totali i risultati sono identici a prima.

-- Nomi dei parametri identici alla versione live (p_totale, non
-- p_giornate_totali): Postgres non permette di rinominarli con un CREATE OR
-- REPLACE. Anche la formula e' quella live, la rata piatta: l'unica aggiunta
-- e' l'azzeramento oltre l'ultima giornata di stagione regolare.
create or replace function private.quota_ingaggio_giornata(
  p_ingaggio bigint,
  p_giornata integer,
  p_totale integer
) returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_giornata > greatest(p_totale, 1) then 0
    else greatest(0, round(p_ingaggio::numeric / greatest(p_totale, 1))::bigint)
  end
$$;

-- Riscritta anche per non ricalcolare tre volte la stessa quota e, soprattutto,
-- per non tentare l'insert di una transazione da zero euro: transactions ha un
-- CHECK (importo <> 0) che farebbe fallire l'intera giornata di playoff.
create or replace function public.addebita_ingaggi_giornata(p_league_id bigint, p_giornata integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_n integer := 0;
  v_saldo bigint;
  v_totali integer;
  v_quota bigint;
begin
  if exists (
    select 1 from public.fixtures
    where league_id = p_league_id and giornata = p_giornata and stato <> 'simulata'
  ) then
    raise exception using errcode = '55000', message = 'Non tutte le partite della giornata sono state simulate.';
  end if;

  select giornate_totali into v_totali from public.leagues where id = p_league_id;

  for r in
    select pi.team_id, pi.ingaggio, p.nome
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and pi.team_id is not null
  loop
    v_quota := private.quota_ingaggio_giornata(r.ingaggio, p_giornata, v_totali);
    continue when v_quota = 0;

    update public.teams
    set budget = budget - v_quota,
        budget_ingaggi_riservato = greatest(0, budget_ingaggi_riservato - v_quota)
    where id = r.team_id
    returning budget into v_saldo;

    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, r.team_id, 'stipendio_giornata', -v_quota,
            'Stipendio giornata ' || p_giornata || ': ' || r.nome, v_saldo);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Il residuo di svincolo guarda solo la stagione REGOLARE: le giornate di
-- tabellone non allungano il contratto e non ne riaprono una quota.
create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pi public.player_instances;
  v_l public.leagues;
  v_season_id bigint;
  v_giocate integer;
  v_totale integer;
  v_residuo bigint;
  v_esito public.player_instances;
  v_saldo bigint;
begin
  select * into v_pi from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_l from public.leagues where id = v_pi.league_id;

  select id into v_season_id from public.seasons
  where league_id = v_l.id and numero = v_l.stagione_corrente;

  select count(distinct f.giornata)::integer,
         count(distinct f.giornata) filter (where f.stato = 'simulata')::integer
    into v_totale, v_giocate
  from public.fixtures f
  where f.season_id = v_season_id
    and f.bracket_tie_id is null;

  v_residuo := private.ingaggio_residuo_stagione(v_pi.ingaggio, coalesce(v_giocate, 0), coalesce(v_totale, 0));

  v_esito := public.svincola_giocatore_cassa_legacy(p_instance_id);

  update public.teams
  set budget = budget - v_residuo,
      budget_ingaggi_riservato = greatest(0, budget_ingaggi_riservato - v_residuo)
  where id = v_pi.team_id
  returning budget into v_saldo;

  if v_residuo > 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_l.id, v_pi.team_id, 'svincolo_ingaggio_residuo', -v_residuo,
      'Quota ingaggio residua non rimborsata: svincolo', v_saldo
    );
  end if;
  return v_esito;
end;
$$;

revoke all on function public.svincola_giocatore(bigint) from public, anon;
grant execute on function public.svincola_giocatore(bigint) to authenticated;
