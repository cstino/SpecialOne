-- ============================================================
--  TRATTATIVA VERA PER LA PROMOZIONE DI UN PROSPETTO VIVAIO.
--
--  Deciso con l'utente il 4 settembre 2026: promuovere un prospetto non
--  deve piu' assegnare l'ingaggio in automatico (public.promuovi_vivaio
--  faceva solo greatest(500000, ingaggio_vivaio)) — va trattato come un
--  vero primo contratto, con la stessa meccanica gia' in uso per il
--  rinnovo dei giocatori in rosa (proposta_rinnovo/offri_rinnovo):
--  richiesta calcolata da private.rinnovo_proposta, tolleranza da
--  private.rinnovo_tolleranza, verifica_capienza sul tetto ingaggi.
--
--  Differenze rispetto al rinnovo (non e' un rinnovo, e' un primo
--  contratto su un giocatore che non ha ancora player_instances):
--  - il "morale" non esiste per un prospetto mai sceso in campo: si usa
--    un valore neutro (50), stesso spirito del fallback ?? 33 gia' usato
--    in frontend per mentalita' mancante.
--  - non c'e' "gia' promosso in questa stagione" (un prospetto si
--    promuove una volta sola, non e' un ciclo stagionale ripetuto).
--  - deciso con l'utente: 3 tentativi come il rinnovo, ma qui SENZA
--    reset — esauriti, la trattativa e' chiusa per sempre (non si
--    riapre alla prossima giornata). Il prospetto resta comunque in
--    cantera finche' non scade il countdown in giornate gia' esistente
--    (public.decrementa_vivaio_giornate), che a quel punto lo rilascia
--    sul mercato UNDER — stesso destino di un prospetto mai trattato.
--
--  public.promuovi_vivaio (promozione istantanea senza trattativa) viene
--  eliminata: era concessa a "authenticated" e chiamabile direttamente
--  dal client, quindi bypassava la trattativa se lasciata in vita.
-- ============================================================

begin;

alter table public.vivaio_prospetti
  add column promozione_tentativi smallint not null default 0
    check (promozione_tentativi between 0 and 3);

comment on column public.vivaio_prospetti.promozione_tentativi is
  'Tentativi di trattativa per la promozione, come rinnovo_tentativi ma senza reset: esauriti i 3, la trattativa e'' chiusa per sempre.';

drop function if exists public.promuovi_vivaio(bigint);

create function public.proposta_promozione(p_vivaio_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;
  if not exists (
    select 1 from public.teams where id = v_prospetto.team_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  select * into v_league from public.leagues where id = v_prospetto.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La promozione si tratta solo a stagione avviata.';
  end if;

  select * into v_player from public.players where id = v_prospetto.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  return jsonb_build_object(
    'ingaggio_attuale', v_prospetto.ingaggio,
    'richiesta', v_proposta.richiesta,
    'tentativi_usati', v_prospetto.promozione_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_prospetto.promozione_tentativi >= 3
  );
end;
$$;

revoke all on function public.proposta_promozione(bigint) from public, anon;
grant execute on function public.proposta_promozione(bigint) to authenticated;

create function public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_squadra public.teams;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_rapporto numeric;
  v_tentativi smallint;
  v_rosa integer;
  v_prossima integer;
  v_istanza public.player_instances;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select * into v_prospetto from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Prospetto non trovato.';
  end if;

  select * into v_squadra from public.teams where id = v_prospetto.team_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Questo prospetto non è tuo.';
  end if;

  select * into v_league from public.leagues where id = v_prospetto.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La promozione si tratta solo a stagione avviata.';
  end if;
  if v_prospetto.promozione_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: resterà in cantera finché non scade il countdown.';
  end if;

  select count(*)::integer into v_rosa
  from public.player_instances where team_id = v_squadra.id and not ritirato;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'La rosa è già al completo (' || private.rosa_massima() || '): libera un posto prima di promuovere.';
  end if;

  select * into v_player from public.players where id = v_prospetto.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_squadra.id
  where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    50::smallint, coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint),
    coalesce(v_player.mentalita_vittorie, 34::smallint), coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));

    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_league.id and f.stato = 'programmata';

    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione)
    values
      (v_prospetto.league_id, v_prospetto.player_id, v_squadra.id,
       v_player.overall, v_player.eta, p_ingaggio, v_prossima)
    returning * into v_istanza;

    delete from public.vivaio_prospetti where id = v_prospetto.id;

    perform private.notifica(v_user_id, v_league.id, 'sistema', 'Prospetto promosso in prima squadra',
      v_player.nome || ' firma il primo contratto: ' || private.in_milioni(p_ingaggio) || ' M€ a stagione.',
      jsonb_build_object('player_instance_id', v_istanza.id));

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Non vedo l''ora di debuttare.'
    );
  end if;

  v_tentativi := (v_prospetto.promozione_tentativi + 1)::smallint;
  update public.vivaio_prospetti set promozione_tentativi = v_tentativi where id = v_prospetto.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Va bene, mister: resto in cantera e aspetto.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$$;

revoke all on function public.offri_promozione(bigint, bigint) from public, anon;
grant execute on function public.offri_promozione(bigint, bigint) to authenticated;

commit;
