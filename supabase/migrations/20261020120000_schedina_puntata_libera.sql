-- Schedina BetOne: la puntata e' libera, da 1 credito in su (prima solo 50/100/250/500).
CREATE OR REPLACE FUNCTION public.betone_salva(p_league_id bigint, p_gruppo text, p_pronostici jsonb, p_puntata integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_lega public.leagues;
  v_season_id bigint;
  v_giornata smallint;
  v_team_id bigint;
  v_fixture_ids bigint[];
  v_chiusura timestamptz;
  v_n integer;
  v_doppie integer;
  v_ids bigint[];
  v_schedina_id bigint;
  v_r record;
  v_saldo public.casino_saldi;
  v_vecchia integer := 0;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere per giocare la schedina.'; end if;
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or not v_lega.conferenze_stampa then raise exception using errcode = '55000', message = 'BetOne non è attivo in questa lega.'; end if;
  if v_lega.stato <> 'stagione' or v_lega.fase_carriera <> 'normale' then raise exception using errcode = '55000', message = 'La stagione non è in corso.'; end if;
  select t.id into v_team_id from public.teams t where t.league_id = p_league_id and t.user_id = v_utente and t.attiva;
  if v_team_id is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  if p_gruppo not in ('est', 'ovest', 'tutte') or (v_lega.conferenze_attive and p_gruppo = 'tutte') or (not coalesce(v_lega.conferenze_attive, false) and p_gruppo <> 'tutte') then
    raise exception using errcode = '22023', message = 'Schedina non valida per questa lega.';
  end if;

  select se.id into v_season_id from public.seasons se where se.league_id = p_league_id and se.numero = v_lega.stagione_corrente;
  select min(f.giornata) into v_giornata from public.fixtures f
   where f.season_id = v_season_id and f.stato = 'programmata' and f.bracket_tie_id is null and f.giornata <= v_lega.giornate_totali;
  if v_giornata is null then raise exception using errcode = '55000', message = 'Non ci sono giornate a cui giocare la schedina.'; end if;

  select array_agg(f.id order by f.id) into v_fixture_ids from public.fixtures f
   where f.season_id = v_season_id and f.giornata = v_giornata and f.stato = 'programmata' and f.bracket_tie_id is null
     and private.betone_gruppo(f.season_id, f.home_team_id) = p_gruppo;
  if v_fixture_ids is null then raise exception using errcode = '22023', message = 'Nessuna partita per questa schedina.'; end if;

  -- Chiusura: 15 minuti prima della prima partita della giornata.
  select min(f.data_sim) - interval '15 minutes' into v_chiusura from public.fixtures f
   where f.season_id = v_season_id and f.giornata = v_giornata and f.bracket_tie_id is null;
  if now() >= v_chiusura then raise exception using errcode = '55000', message = 'Le schedine di questa giornata sono chiuse.'; end if;

  if jsonb_typeof(p_pronostici) <> 'array' then raise exception using errcode = '22023', message = 'Pronostici non validi.'; end if;
  v_n := jsonb_array_length(p_pronostici);
  select array_agg((x->>'fixture_id')::bigint) into v_ids from jsonb_array_elements(p_pronostici) x;
  if v_n <> cardinality(v_fixture_ids) or (select count(distinct i) from unnest(v_ids) i) <> v_n
     or exists (select 1 from unnest(v_ids) i where not (i = any(v_fixture_ids))) then
    raise exception using errcode = '22023', message = 'La schedina deve avere un pronostico per ognuna delle ' || cardinality(v_fixture_ids) || ' partite.';
  end if;
  if exists (select 1 from jsonb_array_elements(p_pronostici) x where (x->>'scelta') is null or (x->>'scelta') not in ('1', 'X', '2', '1X', 'X2', '12')) then
    raise exception using errcode = '22023', message = 'Pronostico non valido: usa 1, X, 2 oppure 1X, X2, 12.';
  end if;
  select count(*) into v_doppie from jsonb_array_elements(p_pronostici) x where length(x->>'scelta') = 2;
  if v_doppie > 2 then raise exception using errcode = '22023', message = 'Hai a disposizione solo 2 doppie per schedina.'; end if;

  -- Si scommette sempre con i crediti (19/10/2026): la puntata si scala subito; cambiandola si scala o si restituisce la differenza.
  -- Puntata libera (20/10/2026): da 1 credito in su, quanto si vuole entro i crediti che si hanno.
  if p_puntata is null or p_puntata < 1 or p_puntata > 10000000 then
    raise exception using errcode = '22023', message = 'Scegli quanto puntare: almeno 1 credito.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  select coalesce(puntata, 0) into v_vecchia from public.betone_schedine
   where season_id = v_season_id and giornata = v_giornata and gruppo = p_gruppo and user_id = v_utente;
  v_vecchia := coalesce(v_vecchia, 0);
  if v_saldo.crediti < p_puntata - v_vecchia then
    raise exception using errcode = '22023', message = 'Crediti insufficienti per questa puntata.';
  end if;
  update public.casino_saldi set crediti = crediti - (p_puntata - v_vecchia), aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;

  insert into public.betone_schedine (league_id, season_id, giornata, gruppo, user_id, team_id, puntata)
  values (p_league_id, v_season_id, v_giornata, p_gruppo, v_utente, v_team_id, p_puntata)
  on conflict (season_id, giornata, gruppo, user_id) do update set aggiornata_il = now(), puntata = excluded.puntata
  returning id into v_schedina_id;
  delete from public.betone_pronostici where schedina_id = v_schedina_id;
  for v_r in select (x->>'fixture_id')::bigint as fixture_id, x->>'scelta' as scelta from jsonb_array_elements(p_pronostici) x loop
    insert into public.betone_pronostici (schedina_id, fixture_id, scelta) values (v_schedina_id, v_r.fixture_id, v_r.scelta);
  end loop;
  return jsonb_build_object('schedina_id', v_schedina_id, 'giornata', v_giornata, 'gruppo', p_gruppo, 'doppie', v_doppie, 'puntata', p_puntata,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
