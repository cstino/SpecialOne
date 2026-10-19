-- ============================================================
--  TRAINING PER I GIOCATORI DEL VIVAIO (19/10/2026, deciso con il committente).
--  Scheda giocatore anche per i prospetti, con cambio ruolo e piano di sviluppo (specializzazione), come per la rosa:
--  - il cambio ruolo ha gli stessi tempi (riduzione del reparto Training) e a fine corsa mette il nuovo ruolo sul prospetto;
--  - il piano di sviluppo vale subito (leghe season 2) e sposta gli attributi man mano che il prospetto cresce nel vivaio;
--  - alla PROMOZIONE ruoli, piano, attributi gia' spostati e cambio in corso passano al giocatore in rosa;
--  - con lo SCAMBIO il training segue il prospetto e continua; con rilascio o scadenza si annulla.
--  Funzioni esistenti riscritte dalla definizione viva (completa_cambi_ruolo, offri_promozione).
-- ============================================================
begin;

alter table public.vivaio_prospetti
  add column posizioni_override text[],
  add column specializzazione_attiva text,
  add column piano_scostamenti jsonb not null default '{}'::jsonb,
  add column piano_overall_rif smallint;

alter table public.cambi_ruolo alter column player_instance_id drop not null,
  add column vivaio_id bigint references public.vivaio_prospetti(id) on delete cascade;
alter table public.cambi_ruolo add constraint cambi_ruolo_soggetto check (player_instance_id is not null or vivaio_id is not null or completato_il is not null);
alter table public.specializzazioni_giocatore alter column player_instance_id drop not null,
  add column vivaio_id bigint references public.vivaio_prospetti(id) on delete set null;

-- Lo scambio sposta il prospetto: il training in corso lo segue nella nuova squadra.
create or replace function private.training_vivaio_segue()
returns trigger language plpgsql set search_path = '' as $f$
begin
  if new.team_id is distinct from old.team_id then
    update public.cambi_ruolo set team_id = new.team_id where vivaio_id = new.id and completato_il is null;
  end if;
  return null;
end $f$;
create trigger vivaio_prospetti_training_segue after update of team_id on public.vivaio_prospetti
  for each row execute function private.training_vivaio_segue();

-- Scheda di un prospetto: attributi correnti (con il piano), ruoli, training. La vede chi gioca nella lega.
create or replace function public.vivaio_scheda(p_vivaio_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
    'posizioni', coalesce(vp.posizioni_override, p.posizioni),
    'attributi', private.attributi_istanza(p.attributi, coalesce(vp.posizioni_override, p.posizioni), p.overall, p.overall,
                   vp.piano_scostamenti, vp.specializzazione_attiva, vp.piano_overall_rif),
    'specializzazione_attiva', vp.specializzazione_attiva,
    'cambio', (select jsonb_build_object('id', c.id, 'ruolo_precedente', c.ruolo_precedente, 'ruolo_target', c.ruolo_target,
                 'avviato_giornata', c.avviato_giornata, 'completa_giornata', c.completa_giornata)
               from public.cambi_ruolo c where c.vivaio_id = vp.id and c.completato_il is null limit 1))
  from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id
  where vp.id = p_vivaio_id and (select private.e_membro(vp.league_id))
$f$;

create or replace function public.ruoli_target_cambio_vivaio(p_vivaio_id bigint)
returns text[] language sql stable security definer set search_path = '' as $f$
  select private.ruoli_target_cambio(coalesce(vp.posizioni_override, p.posizioni))
  from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id where vp.id = p_vivaio_id
$f$;

