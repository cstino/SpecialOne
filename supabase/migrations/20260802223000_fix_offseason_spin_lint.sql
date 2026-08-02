create or replace function public.spin_offseason(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_ctx record;
  v_usati integer;
  v_rosa integer;
  v_impegnati integer;
  v_budget_disponibile bigint;
  v_player public.players;
  v_ingaggio bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_ctx from private.offseason_spin_corrente(p_league_id, v_user);
  if not found then
    raise exception using errcode = '55000', message = 'Gli spin off-season non sono attivi.';
  end if;

  if exists (
    select 1 from public.offseason_spins
    where offseason_id = (v_ctx.v_offseason).id
      and team_id = (v_ctx.v_team).id
      and stato = 'proposto'
  ) then
    raise exception using errcode = '55000', message = 'Hai gia'' uno spin aperto: ingaggialo o mandalo al mercato.';
  end if;

  select count(*)::integer into v_usati
  from public.offseason_spins
  where offseason_id = (v_ctx.v_offseason).id
    and team_id = (v_ctx.v_team).id;
  if v_usati >= 5 then
    raise exception using errcode = '54000', message = 'Hai gia'' usato tutti e 5 gli spin off-season.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances
  where team_id = (v_ctx.v_team).id;
  v_impegnati := private.slot_impegnati((v_ctx.v_team).id);
  if v_rosa + v_impegnati + 1 > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Non hai posti liberi per usare uno spin.';
  end if;

  v_budget_disponibile := (v_ctx.v_team).budget - private.budget_impegnato((v_ctx.v_team).id);

  select p.* into v_player
  from public.players p
  where p.campionato = any((v_ctx.v_league).campionati_attivi)
    and v_budget_disponibile >= private.ingaggio_teorico(p.overall, p.eta)
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id
        and pi.player_id = p.id
        and pi.team_id is not null
    )
    and not exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = p_league_id
        and a.player_id = p.id
        and a.stato = 'aperta'
    )
    and not exists (
      select 1 from public.offseason_spins s
      where s.league_id = p_league_id
        and s.player_id = p.id
    )
  order by random()
  limit 1;

  if not found then
    raise exception using errcode = '55000', message = 'Non ci sono giocatori sostenibili disponibili per gli spin.';
  end if;

  v_ingaggio := private.ingaggio_teorico(v_player.overall, v_player.eta);
  insert into public.offseason_spins(offseason_id, league_id, team_id, player_id, ingaggio)
  values ((v_ctx.v_offseason).id, p_league_id, (v_ctx.v_team).id, v_player.id, v_ingaggio);

  return public.stato_spin_offseason(p_league_id);
end;
$$;

revoke all on function public.spin_offseason(bigint) from public, anon, authenticated;
grant execute on function public.spin_offseason(bigint) to authenticated;

create or replace function public.manda_spin_al_mercato(p_spin_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_spin public.offseason_spins;
  v_league public.leagues;
  v_asta_id bigint;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare gli spin off-season.';
  end if;

  select * into v_spin from public.offseason_spins where id = p_spin_id for update;
  if not found or v_spin.stato <> 'proposto' then
    raise exception using errcode = '55000', message = 'Questo spin non puo'' essere mandato al mercato.';
  end if;

  perform 1 from public.teams where id = v_spin.team_id and user_id = v_user and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo spin non appartiene alla tua squadra.';
  end if;

  select * into v_league from public.leagues where id = v_spin.league_id;
  if v_league.fase_carriera <> 'offseason' or now() >= v_league.offseason_fine then
    raise exception using errcode = '55000', message = 'La finestra off-season e'' terminata.';
  end if;

  if exists (
    select 1 from public.player_instances
    where league_id = v_spin.league_id
      and player_id = v_spin.player_id
      and team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' stato preso.';
  end if;

  insert into public.free_agent_auctions(league_id, giorno, player_id, ingaggio_teorico, origine)
  values (v_spin.league_id, v_giorno, v_spin.player_id, v_spin.ingaggio, 'spin_offseason')
  on conflict (league_id, giorno, player_id) do nothing
  returning id into v_asta_id;

  if v_asta_id is null then
    select id into v_asta_id
    from public.free_agent_auctions
    where league_id = v_spin.league_id
      and giorno = v_giorno
      and player_id = v_spin.player_id;
  end if;

  if v_asta_id is null then
    raise exception using errcode = '55000', message = 'Non riesco ad aprire l''asta per questo giocatore.';
  end if;

  insert into private.auction_thresholds(auction_id, soglia)
  values (v_asta_id, round(v_spin.ingaggio * (0.90 + random() * 0.20)))
  on conflict (auction_id) do nothing;

  update public.offseason_spins
  set stato = 'asta', risolta_il = now()
  where id = v_spin.id;

  return public.stato_spin_offseason(v_spin.league_id);
end;
$$;

revoke all on function public.manda_spin_al_mercato(bigint) from public, anon, authenticated;
grant execute on function public.manda_spin_al_mercato(bigint) to authenticated;
