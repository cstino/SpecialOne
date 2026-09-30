-- ============================================================
--  L'OFF-SEASON SI APRE 24 ORE DOPO L'ULTIMA GIORNATA
--
--  Finita l'ultima partita (finale dei playoff compresa) la lega passa a
--  'conclusa' e l'app mandava subito all'off-season: chi non aveva ancora
--  guardato i risultati se li trovava scavalcati. Ora l'admin puo' aprire
--  l'off-season solo dopo 24 ore dall'ultima partita simulata, e l'app tiene
--  le schermate di stagione finche' il termine non scade.
--
--  Una sola fonte per l'orario: private.sblocco_offseason(), usata sia dal
--  controllo in prepara_offseason sia dalla RPC pubblica che legge il client.
--  Se la lega non ha partite simulate torna null (nessun blocco).
-- ============================================================

create or replace function private.sblocco_offseason(p_league_id bigint)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select max(m.simulata_il) + interval '24 hours'
  from public.matches m
  where m.league_id = p_league_id;
$$;

create or replace function public.sblocco_offseason(p_league_id bigint)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  return private.sblocco_offseason(p_league_id);
end;
$$;

revoke all on function public.sblocco_offseason(bigint) from public, anon;
grant execute on function public.sblocco_offseason(bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if clock_timestamp() < private.sblocco_offseason(p_league_id) then
    raise exception using errcode = '55000', message = format(
      'L''off-season si apre 24 ore dopo l''ultima giornata: da %s, così tutti possono rivedere i risultati.',
      to_char(private.sblocco_offseason(p_league_id) at time zone 'Europe/Rome', 'DD/MM "alle" HH24:MI'));
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Invecchiamento di fine stagione: il join sulla squadra attiva e'
  -- stato tolto (deciso il 30 agosto 2026), cosi' uno svincolato reale
  -- invecchia esattamente come chi e' in rosa.
  for v_player in
    select pi.id, pi.eta_corrente, pi.infortunato_fino_a
    from public.player_instances pi
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        -- La pausa fra due stagioni vale 6 giornate di recupero, non una
        -- guarigione completa (deciso con l'utente l'11 settembre 2026).
        -- Prima qui si azzerava: chi si rompeva per 10 giornate all'ultima
        -- di playoff ripartiva sano, e un infortunio grave di fine stagione
        -- non costava niente. Ora se ne porta dietro 4.
        infortunato_fino_a = greatest(0, v_player.infortunato_fino_a - 6),
        -- Fedina pulita a ogni nuova stagione, come all'inizio dei playoff:
        -- ne' il conto delle ammonizioni ne' una squalifica gia' maturata
        -- attraversano il confine fra due stagioni.
        ammonizioni_stagione = 0,
        squalificato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  -- Stesso invecchiamento per chi non e' mai stato scelto in questa lega,
  -- residuo azzerato come per player_instances.
  update public.free_agent_progression
  set eta_corrente = least(45, eta_corrente + 1), progressione_residuo = 0, aggiornato_il = now()
  where league_id = p_league_id;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$;
