-- Stile "Personalizzato", velocita' di manovra, "Entrambe le fasce".
--
--  * Sotto uno stile preimpostato linea, ampiezza, velocita' e dove si attacca
--    sono bloccate (valgono solo quelle dello stile). Con 'personalizzato' si
--    sbloccano. Il blocco e' applicato dal motore (simula-giornata): qui si
--    accettano e si conservano i valori; l'app li azzera scegliendo uno stile
--    preimpostato e parte da quelli dello stile passando a Personalizzato.
--  * Nuova leva: velocita_manovra (ragionata | veloce; NULL = normale).
--  * Dove si attacca: nuovo valore FASCE (entrambe le fasce).
--  * Le formazioni, i moduli e gli schemi riserva che avevano indicazioni di
--    squadra sopra uno stile passano a 'personalizzato': prima valevano stile +
--    indicazioni, ora le indicazioni restano attive.
--  * Familiarita' con le indicazioni: 28 elementi (si aggiunge la velocita').
--  Funzioni ricostruite dalla definizione live (pg_get_functiondef).

alter table public.lineups add column if not exists velocita_manovra text;
alter table public.moduli_personalizzati add column if not exists velocita_manovra text;
alter table public.schemi_squadra add column if not exists riserva_velocita text;
alter table public.indicazioni_xp add column if not exists velocita_manovra text;

alter table public.lineups drop constraint if exists lineups_velocita_manovra_check;
alter table public.lineups add constraint lineups_velocita_manovra_check check (velocita_manovra is null or velocita_manovra in ('ragionata','veloce'));
alter table public.moduli_personalizzati drop constraint if exists moduli_personalizzati_velocita_manovra_check;
alter table public.moduli_personalizzati add constraint moduli_personalizzati_velocita_manovra_check check (velocita_manovra is null or velocita_manovra in ('ragionata','veloce'));
alter table public.schemi_squadra drop constraint if exists schemi_squadra_riserva_velocita_check;
alter table public.schemi_squadra add constraint schemi_squadra_riserva_velocita_check check (riserva_velocita is null or riserva_velocita in ('ragionata','veloce'));

alter table public.lineups drop constraint lineups_focus_corsia_check;
alter table public.lineups add constraint lineups_focus_corsia_check check (focus_corsia is null or focus_corsia in ('SX','CEN','DX','FASCE'));
alter table public.moduli_personalizzati drop constraint moduli_personalizzati_focus_corsia_check;
alter table public.moduli_personalizzati add constraint moduli_personalizzati_focus_corsia_check check (focus_corsia is null or focus_corsia in ('SX','CEN','DX','FASCE'));
alter table public.schemi_squadra drop constraint schemi_squadra_riserva_focus_corsia_check;
alter table public.schemi_squadra add constraint schemi_squadra_riserva_focus_corsia_check check (riserva_focus_corsia is null or riserva_focus_corsia in ('SX','CEN','DX','FASCE'));

create or replace function private.stili_validi()
 returns text[]
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  select array[
    'equilibrato', 'contropiede', 'possesso_palla', 'fasce',
    'recupero_veloce', 'diretto', 'blocco_basso', 'personalizzato'
  ]::text[];
$function$;

-- Chi aveva indicazioni sopra uno stile passa a Personalizzato.
update public.lineups set stile_gioco = 'personalizzato'
 where stile_gioco <> 'personalizzato' and (linea_difensiva is not null or ampiezza is not null or focus_corsia is not null);
update public.moduli_personalizzati set stile = 'personalizzato'
 where stile is not null and stile <> 'personalizzato' and (linea_difensiva is not null or ampiezza is not null or focus_corsia is not null);
update public.schemi_squadra set riserva_stile = 'personalizzato'
 where riserva_stile is not null and riserva_stile <> 'personalizzato' and (riserva_linea is not null or riserva_ampiezza is not null or riserva_focus_corsia is not null);

drop function public.salva_formazione(bigint,smallint,text,bigint[],bigint[],bigint[],text,text[],text[],text[],text,text,text,text);
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

drop function public.salva_modulo_personalizzato(bigint,text,text,text[],text[],text[],text,bigint,text,text,text,text);
CREATE OR REPLACE FUNCTION public.salva_modulo_personalizzato(p_league_id bigint, p_nome text, p_modulo text, p_disposizione text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_sostituisci bigint DEFAULT NULL::bigint, p_stile text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text, p_velocita text DEFAULT NULL::text)
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

  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX','FASCE') then
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
  if p_velocita is not null and p_velocita not in ('ragionata','veloce') then
    raise exception using errcode = '22023', message = 'Velocita'' di manovra non valida.';
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
        linea_difensiva = p_linea, ampiezza = p_ampiezza, velocita_manovra = p_velocita, ruolo_portiere = p_portiere, aggiornato_il = now()
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
    (league_id, team_id, nome, modulo, disposizione, ruoli, compiti, focus_corsia, stile, linea_difensiva, ampiezza, velocita_manovra, ruolo_portiere)
  values
    (p_league_id, v_team_id, v_nome, p_modulo, p_disposizione, p_ruoli, p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_velocita, p_portiere)
  returning id into v_id;
  return v_id;
