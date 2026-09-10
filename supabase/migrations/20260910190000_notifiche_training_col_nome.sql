-- ============================================================
--  LE NOTIFICHE DI FINE ALLENAMENTO NON DICEVANO CHI
--
--  Richiesta dell'utente il 10 settembre 2026: "quando un giocatore finisce
--  il programma di training deve arrivare una notifica, almeno l'allenatore
--  puo' fargli intraprendere un nuovo training".
--
--  La notifica ESISTEVA gia', in entrambe le funzioni, fin dalla versione
--  originale del 1 settembre. Verificato con un test completo su LegaBot
--  (creato un cambio ruolo scaduto, eseguito private.completa_cambi_ruolo(),
--  contata la notifica, ripristinato tutto): viene creata correttamente, e
--  il trigger notifications_invia_push la spinge anche come push, senza
--  filtri sul tipo. Le sei riqualificazioni completate il 4 settembre non
--  hanno lasciato traccia perche' elimina_notifica() cancella davvero la
--  riga — e quel giorno si stava lavorando proprio su quel pulsante.
--
--  Quello che invece NON andava, ed e' il motivo per cui la notifica non
--  serviva allo scopo descritto:
--
--  1. Non diceva MAI chi. Il testo era "Un giocatore ha completato il
--     training": con 25 uomini in rosa, per avviare un nuovo allenamento
--     bisognava cercarlo a mano, cioe' l'opposto di quello per cui la
--     notifica esiste.
--
--  2. Per le specializzazioni mostrava la CHIAVE INTERNA invece
--     dell'etichetta: "ora e' specializzato come rapace_area" invece di
--     "Rapace d'area". Mai visto da nessuno solo perche' nessuna
--     specializzazione era ancora arrivata a scadenza (0 completate a oggi).
--
--  Entrambe ora nominano il giocatore, usano l'etichetta leggibile e
--  chiudono suggerendo l'azione successiva. Il dato per la navigazione
--  (player_instance_id in 'dati') c'era gia' e resta.
--
--  Funzioni modificate per sostituzione mirata sul testo live: il diff
--  mostra solo le righe di testo e la select a cui e' stato aggiunto il nome.
-- ============================================================

begin;

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
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
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
  v_deltas_base jsonb;
  v_deltas_scalati jsonb;
  v_fattore numeric;
  v_chiave text;
  v_base_attributi jsonb;
  v_override jsonb;
  v_bonus_overall integer;
  v_etichetta text;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_riga in
      select s.*, pi.posizioni_override, pi.eta_corrente, pi.overall_corrente,
        p.posizioni as posizioni_catalogo, p.attributi as attributi_catalogo, p.potential,
        p.nome as nome_giocatore
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_posizioni := coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo);
      v_deltas_base := private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target -> 'deltas';
      -- Etichetta leggibile ("Rapace d'area") invece della chiave interna
      -- ("rapace_area"), che e' quello che finiva nella notifica.
      v_etichetta := coalesce(
        private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target ->> 'etichetta',
        v_riga.specializzazione_target);
      v_fattore := private.fattore_allenamento(v_riga.eta_corrente, v_riga.potential, v_riga.overall_corrente);

      v_deltas_scalati := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(coalesce(v_deltas_base, '{}'::jsonb)) loop
        v_deltas_scalati := v_deltas_scalati || jsonb_build_object(
          v_chiave, round((v_deltas_base->>v_chiave)::numeric * v_fattore)::int
        );
      end loop;

      v_base_attributi := v_riga.attributi_catalogo;
      v_override := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(v_deltas_scalati) loop
        v_override := v_override || jsonb_build_object(
          v_chiave, least(99, coalesce((v_base_attributi->>v_chiave)::int, 0) + (v_deltas_scalati->>v_chiave)::int)
        );
      end loop;

      -- Anti-abuso invariato: il bonus overall scatta solo su un cambio
      -- VERO di specializzazione. Niente pavimento a 1 punto ora: se il
      -- fattore e' quasi zero (poco margine, eta' avanzata), zero e'
      -- l'esito corretto, non un difetto da correggere.
      v_bonus_overall := case
        when v_riga.specializzazione_precedente is distinct from v_riga.specializzazione_target
          then private.bonus_overall_specializzazione(private.macro_ruolo(v_posizioni), v_deltas_scalati)
        else 0
      end;

      update public.player_instances
      set attributi_override = v_override,
          specializzazione_attiva = v_riga.specializzazione_target,
          overall_corrente = least(99, overall_corrente + v_bonus_overall)
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        coalesce(v_riga.nome_giocatore, 'Un giocatore') || ' ha completato l''allenamento: ora è specializzato come ' || v_etichetta
          || case when v_bonus_overall > 0 then format(' (overall +%s)', v_bonus_overall) else '' end
          || '. Puoi avviargli un nuovo allenamento.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$function$
;

commit;
