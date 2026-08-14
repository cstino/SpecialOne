-- Gli ingaggi annuali restano nel budget ma vengono riservati. La riserva
-- diventa liquidita' solo quando il giocatore viene ceduto/svincolato.
alter table public.teams
  add column if not exists budget_ingaggi_riservato bigint not null default 0
  check (budget_ingaggi_riservato >= 0);

create or replace function private.quota_ingaggio_giornata(p_ingaggio bigint, p_giornata integer, p_totale integer)
returns bigint language sql immutable set search_path = '' as $$
  select greatest(0, round(p_ingaggio::numeric / greatest(p_totale, 1))::bigint)
$$;

create or replace function private.ingaggio_residuo_stagione(p_ingaggio bigint, p_giocate integer, p_totale integer)
returns bigint language sql immutable set search_path = '' as $$
  select greatest(0, round(p_ingaggio::numeric * greatest(p_totale - p_giocate, 0) / greatest(p_totale, 1))::bigint)
$$;

-- Conversione una tantum: le vecchie operazioni avevano gia' sottratto gli
-- stipendi dal budget; ne riporta la parte non ancora maturata nel budget e
-- la blocca nella nuova riserva.
do $$
declare r record; v_giocate integer; v_riserva bigint;
begin
  for r in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select count(distinct giornata)::integer into v_giocate
    from public.fixtures where league_id = r.id and stato = 'simulata';
    select coalesce(sum(private.ingaggio_residuo_stagione(pi.ingaggio, v_giocate, r.giornate_totali)), 0)
      into v_riserva
    from public.player_instances pi where pi.league_id = r.id and pi.team_id is not null;
    -- L'aggiornamento e' per squadra, non per lega.
    update public.teams t
    set budget = t.budget + x.riserva,
        budget_ingaggi_riservato = x.riserva
    from (
      select pi.team_id,
             coalesce(sum(private.ingaggio_residuo_stagione(pi.ingaggio, v_giocate, r.giornate_totali)),0)::bigint as riserva
      from public.player_instances pi
      where pi.league_id = r.id and pi.team_id is not null
      group by pi.team_id
    ) x
    where t.id = x.team_id and t.budget_ingaggi_riservato = 0;
  end loop;
end $$;

create or replace function public.budget_disponibile(p_league_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_squadra public.teams; v_rosa integer; v_impegnato bigint;
begin
  select * into v_squadra from public.teams where league_id=p_league_id and user_id=(select auth.uid());
  if not found then raise exception using errcode='42501', message='Non partecipi a questa lega.'; end if;
  select count(*) into v_rosa from public.player_instances where team_id=v_squadra.id;
  v_impegnato := private.budget_impegnato(v_squadra.id);
  return jsonb_build_object('budget',v_squadra.budget,'riservato_ingaggi',v_squadra.budget_ingaggi_riservato,
    'impegnato',v_impegnato,'disponibile',v_squadra.budget-v_squadra.budget_ingaggi_riservato-v_impegnato,
    'rosa',v_rosa,'slot_impegnati',private.slot_impegnati(v_squadra.id),
    'slot_liberi',private.rosa_massima()-v_rosa-private.slot_impegnati(v_squadra.id));
end $$;

create or replace function public.addebita_ingaggi_giornata(p_league_id bigint, p_giornata integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; v_n integer := 0; v_saldo bigint;
begin
  if exists(select 1 from public.fixtures where league_id=p_league_id and giornata=p_giornata and stato <> 'simulata') then
    raise exception using errcode='55000', message='Non tutte le partite della giornata sono state simulate.';
  end if;
  for r in
    select pi.team_id, pi.ingaggio, p.nome
    from public.player_instances pi join public.players p on p.id=pi.player_id
    where pi.league_id=p_league_id and pi.team_id is not null
  loop
    update public.teams set budget=budget-private.quota_ingaggio_giornata(r.ingaggio,p_giornata,(select giornate_totali from public.leagues where id=p_league_id)),
      budget_ingaggi_riservato=greatest(0,budget_ingaggi_riservato-private.quota_ingaggio_giornata(r.ingaggio,p_giornata,(select giornate_totali from public.leagues where id=p_league_id)))
    where id=r.team_id returning budget into v_saldo;
    insert into public.transactions(league_id,team_id,tipo,importo,descrizione,saldo_dopo)
    values(p_league_id,r.team_id,'stipendio_giornata',-private.quota_ingaggio_giornata(r.ingaggio,p_giornata,(select giornate_totali from public.leagues where id=p_league_id)),'Stipendio giornata '||p_giornata||': '||r.nome,v_saldo);
    v_n:=v_n+1;
  end loop;
  return v_n;
end $$;
revoke all on function public.addebita_ingaggi_giornata(bigint,integer) from public, anon, authenticated;
grant execute on function public.addebita_ingaggi_giornata(bigint,integer) to service_role;

-- La procedura esistente contabilizza il pro-rata in cassa; la manteniamo per
-- tutte le verifiche e ne neutralizziamo soltanto quel movimento, spostando la
-- riserva fra le due squadre.
alter function public.rispondi_a_proposta(bigint,boolean) rename to rispondi_a_proposta_cassa_legacy;
create or replace function public.rispondi_a_proposta(p_proposta_id bigint,p_accetta boolean)
returns public.trade_proposals language plpgsql security definer set search_path='' as $$
declare v_p public.trade_proposals; v_l public.leagues; v_da public.teams; v_a public.teams;
  v_g integer; v_off bigint; v_ric bigint; v_esito public.trade_proposals; v_saldo bigint;
begin
  if not coalesce(p_accetta,false) then return public.rispondi_a_proposta_cassa_legacy(p_proposta_id,false); end if;
  select * into v_p from public.trade_proposals where id=p_proposta_id;
  select * into v_l from public.leagues where id=v_p.league_id;
  select * into v_da from public.teams where id=v_p.da_team_id;
  select * into v_a from public.teams where id=v_p.a_team_id;
  select count(distinct giornata)::integer into v_g from public.fixtures where league_id=v_l.id and stato='simulata';
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio,v_g,v_l.giornate_totali)),0) into v_off from public.player_instances where id=any(v_p.giocatori_offerti);
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio,v_g,v_l.giornate_totali)),0) into v_ric from public.player_instances where id=any(v_p.giocatori_richiesti);
  if v_da.budget-v_p.conguaglio-(v_da.budget_ingaggi_riservato-v_off+v_ric)<0 or v_a.budget+v_p.conguaglio-(v_a.budget_ingaggi_riservato-v_ric+v_off)<0 then
    raise exception using errcode='22023', message='Budget disponibile insufficiente per coprire il trasferimento e gli ingaggi residui.';
  end if;
  v_esito:=public.rispondi_a_proposta_cassa_legacy(p_proposta_id,true);
  update public.teams set budget=budget-v_off+v_ric,budget_ingaggi_riservato=budget_ingaggi_riservato-v_off+v_ric where id=v_da.id returning budget into v_saldo;
  update public.teams set budget=budget-v_ric+v_off,budget_ingaggi_riservato=budget_ingaggi_riservato-v_ric+v_off where id=v_a.id;
  return v_esito;
