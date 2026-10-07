-- Le sigle dei ruoli nelle notifiche sono italiane (POR, DC, TD, TS, CDC, CC, ED, ES, COC, AD, AS, ATT),
-- come nell'interfaccia. Nel DB i codici restano quelli EA: cambia solo il testo del messaggio.
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
$function$
;

-- Notifiche gia' scritte: stessa traduzione sul testo.
update public.notifications n
set corpo = regexp_replace(n.corpo, 'ora gioca (GK|CB|RB|LB|CDM|CM|RM|LM|CAM|RW|LW|ST|RWB|LWB|CF),',
  'ora gioca ' || (case (regexp_match(n.corpo, 'ora gioca (\w+),'))[1]
    when 'GK' then 'POR' when 'CB' then 'DC' when 'RB' then 'TD' when 'LB' then 'TS' when 'CDM' then 'CDC'
    when 'CM' then 'CC' when 'RM' then 'ED' when 'LM' then 'ES' when 'CAM' then 'COC' when 'RW' then 'AD'
    when 'LW' then 'AS' when 'ST' then 'ATT' when 'RWB' then 'FD' when 'LWB' then 'FS' when 'CF' then 'CA' end) || ',')
where n.corpo like '%ha completato il training: ora gioca %';
