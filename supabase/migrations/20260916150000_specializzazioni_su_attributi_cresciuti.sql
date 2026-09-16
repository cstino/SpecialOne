-- ============================================================
--  LE SPECIALIZZAZIONI PARTONO DAGLI ATTRIBUTI DI ADESSO
--
--  completa_specializzazioni calcolava il nuovo valore come
--  "attributi del catalogo + delta della specializzazione". Ma gli attributi
--  del catalogo sono quelli dell'importazione: un ragazzo salito da 46 a 70
--  riceveva il bonus su numeri da 46, e la specializzazione valeva sempre meno
--  mano a mano che il giocatore migliorava. Esattamente al contrario di come
--  dovrebbe funzionare.
--
--  Ora la base e' private.attributi_effettivi, cioe' catalogo piu' la crescita
--  maturata (vedi 20260916140000).
--
--  L'override precedente non entra nella base, ed e' voluto: contiene i valori
--  assoluti della specializzazione passata, e sommarci sopra i nuovi delta
--  farebbe accumulare due specializzazioni invece di sostituirne una. Cambiare
--  specializzazione resta un ricominciare, come prima.
--
--  Definizione ripresa dal database e modificata in due punti: il cursore ora
--  legge anche p.overall (serviva per il delta) e la riga della base.
-- ============================================================

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
        p.overall as overall_catalogo,
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

      -- Base = attributi del catalogo PIU' la crescita maturata fino a oggi
      -- (private.attributi_effettivi). Prima era il solo catalogo: un ragazzo
      -- salito da 46 a 70 riceveva il bonus su numeri da 46, cioe' la
      -- specializzazione valeva meno mano a mano che il giocatore migliorava.
      --
      -- L'override precedente NON entra nella base, ed e' voluto: contiene i
      -- valori assoluti della specializzazione passata, e sommarci sopra i
      -- nuovi delta farebbe accumulare due specializzazioni invece di
      -- sostituirne una. Cambiare specializzazione resta un ricominciare.
      v_base_attributi := private.attributi_effettivi(
        v_riga.attributi_catalogo, v_posizioni,
        v_riga.overall_corrente - v_riga.overall_catalogo, null);
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
