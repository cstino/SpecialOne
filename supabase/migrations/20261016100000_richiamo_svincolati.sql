-- Richiamo degli svincolati (deciso il 16/10/2026). Uno svincolato in stagione resta "a carico" della squadra
-- (peso_team_id, ingaggio sul tetto) e torna ogni giorno nelle aste degli svincolati. Finche' nessuno lo prende e il
-- contratto non scade, la squadra puo' RICHIAMARLO: torna in rosa con lo stesso contratto. Regole:
--  - una volta sola per giocatore per stagione (richiamato_stagione);
--  - serve un posto libero in rosa (massimo 30);
--  - le aste aperte su di lui decadono e chi aveva offerto riceve una notifica;
--  - in off-season non c'e' richiamo: lo svincolo resta definitivo (non lascia peso_team_id).
alter table public.player_instances add column if not exists richiamato_stagione smallint;

create or replace function public.richiama_svincolato(p_instance_id bigint)
 returns public.player_instances
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_nome text;
  v_rosa integer;
  v_asta record;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per richiamare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_squadra from public.teams where id = v_istanza.peso_team_id and user_id = v_utente for update;
  if not found or v_istanza.team_id is not null then
    raise exception using errcode = '42501', message = 'Puoi richiamare solo un giocatore che hai svincolato e che nessuno ha ancora preso.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  select nome into v_nome from public.players where id = v_istanza.player_id;
  if v_lega.stato <> 'stagione' or v_lega.fase_carriera = 'offseason' then
    raise exception using errcode = '55000', message = 'Puoi richiamare un giocatore solo durante la stagione.';
  end if;
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi richiamare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;
  if v_istanza.ritirato or v_istanza.contratto_scadenza < private.stagione_contratto(v_lega.id) then
    raise exception using errcode = '22023', message = v_nome || ' non e'' piu'' sotto contratto con te: non puoi richiamarlo.';
  end if;
  if v_istanza.richiamato_stagione = v_lega.stagione_corrente then
    raise exception using errcode = '22023', message = v_nome || ' e'' gia'' stato richiamato una volta in questa stagione: non si puo'' richiamare di nuovo.';
  end if;
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023', message = 'La rosa e'' piena (' || private.rosa_massima() || ' giocatori): libera un posto per richiamare ' || v_nome || '.';
  end if;

  -- Le aste aperte su di lui decadono: chi aveva offerto lo viene a sapere.
  for v_asta in
    select a.id from public.free_agent_auctions a
    where a.league_id = v_lega.id and a.player_id = v_istanza.player_id and a.stato = 'aperta'
    for update
  loop
    perform private.notifica(t.user_id, v_lega.id, 'mercato_esito', 'Asta annullata',
      v_nome || ' e'' stato richiamato dalla sua squadra: l''asta e'' annullata e la tua offerta non vale piu''.',
      jsonb_build_object('player_id', v_istanza.player_id))
    from public.free_agent_bids b join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id and t.user_id is not null and t.id <> v_squadra.id;
    delete from public.free_agent_bids where auction_id = v_asta.id;
    update public.free_agent_auctions set stato = 'deserta', risolta_il = now() where id = v_asta.id;
  end loop;
  delete from private.rilasci_in_coda where league_id = v_lega.id and player_id = v_istanza.player_id;

  -- Torna in rosa con il suo contratto (il trigger azzera peso_team_id: l'ingaggio torna a pesare come titolare in rosa).
  update public.player_instances
  set team_id = v_squadra.id, richiamato_stagione = v_lega.stagione_corrente, sul_mercato = false
  where id = v_istanza.id returning * into v_istanza;

  perform private.notifica(v_utente, v_lega.id, 'mercato_esito', 'Giocatore richiamato',
    v_nome || ' torna nella tua rosa con il suo contratto. Non potrai richiamarlo di nuovo in questa stagione.',
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id));
  return v_istanza;
end;
$function$;
revoke all on function public.richiama_svincolato(bigint) from public;
grant execute on function public.richiama_svincolato(bigint) to authenticated;
