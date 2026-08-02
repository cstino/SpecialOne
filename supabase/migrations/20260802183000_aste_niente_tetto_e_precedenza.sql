-- ============================================================
--  ASTE: VIA IL TETTO DI 3, E IL PAREGGIO LO VINCE CHI HA OFFERTO PRIMA
--
--  Due correzioni decise dall'utente il 2 agosto 2026. Vincono su design
--  §9.4, che diceva il contrario in entrambi i casi.
--
--  1. NIENTE TETTO. §9.4 vietava di vincere piu' di 3 aste al giorno. Il
--     vincolo e' impraticabile per come funziona la giornata: la lista esce
--     completa alle 07:00 e nessuno viene assegnato fino alle 21:00, quindi
--     si offre su tutti e si scopre solo alla fine quante se ne sono vinte.
--     Un tetto su cui non puoi calibrare le offerte non e' una scelta, e'
--     una sorpresa. Se hai i soldi, puoi prenderli tutti.
--
--  2. PAREGGIO: PRECEDENZA A CHI HA OFFERTO PRIMA, non piu' sorteggio.
--     Con l'ordine di arrivo, offrire presto vale qualcosa.
--
--  Conseguenza della (2): il momento che conta e' quello in cui e' stato
--  fissato l'importo ATTUALE, non la prima offerta in assoluto. Altrimenti
--  si potrebbe piazzare 0,5 M€ su tutto alle 07:00 solo per prenotare la
--  precedenza, e alzare l'offerta alle 20:59 tenendosela. La colonna viene
--  percio' rinominata: si chiamava `creata_il` ma veniva gia' riscritta a
--  ogni modifica, e il nome mentiva.
--
--  Conseguenza della (1): senza tetto, l'unico limite e' il budget. Quando
--  finisce a meta' risoluzione, quali aste si vincono dipende dall'ordine in
--  cui vengono processate, cioe' dall'ordine di estrazione.
-- ============================================================

alter table public.free_agent_bids rename column creata_il to aggiornata_il;

comment on column public.free_agent_bids.aggiornata_il is
  'Quando e'' stato fissato l''importo attuale. Modificare l''offerta lo riazzera: '
  'e'' il criterio di precedenza a parita'' di cifra.';

-- ------------------------------------------------------------
--  Offrire: nessun cambiamento di regola, solo il nuovo nome di colonna.
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
  v_utente    uuid := (select auth.uid());
  v_asta      public.free_agent_auctions;
  v_lega      public.leagues;
  v_squadra   public.teams;
  v_rosa      integer;
  v_prorata   bigint;
  v_offerta   public.free_agent_bids;
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

  select count(*) into v_rosa
  from public.player_instances where team_id = v_squadra.id;
  if v_rosa >= v_lega.slot_rosa then
    raise exception using errcode = '22023', message = 'La tua rosa e'' gia'' al completo.';
  end if;

  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  if v_squadra.budget < v_prorata then
    raise exception using errcode = '22023',
      message = 'Non hai budget per sostenere questo ingaggio fino a fine stagione.';
  end if;

  -- Si puo' correggere la propria offerta fino alla chiusura, ma modificarla
  -- fa perdere la precedenza: l'orario riparte da adesso.
  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;

  return v_offerta;
end;
$$;

-- ------------------------------------------------------------
--  Risoluzione: via il tetto, precedenza all'offerta piu' vecchia.
-- ------------------------------------------------------------

create or replace function private.risolvi_aste_giorno(p_giorno date)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asta      record;
  v_soglia    bigint;
  v_vincitore record;
  v_lega      public.leagues;
  v_prorata   bigint;
  v_nome      text;
  v_assegnate integer := 0;
  v_off       record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
    order by a.id
    for update
  loop
    select * into v_lega from public.leagues where id = v_asta.league_id;
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      -- Nessun tetto di vittorie giornaliere: se il budget regge, si vince.
      -- Restano i due limiti reali, ricontrollati adesso perche' fra
      -- l'offerta e le 21:00 la squadra puo' aver comprato altrove.
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < v_lega.slot_rosa
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    -- Cifra piu' alta; a parita' chi l'ha messa sul tavolo per primo.
    -- L'id chiude ogni residua ambiguita' e rende l'esito riproducibile.
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      v_prorata := round(v_vincitore.ingaggio_offerto::numeric
                         * private.giornate_rimanenti(v_lega.id)
                         / greatest(v_lega.giornate_totali, 1));

      insert into public.player_instances
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id;

      update public.teams set budget = budget - v_prorata where id = v_vincitore.team_id;

      if v_prorata <> 0 then
        insert into public.transactions
          (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato', -v_prorata,
               'Asta vinta: ' || v_nome,
               (select budget from public.teams where id = v_vincitore.team_id);
      end if;

      update public.free_agent_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      v_assegnate := v_assegnate + 1;
    end if;

    -- L'offerta vincente viene rivelata a tutta la lega: `vincitore_team_id`
    -- e `ingaggio_finale` stanno sull'asta, che i membri leggono. Le offerte
    -- perdenti restano private, e chi ha offerto riceve comunque l'avviso.
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
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di un anno.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) ||
               ' per ' || round(v_vincitore.ingaggio_offerto / 100000.0) / 10.0 || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;
