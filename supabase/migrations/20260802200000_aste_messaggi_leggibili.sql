-- ============================================================
--  MESSAGGI DELLE ASTE LEGGIBILI
--
--  `round(x / 100000.0) / 10.0` restituisce un numeric con la scala della
--  divisione, quindi il messaggio d'errore diceva «hai gia' impegnato
--  2.0000000000000000 M€». Corretto in fase di verifica: e' testo che legge
--  un utente, non un log.
-- ============================================================

create or replace function private.in_milioni(p_euro bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  -- Virgola decimale: il resto dell'interfaccia e' in italiano.
  select replace(to_char(p_euro / 1000000.0, 'FM9999990.0'), '.', ',');
$$;

revoke all on function private.in_milioni(bigint) from public, anon;
grant execute on function private.in_milioni(bigint) to authenticated, service_role;

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

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > v_lega.slot_rosa then
    raise exception using errcode = '22023',
      message = 'Non hai piu'' posti liberi: ' || v_rosa || ' giocatori in rosa e '
                || v_slot_altri || ' offerte gia'' in gioco, su ' || v_lega.slot_rosa || ' slot.';
  end if;

  v_prorata := round(p_ingaggio::numeric * private.giornate_rimanenti(v_lega.id)
                     / greatest(v_lega.giornate_totali, 1));
  v_impegnato := private.budget_impegnato(v_squadra.id, p_auction_id);

  if v_squadra.budget - v_impegnato < v_prorata then
    raise exception using errcode = '22023',
      message = 'Budget insufficiente: ' || private.in_milioni(v_impegnato)
                || ' M€ sono gia'' impegnati in altre offerte, te ne restano '
                || private.in_milioni(v_squadra.budget - v_impegnato)
                || ' M€ e questa ne richiede ' || private.in_milioni(v_prorata) || ' M€.';
  end if;

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;

  return v_offerta;
end;
$$;

-- Stessa cura nelle notifiche d'asta persa, che avevano la stessa divisione.
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
      -- Nessun tetto di vittorie. Budget e slot sono gia' garantiti
      -- dall'impegno preso al momento dell'offerta; il ricontrollo resta
      -- come rete, non come regola.
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