end;
$function$;

drop function public.salva_schemi(bigint,text,text,text,text[],text[],text[],text,text,text,text,text);
CREATE OR REPLACE FUNCTION public.salva_schemi(p_league_id bigint, p_nome_attivo text, p_riserva_nome text DEFAULT NULL::text, p_modulo text DEFAULT NULL::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_stile text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text, p_velocita text DEFAULT NULL::text)
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
      riserva_ampiezza = null, riserva_velocita = null, riserva_portiere = null, aggiornato_il = now();
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
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX','FASCE') then
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
  if p_velocita is not null and p_velocita not in ('ragionata','veloce') then
    raise exception using errcode = '22023', message = 'Velocita'' di manovra non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  insert into public.schemi_squadra (
    team_id, league_id, nome_attivo, riserva_nome, riserva_modulo, riserva_disposizione, riserva_ruoli,
    riserva_compiti, riserva_focus_corsia, riserva_stile, riserva_linea, riserva_ampiezza, riserva_velocita, riserva_portiere)
  values (
    v_team_id, p_league_id, v_nome_a, v_nome_r, p_modulo, p_disposizione, p_ruoli,
    p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_velocita, p_portiere)
  on conflict (team_id) do update set
    nome_attivo = excluded.nome_attivo, riserva_nome = excluded.riserva_nome, riserva_modulo = excluded.riserva_modulo,
    riserva_disposizione = excluded.riserva_disposizione, riserva_ruoli = excluded.riserva_ruoli,
    riserva_compiti = excluded.riserva_compiti, riserva_focus_corsia = excluded.riserva_focus_corsia,
    riserva_stile = excluded.riserva_stile, riserva_linea = excluded.riserva_linea,
    riserva_ampiezza = excluded.riserva_ampiezza, riserva_velocita = excluded.riserva_velocita, riserva_portiere = excluded.riserva_portiere,
    aggiornato_il = now();
end;
$function$;

