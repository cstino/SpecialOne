-- ============================================================
--  ASTE: OFFRIRE IMPEGNA IL BUDGET (E UNO SLOT)
--
--  Decisione dell'utente, 2 agosto 2026: quando offro per un giocatore il
--  denaro viene bloccato preventivamente.
--
--  Risolve il buco aperto dalla rimozione del tetto di 3 vittorie. Senza
--  impegno si poteva offrire su tutti e dieci gli svincolati avendo i soldi
--  per quattro, e alle 21:00 se ne vincevano quattro **arbitrari**, scelti
--  dall'ordine di estrazione e non da una decisione del giocatore. Con
--  l'impegno il problema non si pone: non ci si puo' impegnare oltre le
--  proprie possibilita', quindi tutto cio' su cui si e' offerto e' anche
--  tutto cio' che si puo' pagare.
--
--  IMPEGNO CALCOLATO, NON DENARO SPOSTATO. Il budget non viene scalato per
--  davvero: si sottrae la somma delle offerte ancora in gioco. Scalare e poi
--  rimborsare avrebbe richiesto un percorso di rimborso affidabile per ogni
--  asta persa, ritirata o deserta, e un solo difetto in quel percorso
--  distruggerebbe denaro. Un impegno calcolato si annulla da solo: ritirare
--  l'offerta lo libera all'istante, e a risoluzione avvenuta l'asta non e'
--  piu' 'aperta' e sparisce dal conto.
--
--  Lo stesso vale per gli SLOT di rosa, che avevano identico problema: si
--  poteva offrire per dieci giocatori con due posti liberi.
-- ============================================================

-- Somma dei pro-rata delle offerte su aste ancora aperte. `p_escludi` serve
-- quando si sta sostituendo la propria offerta su una certa asta: quella
-- vecchia non va contata contro la nuova.
create or replace function private.budget_impegnato(
  p_team_id  bigint,
  p_escludi  bigint default null
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(
    round(b.ingaggio_offerto::numeric
          * private.giornate_rimanenti(l.id)
          / greatest(l.giornate_totali, 1))
  ), 0)::bigint
  from public.free_agent_bids b
  join public.free_agent_auctions a on a.id = b.auction_id
  join public.leagues l on l.id = a.league_id
  where b.team_id = p_team_id
    and a.stato = 'aperta'
    and (p_escludi is null or b.auction_id <> p_escludi);
$$;

create or replace function private.slot_impegnati(
  p_team_id bigint,
  p_escludi bigint default null
)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer
  from public.free_agent_bids b
  join public.free_agent_auctions a on a.id = b.auction_id
  where b.team_id = p_team_id
    and a.stato = 'aperta'
    and (p_escludi is null or b.auction_id <> p_escludi);
$$;

revoke all on function private.budget_impegnato(bigint, bigint) from public, anon;
revoke all on function private.slot_impegnati(bigint, bigint)  from public, anon;
-- Le legge anche il browser, per mostrare quanto resta davvero disponibile.
grant execute on function private.budget_impegnato(bigint, bigint) to authenticated, service_role;
grant execute on function private.slot_impegnati(bigint, bigint)  to authenticated, service_role;

-- Wrapper pubblico: il browser non puo' chiamare `private`, e ha bisogno di
-- sapere quanto gli resta prima di comporre un'offerta.
create or replace function public.budget_disponibile(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_squadra public.teams;
  v_lega    public.leagues;
  v_rosa    integer;
begin
  select * into v_squadra from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;

  return jsonb_build_object(
    'budget',            v_squadra.budget,
    'impegnato',         private.budget_impegnato(v_squadra.id),
    'disponibile',       v_squadra.budget - private.budget_impegnato(v_squadra.id),
    'rosa',              v_rosa,
    'slot_impegnati',    private.slot_impegnati(v_squadra.id),
    'slot_liberi',       v_lega.slot_rosa - v_rosa - private.slot_impegnati(v_squadra.id)
  );
end;
$$;

revoke all on function public.budget_disponibile(bigint) from public, anon;
grant execute on function public.budget_disponibile(bigint) to authenticated;

-- ------------------------------------------------------------
--  Offrire: ora conta il disponibile, non il budget lordo.
-- ------------------------------------------------------------

create or replace function public.offri_per_svincolato(
  p_auction_id bigint,
  p_ingaggio   bigint
)
returns public.free_agent_bids
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_lega       public.leagues;
  v_squadra    public.teams;
  v_rosa       integer;
  v_prorata    bigint;
  v_impegnato  bigint;
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
    raise exception using errcode = '55000', message = 'Questa asta e'' gia'' stata risolta.';
  end if;
  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si offre dalle 07:00 alle 21:00.';
  end if;

  select * into v_lega from public.leagues where id = v_asta.league_id;
  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo e'' 0,5 M€.';
  end if;

  -- Slot: quelli occupati piu' quelli gia' impegnati dalle altre offerte.
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > v_lega.slot_rosa then
    raise exception using errcode = '22023',
      message = 'Non hai piu'' posti liberi: hai ' || v_rosa || ' giocatori e '
                || v_slot_altri || ' offerte gia'' in gioco, su ' || v_lega.slot_rosa || ' slot.';
  end if;

  -- Budget: il pro-rata di questa offerta deve stare in cio' che resta dopo
  -- aver messo da parte quello delle altre offerte ancora aperte.
  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  v_impegnato := private.budget_impegnato(v_squadra.id, p_auction_id);

  if v_squadra.budget - v_impegnato < v_prorata then
    raise exception using errcode = '22023',
      message = 'Budget insufficiente: hai gia'' impegnato '
                || round(v_impegnato / 100000.0) / 10.0 || ' M€ in altre offerte, '
                || 'te ne restano ' || round((v_squadra.budget - v_impegnato) / 100000.0) / 10.0
                || ' M€ e questa ne richiede ' || round(v_prorata / 100000.0) / 10.0 || ' M€.';
  end if;

  -- Modificare l'offerta fa perdere la precedenza: l'orario riparte da adesso.
  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;

  return v_offerta;
end;
$$;
