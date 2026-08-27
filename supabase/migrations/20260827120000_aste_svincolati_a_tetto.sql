-- ============================================================
--  ECONOMIA A TETTO SALARIALE — passo 3a: aste sugli svincolati
--  docs/decisioni-economia.md §2, §3
--
--  Le aste smettono di costare contanti e iniziano a costare spazio
--  salariale. Offerta e risoluzione vanno cambiate INSIEME: se si mettesse
--  il tetto solo sulle offerte, un'offerta ammessa dal tetto ma senza
--  cassa passerebbe il controllo e poi la risoluzione notturna la
--  scarterebbe (o peggio, urterebbe il check budget >= 0). I due lati
--  devono usare lo stesso criterio nello stesso momento.
--
--  offri_per_svincolato_archivio non e' toccata: crea l'asta e poi delega a
--  offri_per_svincolato, quindi eredita il nuovo controllo.
-- ============================================================

-- ------------------------------------------------------------
--  Che stagione copre un contratto firmato adesso
--
--  In stagione: scade a fine stagione corrente (decisioni-economia §2).
--  In off-season: il contratto copre la stagione entrante, perche' la
--  stagione corrente e' finita.
--
--  Serve anche a draft e scambi ai passi successivi: meglio una funzione
--  sola che tre CASE copiati.
-- ------------------------------------------------------------

create or replace function private.stagione_contratto(p_league_id bigint)
returns smallint
language sql
stable
set search_path = ''
as $$
  select case when l.fase_carriera = 'offseason'
              then (l.stagione_corrente + 1)::smallint
              else l.stagione_corrente
         end
  from public.leagues l
  where l.id = p_league_id
$$;

comment on function private.stagione_contratto(bigint) is
  'Stagione coperta da un contratto firmato ora: la corrente, o la entrante se siamo in off-season.';

revoke all on function private.stagione_contratto(bigint) from public, anon, authenticated;
grant execute on function private.stagione_contratto(bigint) to authenticated, service_role;

-- ------------------------------------------------------------
--  Offerta: il vincolo e' la capienza, non la cassa
--
--  Sparisce tutto il calcolo pro-rata (l'ingaggio non si paga piu' a rate)
--  e sparisce budget_impegnato. Al loro posto verifica_capienza, che tiene
--  gia' conto delle altre offerte aperte tramite ingaggi_impegnati_aste.
--
--  Il controllo sugli slot di rosa resta identico: non e' economico.
-- ------------------------------------------------------------

create or replace function public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
returns free_agent_bids
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_squadra    public.teams;
  v_rosa       integer;
  v_slot_altri integer;
  v_offerta    public.free_agent_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.free_agent_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  if not private.mercato_aperto_lega(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 23:30 alle 21:00 o quando l''admin lo apre.';
  end if;

  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Non hai più posti liberi: ' || v_rosa || ' giocatori in rosa e '
                || v_slot_altri || ' offerte già in gioco, su un massimo di ' || private.rosa_massima() || ' giocatori.';
  end if;

  perform private.verifica_capienza(
    v_squadra.id,
    p_ingaggio,
    private.stagione_contratto(v_asta.league_id),
    p_auction_id);

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

revoke all on function public.offri_per_svincolato(bigint, bigint) from public, anon;
grant execute on function public.offri_per_svincolato(bigint, bigint) to authenticated;

-- ------------------------------------------------------------
--  Risoluzione: stesso criterio, e il contratto ha una scadenza esplicita
--
--  Tre differenze rispetto alla versione a cassa:
--
--  1. Il filtro sul vincitore usa la capienza invece del budget. Escludendo
--     l'asta corrente (p_escludi) si evita di contare l'offerta che si sta
--     valutando come se fosse gia' un impegno.
--
--  2. contratto_scadenza viene scritta esplicitamente. Prima non lo era, e
--     l'istanza prendeva il DEFAULT della colonna, che vale 1: dalla
--     stagione 2 in poi ogni asta vinta produceva un contratto gia' scaduto.
--     Era un bug latente, non una scelta.
--
--  3. Niente addebito: budget non viene toccato. La riga in transactions
--     resta per tracciabilita' (CLAUDE.md §6) e registra l'impegno di
--     spazio salariale; saldo_dopo continua a riportare la cassa, che in
--     questa fase di transizione esiste ancora ed e' semplicemente
--     invariata. Al passo 5 il registro cambiera' semantica.
--
--  Non chiama piu' risolvi_aste_giorno_cassa_legacy, che resta in piedi ma
--  inutilizzata.
-- ------------------------------------------------------------

create or replace function private.risolvi_aste_giorno(
  p_giorno date,
  p_league_id bigint default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_stagione          smallint;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < private.rosa_massima()
      and private.capienza_residua(b.team_id, v_stagione, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      -- Un giocatore svincolato conserva la propria istanza di lega: un
      -- insert semplice urterebbe unique(league_id, player_id). L'upsert
      -- riusa l'istanza solo se e' ancora libera; se nel frattempo e' stata
      -- assegnata altrove, questa sola asta fallisce senza segnarsi come
      -- conclusa (non l'intera risoluzione).
      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto, v_stagione
      from public.players p where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio,
            contratto_scadenza = excluded.contratto_scadenza
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      insert into public.transactions
        (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato',
             -v_vincitore.ingaggio_offerto,
             'Asta vinta: ' || v_nome || ' — ' ||
             private.in_milioni(v_vincitore.ingaggio_offerto) ||
             ' M€ di ingaggio fino alla stagione ' || v_stagione,
             (select budget from public.teams where id = v_vincitore.team_id);

      update public.free_agent_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      v_assegnate := v_assegnate + 1;
    end if;

    for v_off in
      select b.team_id, t.user_id from public.free_agent_bids b
      join public.teams t on t.id = b.team_id
      where b.auction_id = v_asta.id
    loop
      perform private.notifica(
        v_off.user_id, v_asta.league_id, 'mercato_asta',
        case when v_vincitore.id is not null and v_off.team_id = v_vincitore.team_id
             then 'Asta vinta: ' || v_nome
             else 'Asta persa: ' || v_nome end,
        case
          when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta del giocatore.'
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di una stagione.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) ||
               ' per ' || private.in_milioni(v_vincitore.ingaggio_offerto) || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste_giorno(date, bigint) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date, bigint) to service_role;
