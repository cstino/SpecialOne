-- ============================================================
--  SVINCOLO GIOCATORE  (design §9.5)
--
--  Libera immediatamente lo slot senza toccare il budget: l'ingaggio della
--  stagione corrente e' gia' stato pagato. L'istanza resta nella lega con
--  team_id null e rientra cosi' nel pool delle aste successive.
-- ============================================================

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_istanza     public.player_instances;
  v_squadra     public.teams;
  v_lega        public.leagues;
  v_giocatore   public.players;
  v_rosa        integer;
  v_portieri    integer;
  v_prossima    integer;
  v_form_tolte  integer := 0;
  v_nota        text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  -- Prima lettura per individuare la squadra. La riga viene ricontrollata
  -- dopo il lock: fra le due operazioni uno scambio potrebbe averla mossa.
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where id = v_istanza.team_id
    and user_id = v_utente;

  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  -- Tutte le operazioni che cambiano una rosa serializzano sulla squadra.
  -- Dopo il lock si ricontrolla la proprieta' dell'istanza.
  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id
    and team_id = v_squadra.id
  for update;

  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;

  if not private.mercato_aperto() then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: puoi svincolare dalle 07:00 alle 21:00.';
  end if;

  -- Si contano direttamente i giocatori che resterebbero, cosi' il controllo
  -- non dipende dal ruolo del giocatore svincolato calcolato a parte.
  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa, v_portieri
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id
    and pi.id <> v_istanza.id;

  if v_rosa < 11 then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto gli undici giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  select * into v_giocatore from public.players where id = v_istanza.player_id;

  -- Una formazione che contiene il giocatore non rappresenta piu' una scelta
  -- valida dell'utente. Si cancellano solo le giornate ancora da simulare.
  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_lega.id
    and f.stato = 'programmata';

  if v_prossima is not null then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id = v_squadra.id
      and giornata >= v_prossima
      and (
        titolari && array[v_istanza.id]::bigint[]
        or panchina && array[v_istanza.id]::bigint[]
        or tribuna && array[v_istanza.id]::bigint[]
      );
    get diagnostics v_form_tolte = row_count;
  end if;

  update public.player_instances
  set team_id = null
  where id = v_istanza.id
  returning * into v_istanza;

  if v_form_tolte > 0 then
    v_nota := ' La formazione delle prossime giornate va salvata di nuovo.';
  end if;

  perform private.notifica(
    v_utente,
    v_lega.id,
    'mercato_esito',
    'Giocatore svincolato',
    v_giocatore.nome || ' non fa piu'' parte della tua rosa.' || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );

  return v_istanza;
end;
$$;

comment on function public.svincola_giocatore(bigint) is
  'Svincola un proprio giocatore senza rimborso, preservando i minimi di rosa e portieri (design §9.5).';

revoke all on function public.svincola_giocatore(bigint) from public, anon, authenticated;
grant execute on function public.svincola_giocatore(bigint) to authenticated;

-- ------------------------------------------------------------
--  Rientro dello svincolato tramite asta
--
--  Un giocatore svincolato conserva la propria istanza di lega. Il resolver
--  precedente provava sempre a inserirne una nuova e urtava il vincolo
--  unique (league_id, player_id). L'upsert riusa l'istanza solo se e'
--  ancora libera; se nel frattempo e' stata assegnata, l'intera risoluzione
--  fallisce senza addebitare budget o segnare l'asta come conclusa.
-- ------------------------------------------------------------

create or replace function private.risolvi_aste_giorno(p_giorno date)
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
  v_lega              public.leagues;
  v_prorata           bigint;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
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
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < v_lega.slot_rosa
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
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

      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

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
               ' per ' || private.in_milioni(v_vincitore.ingaggio_offerto) || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste_giorno(date) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date) to service_role;
