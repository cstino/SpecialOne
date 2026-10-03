-- ============================================================
--  Piano di sviluppo e cambio ruolo insieme (season 2, 3 ottobre 2026).
--
--  Col piano che vale subito (migrazione 20261003100000) l'esclusione
--  reciproca fra piano e cambio ruolo non ha piu' ragione. Nelle leghe con le
--  tattiche accese: avvia_specializzazione non guarda piu' il cambio ruolo in
--  corso; completa_cambi_ruolo, se il piano attivo non vale per il nuovo ruolo
--  (il catalogo dei piani e' per ruolo primario), lo riporta alla crescita
--  naturale tenendo quello che ha gia' spostato, e avvisa l'utente.
--  avvia_cambio_ruolo non cambia: in queste leghe non ci sono piani "in corso".
--
--  Funzioni ricostruite dal testo vivo del database (non a memoria).
-- ============================================================
begin;

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

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

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
$function$
;

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
        coalesce(v_nome, 'Un giocatore') || ' ha completato il training: ora gioca ' || v_cambio.ruolo_target ||
        ', e conserva i ruoli precedenti come secondari. Puoi avviargli un nuovo allenamento.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_cambio.player_instance_id)
      )
      from public.teams t where t.id = v_cambio.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$function$
;

commit;
