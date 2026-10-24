-- Formazione: niente portieri fuori dai pali e niente giocatori di movimento in porta (24/10/2026, committente).
-- Serve contro chi vuole perdere apposta per finire nei Draft Playoffs schierando una formazione assurda. Le altre
-- scelte fuori ruolo restano libere (con la loro penalita' del motore): si vietano solo i due casi estremi.
-- Eccezioni, per non bloccare chi e' davvero in emergenza: se in rosa non c'e' nessun portiere disponibile (tutti
-- infortunati o squalificati) in porta puo' andare chiunque; se i giocatori di movimento disponibili sono meno di 10,
-- un portiere puo' giocare fuori. Il ruolo vale come altrove: posizioni_override se c'e', altrimenti quello del giocatore.
-- Funzione riscritta dalla definizione viva.

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text, p_velocita text DEFAULT NULL::text)
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
  v_gk_disp integer;
  v_mov_disp integer;
  v_primo_gk boolean;
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
    p_focus_corsia := null;
    p_linea := null;
    p_ampiezza := null;
    p_velocita := null;
    p_portiere := null;
  end if;

  -- Dove si attacca. NULL = da nessuna parte in particolare, ed e' una scelta
  -- come le altre: concentrare su una corsia paga se l'avversario la' e'
  -- scoperto e costa se e' il suo lato forte (engine/corsie.js).
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX','FASCE') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;

  -- Indicazioni di squadra (registro tattico, punto 30). NULL = l'opzione
  -- predefinita: linea media, ampiezza normale, portiere normale.
  if p_linea is not null and p_linea not in ('alta','bassa') then
    raise exception using errcode = '22023', message = 'Linea difensiva non valida.';
  end if;
  if p_ampiezza is not null and p_ampiezza not in ('larga','stretta') then
    raise exception using errcode = '22023', message = 'Ampiezza non valida.';
  end if;
  if p_velocita is not null and p_velocita not in ('ragionata','veloce') then
    raise exception using errcode = '22023', message = 'Velocita'' di manovra non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
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
  if not private.disposizione_simmetrica(p_disposizione) then
    raise exception using errcode = '22023',
      message = 'Schema non valido: un terzino, un esterno di centrocampo o un''ala non possono esistere solo a destra o solo a sinistra.';
  end if;
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

  -- Portiere vero in porta, niente portieri fra i dieci di movimento (eccezioni: nessun portiere disponibile,
  -- o meno di 10 giocatori di movimento disponibili).
  select count(*) filter (where 'GK' = any(coalesce(pi.posizioni_override, p.posizioni))),
         count(*) filter (where not ('GK' = any(coalesce(pi.posizioni_override, p.posizioni))))
    into v_gk_disp, v_mov_disp
    from public.player_instances pi join public.players p on p.id = pi.player_id
   where pi.league_id = p_league_id and pi.team_id = v_team.id and not coalesce(pi.ritirato, false)
     and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0;
  select 'GK' = any(coalesce(pi.posizioni_override, p.posizioni)) into v_primo_gk
    from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = p_titolari[1];
  if not coalesce(v_primo_gk, false) and v_gk_disp > 0 then
    raise exception using errcode = '22023', message = 'In porta deve giocare un portiere: ne hai disponibili in rosa.';
  end if;
  if v_mov_disp >= 10 and exists (
    select 1 from unnest(p_titolari[2:11]) as u(id)
      join public.player_instances pi on pi.id = u.id join public.players p on p.id = pi.player_id
     where 'GK' = any(coalesce(pi.posizioni_override, p.posizioni))
  ) then
    raise exception using errcode = '22023', message = 'Un portiere non puo'' giocare fuori dai pali: mettilo in porta, in panchina o in tribuna.';
  end if;

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il,
    disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, velocita_manovra, ruolo_portiere
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now(),
    p_disposizione, p_ruoli, p_compiti, p_focus_corsia, p_linea, p_ampiezza, p_velocita, p_portiere
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
    compiti = excluded.compiti,
    focus_corsia = excluded.focus_corsia,
    linea_difensiva = excluded.linea_difensiva,
    ampiezza = excluded.ampiezza,
    velocita_manovra = excluded.velocita_manovra,
    ruolo_portiere = excluded.ruolo_portiere;

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
    'focus_corsia', p_focus_corsia,
    'linea_difensiva', p_linea,
    'ampiezza', p_ampiezza,
    'velocita_manovra', p_velocita,
    'ruolo_portiere', p_portiere,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$;
