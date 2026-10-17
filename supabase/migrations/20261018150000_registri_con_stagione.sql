-- ============================================================
--  Registri idempotenti con la stagione. Guarigione degli svincolati e conto alla rovescia del vivaio ricordavano
--  solo (lega, giornata): dalla seconda stagione la giornata 11 di quest'anno risultava "gia' eseguita" per colpa
--  dell'11 dell'anno scorso, e i due passaggi venivano saltati in silenzio (LegaBot stagione 5, Serie F stagione 2).
--  Ora la chiave e' (lega, stagione, giornata). Le righe vecchie restano come storico (stagione 0); le giornate
--  saltate non si recuperano, il conto riparte dalla prossima.
--  Funzioni riscritte dalla definizione viva.
-- ============================================================

begin;

alter table private.guarigioni_svincolati add column stagione smallint not null default 0;
alter table private.guarigioni_svincolati drop constraint guarigioni_svincolati_pkey;
alter table private.guarigioni_svincolati add primary key (league_id, stagione, giornata);

alter table private.vivaio_countdown_giornate add column stagione smallint not null default 0;
alter table private.vivaio_countdown_giornate drop constraint vivaio_countdown_giornate_pkey;
alter table private.vivaio_countdown_giornate add primary key (league_id, stagione, giornata);

CREATE OR REPLACE FUNCTION public.guarisci_svincolati(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_scalati  integer := 0;
  v_guariti  integer := 0;
begin
  insert into private.guarigioni_svincolati (league_id, stagione, giornata)
  values (p_league_id, (select l.stagione_corrente from public.leagues l where l.id = p_league_id), p_giornata)
  on conflict (league_id, stagione, giornata) do nothing;
  if not found then
    return jsonb_build_object('gia_eseguito', true, 'scalati', 0, 'guariti', 0);
  end if;

  with scalati as (
    update public.player_instances pi
    set infortunato_fino_a = greatest(0, pi.infortunato_fino_a - 1)
    where pi.league_id = p_league_id
      and pi.team_id is null
      and not pi.ritirato
      and pi.infortunato_fino_a > 0
    returning pi.infortunato_fino_a
  )
  select count(*)::integer, count(*) filter (where infortunato_fino_a = 0)::integer
  into v_scalati, v_guariti
  from scalati;

  return jsonb_build_object('gia_eseguito', false, 'scalati', v_scalati, 'guariti', v_guariti);
end;
$function$;

CREATE OR REPLACE FUNCTION public.decrementa_vivaio_giornate(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_scaduto record;
  v_nome text;
  v_rilasciati integer := 0;
begin
  insert into private.vivaio_countdown_giornate (league_id, stagione, giornata)
  values (p_league_id, (select l.stagione_corrente from public.leagues l where l.id = p_league_id), p_giornata)
  on conflict (league_id, stagione, giornata) do nothing;
  if not found then
    return jsonb_build_object('gia_eseguito', true, 'rilasciati', 0);
  end if;

  update public.vivaio_prospetti
  set giornate_rimanenti = giornate_rimanenti - 1
  where league_id = p_league_id;

  for v_scaduto in
    select vp.id, vp.league_id, vp.team_id, vp.player_id
    from public.vivaio_prospetti vp
    where vp.league_id = p_league_id and vp.giornate_rimanenti <= 0
    for update
  loop
    select p.nome into v_nome from public.players p where p.id = v_scaduto.player_id;
    delete from public.vivaio_prospetti where id = v_scaduto.id;
    insert into private.rilasci_vivaio_in_coda (league_id, player_id)
    values (v_scaduto.league_id, v_scaduto.player_id)
    on conflict (league_id, player_id) do nothing;
    perform private.notifica(
      (select user_id from public.teams where id = v_scaduto.team_id),
      v_scaduto.league_id, 'mercato_esito', 'Prospetto scaduto: ' || coalesce(v_nome, 'vivaio'),
      'Non è stato promosso in tempo: torna sul mercato UNDER.',
      jsonb_build_object('vivaio', true)
    );
    v_rilasciati := v_rilasciati + 1;
  end loop;

  return jsonb_build_object('gia_eseguito', false, 'rilasciati', v_rilasciati);
end;
$function$;

commit;
