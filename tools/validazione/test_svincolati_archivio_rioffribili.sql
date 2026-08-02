begin;

create temp table risultati_svincolati_archivio (
  step text primary key,
  ok boolean not null,
  dettaglio text
) on commit drop;

grant insert, select on risultati_svincolati_archivio to authenticated;

do $$
declare
  v_league_id bigint := 3;
  v_user uuid := '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266';
  v_team_id bigint := 4;
  v_player_id bigint;
  v_old_auction bigint;
  v_bid public.free_agent_bids;
  v_today date := (now() at time zone 'Europe/Rome')::date;
  v_new_auction record;
begin
  select p.id
  into v_player_id
  from public.players p
  join public.leagues l on l.id = v_league_id and p.campionato = any(l.campionati_attivi)
  where not exists (
    select 1 from public.player_instances pi
    where pi.league_id = v_league_id
      and pi.player_id = p.id
      and pi.team_id is not null
  )
  and not exists (
    select 1 from public.free_agent_auctions a
    where a.league_id = v_league_id
      and a.giorno = v_today
      and a.player_id = p.id
  )
  order by p.overall desc
  limit 1;

  if v_player_id is null then
    raise exception using errcode = 'P0002', message = 'Nessun giocatore libero disponibile per il test.';
  end if;

  insert into public.free_agent_auctions(league_id, giorno, player_id, ingaggio_teorico, stato, origine, risolta_il)
  select v_league_id, date '2099-09-01', p.id, private.ingaggio_teorico(p.overall, p.eta), 'deserta', 'estrazione', now()
  from public.players p
  where p.id = v_player_id
  returning id into v_old_auction;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  v_bid := public.offri_per_svincolato_archivio(v_league_id, v_player_id, 1000000::bigint);

  select *
  into v_new_auction
  from public.free_agent_auctions
  where id = v_bid.auction_id;

  insert into risultati_svincolati_archivio
  values (
    'riofferta archivio',
    v_new_auction.league_id = v_league_id
      and v_new_auction.player_id = v_player_id
      and v_new_auction.giorno = v_today
      and v_new_auction.origine = 'archivio'
      and v_new_auction.stato = 'aperta'
      and v_bid.team_id = v_team_id
      and v_bid.ingaggio_offerto = 1000000,
    jsonb_build_object(
      'old_auction', v_old_auction,
      'new_auction', v_new_auction.id,
      'origine', v_new_auction.origine,
      'bid', v_bid.id
    )::text
  );
end $$;

select * from risultati_svincolati_archivio order by step;

rollback;