create or replace function public.avvia_cambio_ruolo_vivaio(p_vivaio_id bigint, p_ruolo_target text)
returns public.cambi_ruolo language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_vp public.vivaio_prospetti;
  v_squadra public.teams;
  v_lega public.leagues;
  v_pos text[];
  v_validi text[];
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_cambio public.cambi_ruolo;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.'; end if;
  select * into v_vp from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Prospetto inesistente.'; end if;
  select * into v_squadra from public.teams where id = v_vp.team_id and user_id = v_utente;
  if not found then raise exception using errcode = '42501', message = 'Questo prospetto non è nel tuo vivaio.'; end if;
  select * into v_lega from public.leagues where id = v_vp.league_id;
  if v_lega.stato <> 'stagione' then raise exception using errcode = '55000', message = 'Puoi avviare un cambio di ruolo solo durante la stagione.'; end if;
  if exists (select 1 from public.cambi_ruolo where vivaio_id = p_vivaio_id and completato_il is null) then
    raise exception using errcode = '55000', message = 'Questo prospetto ha già un cambio di ruolo in corso.';
  end if;
  select coalesce(v_vp.posizioni_override, p.posizioni) into v_pos from public.players p where p.id = v_vp.player_id;
  v_validi := private.ruoli_target_cambio(v_pos);
  if v_validi is null or not (p_ruolo_target = any(v_validi)) then
    raise exception using errcode = '22023', message = 'Ruolo non raggiungibile da un giocatore che gioca ' || v_pos[1] || '.';
  end if;
  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce((private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);
  v_durata := greatest(2, round(greatest(6, 14 - 2 * (cardinality(v_pos) - 1)) * (1 - v_riduzione / 100.0)));
  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';
  insert into public.cambi_ruolo (league_id, team_id, vivaio_id, ruolo_precedente, ruolo_target, avviato_giornata, completa_giornata)
  values (v_lega.id, v_squadra.id, p_vivaio_id, v_pos[1], p_ruolo_target, v_prossima, v_prossima + v_durata)
  returning * into v_cambio;
  return v_cambio;
end $f$;

create or replace function public.specializzazioni_disponibili_vivaio(p_vivaio_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_pos text[]; v_attiva text; v_catalogo jsonb; v_reparto text; v_chiave text; v_etichetta text; v_pesi jsonb; v_media numeric; v_crescita jsonb;
  v_risultato jsonb := '{}'::jsonb;
begin
  select coalesce(vp.posizioni_override, p.posizioni), vp.specializzazione_attiva into v_pos, v_attiva
  from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id where vp.id = p_vivaio_id;
  if v_pos is null then return '{}'::jsonb; end if;
  v_catalogo := private.specializzazioni_ruolo(v_pos[1]);
  v_reparto := private.macro_ruolo(v_pos);
  if v_attiva is not null and not (v_catalogo ? v_attiva) then
    select x.etichetta into v_etichetta from private.piani_ruoli() x where x.chiave = v_attiva limit 1;
    v_catalogo := v_catalogo || jsonb_build_object(v_attiva, jsonb_build_object('etichetta', coalesce(v_etichetta, v_attiva), 'pesi', private.piano_pesi(v_attiva)));
  end if;
  for v_chiave in select jsonb_object_keys(v_catalogo) loop
    v_pesi := v_catalogo -> v_chiave -> 'pesi';
    v_media := private.piano_media(v_chiave, v_reparto);
    select jsonb_object_agg(a.attributo, round(50 * (coalesce((v_pesi->>a.attributo)::numeric, 4) / v_media - 1))::int) into v_crescita
    from private.attributi_piano(v_reparto) a;
    v_risultato := v_risultato || jsonb_build_object(v_chiave, jsonb_build_object(
      'etichetta', v_catalogo -> v_chiave ->> 'etichetta', 'crescita_pct', v_crescita, 'attivo', v_chiave = coalesce(v_attiva, 'bilanciato')));
  end loop;
  return v_risultato;
end $f$;

-- Piano di sviluppo del prospetto: vale subito (come in rosa nelle leghe season 2); quanto il piano uscente ha gia'
-- spostato resta al prospetto.
create or replace function public.avvia_specializzazione_vivaio(p_vivaio_id bigint, p_specializzazione text)
returns public.specializzazioni_giocatore language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_vp public.vivaio_prospetti;
  v_squadra public.teams;
  v_lega public.leagues;
  v_pos text[]; v_overall smallint; v_maturato jsonb; v_congelati jsonb; v_chiave text; v_prossima integer;
  v_all public.specializzazioni_giocatore;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.'; end if;
  select * into v_vp from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Prospetto inesistente.'; end if;
  select * into v_squadra from public.teams where id = v_vp.team_id and user_id = v_utente;
  if not found then raise exception using errcode = '42501', message = 'Questo prospetto non è nel tuo vivaio.'; end if;
  select * into v_lega from public.leagues where id = v_vp.league_id;
  if v_lega.stato <> 'stagione' then raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.'; end if;
  if coalesce(v_vp.specializzazione_attiva, 'bilanciato') = p_specializzazione then
    raise exception using errcode = '55000', message = 'Questo prospetto segue già questo piano di sviluppo.';
  end if;
  select coalesce(v_vp.posizioni_override, p.posizioni), p.overall into v_pos, v_overall from public.players p where p.id = v_vp.player_id;
  if not (private.specializzazioni_ruolo(v_pos[1]) ? p_specializzazione) then
    raise exception using errcode = '22023', message = 'Specializzazione non valida per questo ruolo.';
  end if;
  v_maturato := private.scostamenti_piano(v_vp.specializzazione_attiva, private.macro_ruolo(v_pos),
    case when v_vp.piano_overall_rif is null then 0 else v_overall - v_vp.piano_overall_rif end);
  v_congelati := coalesce(v_vp.piano_scostamenti, '{}'::jsonb);
  for v_chiave in select jsonb_object_keys(v_maturato) loop
    v_congelati := v_congelati || jsonb_build_object(v_chiave, round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
  end loop;
  update public.vivaio_prospetti set piano_scostamenti = v_congelati, specializzazione_attiva = p_specializzazione, piano_overall_rif = v_overall
   where id = p_vivaio_id;
  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';
  insert into public.specializzazioni_giocatore (league_id, team_id, vivaio_id, specializzazione_precedente, specializzazione_target, avviato_giornata, completa_giornata, completato_il)
  values (v_lega.id, v_squadra.id, p_vivaio_id, v_vp.specializzazione_attiva, p_specializzazione, v_prossima, v_prossima, now())
  returning * into v_all;
  return v_all;
end $f$;

CREATE OR REPLACE FUNCTION private.completa_cambi_ruolo()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_prossima integer;
  v_cambio record;
  v_precedenti text[];
  v_nuove text[];
  v_nome text;
  v_pi record;
  v_maturato jsonb;
  v_congelati jsonb;
  v_chiave text;
  v_etichetta text;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali, tattiche_attive from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_cambio in
      select * from public.cambi_ruolo
      where league_id = v_lega.id and completato_il is null and completa_giornata <= v_prossima
      order by id
      for update
    loop
      -- Prospetto del vivaio (19/10/2026): il nuovo ruolo va sul prospetto e lo seguira' alla promozione.
      if v_cambio.vivaio_id is not null then
        select coalesce(vp.posizioni_override, p.posizioni), p.nome into v_precedenti, v_nome
        from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id where vp.id = v_cambio.vivaio_id;
        select (array[v_cambio.ruolo_target] || coalesce(array_agg(r order by ord), '{}'::text[]))[1:6] into v_nuove
        from unnest(coalesce(v_precedenti, '{}'::text[])) with ordinality as u(r, ord) where r <> v_cambio.ruolo_target;
        update public.vivaio_prospetti set posizioni_override = v_nuove where id = v_cambio.vivaio_id;
        update public.cambi_ruolo set completato_il = now() where id = v_cambio.id;
        perform private.notifica(t.user_id, v_lega.id, 'sistema', 'Riqualificazione completata',
          coalesce(v_nome, 'Un prospetto') || ' (vivaio) ha completato il training e ha cambiato ruolo: conserva i ruoli precedenti come secondari.',
          jsonb_build_object('view', 'team'))
        from public.teams t where t.id = v_cambio.team_id;
        v_completati := v_completati + 1;
        continue;
      end if;
      -- Elenco ruoli da cui si parte: l'override se il giocatore ha gia'
      -- cambiato ruolo in passato, altrimenti quello del catalogo.
      select coalesce(pi.posizioni_override, p.posizioni) into v_precedenti
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.id = v_cambio.player_instance_id;

      -- Il target va in testa (ruolo naturale), tutti gli altri lo
      -- seguono nell'ordine di prima. array_agg su zero righe torna NULL,
      -- da cui il coalesce: un giocatore con un solo ruolo resta con uno.
      -- Il taglio a 6 tiene il limite del catalogo anche dopo piu'
      -- riqualificazioni: a cadere e' sempre il ruolo piu' vecchio.
      select (array[v_cambio.ruolo_target] || coalesce(array_agg(r order by ord), '{}'::text[]))[1:6]
      into v_nuove
      from unnest(coalesce(v_precedenti, '{}'::text[])) with ordinality as u(r, ord)
      where r <> v_cambio.ruolo_target;

      update public.player_instances
      set posizioni_override = v_nuove
      where id = v_cambio.player_instance_id;

      update public.cambi_ruolo set completato_il = now() where id = v_cambio.id;

      -- Il nome serve alla notifica: senza, l'avviso diceva solo "un
      -- giocatore" e con 25 uomini in rosa toccava cercarlo a mano — cioe'
      -- proprio il contrario di quello per cui la notifica esiste
      -- (segnalato dall'utente il 10 settembre 2026).
      select p.nome into v_nome
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.id = v_cambio.player_instance_id;

      -- Season 2: piano e cambio ruolo possono andare insieme. Se il piano
      -- attivo non fa parte dei piani del NUOVO ruolo, tornerebbe attivo senza
      -- poterlo piu' vedere ne' annullare: si riporta alla crescita naturale,
      -- tenendo al giocatore quello che il piano ha gia' spostato (stessa
      -- contabilita' di avvia_specializzazione, col reparto di PRIMA).
      if coalesce(v_lega.tattiche_attive, false) then
        select pi.specializzazione_attiva, pi.piano_scostamenti, pi.piano_overall_rif, pi.overall_corrente
        into v_pi from public.player_instances pi where pi.id = v_cambio.player_instance_id;
        if v_pi.specializzazione_attiva is not null and v_pi.specializzazione_attiva <> 'bilanciato'
           and not (private.specializzazioni_ruolo(v_nuove[1]) ? v_pi.specializzazione_attiva) then
          v_etichetta := coalesce(
            private.specializzazioni_ruolo(v_precedenti[1]) -> v_pi.specializzazione_attiva ->> 'etichetta',
            v_pi.specializzazione_attiva);
          v_maturato := private.scostamenti_piano(
            v_pi.specializzazione_attiva, private.macro_ruolo(v_precedenti),
            case when v_pi.piano_overall_rif is null then 0 else v_pi.overall_corrente - v_pi.piano_overall_rif end);
          v_congelati := coalesce(v_pi.piano_scostamenti, '{}'::jsonb);
          for v_chiave in select jsonb_object_keys(v_maturato) loop
            v_congelati := v_congelati || jsonb_build_object(v_chiave,
              round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
          end loop;
          update public.player_instances
          set piano_scostamenti = v_congelati, specializzazione_attiva = 'bilanciato', piano_overall_rif = overall_corrente
          where id = v_cambio.player_instance_id;

          perform private.notifica(
            t.user_id, v_lega.id, 'sistema', 'Piano di sviluppo interrotto',
            coalesce(v_nome, 'Un giocatore') || ' ha cambiato ruolo e il piano ' || v_etichetta
              || ' non vale per il nuovo ruolo: torna alla crescita naturale. Puoi sceglierne un altro.',
            jsonb_build_object('view', 'team', 'player_instance_id', v_cambio.player_instance_id)
          )
          from public.teams t where t.id = v_cambio.team_id;
        end if;
      end if;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Riqualificazione completata',
        coalesce(v_nome, 'Un giocatore') || ' ha completato il training: ora gioca ' ||
        (case v_cambio.ruolo_target when 'GK' then 'POR' when 'CB' then 'DC' when 'RB' then 'TD' when 'LB' then 'TS'
          when 'CDM' then 'CDC' when 'CM' then 'CC' when 'RM' then 'ED' when 'LM' then 'ES' when 'CAM' then 'COC'
          when 'RW' then 'AD' when 'LW' then 'AS' when 'ST' then 'ATT' when 'RWB' then 'FD' when 'LWB' then 'FS'
          when 'CF' then 'CA' else v_cambio.ruolo_target end) ||
        ', e conserva i ruoli precedenti come secondari. Puoi avviargli un nuovo allenamento.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_cambio.player_instance_id)
      )
      from public.teams t where t.id = v_cambio.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$function$;

CREATE OR REPLACE FUNCTION public.offri_promozione(p_vivaio_id bigint, p_ingaggio bigint)
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
    coalesce(v_player.mentalita_vittorie, 34::smallint), coalesce(v_posizione, 1::smallint),
    coalesce(private.squadre_nel_gruppo((select se.id from public.seasons se where se.league_id = v_prospetto.league_id and se.numero = v_league.stagione_corrente), v_squadra.id), v_league.n_squadre)::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);
  v_rapporto := p_ingaggio / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(v_squadra.id, p_ingaggio, private.stagione_contratto(v_prospetto.league_id));

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

    update public.cambi_ruolo set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;
    update public.specializzazioni_giocatore set player_instance_id = v_istanza.id, vivaio_id = null where vivaio_id = v_prospetto.id;

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
$function$;

revoke all on function public.vivaio_scheda(bigint), public.ruoli_target_cambio_vivaio(bigint), public.avvia_cambio_ruolo_vivaio(bigint, text),
  public.specializzazioni_disponibili_vivaio(bigint), public.avvia_specializzazione_vivaio(bigint, text) from public, anon;
grant execute on function public.vivaio_scheda(bigint), public.ruoli_target_cambio_vivaio(bigint), public.avvia_cambio_ruolo_vivaio(bigint, text),
  public.specializzazioni_disponibili_vivaio(bigint), public.avvia_specializzazione_vivaio(bigint, text) to authenticated;

commit;
