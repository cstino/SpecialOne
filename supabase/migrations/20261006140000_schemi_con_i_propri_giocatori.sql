-- Ogni schema ha i suoi giocatori: la riserva conserva la propria distinta (titolari, panchina, tribuna)
-- oltre a modulo, ruoli e indicazioni. Prima i giocatori erano uno solo e passando da uno schema all'altro
-- si ritrovavano quelli dell'ultimo salvato. Funzione ricostruita dalla definizione live.

alter table public.schemi_squadra
  add column if not exists riserva_titolari bigint[],
  add column if not exists riserva_panchina bigint[],
  add column if not exists riserva_tribuna bigint[];

drop function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.salva_schemi(p_league_id bigint, p_nome_attivo text, p_riserva_nome text DEFAULT NULL::text, p_modulo text DEFAULT NULL::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_stile text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text, p_velocita text DEFAULT NULL::text, p_riserva_titolari bigint[] DEFAULT NULL::bigint[], p_riserva_panchina bigint[] DEFAULT NULL::bigint[], p_riserva_tribuna bigint[] DEFAULT NULL::bigint[])
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
      riserva_ampiezza = null, riserva_velocita = null, riserva_portiere = null,
      riserva_titolari = null, riserva_panchina = null, riserva_tribuna = null, aggiornato_il = now();
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
  -- La distinta della riserva (titolari, panchina, tribuna): ogni schema ha i suoi giocatori. Gli undici
  -- posti possono avere 0 (vuoto); tutti gli altri id devono essere della rosa di questa squadra.
  if p_riserva_titolari is not null then
    if cardinality(p_riserva_titolari) <> 11 then
      raise exception using errcode = '22023', message = 'La distinta della riserva deve avere undici posti.';
    end if;
    if exists (
      select 1 from unnest(p_riserva_titolari || coalesce(p_riserva_panchina, '{}'::bigint[]) || coalesce(p_riserva_tribuna, '{}'::bigint[])) as x(id)
      where x.id is null or (x.id <> 0 and not exists (
        select 1 from public.player_instances pi where pi.id = x.id and pi.team_id = v_team_id and pi.league_id = p_league_id))
    ) then
      raise exception using errcode = '42501', message = 'La distinta della riserva contiene un giocatore fuori dalla tua rosa.';
    end if;
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  insert into public.schemi_squadra (
    team_id, league_id, nome_attivo, riserva_nome, riserva_modulo, riserva_disposizione, riserva_ruoli,
    riserva_compiti, riserva_focus_corsia, riserva_stile, riserva_linea, riserva_ampiezza, riserva_velocita, riserva_portiere,
    riserva_titolari, riserva_panchina, riserva_tribuna)
  values (
    v_team_id, p_league_id, v_nome_a, v_nome_r, p_modulo, p_disposizione, p_ruoli,
    p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_velocita, p_portiere,
    p_riserva_titolari, p_riserva_panchina, p_riserva_tribuna)
  on conflict (team_id) do update set
    nome_attivo = excluded.nome_attivo, riserva_nome = excluded.riserva_nome, riserva_modulo = excluded.riserva_modulo,
    riserva_disposizione = excluded.riserva_disposizione, riserva_ruoli = excluded.riserva_ruoli,
    riserva_compiti = excluded.riserva_compiti, riserva_focus_corsia = excluded.riserva_focus_corsia,
    riserva_stile = excluded.riserva_stile, riserva_linea = excluded.riserva_linea,
    riserva_ampiezza = excluded.riserva_ampiezza, riserva_velocita = excluded.riserva_velocita, riserva_portiere = excluded.riserva_portiere,
    riserva_titolari = excluded.riserva_titolari, riserva_panchina = excluded.riserva_panchina, riserva_tribuna = excluded.riserva_tribuna,
    aggiornato_il = now();
end;
$function$;

revoke all on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text, text, bigint[], bigint[], bigint[]) from public, anon;
grant execute on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text, text, bigint[], bigint[], bigint[]) to authenticated, service_role;
