-- Training (cambio ruolo e piano di sviluppo) attraverso il cambio di stagione (segnalato il 6/11/2026).
--
-- Gli allenamenti contano le giornate con il numero della giornata ("pronto alla giornata 35"), ma ogni
-- stagione riparte dalla giornata 1. Tre difetti ne venivano fuori:
--   1. senza partite da giocare (off-season, o la fine dei playoff) la "prossima giornata" era
--      giornate_totali + 1 = 23 in Serie F, anche se i playoff erano arrivati alla 29: chi avviava un
--      cambio ruolo in off-season leggeva "entra in vigore alla giornata 35";
--   2. un allenamento a cavallo di due stagioni aspettava la giornata 35 della stagione DOPO: un DC verso
--      TD da 12 giornate partito in off-season sarebbe finito a fine della stagione successiva, e quelli
--      oltre l'ultima giornata giocata non finivano mai;
--   3. infatti 25 cambi ruolo avviati nella Season 1 erano ancora fermi, con il giocatore bloccato.
--
-- Rimedio: una sola funzione dice qual e' la prossima giornata del training (prima giornata da giocare
-- della stagione in corso; se non ce ne sono, quella dopo l'ultima in calendario; a stagione nuova senza
-- calendario, la 1). Al passaggio di stagione gli allenamenti in corso si riportano sulla numerazione
-- nuova togliendo le giornate della stagione finita, piu' 6 giornate di "estate" (richiesta del
-- committente, 6/11/2026): l'off-season vale come 6 giornate di allenamento, anche per chi l'ha avviato
-- in off-season.

create or replace function private.giornata_training(p_league_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select min(f.giornata) from public.fixtures f join public.seasons s on s.id = f.season_id
      where s.league_id = l.id and s.numero = l.stagione_corrente and f.stato = 'programmata'),
    (select max(f.giornata) + 1 from public.fixtures f join public.seasons s on s.id = f.season_id
      where s.league_id = l.id and s.numero = l.stagione_corrente),
    1)::integer
  from public.leagues l where l.id = p_league_id
$$;

create or replace function private.riallinea_training_nuova_stagione()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fatte integer;
begin
  -- Giornate della stagione appena chiusa: quante ne ha "consumate" chi era in allenamento.
  select coalesce(max(f.giornata), 0) into v_fatte
  from public.fixtures f join public.seasons s on s.id = f.season_id
  where s.league_id = new.id and s.numero = old.stagione_corrente;
  v_fatte := v_fatte + 6;  -- l'estate

  update public.cambi_ruolo
  set avviato_giornata = avviato_giornata - v_fatte, completa_giornata = completa_giornata - v_fatte
  where league_id = new.id and completato_il is null;
  update public.specializzazioni_giocatore
  set avviato_giornata = avviato_giornata - v_fatte, completa_giornata = completa_giornata - v_fatte
  where league_id = new.id and completato_il is null;
  return null;
end;
$$;

drop trigger if exists leagues_riallinea_training on public.leagues;
create trigger leagues_riallinea_training
  after update of stagione_corrente on public.leagues
  for each row when (new.stagione_corrente > old.stagione_corrente)
  execute function private.riallinea_training_nuova_stagione();

-- Le funzioni che avviano e completano gli allenamenti leggono la prossima giornata da qui.

CREATE OR REPLACE FUNCTION public.avvia_cambio_ruolo(p_instance_id bigint, p_ruolo_target text)
 RETURNS cambi_ruolo
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_target_validi text[];
  v_livello smallint;
  v_riduzione numeric;
  v_base integer;
  v_durata integer;
  v_prossima integer;
  v_cambio public.cambi_ruolo;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un cambio di ruolo solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un cambio di ruolo in corso.';
  end if;
  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' facendo un allenamento di specializzazione: non puo'' anche cambiare ruolo insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_target_validi := private.ruoli_target_cambio(v_posizioni_attuali);
  if v_target_validi is null or not (p_ruolo_target = any(v_target_validi)) then
    raise exception using errcode = '22023',
      message = 'Ruolo non raggiungibile da un giocatore che gioca ' || v_posizioni_attuali[1] || '.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_base := greatest(6, 14 - 2 * (cardinality(v_posizioni_attuali) - 1));
  -- Season 3 (diario §3): verso un ruolo che il giocatore ha gia' in scheda il 25% in meno, sommato allo
  -- sconto dell'allenamento.
  v_durata := greatest(2, round(v_base * (1 - (v_riduzione
    + case when p_ruolo_target = any(v_posizioni_attuali) then 25 else 0 end) / 100.0)));

  v_prossima := private.giornata_training(v_lega.id);

  insert into public.cambi_ruolo (
    league_id, team_id, player_instance_id, ruolo_precedente, ruolo_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_posizioni_attuali[1], p_ruolo_target,
    v_prossima, v_prossima + v_durata
  ) returning * into v_cambio;

  return v_cambio;
