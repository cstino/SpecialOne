-- Gli svincolati vecchi restano rioffribili.
-- I "nuovi oggi" sono solo una vetrina giornaliera; se un giocatore resta
-- senza squadra, dall'archivio il client puo' riaprirlo in asta per oggi.

alter table public.free_agent_auctions
  drop constraint if exists free_agent_auctions_origine_check;

alter table public.free_agent_auctions
  add constraint free_agent_auctions_origine_check
  check (origine in ('estrazione', 'spin_offseason', 'archivio'));

create or replace function public.offri_per_svincolato_archivio(
  p_league_id bigint,
  p_player_id bigint,
  p_ingaggio  bigint
)
returns public.free_agent_bids
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_player public.players;
  v_squadra public.teams;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_asta_id bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega
  from public.leagues
  where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where league_id = p_league_id
    and user_id = v_user
    and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select * into v_player
  from public.players
  where id = p_player_id
    and campionato = any(v_lega.campionati_attivi);
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non disponibile in questa lega.';
  end if;

  if exists (
    select 1
    from public.player_instances pi
    where pi.league_id = p_league_id
      and pi.player_id = p_player_id
      and pi.team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' sotto contratto.';
  end if;

  select id into v_asta_id
  from public.free_agent_auctions
  where league_id = p_league_id
    and giorno = v_giorno
    and player_id = p_player_id
    and stato = 'aperta'
  limit 1;

  if v_asta_id is null then
    insert into public.free_agent_auctions(league_id, giorno, player_id, ingaggio_teorico, origine)
    values (p_league_id, v_giorno, p_player_id, private.ingaggio_teorico(v_player.overall, v_player.eta), 'archivio')
    on conflict (league_id, giorno, player_id) do update
      set stato = case
            when public.free_agent_auctions.stato = 'aperta' then public.free_agent_auctions.stato
            else public.free_agent_auctions.stato
          end
    returning id into v_asta_id;

    if not exists (select 1 from public.free_agent_auctions where id = v_asta_id and stato = 'aperta') then
      raise exception using errcode = '55000', message = 'Questo giocatore ha gia'' un esito oggi.';
    end if;

    insert into private.auction_thresholds(auction_id, soglia)
    select v_asta_id, round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20))
    where not exists (select 1 from private.auction_thresholds where auction_id = v_asta_id);
  end if;

  return public.offri_per_svincolato(v_asta_id, p_ingaggio);
end;
$$;

revoke all on function public.offri_per_svincolato_archivio(bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function public.offri_per_svincolato_archivio(bigint, bigint, bigint) to authenticated;
