-- I ragazzi del vivaio invecchiano a fine stagione come quelli in rosa (20/11/2026).
-- Prima l'eta' del prospetto era quella del catalogo (players.eta, 15 anni) e non cambiava mai:
-- segnalato col caso di Diallo (Pro secco), arrivato in Season 2 e ancora quindicenne in Season 3.
-- Ora vivaio_prospetti.eta_corrente nasce dall'eta' del catalogo, sale di 1 in prepara_offseason
-- insieme a player_instances e free_agent_progression, e vale per promozione, scambi e app.

alter table public.vivaio_prospetti add column eta_corrente smallint;

-- Chi e' gia' in vivaio: un anno per ogni stagione passata da quando e' entrato.
update public.vivaio_prospetti vp
set eta_corrente = least(45, p.eta + greatest(0, l.stagione_corrente - vp.entrata_stagione))
from public.players p, public.leagues l
where p.id = vp.player_id and l.id = vp.league_id;

create or replace function private.imposta_eta_vivaio()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.eta_corrente is null then
    select p.eta into new.eta_corrente from public.players p where p.id = new.player_id;
  end if;
  return new;
end $$;
revoke execute on function private.imposta_eta_vivaio() from public, anon, authenticated;

create trigger vivaio_prospetti_eta before insert on public.vivaio_prospetti
for each row execute function private.imposta_eta_vivaio();

