-- ============================================================
--  SCHEDINA A PUNTATA (19/10/2026, deciso con il committente). Si scommette sempre con i crediti: 50, 100, 250 o 500.
--  Vincita = puntata x moltiplicatore secondo gli errori; con 6 partite: 0 errori x20, 1 x4, 2 x1,5, di piu' 0. Con piu'
--  partite la scala cresce (0 err x20*1,6^(N-6), 1 err x4*1,4^(N-6), 2 err x1,5*1,2^(N-6), 3 err x1 se N >= 8).
--  Ogni doppia dimezza il moltiplicatore. Le schedine gia' giocate gratis prima del cambio restano con la regola di
--  allora (20 per giusto, 300 la perfetta). WIN e classifica invariate. Funzioni riscritte dalla definizione viva.
-- ============================================================
begin;
alter table public.betone_schedine add column puntata integer not null default 0, add column vinto bigint;

create or replace function private.betone_moltiplicatore(p_partite integer, p_errori integer, p_doppie integer)
returns numeric language sql immutable set search_path = '' as $f$
  select round((case p_errori
      when 0 then 20 * power(1.6, greatest(0, p_partite - 6))
      when 1 then 4 * power(1.4, greatest(0, p_partite - 6))
      when 2 then 1.5 * power(1.2, greatest(0, p_partite - 6))
      when 3 then case when p_partite >= 8 then 1 else 0 end
      else 0 end) * power(0.5, greatest(0, p_doppie)), 2)
$f$;
create or replace function public.betone_moltiplicatore(p_partite integer, p_errori integer, p_doppie integer)
returns numeric language sql immutable set search_path = '' as $f$ select private.betone_moltiplicatore(p_partite, p_errori, p_doppie) $f$;
grant execute on function public.betone_moltiplicatore(integer, integer, integer) to authenticated;

drop function public.betone_salva(bigint, text, jsonb);
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
  if p_puntata is null or p_puntata not in (50, 100, 250, 500) then
    raise exception using errcode = '22023', message = 'Scegli quanto puntare: 50, 100, 250 o 500 crediti.';
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

CREATE OR REPLACE FUNCTION private.betone_risolvi()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_s record;
  v_giuste integer;
  v_puntata integer;
  v_doppie integer;
  v_vinto bigint;
  v_totale integer;
  v_n integer := 0;
begin
  for v_s in
    select s.id, s.league_id, s.user_id, s.giornata, s.gruppo
    from public.betone_schedine s
    where s.risolta_il is null
      and exists (select 1 from public.betone_pronostici p where p.schedina_id = s.id)
      and not exists (select 1 from public.betone_pronostici p
                        join public.fixtures f on f.id = p.fixture_id
                        left join public.matches m on m.fixture_id = f.id
                       where p.schedina_id = s.id and (f.stato <> 'simulata' or m.id is null))
  loop
    update public.betone_pronostici p
       set giusta = position((case when m.gol_home > m.gol_away then '1' when m.gol_home < m.gol_away then '2' else 'X' end) in p.scelta) > 0
      from public.matches m
     where p.schedina_id = v_s.id and m.fixture_id = p.fixture_id;
    select count(*) filter (where giusta), count(*) into v_giuste, v_totale from public.betone_pronostici where schedina_id = v_s.id;
    select coalesce(puntata, 0) into v_puntata from public.betone_schedine where id = v_s.id;
    select count(*) filter (where length(scelta) = 2) into v_doppie from public.betone_pronostici where schedina_id = v_s.id;
    -- Vincita = puntata x moltiplicatore (19/10/2026). Le schedine giocate gratis prima del cambio (puntata 0) valgono
    -- con la regola di allora: 20 crediti per pronostico giusto e 300 per la perfetta.
    v_vinto := case when v_puntata > 0 then round(v_puntata * private.betone_moltiplicatore(v_totale, v_totale - v_giuste, v_doppie))
                    else 20 * v_giuste + (case when v_giuste = v_totale then 300 else 0 end) end;
    update public.betone_schedine set risolta_il = now(), giuste = v_giuste, totale = v_totale, perfetta = (v_giuste = v_totale), vinto = v_vinto where id = v_s.id;
    -- Avviso neutro: dire "5 su 6" rivelerebbe i risultati di chi non ha ancora guardato la sua partita.
    -- La vincita va sul saldo del casino'.
    begin
      perform private.casino_saldo(v_s.league_id, v_s.user_id);
      update public.casino_saldi set crediti = crediti + v_vinto, aggiornato_il = now()
       where league_id = v_s.league_id and user_id = v_s.user_id;
    exception when others then null;  -- senza squadra attiva niente crediti, ma la schedina si valuta lo stesso
    end;
    perform private.notifica(v_s.user_id, v_s.league_id, 'sistema', 'BetOne',
      'La tua schedina della giornata ' || v_s.giornata || ' è stata valutata.',
      jsonb_build_object('view', 'betone'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
revoke all on function public.betone_salva(bigint, text, jsonb, integer) from public, anon;
grant execute on function public.betone_salva(bigint, text, jsonb, integer) to authenticated;
commit;
