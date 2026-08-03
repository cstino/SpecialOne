-- ============================================================
--  PANNELLO ADMIN: FALLBACK MANUALE SE I CRON NON PARTONO
--
--  Decisione utente, 3 agosto 2026. Tre azioni, sempre disponibili solo
--  all'amministratore della lega, pensate come rete di sicurezza e non come
--  meccanica di gioco: se pg_cron dovesse saltare una notte o una giornata,
--  l'admin non deve restare bloccato ad aspettare il giorno dopo.
--
--  1. Simulare la giornata: non serve nulla di nuovo. La Edge Function
--     simula-giornata gia' accetta la chiamata dal browser con il JWT
--     dell'admin (auth: ['user','secret']) e verifica lei stessa che
--     l'utente sia league.admin_id quando non e' il cron a chiamare. Il
--     collegamento manca solo lato frontend.
--
--  2. Aprire il mercato = far scattare l'estrazione di oggi in anticipo o in
--     ritardo. private.estrai_svincolati_lega(lega, giorno) esiste gia' da
--     oggi pomeriggio (per rendere le aste verificabili) e non ha alcun
--     vincolo orario: e' gia' pronta per essere chiamata a mano.
--
--  3. Chiudere il mercato = risolvere le aste del giorno e far scadere le
--     proposte in attesa, PER QUESTA LEGA SOLA. risolvi_aste_giorno pero'
--     non aveva un filtro di lega (il cron risolve tutte le leghe insieme,
--     non ha bisogno di isolarle): qui gli si aggiunge un parametro
--     opzionale, default null per non cambiare il comportamento del cron.
--     Le proposte scadute erano dentro chiudi_mercato_giornaliero, mai
--     spezzata dalla logica dell'orario: la si spacca ora con lo stesso
--     schema gia' usato per le aste.
-- ============================================================

-- ------------------------------------------------------------
--  1. Aggiungere il filtro di lega a risolvi_aste_giorno
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
      and (p_league_id is null or a.league_id = p_league_id)
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

create or replace function private.risolvi_aste()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;
  return private.risolvi_aste_giorno((now() at time zone 'Europe/Rome')::date);
end;
$$;

-- ------------------------------------------------------------
--  2. Spezzare chiudi_mercato_giornaliero: logica per-lega + guardia oraria
-- ------------------------------------------------------------

create or replace function private.scadi_proposte_giorno(p_league_id bigint default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scadute integer := 0;
  v_p       record;
begin
  for v_p in
    select tp.id, tp.league_id, tp.da_team_id, tp.a_team_id
    from public.trade_proposals tp
    where tp.stato = 'in_attesa'
      and tp.scade_il <= now()
      and (p_league_id is null or tp.league_id = p_league_id)
    for update
  loop
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where id = v_p.id;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta scaduta',
      'Il mercato ha chiuso senza una risposta da '
        || (select nome from public.teams where id = v_p.a_team_id) || '.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    v_scadute := v_scadute + 1;
  end loop;

  return v_scadute;
end;
$$;

create or replace function private.chiudi_mercato_giornaliero()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;
  return private.scadi_proposte_giorno(null);
end;
$$;

revoke all on function private.risolvi_aste_giorno(date, bigint) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date, bigint) to service_role;
revoke all on function private.scadi_proposte_giorno(bigint) from public, anon, authenticated;
grant execute on function private.scadi_proposte_giorno(bigint) to service_role;

-- ------------------------------------------------------------
--  3. RPC pubbliche riservate all'admin
-- ------------------------------------------------------------

create or replace function public.admin_apri_mercato(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_league public.leagues;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il pannello admin.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_utente then
    raise exception using errcode = '42501', message = 'Solo l''amministratore puo'' aprire il mercato.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato e'' disponibile solo a stagione avviata.';
  end if;

  return private.estrai_svincolati_lega(p_league_id, (now() at time zone 'Europe/Rome')::date);
end;
$$;

revoke all on function public.admin_apri_mercato(bigint) from public, anon;
grant execute on function public.admin_apri_mercato(bigint) to authenticated;

comment on function public.admin_apri_mercato(bigint) is
  'Fallback manuale se il cron delle 07:00 non parte: estrae gli svincolati di oggi per questa lega. Solo admin.';

create or replace function public.admin_chiudi_mercato(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_league public.leagues;
  v_aste    integer;
  v_proposte integer;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il pannello admin.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_utente then
    raise exception using errcode = '42501', message = 'Solo l''amministratore puo'' chiudere il mercato.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Il mercato e'' disponibile solo a stagione avviata.';
  end if;

  v_aste := private.risolvi_aste_giorno((now() at time zone 'Europe/Rome')::date, p_league_id);
  v_proposte := private.scadi_proposte_giorno(p_league_id);

  return jsonb_build_object('aste_risolte', v_aste, 'proposte_scadute', v_proposte);
end;
$$;

revoke all on function public.admin_chiudi_mercato(bigint) from public, anon;
grant execute on function public.admin_chiudi_mercato(bigint) to authenticated;

comment on function public.admin_chiudi_mercato(bigint) is
  'Fallback manuale se il cron delle 21:00 non parte: risolve le aste di oggi e fa scadere le proposte in attesa, per questa lega. Solo admin.';
