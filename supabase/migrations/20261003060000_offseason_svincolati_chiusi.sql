-- ============================================================
--  OFF-SEASON: NIENTE ESTRAZIONE SERALE E NIENTE OFFERTE DALL'ARCHIVIO
--  Completa 20261003050000: con il mercato svincolati chiuso in off-season,
--  l'estrazione delle 23:30 salta le leghe in off-season (non nascono aste
--  in cui non si puo' offrire) e anche l'offerta dall'archivio rifiuta.
-- ============================================================

CREATE OR REPLACE FUNCTION private.estrai_svincolati()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_oggi date;
  v_ora time;
  v_inizio_finestra timestamptz;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;

  -- Le 23:30 di stasera, ora di Roma: tutto cio' che e' stato estratto
  -- prima appartiene a un'apertura manuale dell'admin, non a questo giro.
  v_inizio_finestra := (v_oggi + time '23:30') at time zone 'Europe/Rome';

  for v_lega in select id from public.leagues where stato = 'stagione' and fase_carriera <> 'offseason' and not mercato_bloccato loop
    -- Con la schedule a ogni minuto questa funzione rigira fino alle
    -- 23:45: senza questa guardia creerebbe una tornata nuova ogni volta.
    -- Le riesecuzioni servono da rete se il primo giro fallisce.
    if exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = v_lega
        and a.giorno = v_oggi
        and a.origine = 'estrazione'
        and a.creata_il >= v_inizio_finestra
    ) then
      continue;
    end if;

    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.offri_per_svincolato_archivio(p_league_id bigint, p_player_id bigint, p_ingaggio bigint)
 RETURNS free_agent_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_player public.players;
  v_squadra public.teams;
  v_giorno date := (now() at time zone 'Europe/Rome')::date;
  v_asta public.free_agent_auctions;
  v_asta_id bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  if exists (select 1 from public.leagues l where l.id = p_league_id and l.fase_carriera = 'offseason') then
    raise exception using errcode = '55000',
      message = 'In off-season il mercato degli svincolati è chiuso: riapre con la nuova stagione.';
  end if;
  if not private.mercato_aperto_lega(p_league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  select * into v_squadra
  from public.teams
  where league_id = p_league_id and user_id = v_user and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  select * into v_player
  from public.players
  where id = p_player_id and campionato = any(v_lega.campionati_attivi);
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non disponibile in questa lega.';
  end if;
  if exists (
    select 1 from public.player_instances pi
    where pi.league_id = p_league_id and pi.player_id = p_player_id and pi.team_id is not null
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore e'' gia'' sotto contratto.';
  end if;
  if exists (
    select 1 from public.retired_players rp
    where rp.league_id = p_league_id and rp.player_id = p_player_id
  ) then
    raise exception using errcode = '23505', message = 'Questo giocatore si e'' ritirato.';
  end if;

  select * into v_asta
  from public.free_agent_auctions
  where league_id = p_league_id and giorno = v_giorno and player_id = p_player_id
  for update;

  if found then
    v_asta_id := v_asta.id;
    if v_asta.stato = 'deserta' then
      delete from public.free_agent_bids where auction_id = v_asta_id;
      update public.free_agent_auctions
      set stato = 'aperta', origine = 'archivio', tornata = 0,
          risolta_il = null, vincitore_team_id = null, ingaggio_finale = null
      where id = v_asta_id;
      update private.auction_thresholds
      set soglia = round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20))
      where auction_id = v_asta_id;
    elsif v_asta.stato <> 'aperta' then
      raise exception using errcode = '55000', message = 'Questo giocatore ha gia'' un esito oggi.';
    end if;
  else
    insert into public.free_agent_auctions
      (league_id, giorno, player_id, ingaggio_teorico, origine, tornata)
    values (p_league_id, v_giorno, p_player_id,
            private.ingaggio_teorico(v_player.overall, v_player.eta), 'archivio', 0)
    returning id into v_asta_id;
    insert into private.auction_thresholds(auction_id, soglia)
    values (v_asta_id,
            round(private.ingaggio_teorico(v_player.overall, v_player.eta) * (0.90 + random() * 0.20)));
  end if;

  return public.offri_per_svincolato(v_asta_id, p_ingaggio);
end;
$function$
;