end;
$function$;

CREATE OR REPLACE FUNCTION public.avvia_cambio_ruolo_vivaio(p_vivaio_id bigint, p_ruolo_target text)
 RETURNS cambi_ruolo
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Season 3 (diario §3): verso un ruolo gia' in scheda il 25% in meno, come in avvia_cambio_ruolo.
  v_durata := greatest(2, round(greatest(6, 14 - 2 * (cardinality(v_pos) - 1)) * (1 - (v_riduzione
    + case when p_ruolo_target = any(v_pos) then 25 else 0 end) / 100.0)));
  v_prossima := private.giornata_training(v_lega.id);
  insert into public.cambi_ruolo (league_id, team_id, vivaio_id, ruolo_precedente, ruolo_target, avviato_giornata, completa_giornata)
  values (v_lega.id, v_squadra.id, p_vivaio_id, v_pos[1], p_ruolo_target, v_prossima, v_prossima + v_durata)
  returning * into v_cambio;
  return v_cambio;
end $function$;

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
    v_prossima := private.giornata_training(v_lega.id);

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

CREATE OR REPLACE FUNCTION public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
 RETURNS specializzazioni_giocatore
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
  v_maturato jsonb;
  v_congelati jsonb;
  v_chiave text;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if coalesce(v_istanza.specializzazione_attiva, 'bilanciato') = p_specializzazione then
    raise exception using errcode = '55000', message = 'Questo giocatore segue già questo piano di sviluppo.';
  end if;

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;
  -- Season 2: il piano vale subito, quindi puo' convivere con un cambio ruolo
  -- in corso (completa_cambi_ruolo riporta alla crescita naturale un piano che
  -- non vale per il nuovo ruolo). Le altre leghe tengono l'esclusione.
  if not coalesce(v_lega.tattiche_attive, false) and exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' cambiando ruolo: non puo'' anche allenare una specializzazione insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni_attuali[1]);
  if not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = 'Specializzazione non valida per questo ruolo.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  v_prossima := private.giornata_training(v_lega.id);

  -- Season 2 (3 ottobre 2026): il piano sceglie DOVE va la crescita che il
  -- giocatore fa comunque, quindi non c'e' niente da attendere: vale subito.
  -- Solo nelle leghe con le tattiche accese (il flag della season 2); le altre
  -- tengono l'attesa di prima fino al lancio. Stessa contabilita' di
  -- private.completa_specializzazioni: quello che il piano uscente ha gia'
  -- spostato resta al giocatore. La riga resta nello storico, gia' completata.
  if coalesce(v_lega.tattiche_attive, false) then
    v_maturato := private.scostamenti_piano(
      v_istanza.specializzazione_attiva, private.macro_ruolo(v_posizioni_attuali),
      case when v_istanza.piano_overall_rif is null then 0 else v_istanza.overall_corrente - v_istanza.piano_overall_rif end);
    v_congelati := coalesce(v_istanza.piano_scostamenti, '{}'::jsonb);
    for v_chiave in select jsonb_object_keys(v_maturato) loop
      v_congelati := v_congelati || jsonb_build_object(v_chiave,
        round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
    end loop;

    update public.player_instances
    set piano_scostamenti = v_congelati,
        specializzazione_attiva = p_specializzazione,
        piano_overall_rif = overall_corrente
    where id = p_instance_id;

    insert into public.specializzazioni_giocatore (
      league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
      avviato_giornata, completa_giornata, completato_il
    ) values (
      v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
      v_prossima, v_prossima, now()
    ) returning * into v_allenamento;
    return v_allenamento;
  end if;

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$function$;

CREATE OR REPLACE FUNCTION public.avvia_specializzazione_vivaio(p_vivaio_id bigint, p_specializzazione text)
 RETURNS specializzazioni_giocatore
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_prossima := private.giornata_training(v_lega.id);
  insert into public.specializzazioni_giocatore (league_id, team_id, vivaio_id, specializzazione_precedente, specializzazione_target, avviato_giornata, completa_giornata, completato_il)
  values (v_lega.id, v_squadra.id, p_vivaio_id, v_vp.specializzazione_attiva, p_specializzazione, v_prossima, v_prossima, now())
  returning * into v_all;
  return v_all;
end $function$;

CREATE OR REPLACE FUNCTION private.completa_specializzazioni()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_prossima integer;
  v_riga record;
  v_posizioni text[];
  v_maturato jsonb;
  v_congelati jsonb;
  v_chiave text;
  v_etichetta text;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    v_prossima := private.giornata_training(v_lega.id);

    for v_riga in
      select s.*, pi.posizioni_override, pi.overall_corrente, pi.specializzazione_attiva,
        pi.piano_scostamenti, pi.piano_overall_rif,
        p.posizioni as posizioni_catalogo, p.nome as nome_giocatore
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_posizioni := coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo);
      v_etichetta := coalesce(
        private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target ->> 'etichetta',
        v_riga.specializzazione_target);

      -- Quello che il piano uscente ha gia' spostato resta al giocatore.
      v_maturato := private.scostamenti_piano(
        v_riga.specializzazione_attiva, private.macro_ruolo(v_posizioni),
        case when v_riga.piano_overall_rif is null then 0 else v_riga.overall_corrente - v_riga.piano_overall_rif end);
      v_congelati := coalesce(v_riga.piano_scostamenti, '{}'::jsonb);
      for v_chiave in select jsonb_object_keys(v_maturato) loop
        v_congelati := v_congelati || jsonb_build_object(v_chiave,
          round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
      end loop;

      update public.player_instances
      set piano_scostamenti = v_congelati,
          specializzazione_attiva = v_riga.specializzazione_target,
          piano_overall_rif = overall_corrente
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        coalesce(v_riga.nome_giocatore, 'Un giocatore') || ' segue ora il piano ' || v_etichetta
          || ': da qui in avanti la sua crescita si concentra sulle abilità di quel ruolo.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$function$;

-- Recupero dei cambi ruolo gia' storti (solo Serie F ne ha di aperti).
-- a) Avviati nella Season 1 o nella sua off-season (prima della prima partita della Season 2, 7/10 21:00
--    UTC): sarebbero finiti all'inizio della Season 2. Si chiudono ora: li completa il job al minuto,
--    con la solita notifica.
update public.cambi_ruolo c
set completa_giornata = least(c.completa_giornata, private.giornata_training(c.league_id))
where c.completato_il is null
  and c.creato_il < (select min(f.data_sim) from public.fixtures f join public.seasons s on s.id = f.season_id
                     where s.league_id = c.league_id and s.numero = 2);

-- b) Avviati in questa off-season: erano partiti dalla "giornata 23" invece che dalla prossima vera.
--    Si spostano alla prossima giornata del training tenendo la stessa durata.
update public.cambi_ruolo c
set completa_giornata = c.completa_giornata - c.avviato_giornata + private.giornata_training(c.league_id),
    avviato_giornata = private.giornata_training(c.league_id)
from public.leagues l
where c.completato_il is null and l.id = c.league_id and l.fase_carriera = 'offseason'
  and c.creato_il > (select max(f.data_sim) from public.fixtures f join public.seasons s on s.id = f.season_id
                     where s.league_id = l.id and s.numero = l.stagione_corrente);
-- c) Quelli avviati durante la Season 2 restano come sono: chi doveva finire entro i playoff si chiude
--    adesso (la prossima giornata e' la 30, non piu' la 23), gli altri si riallineano alla Season 3.