alter table public.vivaio_prospetti alter column eta_corrente set not null;

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if clock_timestamp() < private.sblocco_offseason(p_league_id) then
    raise exception using errcode = '55000', message = format(
      'L''off-season si apre 24 ore dopo l''ultima giornata: da %s, così tutti possono rivedere i risultati.',
      to_char(private.sblocco_offseason(p_league_id) at time zone 'Europe/Rome', 'DD/MM "alle" HH24:MI'));
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 24 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 24 squadre.';
  end if;

  -- Prestiti (Season 3): a fine stagione rientrano tutti, prima di rinnovi e invecchiamento.
  perform private.chiudi_prestiti_lega(p_league_id);

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + make_interval(hours => v_lega.durata_offseason_ore)) at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Invecchiamento di fine stagione: il join sulla squadra attiva e'
  -- stato tolto (deciso il 30 agosto 2026), cosi' uno svincolato reale
  -- invecchia esattamente come chi e' in rosa.
  for v_player in
    select pi.id, pi.eta_corrente, pi.infortunato_fino_a
    from public.player_instances pi
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        -- La pausa fra due stagioni vale 6 giornate di recupero, non una
        -- guarigione completa (deciso con l'utente l'11 settembre 2026).
        -- Prima qui si azzerava: chi si rompeva per 10 giornate all'ultima
        -- di playoff ripartiva sano, e un infortunio grave di fine stagione
        -- non costava niente. Ora se ne porta dietro 4.
        infortunato_fino_a = greatest(0, v_player.infortunato_fino_a - 6),
        -- Fedina pulita a ogni nuova stagione, come all'inizio dei playoff:
        -- ne' il conto delle ammonizioni ne' una squalifica gia' maturata
        -- attraversano il confine fra due stagioni.
        ammonizioni_stagione = 0,
        squalificato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  -- Stesso invecchiamento per chi non e' mai stato scelto in questa lega,
  -- residuo azzerato come per player_instances.
  update public.free_agent_progression
  set eta_corrente = least(45, eta_corrente + 1), progressione_residuo = 0, aggiornato_il = now()
  where league_id = p_league_id;

  -- E per i ragazzi del vivaio (20/11/2026): prima restavano fermi all'eta' con cui erano nati.
  update public.vivaio_prospetti
  set eta_corrente = least(45, eta_corrente + 1)
  where league_id = p_league_id;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint, p_durata smallint DEFAULT 1, p_opzione text DEFAULT NULL::text, p_minutaggio text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_pluri boolean;
  v_richiesta bigint;
  v_fine integer;
  v_s integer;
  v_richiesto text;
  v_media numeric;
  v_rifiuto text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare una promozione.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_ingaggio > private.ingaggio_massimo() then
    raise exception using errcode = '22023',
      message = 'L''ingaggio massimo è ' || replace(round(private.ingaggio_massimo() / 1000000.0, 1)::text, '.', ',') || ' M€.';
  end if;
  if p_durata is null or p_durata not between 1 and 3 then
    raise exception using errcode = '22023', message = 'Il contratto dura da 1 a 3 stagioni.';
  end if;
  if p_opzione is not null and p_opzione not in ('squadra', 'giocatore') then
    raise exception using errcode = '22023', message = 'Opzione non valida.';
  end if;
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
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
  -- In vivaio si invecchia come in rosa (20/11/2026): conta l'eta' del prospetto, non quella del catalogo.
  v_player.eta := coalesce(v_prospetto.eta_corrente, v_player.eta);
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  -- Contratti pluriennali (9/11/2026): la durata e l'opzione spostano la richiesta come nel rinnovo.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if not v_pluri and (p_durata <> 1 or p_opzione is not null) then
    raise exception using errcode = '22023', message = 'In questa stagione il primo contratto dura fino a fine stagione.';
  end if;
  v_richiesta := v_proposta.richiesta;
  -- Minutaggio promesso (14/11/2026): si tratta come al rinnovo. Il gradino offerto sposta la richiesta; uno non alla
  -- sua altezza lo rifiuta senza consumare un tentativo. Senza sceglierlo vale quello che chiede (come prima).
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto(v_league.id, v_player.overall::smallint, v_player.eta::smallint,
                     (coalesce(v_prospetto.posizioni_override, v_player.posizioni))[1]);
    if p_minutaggio is not null and v_richiesto is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_squadra.id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_richiesto, v_player.eta::smallint, v_player.overall::smallint, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_prospetto.promozione_tentativi,
          'tentativi_totali', 3,
          'messaggio', case
            when p_minutaggio = 'promessa' and v_player.eta >= 21 then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non salgo in prima squadra per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
      v_richiesta := private.richiesta_per_gradino(v_richiesta, p_minutaggio, v_richiesto);
    end if;
  end if;
  if v_pluri then
    v_richiesta := least(private.ingaggio_massimo(), greatest(500000, round(v_richiesta
      * private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential, 50::smallint, p_durata, p_opzione)
      / 100000) * 100000))::bigint;
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_squadra.id
  where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.tolleranza_trattativa(
    50::smallint, coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint),
    coalesce(v_player.mentalita_vittorie, 34::smallint), v_squadra.id
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);
  -- Chi cresce ancora (fino a 23 anni, almeno 3 punti di margine) non scende mai sotto quanto prende in cantera, e il
  -- sovrapprezzo per gli anni in piu' si conta su quella cifra (9/11/2026, decisione del committente).
  if v_player.eta <= 23 and coalesce(v_player.potential, v_player.overall) - v_player.overall >= 3 then
    v_soglia := least(v_richiesta, greatest(v_soglia, v_prospetto.ingaggio * case when v_pluri
      then private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential, 50::smallint, p_durata, p_opzione) else 1 end));
  end if;
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));
    -- Ogni stagione coperta dal contratto, compresa quella dell'opzione del giocatore (puo' esercitarla lui).
    v_fine := private.stagione_contratto(v_prospetto.league_id) + p_durata - 1 + case when p_opzione = 'giocatore' then 1 else 0 end;
    for v_s in (private.stagione_contratto(v_prospetto.league_id) + 1)..v_fine loop
      perform private.verifica_capienza(v_squadra.id, p_ingaggio, v_s::smallint);
    end loop;

    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_league.id and f.stato = 'programmata';

    -- Il training fatto nel vivaio passa con lui: ruoli, piano di sviluppo, attributi gia' spostati, cambio ruolo in corso.
    insert into public.player_instances
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, giornata_acquisizione,
       posizioni_override, specializzazione_attiva, piano_scostamenti, piano_overall_rif)
    values
      (v_prospetto.league_id, v_prospetto.player_id, v_squadra.id,
       v_player.overall, v_player.eta, p_ingaggio, v_prossima,
       v_prospetto.posizioni_override, v_prospetto.specializzazione_attiva, coalesce(v_prospetto.piano_scostamenti, '{}'::jsonb), v_prospetto.piano_overall_rif)
    returning * into v_istanza;
    -- Il trigger fissa la scadenza alla stagione in corso: il contratto dura p_durata stagioni contando questa.
    if p_durata > 1 or p_opzione is not null then
      update public.player_instances
      set contratto_scadenza = v_istanza.contratto_scadenza + p_durata - 1, opzione_contratto = p_opzione
      where id = v_istanza.id returning * into v_istanza;
    end if;

    -- Il trigger della firma ha gia' messo il gradino che chiede (e la stagione d'arrivo): quello trattato lo sostituisce.
    if v_league.tattiche_attive and p_minutaggio is not null and v_richiesto is not null then
      update public.player_instances set minutaggio_promesso = p_minutaggio
      where id = v_istanza.id returning * into v_istanza;
    end if;

    update public.cambi_ruolo set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;
    update public.specializzazioni_giocatore set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;

    insert into private.registro_trattative (league_id, team_id, tipo, player_id, vivaio_id, offerta, richiesta, soglia,
    tolleranza, morale, durata, opzione, gradino, esito)
  values (v_prospetto.league_id, v_squadra.id, 'primo_contratto', v_prospetto.player_id, v_prospetto.id, p_ingaggio, v_richiesta, round(v_soglia),
    v_tolleranza, 50, p_durata, p_opzione, coalesce(p_minutaggio, v_richiesto), 'accettato');
    delete from public.vivaio_prospetti where id = v_prospetto.id;

    perform private.notifica(v_user_id, v_league.id, 'sistema', 'Prospetto promosso in prima squadra',
      v_player.nome || ' firma il primo contratto: ' || private.in_milioni(p_ingaggio) || ' M€ a stagione fino alla stagione '
        || v_istanza.contratto_scadenza
        || case p_opzione when 'squadra' then ' (+1 opzione squadra)' when 'giocatore' then ' (+1 opzione giocatore)' else '' end || '.',
      jsonb_build_object('player_instance_id', v_istanza.id));

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', p_durata,
      'opzione', p_opzione,
      'contratto_scadenza', v_istanza.contratto_scadenza,
      'minutaggio', v_istanza.minutaggio_promesso,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Non vedo l''ora di debuttare.'
    );
  end if;

  v_tentativi := (v_prospetto.promozione_tentativi + 1)::smallint;
  update public.vivaio_prospetti set promozione_tentativi = v_tentativi where id = v_prospetto.id;
  insert into private.registro_trattative (league_id, team_id, tipo, player_id, vivaio_id, offerta, richiesta, soglia,
    tolleranza, morale, durata, opzione, gradino, esito)
  values (v_prospetto.league_id, v_squadra.id, 'primo_contratto', v_prospetto.player_id, v_prospetto.id, p_ingaggio, v_richiesta, round(v_soglia),
    v_tolleranza, 50, p_durata, p_opzione, coalesce(p_minutaggio, v_richiesto), case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end);

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'No, mister: così non firmo. Resto in cantera finché non scade il mio tempo.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION public.proposta_promozione(p_vivaio_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_prospetto public.vivaio_prospetti;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_pluri boolean;
  v_molt jsonb := '[]'::jsonb;
  v_d integer;
  v_o text;
  v_gradini jsonb := '[]'::jsonb;
  v_g text;
  v_richiesto text;
  v_media numeric;
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
  -- In vivaio si invecchia come in rosa (20/11/2026): conta l'eta' del prospetto, non quella del catalogo.
  v_player.eta := coalesce(v_prospetto.eta_corrente, v_player.eta);
  select * into v_proposta
  from private.rinnovo_proposta(
    v_prospetto.id, v_player.overall, v_player.eta, v_prospetto.ingaggio,
    coalesce(v_player.mentalita_bandiera, 33::smallint), coalesce(v_player.mentalita_economia, 33::smallint)
  );

  -- Minutaggio promesso (14/11/2026): gli stessi gradini del rinnovo, ognuno con la sua richiesta o col motivo del no.
  if v_league.tattiche_attive then
    v_richiesto := private.gradino_richiesto(v_league.id, v_player.overall::smallint, v_player.eta::smallint,
                     (coalesce(v_prospetto.posizioni_override, v_player.posizioni))[1]);
    if v_richiesto is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_prospetto.team_id and not x.ritirato;
      foreach v_g in array array['titolare', 'turnover', 'sporadico', 'promessa'] loop
        v_gradini := v_gradini || jsonb_build_object(
          'chiave', v_g,
          'richiesta', private.richiesta_per_gradino(v_proposta.richiesta, v_g, v_richiesto),
          'rifiuto', private.gradino_rifiutato(v_g, v_richiesto, v_player.eta::smallint, v_player.overall::smallint, v_media)
        );
      end loop;
    end if;
  end if;

  -- Contratti pluriennali anche per il primo contratto (9/11/2026): 1-3 stagioni + opzione, stessi moltiplicatori
  -- del rinnovo (il giovane che sa di crescere chiede di piu' per legarsi a lungo), morale neutro.
  v_pluri := private.pluriennali_attivi(v_league.id);
  if v_pluri then
    foreach v_o in array array['', 'squadra', 'giocatore'] loop
      for v_d in 1..3 loop
        v_molt := v_molt || jsonb_build_object(
          'durata', v_d, 'opzione', nullif(v_o, ''),
          'moltiplicatore', private.moltiplicatore_durata(v_player.eta, v_player.overall, v_player.potential,
                                                          50::smallint, v_d::smallint, nullif(v_o, '')));
      end loop;
    end loop;
  end if;

  return jsonb_build_object(
    'pluriennali', v_pluri,
    'stagione_corrente', v_league.stagione_corrente,
    'moltiplicatori', case when v_pluri then v_molt end,
    'ingaggio_massimo', private.ingaggio_massimo(),
    'ingaggio_attuale', v_prospetto.ingaggio,
    'richiesta', v_proposta.richiesta,
    'gradino_richiesto', v_richiesto,
    'gradini', case when v_richiesto is not null then v_gradini end,
    'tentativi_usati', v_prospetto.promozione_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_prospetto.promozione_tentativi >= 3
  );
end;
$function$

;

CREATE OR REPLACE FUNCTION private.stampa_scambio(p_trade_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tp public.trade_proposals;
  v_da public.teams;
  v_a public.teams;
  v_top record;
  v_ha_top boolean;
  v_dest public.teams;
  v_orig public.teams;
  v_contro text;
  v_insieme text;
  v_in_da numeric; v_out_da numeric; v_voto_da numeric;
  v_in_a numeric;  v_out_a numeric;  v_voto_a numeric;
  v_best_in_da text; v_best_in_a text; v_best_out_da text; v_best_out_a text;
  v_testo text;
  v_morale integer;
  v_insider text;
  v_post bigint;
  v_basso public.teams;
  v_voto_basso numeric;
  v_alto public.teams;
  v_voto_alto numeric;
  v_n integer := 0;
  v_k text := p_trade_id::text;
begin
  select * into v_tp from public.trade_proposals where id = p_trade_id and stato = 'accettata';
  if not found then return 0; end if;
  select * into v_da from public.teams where id = v_tp.da_team_id;
  select * into v_a from public.teams where id = v_tp.a_team_id;

  -- Tutto quello che si muove, con la squadra che lo riceve. Le scelte valgono come un buon titolare.
  create temp table if not exists tmp_stampa_mossi (pi_id bigint, nome text, ovr integer, eta integer, pot integer, ruolo text,
    ingaggio numeric, dest bigint, valore numeric) on commit drop;
  truncate pg_temp.tmp_stampa_mossi;
  insert into pg_temp.tmp_stampa_mossi
  select pi.id, p.nome, pi.overall_corrente, pi.eta_corrente, p.potential, (coalesce(pi.posizioni_override, p.posizioni))[1], pi.ingaggio,
         case when pi.id = any (v_tp.giocatori_offerti) then v_tp.a_team_id else v_tp.da_team_id end,
         private.stampa_valore(pi.overall_corrente, pi.eta_corrente, p.potential)
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.id = any (v_tp.giocatori_offerti || v_tp.giocatori_richiesti);
  insert into pg_temp.tmp_stampa_mossi
  select null, p.nome, p.overall, coalesce(vp.eta_corrente, p.eta), p.potential, (coalesce(vp.posizioni_override, p.posizioni))[1], vp.ingaggio,
         case when vp.id = any (v_tp.vivaio_offerti) then v_tp.a_team_id else v_tp.da_team_id end,
         private.stampa_valore(p.overall, coalesce(vp.eta_corrente, p.eta), p.potential)
  from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id
  where vp.id = any (v_tp.vivaio_offerti || v_tp.vivaio_richiesti);
  insert into pg_temp.tmp_stampa_mossi
  select null::bigint, null::text, null::integer, null::integer, null::integer, null::text, null::numeric, v_tp.a_team_id, private.stampa_valore(74, 25, 74) from unnest(v_tp.scelte_offerte)
  union all
  select null, null, null, null, null, null, null, v_tp.da_team_id, private.stampa_valore(74, 25, 74) from unnest(v_tp.scelte_richieste);

  -- Valore ricevuto da ciascuna squadra: il pezzo migliore conta per intero, gli altri via via meno (0,7^n).
  select coalesce(sum(valore * power(0.7, rn - 1)) filter (where dest = v_da.id), 0),
         coalesce(sum(valore * power(0.7, rn - 1)) filter (where dest = v_a.id), 0)
    into v_in_da, v_in_a
  from (select dest, valore, row_number() over (partition by dest order by valore desc) as rn from pg_temp.tmp_stampa_mossi) x;
  v_out_da := v_in_a; v_out_a := v_in_da;
  v_voto_da := least(9, greatest(4, round((6 + 3.5 * (v_in_da - v_out_da) / greatest(v_in_da, v_out_da, 1)) * 2) / 2));
  v_voto_a  := least(9, greatest(4, round((6 + 3.5 * (v_in_a - v_out_a) / greatest(v_in_a, v_out_a, 1)) * 2) / 2));
  select nome into v_best_in_da from pg_temp.tmp_stampa_mossi where dest = v_da.id and nome is not null order by ovr desc nulls last limit 1;
  select nome into v_best_in_a from pg_temp.tmp_stampa_mossi where dest = v_a.id and nome is not null order by ovr desc nulls last limit 1;
  v_best_out_da := v_best_in_a; v_best_out_a := v_best_in_da;

  -- 1. La Gazzetta: l'ufficialita', col nome piu' pesante dello scambio in testa.
  select * into v_top from pg_temp.tmp_stampa_mossi where nome is not null order by ovr desc nulls last, valore desc limit 1;
  v_ha_top := found;
  if v_ha_top then
    select * into v_dest from public.teams where id = v_top.dest;
    select * into v_orig from public.teams where id = case when v_top.dest = v_da.id then v_a.id else v_da.id end;
    if v_top.dest = v_a.id then
      v_contro := case when cardinality(v_tp.giocatori_richiesti) + cardinality(v_tp.vivaio_richiesti) + cardinality(v_tp.scelte_richieste) > 0
        then private.descrizione_cessione(v_tp.giocatori_richiesti, v_tp.vivaio_richiesti, v_tp.scelte_richieste) end;
      v_insieme := case when v_top.pi_id is not null and cardinality(array_remove(v_tp.giocatori_offerti, v_top.pi_id)) + cardinality(v_tp.vivaio_offerti) + cardinality(v_tp.scelte_offerte) > 0
        then private.descrizione_cessione(array_remove(v_tp.giocatori_offerti, v_top.pi_id), v_tp.vivaio_offerti, v_tp.scelte_offerte) end;
    else
      v_contro := case when cardinality(v_tp.giocatori_offerti) + cardinality(v_tp.vivaio_offerti) + cardinality(v_tp.scelte_offerte) > 0
        then private.descrizione_cessione(v_tp.giocatori_offerti, v_tp.vivaio_offerti, v_tp.scelte_offerte) end;
      v_insieme := case when v_top.pi_id is not null and cardinality(array_remove(v_tp.giocatori_richiesti, v_top.pi_id)) + cardinality(v_tp.vivaio_richiesti) + cardinality(v_tp.scelte_richieste) > 0
        then private.descrizione_cessione(array_remove(v_tp.giocatori_richiesti, v_top.pi_id), v_tp.vivaio_richiesti, v_tp.scelte_richieste) end;
    end if;
    v_testo := private.social_scegli('gs' || v_k, array[
      '🔴 UFFICIALE | ' || v_top.nome || ' è un nuovo giocatore di ' || v_dest.nome || '. ' || initcap(left(private.ruolo_esteso(v_top.ruolo), 1)) || substr(private.ruolo_esteso(v_top.ruolo), 2)
        || ' di ' || v_top.eta || ' anni, ' || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || ', lascia ' || v_orig.nome
        || coalesce(' nell''operazione che porta in direzione opposta ' || v_contro, ' senza contropartite tecniche') || '.'
        || coalesce(' Con lui si trasferisce anche ' || v_insieme || '.', '')
        || coalesce(' Ingaggio da ' || private.milioni(v_top.ingaggio) || ' a stagione.', ''),
      '🔴 È FATTA | ' || v_dest.nome || ' e ' || v_orig.nome || ' chiudono lo scambio: ' || v_top.nome || ' (' || private.ruolo_esteso(v_top.ruolo) || ', '
        || v_top.eta || ' anni) cambia maglia. Per ' || v_dest.nome || ' arriva ' || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || '.'
        || coalesce(' ' || v_orig.nome || ' riceve ' || v_contro || '.', '')
        || coalesce(' Nell''affare entra anche ' || v_insieme || '.', ''),
      '🔴 COLPO ' || upper(v_dest.nome) || ' | Preso ' || v_top.nome || ', ' || private.ruolo_esteso(v_top.ruolo) || ' di ' || v_top.eta || ' anni: '
        || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || '. Saluta ' || v_orig.nome || ' dopo una trattativa lampo.'
        || coalesce(' La contropartita: ' || v_contro || '.', '')
        || coalesce(' Per lui ' || private.milioni(v_top.ingaggio) || ' di ingaggio.', '')]);
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, player_instance_id, testo, creato_il)
    values (v_tp.league_id, 'stampa-scambio:' || v_k, 'testata', 'La Gazzetta dello Sport', 'gazzetta', 'gazzetta',
            v_dest.id, v_orig.id, v_top.pi_id, left(v_testo, 700), v_tp.risolta_il + interval '3 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;

  -- 2. Le pagelle del Corriere dello Sport.
  v_testo := private.stampa_pagelle_testo(v_tp, v_voto_da, v_voto_a);
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
  values (v_tp.league_id, 'pagelle-scambio:' || v_k, 'testata', 'Corriere dello Sport', 'corrieredellosport', 'corrieredellosport',
          v_da.id, v_a.id, left(v_testo, 700), v_tp.risolta_il + interval '25 minutes')
  on conflict (league_id, chiave) do nothing
  returning id into v_post;
  v_n := v_n + 1;

  -- Un tifoso risponde alle pagelle: quello bocciato protesta, altrimenti quello promosso gongola.
  if v_post is not null then
    if v_voto_da <= v_voto_a then v_basso := v_da; v_voto_basso := v_voto_da; v_alto := v_a; v_voto_alto := v_voto_a;
    else v_basso := v_a; v_voto_basso := v_voto_a; v_alto := v_da; v_voto_alto := v_voto_da; end if;
    if v_voto_basso <= 5.5 then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
      values (v_tp.league_id, 'pagelle-tifoso:' || v_k, 'tifosi',
              (private.tifoso_finto('pg' || v_k, v_basso.nome)).nome, (private.tifoso_finto('pg' || v_k, v_basso.nome)).handle, v_basso.id, v_post,
              private.social_scegli('pgt' || v_k, array[
                private.voto_testo(v_voto_basso) || '?? ma l''avete vista giocare @' || private.handle_squadra(v_basso.nome) || ' almeno una volta? giornalai',
                'voto ridicolo. tra due mesi venite a chiedere scusa 🤡',
                'il @corrieredellosport non ci capisce niente di calcio, come sempre',
                'ok il ' || private.voto_testo(v_voto_basso) || ' ma ne riparliamo a fine stagione. salvate il post 📌']),
              v_tp.risolta_il + interval '32 minutes')
      on conflict (league_id, chiave) do nothing;
    elsif v_voto_alto >= 7 then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
      values (v_tp.league_id, 'pagelle-tifoso:' || v_k, 'tifosi',
              (private.tifoso_finto('pg' || v_k, v_alto.nome)).nome, (private.tifoso_finto('pg' || v_k, v_alto.nome)).handle, v_alto.id, v_post,
              private.social_scegli('pgt' || v_k, array[
                'pure il @corrieredellosport lo dice. mercato da paura @' || private.handle_squadra(v_alto.nome) || ' 🔥',
                private.voto_testo(v_voto_alto) || ' è pure poco. ditelo che vi rode 😎',
                'finalmente una pagella giusta. si vola 🚀']),
              v_tp.risolta_il + interval '32 minutes')
      on conflict (league_id, chiave) do nothing;
    end if;
  end if;

  -- 3. Il retroscena (sei scambi su dieci): verosimile, mai dati veri delle trattative.
  if v_ha_top and abs(hashtext('ins' || v_k)) % 10 < 6 then
    v_morale := null;
    if v_top.pi_id is not null then
      select tg.morale_prima into v_morale from private.trasferimenti_giocatori tg
       where tg.player_instance_id = v_top.pi_id and tg.creato_il between v_tp.risolta_il - interval '10 minutes' and v_tp.risolta_il + interval '1 hour'
       order by tg.creato_il desc limit 1;
    end if;
    v_insider := case when abs(hashtext('chi' || v_k)) % 2 = 0 then 'fabrizioromano' else 'dimarzio' end;
    v_testo := case
      when v_morale is not null and v_morale < 45 then private.social_scegli('rt' || v_k, array[
        'Mi risulta che ' || v_top.nome || ' avesse chiesto di partire già da qualche settimana. Rapporti freddi con lo staff di ' || v_orig.nome || ': l''addio era nell''aria.',
        'Dietro la cessione di ' || v_top.nome || ' c''è un malumore che durava da tempo. Il giocatore voleva cambiare aria e ' || v_dest.nome || ' ha colto l''occasione al volo.'])
      when v_top.eta >= 30 then private.social_scegli('rt' || v_k, array[
        v_orig.nome || ' voleva abbassare l''età media della rosa: per questo ha aperto alla cessione di ' || v_top.nome || '. Il giocatore ha accettato senza fare storie.',
        'A ' || v_top.eta || ' anni ' || v_top.nome || ' cercava un progetto per vincere subito. ' || v_dest.nome || ' gli ha garantito un ruolo centrale: decisivo il colloquio con l''allenatore.'])
      when v_top.eta <= 21 then private.social_scegli('rt' || v_k, array[
        v_dest.nome || ' seguiva ' || v_top.nome || ' da tempo: decisiva la promessa di minuti da protagonista. Il ragazzo ha detto sì in poche ore.',
        'Su ' || v_top.nome || ' c''erano gli occhi di mezza lega, ma ' || v_dest.nome || ' si è mossa prima di tutti. Talento puro, lo staff lo considera un investimento per anni.'])
      else private.social_scegli('rt' || v_k, array[
        v_dest.nome || ' cercava un ' || private.ruolo_esteso(v_top.ruolo) || ' da settimane: ' || v_top.nome || ' era la prima scelta dello staff tecnico. Trattativa lampo.',
        'L''allenatore di ' || v_dest.nome || ' ha chiamato personalmente ' || v_top.nome || ' prima di chiudere. Una telefonata che ha convinto il giocatore.'])
    end;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, player_instance_id, testo, creato_il)
    values (v_tp.league_id, 'retroscena-scambio:' || v_k, 'testata',
            case v_insider when 'fabrizioromano' then 'Fabrizio Romano' else 'Gianluca Di Marzio' end, v_insider, v_insider,
            v_dest.id, v_orig.id, v_top.pi_id,
            case v_insider when 'fabrizioromano' then '🚨 ' else 'ESCLUSIVA | ' end || v_testo, v_tp.risolta_il + interval '70 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;
  return v_n;
end;
$function$

;