end $$;
revoke all on function public.rispondi_a_proposta_cassa_legacy(bigint,boolean) from public,anon,authenticated;
grant execute on function public.rispondi_a_proposta(bigint,boolean) to authenticated;

-- Svincolare libera immediatamente la quota dell'ingaggio che non e' ancora
-- maturata; eventuale buonuscita pluriennale resta invariata nella funzione originale.
alter function public.svincola_giocatore(bigint) rename to svincola_giocatore_cassa_legacy;
create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances language plpgsql security definer set search_path='' as $$
declare v_pi public.player_instances; v_l public.leagues; v_r bigint; v_esito public.player_instances; v_saldo bigint;
begin
  select * into v_pi from public.player_instances where id=p_instance_id;
  select * into v_l from public.leagues where id=v_pi.league_id;
  select private.ingaggio_residuo_stagione(v_pi.ingaggio,(select count(distinct giornata)::integer from public.fixtures where league_id=v_l.id and stato='simulata'),v_l.giornate_totali) into v_r;
  v_esito:=public.svincola_giocatore_cassa_legacy(p_instance_id);
  update public.teams set budget=budget+v_r,budget_ingaggi_riservato=greatest(0,budget_ingaggi_riservato-v_r) where id=v_pi.team_id returning budget into v_saldo;
  insert into public.transactions(league_id,team_id,tipo,importo,descrizione,saldo_dopo) values(v_l.id,v_pi.team_id,'sblocco_ingaggio',v_r,'Ingaggio residuo sbloccato: svincolo',v_saldo);
  return v_esito;
end $$;
revoke all on function public.svincola_giocatore_cassa_legacy(bigint) from public,anon,authenticated;
grant execute on function public.svincola_giocatore(bigint) to authenticated;

-- Anche le aste vincenti entrano nella riserva: la funzione storica resta
-- responsabile di soglia, precedenza e assegnazione del giocatore.
alter function private.risolvi_aste_giorno(date,bigint) rename to risolvi_aste_giorno_cassa_legacy;
create or replace function private.risolvi_aste_giorno(p_giorno date,p_league_id bigint default null)
returns integer language plpgsql security definer set search_path='' as $$
declare v_da timestamptz:=clock_timestamp(); v_n integer; r record; v_prorata bigint; v_saldo bigint;
begin
  v_n:=private.risolvi_aste_giorno_cassa_legacy(p_giorno,p_league_id);
  for r in
    select a.id,a.league_id,a.vincitore_team_id,a.ingaggio_finale,l.giornate_totali
    from public.free_agent_auctions a join public.leagues l on l.id=a.league_id
    where a.stato='assegnata' and a.risolta_il>=v_da and (p_league_id is null or a.league_id=p_league_id)
  loop
    v_prorata:=private.ingaggio_residuo_stagione(r.ingaggio_finale,
      (select count(distinct giornata)::integer from public.fixtures where league_id=r.league_id and stato='simulata'),r.giornate_totali);
    update public.teams set budget=budget+v_prorata,budget_ingaggi_riservato=budget_ingaggi_riservato+v_prorata
    where id=r.vincitore_team_id returning budget into v_saldo;
    insert into public.transactions(league_id,team_id,tipo,importo,descrizione,saldo_dopo)
    values(r.league_id,r.vincitore_team_id,'rettifica_riserva_ingaggi',v_prorata,'Ingaggio asta trasferito in riserva',v_saldo);
  end loop;
  return v_n;
end $$;
revoke all on function private.risolvi_aste_giorno(date,bigint) from public,anon,authenticated;
grant execute on function private.risolvi_aste_giorno(date,bigint) to service_role;
