-- Bug: la quota ingaggio residua calcolata da svincola_giocatore usava
-- leagues.giornate_totali, una colonna generata da n_squadre/n_gironi che
-- prepara_offseason aggiorna subito quando l'admin apre l'off-season con
-- nuovi posti squadra (per la STAGIONE SUCCESSIVA). Il risultato: appena
-- l'off-season si apriva, la stagione appena conclusa risultava avere
-- "giornate mancanti" fantasma, e chi svincolava un giocatore con
-- contratto gia' scaduto (zero stagioni residue, nessuna buonuscita dovuta)
-- veniva comunque addebitato come se la stagione fosse ancora a meta'.
--
-- Fix: la quota residua si calcola sulle giornate realmente generate per
-- la stagione del contratto (fixtures.season_id), non sulla colonna live
-- della lega. Il numero totale di giornate della stagione non cambia mai
-- dopo che il calendario e' stato generato, indipendentemente da quante
-- squadre entrino nella stagione successiva.
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

  select count(distinct f.giornata)::integer, count(distinct f.giornata) filter (where f.stato = 'simulata')::integer
    into v_totale, v_giocate
  from public.fixtures f
  where f.season_id = v_season_id;

  v_residuo := private.ingaggio_residuo_stagione(v_pi.ingaggio, coalesce(v_giocate, 0), coalesce(v_totale, 0));

  -- Mantiene controlli di proprieta', rosa, formazioni e buonuscita pluriennale.
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

-- Storno una tantum: 5 svincoli su McDon's (lega 37, "Real Fampionato"),
-- eseguiti il 25/08/2026 fra le 21:42 e le 21:43, dopo la fine della
-- stagione 1 (21/21 giornate) ma dopo che l'off-season aveva gia' portato
-- n_squadre a 10 (da 8), per giocatori con contratto gia' in scadenza
-- (zero stagioni residue, nessuna buonuscita). Verificato via query diretta
-- sulle transactions della squadra: -177778, -800000, -244444, -488889,
-- -444444 = -2.155.555, tutti con tipo 'svincolo_ingaggio_residuo' e nessuna
-- buonuscita abbinata.
do $$
declare
  v_importo bigint := 2155555;
  v_saldo bigint;
begin
  update public.teams
  set budget = budget + v_importo
  where id = 82
  returning budget into v_saldo;

  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (
    37, 82, 'correzione_svincolo_ingaggio_residuo', v_importo,
    'Storno quota ingaggio residua addebitata per errore (bug giornate_totali durante apertura off-season)',
    v_saldo
  );
end $$;
