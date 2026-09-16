-- ============================================================
--  RIPARAZIONE DEI TRAINING VERSO CF — Cocciaspigola, Serie F
--
--  La migrazione precedente ha tolto il CF dai bersagli del cambio ruolo,
--  perche' nessun modulo lo schiera e chi ci arrivava restava fuori ruolo per
--  sempre. Restava pero' il danno gia' prodotto, tutto nella stessa squadra:
--
--    - cinque training verso CF ancora in corso, in scadenza alla giornata 19
--      (Boniface, Wood, En-Nesyri, Fofana, Hirst);
--    - uno gia' completato il 12 settembre, J. Robinson, che da ST e' diventato
--      CF e da allora gioca la sua posizione naturale a 0.98 invece di 1.00.
--      Un allenamento che lo ha peggiorato.
--
--  Deciso con l'amministratore della lega: i cinque vengono dirottati su CAM —
--  la sostituzione che lui stesso ha indicato per lo ST — cosi' il tempo gia'
--  investito non si perde. Robinson viene trattato come se avesse puntato al
--  CAM fin dall'inizio.
--
--  I ruoli si ricostruiscono con la stessa regola di private.completa_cambi_ruolo:
--  il bersaglio va in testa, gli altri lo seguono nell'ordine che avevano. In
--  piu' qui si toglie il CF, che non deve restare nemmeno come secondario: e'
--  una posizione che il gioco non sa schierare e occuperebbe uno dei sei posti
--  disponibili senza mai servire a niente.
--
--  I destinatari della notifica si raccolgono PRIMA di cambiare i bersagli.
--  Cercarli dopo avrebbe voluto dire selezionare "i training verso CAM", che
--  comprende anche quelli avviati legittimamente da altri: avrebbero ricevuto
--  la spiegazione di un cambio che non li riguarda.
-- ============================================================

do $$
declare
  v_destinatari record;
  v_dirottati   integer := 0;
  v_riparato    record;
  v_nuovi       text[];
begin
  -- ------------------------------------------------------------
  --  1. Chi va avvisato, prima di toccare qualsiasi cosa
  -- ------------------------------------------------------------
  create temp table if not exists da_avvisare (user_id uuid, league_id bigint) on commit drop;
  insert into da_avvisare
  select distinct t.user_id, pi.league_id
  from public.cambi_ruolo cr
  join public.player_instances pi on pi.id = cr.player_instance_id
  join public.teams t on t.id = pi.team_id
  where cr.completato_il is null and cr.ruolo_target = 'CF' and t.user_id is not null;

  -- ------------------------------------------------------------
  --  2. I training ancora in corso: bersaglio CF -> CAM
  -- ------------------------------------------------------------
  update public.cambi_ruolo set ruolo_target = 'CAM'
  where completato_il is null and ruolo_target = 'CF';
  get diagnostics v_dirottati = row_count;
  raise notice 'Training dirottati su CAM: %', v_dirottati;

  -- ------------------------------------------------------------
  --  3. Chi il CF ce l'ha gia' addosso
  -- ------------------------------------------------------------
  for v_riparato in
    select pi.id, p.nome, coalesce(pi.posizioni_override, p.posizioni) as ruoli
    from public.cambi_ruolo cr
    join public.player_instances pi on pi.id = cr.player_instance_id
    join public.players p on p.id = pi.player_id
    where cr.completato_il is not null and cr.ruolo_target = 'CF'
      and 'CF' = any(coalesce(pi.posizioni_override, p.posizioni))
  loop
    -- CAM in testa, gli altri nell'ordine di prima, senza CF e senza doppioni.
    select (array['CAM'] || coalesce(array_agg(r order by ord), '{}'::text[]))[1:6]
    into v_nuovi
    from unnest(v_riparato.ruoli) with ordinality as u(r, ord)
    where r <> 'CAM' and r <> 'CF';

    update public.player_instances set posizioni_override = v_nuovi where id = v_riparato.id;

    -- Anche la riga storica dice CAM: lasciarla a CF avrebbe raccontato un
    -- cambio di ruolo che nel gioco non esiste piu'.
    update public.cambi_ruolo set ruolo_target = 'CAM'
    where player_instance_id = v_riparato.id and completato_il is not null and ruolo_target = 'CF';

    raise notice 'Riparato %: ora %', v_riparato.nome, array_to_string(v_nuovi, ' ');
  end loop;

  -- ------------------------------------------------------------
  --  4. L'avviso
  -- ------------------------------------------------------------
  for v_destinatari in select user_id, league_id from da_avvisare loop
    perform private.notifica(
      v_destinatari.user_id, v_destinatari.league_id, 'sistema',
      'Allenamenti verso CF dirottati su CAM',
      'Il ruolo CF non e'' schierabile in nessun modulo: offrirlo come obiettivo di '
        || 'allenamento era un errore, ed e'' stato tolto. Gli allenamenti che avevi avviato '
        || 'verso CF puntano ora al CAM, senza perdere il tempo gia'' fatto.',
      jsonb_build_object('view', 'team')
    );
  end loop;
end $$;
