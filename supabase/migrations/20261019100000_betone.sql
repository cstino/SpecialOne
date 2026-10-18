-- ============================================================
--  BETONE (menu Extra campo, 18/10/2026, deciso con il committente): la schedina stile totocalcio della giornata
--  a venire. Per ogni partita 1, X o 2; solo 2 doppie chance per schedina (1X, X2 o 12). Una schedina per conferenza
--  (East e West in Serie F), una sola nelle leghe senza conferenze. Si chiude 15 minuti prima della simulazione.
--  Le schedine altrui restano nascoste finche' non sono valutate. Schedina PERFETTA = una WIN; classifica per
--  numero di win e, a parita', per totale di partite azzeccate. Nessun premio economico. Solo leghe con le novita'
--  (leagues.conferenze_stampa). Si valuta da sola dopo la simulazione (cron), senza toccare la funzione che gioca.
-- ============================================================

begin;

create table public.betone_schedine (
  id           bigint generated always as identity primary key,
  league_id    bigint not null references public.leagues(id) on delete cascade,
  season_id    bigint not null references public.seasons(id) on delete cascade,
  giornata     smallint not null,
  gruppo       text not null check (gruppo in ('est', 'ovest', 'tutte')),
  user_id      uuid not null references auth.users(id) on delete cascade,
  team_id      bigint not null references public.teams(id) on delete cascade,
  creata_il    timestamptz not null default now(),
  aggiornata_il timestamptz not null default now(),
  risolta_il   timestamptz,
  giuste       smallint,
  totale       smallint,
  perfetta     boolean,
  unique (season_id, giornata, gruppo, user_id)
);
create index betone_schedine_lega_idx on public.betone_schedine (league_id, season_id, giornata);

create table public.betone_pronostici (
  schedina_id bigint not null references public.betone_schedine(id) on delete cascade,
  fixture_id  bigint not null references public.fixtures(id) on delete cascade,
  scelta      text not null check (scelta in ('1', 'X', '2', '1X', 'X2', '12')),
  giusta      boolean,
  primary key (schedina_id, fixture_id)
);

alter table public.betone_schedine enable row level security;
alter table public.betone_pronostici enable row level security;

-- Le proprie sempre; quelle degli altri solo a schedina valutata (e solo ai membri della lega).
create policy betone_schedine_lettura on public.betone_schedine
  for select to authenticated
  using (user_id = (select auth.uid()) or (risolta_il is not null and (select private.e_membro(league_id))));
create policy betone_pronostici_lettura on public.betone_pronostici
  for select to authenticated
  using (exists (select 1 from public.betone_schedine s where s.id = schedina_id
                  and (s.user_id = (select auth.uid()) or (s.risolta_il is not null and (select private.e_membro(s.league_id))))));
grant select on public.betone_schedine, public.betone_pronostici to authenticated;
grant all on public.betone_schedine, public.betone_pronostici to service_role;

-- Il gruppo di una partita: la conferenza della squadra di casa, oppure 'tutte' nelle leghe senza conferenze.
create or replace function private.betone_gruppo(p_season_id bigint, p_home_team_id bigint)
returns text language sql stable security definer set search_path = '' as $f$
  select coalesce((select st.conferenza from public.standings st where st.season_id = p_season_id and st.team_id = p_home_team_id), 'tutte')
$f$;

-- Salva (o aggiorna) la schedina dell'utente per la prossima giornata di campionato.
-- p_pronostici: [{"fixture_id": 123, "scelta": "1X"}, ...] per TUTTE le partite del gruppo.
create or replace function public.betone_salva(p_league_id bigint, p_gruppo text, p_pronostici jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
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

  insert into public.betone_schedine (league_id, season_id, giornata, gruppo, user_id, team_id)
  values (p_league_id, v_season_id, v_giornata, p_gruppo, v_utente, v_team_id)
  on conflict (season_id, giornata, gruppo, user_id) do update set aggiornata_il = now()
  returning id into v_schedina_id;
  delete from public.betone_pronostici where schedina_id = v_schedina_id;
  for v_r in select (x->>'fixture_id')::bigint as fixture_id, x->>'scelta' as scelta from jsonb_array_elements(p_pronostici) x loop
    insert into public.betone_pronostici (schedina_id, fixture_id, scelta) values (v_schedina_id, v_r.fixture_id, v_r.scelta);
  end loop;
  return jsonb_build_object('schedina_id', v_schedina_id, 'giornata', v_giornata, 'gruppo', p_gruppo, 'doppie', v_doppie);
end $f$;
revoke all on function public.betone_salva(bigint, text, jsonb) from public, anon;
grant execute on function public.betone_salva(bigint, text, jsonb) to authenticated;

-- Valuta le schedine le cui partite sono tutte simulate. 90' di campionato: 1 casa, X pari, 2 ospite.
create or replace function private.betone_risolvi()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_s record;
  v_giuste integer;
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
    update public.betone_schedine set risolta_il = now(), giuste = v_giuste, totale = v_totale, perfetta = (v_giuste = v_totale) where id = v_s.id;
    -- Avviso neutro: dire "5 su 6" rivelerebbe i risultati di chi non ha ancora guardato la sua partita.
    perform private.notifica(v_s.user_id, v_s.league_id, 'sistema', 'BetOne',
      'La tua schedina della giornata ' || v_s.giornata || ' è stata valutata.',
      jsonb_build_object('view', 'betone'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $f$;

-- Classifica di stagione: win (schedine perfette), poi partite azzeccate. Solo schedine valutate (nessuna fuga di informazioni).
create or replace function public.betone_classifica(p_league_id bigint, p_gruppo text default null)
returns table (team_id bigint, wins integer, giuste integer, totale integer, schedine integer)
language sql stable security definer set search_path = '' as $f$
  select s.team_id,
         count(*) filter (where s.perfetta)::integer,
         coalesce(sum(s.giuste), 0)::integer,
         coalesce(sum(s.totale), 0)::integer,
         count(*)::integer
  from public.betone_schedine s
  join public.leagues l on l.id = s.league_id
  join public.seasons se on se.id = s.season_id and se.numero = l.stagione_corrente
  where s.league_id = p_league_id and s.risolta_il is not null
    and (select private.e_membro(p_league_id))
    and (p_gruppo is null or s.gruppo = p_gruppo)
  group by s.team_id
  order by 2 desc, 3 desc, 1
$f$;
revoke all on function public.betone_classifica(bigint, text) from public, anon;
grant execute on function public.betone_classifica(bigint, text) to authenticated;

select cron.schedule('betone-risolvi', '* * * * *', 'select private.betone_risolvi();');

commit;
