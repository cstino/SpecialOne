-- ============================================================
--  SCHEMI: SIMMETRIA OBBLIGATORIA DESTRA/SINISTRA
--  Segnalato dal committente il 4 ottobre 2026: era possibile salvare uno
--  schema con CB, CB, RB e nessun LB (Regginho FC). Nel calcio un terzino
--  destro senza il sinistro, un'ala destra senza la sinistra o un esterno di
--  centrocampo solo da un lato non esistono.
--
--  Regola (private.disposizione_simmetrica): terzini e terzini a tutta fascia
--  (LB+LWB contro RB+RWB), esterni di centrocampo (LM contro RM) e ali (LW
--  contro RW) devono essere in numero uguale a destra e a sinistra. Un LB con
--  un RWB e' ammesso (stessa funzione, un lato spinge e uno no).
--  Applicata in salva_formazione, salva_modulo_personalizzato e salva_schemi:
--  le tre strade da cui uno schema entra nel database. Nessuna riga esistente
--  la violava (controllato prima).
-- ============================================================

create or replace function private.disposizione_simmetrica(p_disposizione text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_disposizione is null or (
    (select count(*) from unnest(p_disposizione) x where x in ('LB', 'LWB'))
      = (select count(*) from unnest(p_disposizione) x where x in ('RB', 'RWB'))
    and (select count(*) from unnest(p_disposizione) x where x = 'LM')
      = (select count(*) from unnest(p_disposizione) x where x = 'RM')
    and (select count(*) from unnest(p_disposizione) x where x = 'LW')
      = (select count(*) from unnest(p_disposizione) x where x = 'RW')
  )
$$;

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text)
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
    p_focus_corsia := null;
    p_linea := null;
    p_ampiezza := null;
    p_portiere := null;
  end if;

  -- Dove si attacca. NULL = da nessuna parte in particolare, ed e' una scelta
  -- come le altre: concentrare su una corsia paga se l'avversario la' e'
  -- scoperto e costa se e' il suo lato forte (engine/corsie.js).
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX') then
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

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il,
    disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now(),
    p_disposizione, p_ruoli, p_compiti, p_focus_corsia, p_linea, p_ampiezza, p_portiere
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
    'ruolo_portiere', p_portiere,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.salva_modulo_personalizzato(p_league_id bigint, p_nome text, p_modulo text, p_disposizione text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_sostituisci bigint DEFAULT NULL::bigint, p_stile text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team_id bigint;
  v_std     text[];
  v_nome    text := btrim(coalesce(p_nome, ''));
  v_id      bigint;
  v_i       integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare un modulo.';
  end if;

  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  if char_length(v_nome) not between 1 and 30 then
    raise exception using errcode = '22023', message = 'Il nome deve avere da 1 a 30 caratteri.';
  end if;

  -- Stessi controlli di salva_formazione: da qui non puo' uscire uno schema
  -- che poi la formazione rifiuterebbe.
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  v_std := private.disposizione_standard(p_modulo);
  if v_std is null then
    raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
  end if;
  if p_disposizione is null or cardinality(p_disposizione) <> 11 then
    raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
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

  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(p_disposizione[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], p_disposizione[v_i]);
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

  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;
  if p_stile is not null and not (p_stile = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  if p_linea is not null and p_linea not in ('alta','bassa') then
    raise exception using errcode = '22023', message = 'Linea difensiva non valida.';
  end if;
  if p_ampiezza is not null and p_ampiezza not in ('larga','stretta') then
    raise exception using errcode = '22023', message = 'Ampiezza non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  if exists (
    select 1 from public.moduli_personalizzati m
    where m.team_id = v_team_id and lower(btrim(m.nome)) = lower(v_nome)
      and m.id is distinct from p_sostituisci
  ) then
    raise exception using errcode = '23505', message = 'Hai già un modulo con questo nome.';
  end if;

  if p_sostituisci is not null then
    update public.moduli_personalizzati m
    set nome = v_nome, modulo = p_modulo, disposizione = p_disposizione, ruoli = p_ruoli,
        compiti = p_compiti, focus_corsia = p_focus_corsia, stile = p_stile,
        linea_difensiva = p_linea, ampiezza = p_ampiezza, ruolo_portiere = p_portiere, aggiornato_il = now()
    where m.id = p_sostituisci and m.team_id = v_team_id
    returning m.id into v_id;
    if v_id is null then
      raise exception using errcode = 'P0002', message = 'Il modulo da sovrascrivere non esiste.';
    end if;
    return v_id;
  end if;

  -- Il tetto si controlla sotto lock della squadra: due salvataggi insieme
  -- dallo stesso account non devono arrivare a 4.
  perform 1 from public.teams t where t.id = v_team_id for update;
  if (select count(*) from public.moduli_personalizzati m where m.team_id = v_team_id) >= 3 then
    raise exception using errcode = '23514',
      message = 'Hai già 3 moduli personalizzati: sovrascrivine uno o eliminane uno.';
  end if;

  insert into public.moduli_personalizzati
    (league_id, team_id, nome, modulo, disposizione, ruoli, compiti, focus_corsia, stile, linea_difensiva, ampiezza, ruolo_portiere)
  values
    (p_league_id, v_team_id, v_nome, p_modulo, p_disposizione, p_ruoli, p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_portiere)
  returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.salva_schemi(p_league_id bigint, p_nome_attivo text, p_riserva_nome text DEFAULT NULL::text, p_modulo text DEFAULT NULL::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_stile text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team_id bigint;
  v_std     text[];
  v_attive  boolean;
  v_nome_a  text := btrim(coalesce(p_nome_attivo, ''));
  v_nome_r  text := btrim(coalesce(p_riserva_nome, ''));
  v_i       integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per salvare gli schemi.';
  end if;

  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  select coalesce(l.tattiche_attive, false) into v_attive from public.leagues l where l.id = p_league_id;
  if not v_attive then
    raise exception using errcode = '55000', message = 'Gli schemi a due slot non sono ancora attivi in questa lega.';
  end if;

  if char_length(v_nome_a) not between 1 and 24 then
    raise exception using errcode = '22023', message = 'Il nome dello schema deve avere da 1 a 24 caratteri.';
  end if;

  if p_modulo is null then
    insert into public.schemi_squadra (team_id, league_id, nome_attivo)
    values (v_team_id, p_league_id, v_nome_a)
    on conflict (team_id) do update set
      nome_attivo = excluded.nome_attivo,
      riserva_nome = null, riserva_modulo = null, riserva_disposizione = null, riserva_ruoli = null,
      riserva_compiti = null, riserva_focus_corsia = null, riserva_stile = null, riserva_linea = null,
      riserva_ampiezza = null, riserva_portiere = null, aggiornato_il = now();
    return;
  end if;

  if char_length(v_nome_r) not between 1 and 24 then
    raise exception using errcode = '22023', message = 'Il nome dello schema riserva deve avere da 1 a 24 caratteri.';
  end if;
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  v_std := private.disposizione_standard(p_modulo);
  if v_std is null then
    raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
  end if;
  if p_disposizione is null or cardinality(p_disposizione) <> 11 then
    raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
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
  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(p_disposizione[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], p_disposizione[v_i]);
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
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;
  if p_stile is not null and not (p_stile = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  if p_linea is not null and p_linea not in ('alta','bassa') then
    raise exception using errcode = '22023', message = 'Linea difensiva non valida.';
  end if;
  if p_ampiezza is not null and p_ampiezza not in ('larga','stretta') then
    raise exception using errcode = '22023', message = 'Ampiezza non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  insert into public.schemi_squadra (
    team_id, league_id, nome_attivo, riserva_nome, riserva_modulo, riserva_disposizione, riserva_ruoli,
    riserva_compiti, riserva_focus_corsia, riserva_stile, riserva_linea, riserva_ampiezza, riserva_portiere)
  values (
    v_team_id, p_league_id, v_nome_a, v_nome_r, p_modulo, p_disposizione, p_ruoli,
    p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_portiere)
  on conflict (team_id) do update set
    nome_attivo = excluded.nome_attivo, riserva_nome = excluded.riserva_nome, riserva_modulo = excluded.riserva_modulo,
    riserva_disposizione = excluded.riserva_disposizione, riserva_ruoli = excluded.riserva_ruoli,
    riserva_compiti = excluded.riserva_compiti, riserva_focus_corsia = excluded.riserva_focus_corsia,
    riserva_stile = excluded.riserva_stile, riserva_linea = excluded.riserva_linea,
    riserva_ampiezza = excluded.riserva_ampiezza, riserva_portiere = excluded.riserva_portiere,
    aggiornato_il = now();
end;
$function$
;

notify pgrst, 'reload schema';
