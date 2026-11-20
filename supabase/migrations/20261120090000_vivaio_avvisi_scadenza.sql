-- Vivaio: il prospetto avvisa l'allenatore prima che scada il suo tempo (richiesta del committente, 20/11/2026).
-- La Pro secco ha perso Magnus Diallo il 19/11 senza accorgersene: il timer scadeva in silenzio.
-- Ora il giocatore "scrive" all'allenatore due volte, come una notifica (anche push):
--   * a 5 giornate dalla fine, morbido: vorrebbe la prima squadra, altrimenti a fine contratto cercherà fortuna altrove;
--   * a 1 giornata dalla fine, aut aut: o la promozione prima della prossima partita, o se ne va.
-- Niente avviso a chi ha già chiuso la trattativa (3 tentativi usati: ha detto che resta finché non scade).
-- Il conto: dopo il passaggio di questa giornata restano N giornate; a 0 il prospetto se ne va (come prima).
create or replace function public.decrementa_vivaio_giornate(p_league_id bigint, p_giornata smallint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_scaduto record;
  v_avviso record;
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

  -- Gli avvisi del prospetto (20/11/2026).
  for v_avviso in
    select vp.id, vp.team_id, vp.giornate_rimanenti, p.nome
    from public.vivaio_prospetti vp
    join public.players p on p.id = vp.player_id
    where vp.league_id = p_league_id and vp.giornate_rimanenti in (5, 1) and vp.promozione_tentativi < 3
  loop
    perform private.vivaio_avvisa_scadenza(v_avviso.id);
  end loop;

  return jsonb_build_object('gia_eseguito', false, 'rilasciati', v_rilasciati);
end;
$function$;

-- Il messaggio del prospetto: a 2 o più giornate quello morbido (col numero vero), a 1 quello secco.
create or replace function private.vivaio_avvisa_scadenza(p_prospetto_id bigint)
 returns bigint
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v record;
  v_nome text;
begin
  select vp.id, vp.league_id, vp.team_id, vp.giornate_rimanenti, p.nome
    into v
    from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id
   where vp.id = p_prospetto_id;
  if not found or v.giornate_rimanenti < 1 then
    return null;
  end if;
  -- il cognome (o il nome intero se è uno solo) per il titolo: «Duarte: "Mister, …"»
  v_nome := coalesce(nullif(regexp_replace(v.nome, '^.*\s', ''), ''), v.nome);
  if v.giornate_rimanenti = 1 then
    return private.notifica(
      (select user_id from public.teams where id = v.team_id), v.league_id, 'mercato_proposta',
      v_nome || ': «Mister, è l''ultima occasione»',
      'Mister, il mio contratto da under scade con la prossima partita. O mi promuove in prima squadra prima di allora, '
        || 'o me ne vado. Non aspetto oltre.',
      jsonb_build_object('view', 'team', 'vivaio', true, 'vivaio_avviso', 1, 'prospetto_id', v.id));
  end if;
  return private.notifica(
    (select user_id from public.teams where id = v.team_id), v.league_id, 'mercato_proposta',
    v_nome || ': «Mister, posso parlarle?»',
    'Mister, tra ' || v.giornate_rimanenti || ' giornate scade il mio contratto da under. Mi piacerebbe essere promosso '
      || 'in prima squadra: se non succede, quando scade andrò a cercare fortuna altrove.',
    jsonb_build_object('view', 'team', 'vivaio', true, 'vivaio_avviso', v.giornate_rimanenti, 'prospetto_id', v.id));
end;
$function$;
revoke all on function private.vivaio_avvisa_scadenza(bigint) from public, anon, authenticated;

-- Chi oggi è già fra 2 e 5 giornate (e non ha chiuso la trattativa) riceve subito il primo avviso, col numero vero:
-- altrimenti salterebbe quello morbido e sentirebbe solo l'ultimatum.
select private.vivaio_avvisa_scadenza(vp.id)
  from public.vivaio_prospetti vp
 where vp.giornate_rimanenti between 2 and 5 and vp.promozione_tentativi < 3;
