-- ============================================================
--  L'INTERRUTTORE VALE ANCHE DOVE IL MOTORE NON ARRIVA
--
--  L'interruttore per lega (20260917100000) ferma il motore, ma restavano due
--  strade per cui il sistema tattico agiva lo stesso a interruttore spento.
--
--  1. SALVA_FORMAZIONE scriveva schema, ruoli e compiti comunque. Sembra
--     innocuo — il motore non li guarda — ma la familiarita' e' indicizzata
--     SULLO SCHIERAMENTO (formation_xp.disposizione): si sarebbe creato un
--     contatore per una forma che in campo non e' mai stata giocata davvero, e
--     la barra avrebbe raccontato una storia falsa. Ora i tre campi vengono
--     ignorati, senza errore: chi salva non deve ricevere un rifiuto per
--     un'impostazione che non ha scelto lui.
--
--  2. IL CAPITANO agiva su applica_morale_checkpoint, che gira sempre — non
--     passa dal motore e quindi non passava dall'interruttore. Era la fuga piu'
--     insidiosa delle due, perche' il checkpoint del morale tocca i rinnovi.
--
--  Le due definizioni sono riprese integralmente dal database vivo: cambiano
--  poche righe ciascuna, il resto e' quello che gira adesso.
-- ============================================================

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_i integer;
  v_std text[];
  v_schema text[];
  v_league public.leagues;
  v_team public.teams;
  v_all bigint[];
  v_convocati bigint[];
  v_rosa_count integer;
  v_unique_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare la formazione.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La stagione non e'' ancora iniziata.';
  end if;
  -- Playoff e playout vivono a giornate OLTRE la stagione regolare (con 16
  -- squadre: regolare fino alla 30, playoff 31 e 32), quindi il confronto
  -- con giornate_totali da solo rendeva impossibile schierare la formazione
  -- proprio nelle partite decisive. Si accetta anche una giornata piu' alta,
  -- purche' esista davvero come turno di questa stagione.
  if p_giornata < 1 or (
    p_giornata > v_league.giornate_totali
    and not exists (
      select 1
      from public.fixtures f
      join public.seasons s on s.id = f.season_id
      where s.league_id = p_league_id
        and s.numero = v_league.stagione_corrente
        and f.giornata = p_giornata
    )
  ) then
    raise exception using errcode = '22023', message = 'Giornata non valida per questa lega.';
  end if;
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_gioco = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  -- Schema personalizzato: gli undici slot davvero schierati. NULL = lo
  -- schieramento standard del modulo, cioe' il comportamento di sempre.
  -- Ogni posizione puo' solo salire o scendere di una linea sulla propria
  -- corsia (private.spostamenti_slot), quindi da qui non puo' uscire uno
  -- schieramento che il motore non sa valutare.
  -- A interruttore spento lo schema personalizzato non si scrive nemmeno.
  -- Non e' pignoleria: la familiarita' e' indicizzata SULLO SCHIERAMENTO
  -- (formation_xp.disposizione), quindi salvare una variante che il motore
  -- ignora creerebbe un contatore per una forma mai davvero giocata, e la
  -- barra racconterebbe una storia falsa. Chi salva senza saperlo non riceve
  -- un errore: gli si ignorano i tre campi, come se non li avesse mandati.
  if not (select l.tattiche_attive from public.leagues l where l.id = p_league_id) then
    p_disposizione := null;
    p_ruoli := null;
    p_compiti := null;
  end if;

  if p_disposizione is not null then
    if cardinality(p_disposizione) <> 11 then
      raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
    end if;
    v_std := private.disposizione_standard(p_modulo);
    if v_std is null then
      raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
    end if;
    for v_i in 1..11 loop
      if not (p_disposizione[v_i] = any(private.spostamenti_slot(v_std[v_i]))) then
        raise exception using errcode = '22023',
          message = format('La posizione %s non puo'' diventare %s.', v_std[v_i], p_disposizione[v_i]);
      end if;
    end loop;
  end if;

  v_schema := coalesce(p_disposizione, private.disposizione_standard(p_modulo));

  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(v_schema[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], v_schema[v_i]);
      end if;
    end loop;
  end if;

  if p_compiti is not null then
    if cardinality(p_compiti) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 compiti, uno per posizione.';
    end if;
    if exists (select 1 from unnest(p_compiti) c where c is not null and c not in ('difesa','equilibrio','attacco')) then
      raise exception using errcode = '22023', message = 'Compito non valido.';
    end if;
  end if;

  if coalesce(cardinality(p_titolari), 0) <> 11 then
    raise exception using errcode = '22023', message = 'Servono esattamente 11 titolari.';
  end if;
  if coalesce(cardinality(p_panchina), 0) > 9 then
    raise exception using errcode = '22023', message = 'La panchina puo'' contenere al massimo 9 giocatori.';
  end if;
  if p_titolari[1] is null then
    raise exception using errcode = '22023', message = 'Il primo slot deve contenere il portiere, anche se di movimento.';
  end if;
  if array_position(p_titolari, null) is not null
     or array_position(p_panchina, null) is not null
     or array_position(p_tribuna, null) is not null then
    raise exception using errcode = '22023', message = 'La formazione contiene uno slot vuoto non valido.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  v_all := p_titolari || coalesce(p_panchina, '{}'::bigint[]) || coalesce(p_tribuna, '{}'::bigint[]);
  v_unique_count := (select count(distinct id)::integer from unnest(v_all) as u(id));
  if v_unique_count <> cardinality(v_all) then
    raise exception using errcode = '22023', message = 'Lo stesso giocatore compare piu'' volte nella formazione.';
  end if;

  select count(*) into v_rosa_count
  from public.player_instances
  where league_id = p_league_id and team_id = v_team.id and id = any(v_all);
  if v_rosa_count <> cardinality(v_all) then
    raise exception using errcode = '42501', message = 'La formazione contiene un giocatore fuori dalla tua rosa.';
  end if;

  v_convocati := p_titolari || coalesce(p_panchina, '{}'::bigint[]);
  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and team_id = v_team.id
      and id = any(v_convocati) and infortunato_fino_a > 0
  ) then
    raise exception using errcode = '22023', message = 'Un giocatore infortunato non puo'' essere titolare o andare in panchina. Spostalo in tribuna.';
  end if;

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il,
    disposizione, ruoli, compiti
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now(),
    p_disposizione, p_ruoli, p_compiti
  )
  on conflict (team_id, giornata) do update set
    modulo = excluded.modulo,
    titolari = excluded.titolari,
    panchina = excluded.panchina,
    tribuna = excluded.tribuna,
    stile_gioco = excluded.stile_gioco,
    automatica = false,
    salvata_il = now(),
    disposizione = excluded.disposizione,
    ruoli = excluded.ruoli,
    compiti = excluded.compiti;

  -- Chi batte piazzati e rigori: assegnato in automatico, e ricontrollato a
  -- ogni salvataggio. Un incarico sopravvive solo se quel giocatore e' ancora
  -- fra i titolari; altrimenti passa al migliore disponibile. Chi vuole lo
  -- cambia dopo, dalla stessa pagina.
  perform private.sistema_incaricati(v_team.id, p_giornata);

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', v_team.id,
    'giornata', p_giornata,
    'modulo', p_modulo,
    'stile_gioco', p_stile_gioco,
    'disposizione', p_disposizione,
    'ruoli', p_ruoli,
    'compiti', p_compiti,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.applica_morale_checkpoint(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_aggiornati integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_nuovo smallint;
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;

  -- Stessa scansione della progressione overall: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_morale_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_stagione_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    for v_giocatore in
      select
        pi.id,
        pi.morale,
        pi.ingaggio,
        pi.overall_corrente,
        pi.eta_corrente,
        pi.team_id,
        -- Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
        -- un capitano, o se il capitano e' quello che si sta valutando: chi
        -- porta la fascia non consola se stesso.
        case when t.capitano is null or t.capitano = pi.id then 0
             when not l.tattiche_attive then 0
             else private.qualita_capitano(t.capitano) end as forza_capitano,
        p.mentalita_bandiera,
        p.mentalita_economia,
        p.mentalita_vittorie,
        -- media overall della propria rosa: e' il metro con cui il giocatore
        -- giudica quanto dovrebbe giocare
        (select avg(x.overall_corrente)
           from public.player_instances x
          where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
        -- quota di minuti effettivamente giocati sulle giornate disputate
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate,
        coalesce((select st.posizione
                    from public.standings st
                   where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      join public.leagues l on l.id = pi.league_id
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      v_delta_min := greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente))
        ) * 30
      ));

      -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
      v_delta_eco := greatest(-10, least(6,
        ((v_giocatore.ingaggio::numeric
          / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
      )) * (v_giocatore.mentalita_economia / 33.0);

      -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
      v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_lega.n_squadre - 1)))
        * 16 * (v_giocatore.mentalita_vittorie / 33.0);

      -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
      --    Un bandiera 60 assorbe il 30% del malcontento.
      v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

      -- 5. Il capitano. In Football Manager la fascia agisce sullo spogliatoio
      --    nel tempo, non sui novanta minuti: e' qui che deve pesare, non nel
      --    motore. Un trascinatore assorbe fino al 30% del malcontento dei
      --    compagni; un capitano scontento lo peggiora, perche' la qualita' va
      --    anche sotto zero. Si moltiplica con l'attenuazione da bandiera
      --    invece di sommarsi: sono due modi diversi di reggere lo stesso colpo,
      --    e sommandoli un bandiera capitano sarebbe diventato immune.
      v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);

      v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
      v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit))
                    * v_attenuazione * v_att_capitano;

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;

$function$;
