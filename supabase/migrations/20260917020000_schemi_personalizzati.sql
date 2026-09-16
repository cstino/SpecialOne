-- ============================================================
--  SCHEMI PERSONALIZZATI: SALVARE POSIZIONI, RUOLI E COMPITI
--
--  Scelto un modulo, ogni posizione puo' SALIRE O SCENDERE DI UNA LINEA
--  restando sulla propria corsia — un 4-4-2 i cui due CM diventano CDM, per
--  dire. E' la stessa idea delle tattiche personalizzate di FC, e soprattutto
--  e' una regola che si spiega in una riga: cosa che conta, perche' finisce
--  davanti all'utente.
--
--  Le tre colonne nascono NULL e restano NULL per chi non entra nel dettaglio:
--  lo schieramento e' quello standard del modulo e non c'e' nessun ruolo ne'
--  compito, cioe' esattamente il gioco di oggi.
--
--  Le due tabelle qui sotto sono GENERATE da engine/config.js (SPOSTAMENTI_SLOT)
--  e engine/ruoli.js (RUOLI): il motore resta l'unica verita'. Se cambiano la',
--  vanno rigenerate qui.
-- ============================================================

create or replace function private.spostamenti_slot(p_slot text)
returns text[] language sql immutable parallel safe set search_path = ''
as $$
  select case p_slot
    when 'GK' then array['GK']::text[]
    when 'CB' then array['CB','CDM']::text[]
    when 'LB' then array['LB','LWB']::text[]
    when 'RB' then array['RB','RWB']::text[]
    when 'LWB' then array['LWB','LB','LM']::text[]
    when 'RWB' then array['RWB','RB','RM']::text[]
    when 'CDM' then array['CDM','CB','CM']::text[]
    when 'CM' then array['CM','CDM','CAM']::text[]
    when 'CAM' then array['CAM','CM','ST']::text[]
    when 'LM' then array['LM','LWB','LW']::text[]
    when 'RM' then array['RM','RWB','RW']::text[]
    when 'LW' then array['LW','LM']::text[]
    when 'RW' then array['RW','RM']::text[]
    when 'ST' then array['ST','CAM']::text[]
    else array[p_slot]::text[]
  end
$$;

revoke all on function private.spostamenti_slot(text) from public, anon, authenticated;
grant execute on function private.spostamenti_slot(text) to authenticated;

create or replace function private.ruoli_slot(p_slot text)
returns text[] language sql immutable parallel safe set search_path = ''
as $$
  select case p_slot
    when 'GK' then array[]::text[]
    when 'CB' then array['centrale','centrale_marcatore','centrale_impostatore']::text[]
    when 'LB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'RB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'LWB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'RWB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'CDM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'CM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'CAM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'LM' then array['esterno','ala_pura','esterno_a_rientrare','esterno_di_rientro']::text[]
    when 'RM' then array['esterno','ala_pura','esterno_a_rientrare','esterno_di_rientro']::text[]
    when 'LW' then array['esterno','ala_pura','esterno_a_rientrare','esterno_di_rientro']::text[]
    when 'RW' then array['esterno','ala_pura','esterno_a_rientrare','esterno_di_rientro']::text[]
    when 'ST' then array['punta','finalizzatore','punta_di_manovra']::text[]
    when 'CF' then array['punta','finalizzatore','punta_di_manovra']::text[]
    else '{}'::text[]
  end
$$;

revoke all on function private.ruoli_slot(text) from public, anon, authenticated;
grant execute on function private.ruoli_slot(text) to authenticated;

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

-- ------------------------------------------------------------
--  Via la firma vecchia
--
--  Aggiungere parametri con un default non sostituisce la funzione: ne crea una
--  seconda. Con entrambe presenti PostgREST sceglie in base ai nomi degli
--  argomenti, e il frontend che ne passa sette continuerebbe a chiamare quella
--  vecchia — che ignora schema, ruoli e compiti. Il bug sarebbe stato silenzioso.
-- ------------------------------------------------------------
drop function if exists public.salva_formazione(bigint, smallint, text, bigint[], bigint[], bigint[], text);
