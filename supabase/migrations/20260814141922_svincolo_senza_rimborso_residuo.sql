-- Lo svincolo non rimborsa la quota della stagione in corso. Essa viene
-- soltanto tolta dalla riserva e registrata come costo di rescissione;
-- l'eventuale buonuscita per le stagioni future continua a essere calcolata
-- dalla procedura originaria (meta' per difetto).
create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pi public.player_instances;
  v_l public.leagues;
  v_residuo bigint;
  v_esito public.player_instances;
  v_saldo bigint;
begin
  select * into v_pi from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_l from public.leagues where id = v_pi.league_id;
  v_residuo := private.ingaggio_residuo_stagione(
    v_pi.ingaggio,
    (select count(distinct f.giornata)::integer from public.fixtures f where f.league_id = v_l.id and f.stato = 'simulata'),
    v_l.giornate_totali
  );

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