CREATE OR REPLACE FUNCTION private.avanza_familiarita(p_team_id bigint, p_league_id bigint, p_modulo text, p_stile text, p_giornata smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_disp      text[];
  v_ruoli     text[];
  v_compiti   text[];
  v_semina    smallint;
  v_prec      public.indicazioni_xp;
  v_distanza  numeric;
  v_diversi   integer;
  v_focus     text;
  v_linea     text;
  v_ampiezza  text;
  v_velocita  text;
  v_portiere  text;
begin
  select coalesce(l.disposizione, private.disposizione_standard(p_modulo)), l.ruoli, l.compiti, l.focus_corsia,
         l.linea_difensiva, l.ampiezza, l.ruolo_portiere, l.velocita_manovra
  into v_disp, v_ruoli, v_compiti, v_focus, v_linea, v_ampiezza, v_portiere, v_velocita
  from public.lineups l
  where l.team_id = p_team_id and l.giornata = p_giornata;

  if v_disp is null then
    v_disp := private.disposizione_standard(p_modulo);
  end if;
  if v_disp is null then
    return; -- modulo sconosciuto: non si inventa una barra
  end if;

  -- ----- barra DISPOSIZIONE -----
  -- Se questo schieramento non e' mai stato giocato, eredita dal piu' simile.
  if not exists (
    select 1 from public.formation_xp
    where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp
  ) then
    -- Si eredita dalla QUOTA, non dal conteggio grezzo. Il contatore cresce
    -- senza limite — una squadra puo' avere 21 partite col suo 4-4-2 — e
    -- moltiplicare quello per 0,71 darebbe ancora 15, cioe' una barra piena:
    -- l'eredita' non morderebbe mai per chi gioca da tempo lo stesso modulo,
    -- che e' esattamente chi dovrebbe sentirla.
    select coalesce(max(round(
             least(1.0, fx.partite_giocate::numeric / private.fam_partite_piena())
             * private.resa_familiarita(1 - private.similarita_disposizione(fx.disposizione, v_disp))
             * private.fam_partite_piena()
           )), 0)
    into v_semina
    from public.formation_xp fx
    where fx.team_id = p_team_id;

    insert into public.formation_xp (team_id, league_id, modulo, disposizione, partite_giocate)
    values (p_team_id, p_league_id, p_modulo, v_disp, greatest(0, coalesce(v_semina, 0)))
    on conflict (team_id, modulo, disposizione) do nothing;
  end if;

  update public.formation_xp
  set partite_giocate = partite_giocate + 1, aggiornata_il = now()
  where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp;

  -- Modulo secondario (season 2): anche lui accumula una partita, anche se non
  -- e' stato schierato. Prima delle indicazioni: la barra indicazioni ha un
  -- return anticipato alla prima riga e non deve saltarlo.
  perform private.avanza_secondario(p_team_id, p_league_id, p_modulo, v_disp);

  -- ----- barra INDICAZIONI -----
  select * into v_prec from public.indicazioni_xp where team_id = p_team_id;

  if not found then
    -- Prima riga per questa squadra. NON parte da zero: la barra indicazioni
    -- assorbe quello che prima era la familiarita' con lo STILE, e azzerarla
    -- qui vorrebbe dire che alla prima giornata dopo questa migrazione ogni
    -- squadra della lega perde meta' della sua familiarita' senza aver
    -- cambiato niente.
    insert into public.indicazioni_xp (team_id, league_id, partite_giocate, stile, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere, velocita_manovra)
    values (
      p_team_id, p_league_id,
      least(private.fam_partite_piena(),
            coalesce((select sx.partite_giocate from public.stile_xp sx
                      where sx.team_id = p_team_id and sx.stile = p_stile), 0))::smallint + 1,
      p_stile, v_ruoli, v_compiti, v_focus, v_linea, v_ampiezza, v_portiere, v_velocita);
    return;
  end if;

  -- Distanza su 23 elementi: lo stile, gli undici ruoli, gli undici compiti.
  -- Un elemento assente da entrambe le parti non e' un cambiamento.
  v_diversi := (case when coalesce(v_prec.stile, '') <> coalesce(p_stile, '') then 1 else 0 end)
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.ruoli[i], '') <> coalesce(v_ruoli[i], ''))
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.compiti[i], '') <> coalesce(v_compiti[i], ''))
    -- Ventiquattresimo elemento: dove si attacca. E' un'indicazione come le
    -- altre, quindi cambiarla costa familiarita' come cambiare un compito.
    + (case when coalesce(v_prec.focus_corsia, '') <> coalesce(v_focus, '') then 1 else 0 end)
    -- Dal 29 settembre 2026 anche linea, ampiezza e portiere (registro,
    -- punto 30): ventisette elementi.
    + (case when coalesce(v_prec.linea_difensiva, '') <> coalesce(v_linea, '') then 1 else 0 end)
    + (case when coalesce(v_prec.ampiezza, '') <> coalesce(v_ampiezza, '') then 1 else 0 end)
    + (case when coalesce(v_prec.ruolo_portiere, '') <> coalesce(v_portiere, '') then 1 else 0 end)
    -- Dal 6 ottobre 2026 anche la velocita' di manovra: ventotto elementi.
    + (case when coalesce(v_prec.velocita_manovra, '') <> coalesce(v_velocita, '') then 1 else 0 end);
  v_distanza := v_diversi::numeric / 28;

  -- Stessa cura dell'eredita': si arretra la quota, non il conteggio grezzo.
  update public.indicazioni_xp
  set partite_giocate = least(32767, greatest(0,
        round(least(1.0, partite_giocate::numeric / private.fam_partite_piena())
              * private.resa_familiarita(v_distanza)
              * private.fam_partite_piena())::smallint + 1)),
      stile = p_stile, ruoli = v_ruoli, compiti = v_compiti, focus_corsia = v_focus,
      linea_difensiva = v_linea, ampiezza = v_ampiezza, ruolo_portiere = v_portiere, velocita_manovra = v_velocita, aggiornata_il = now()
  where team_id = p_team_id;
end;
$function$;

revoke all on function public.salva_formazione(bigint, smallint, text, bigint[], bigint[], bigint[], text, text[], text[], text[], text, text, text, text, text) from public, anon;
grant execute on function public.salva_formazione(bigint, smallint, text, bigint[], bigint[], bigint[], text, text[], text[], text[], text, text, text, text, text) to authenticated, service_role;
revoke all on function public.salva_modulo_personalizzato(bigint, text, text, text[], text[], text[], text, bigint, text, text, text, text, text) from public, anon;
grant execute on function public.salva_modulo_personalizzato(bigint, text, text, text[], text[], text[], text, bigint, text, text, text, text, text) to authenticated, service_role;
revoke all on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text, text) from public, anon;
grant execute on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text, text) to authenticated, service_role;
