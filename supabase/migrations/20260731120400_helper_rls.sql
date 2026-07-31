-- ============================================================
--  FUNZIONI DI SUPPORTO A RLS  +  policy su leghe e squadre
--
--  Tutte SECURITY DEFINER: devono poter leggere `teams` scavalcando la RLS
--  di `teams`, altrimenti una policy su teams che interroga teams entra in
--  ricorsione infinita. E' la trappola classica di RLS su Supabase.
--
--  Tutte con `set search_path = ''` e riferimenti pienamente qualificati:
--  senza, chi chiama puo' dirottare la risoluzione dei nomi.
--
--  Tutte controllano `auth.uid()` al loro interno: una SECURITY DEFINER che
--  si fida del parametro che riceve e' una escalation di privilegi.
-- ============================================================

-- La squadra dell'utente corrente in una lega (null se non partecipa).
create or replace function private.mia_squadra(p_league_id bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select t.id
  from public.teams t
  where t.league_id = p_league_id
    and t.user_id = (select auth.uid())
  limit 1;
$$;

-- L'utente corrente partecipa a questa lega? (o ne e' l'admin)
create or replace function private.e_membro(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.teams t
    where t.league_id = p_league_id
      and t.user_id = (select auth.uid())
  ) or exists (
    select 1 from public.leagues l
    where l.id = p_league_id
      and l.admin_id = (select auth.uid())
  );
$$;

-- Questa squadra e' dell'utente corrente?
create or replace function private.e_mia_squadra(p_team_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.teams t
    where t.id = p_team_id
      and t.user_id = (select auth.uid())
  );
$$;

-- L'utente corrente e' membro della lega a cui appartiene questa squadra?
create or replace function private.e_membro_di_team(p_team_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teams t
    join public.teams mie on mie.league_id = t.league_id
    where t.id = p_team_id
      and mie.user_id = (select auth.uid())
  );
$$;

-- Le funzioni servono dentro le policy, quindi `authenticated` deve poterle
-- eseguire: le espressioni di una policy girano con i privilegi di chi
-- interroga, non del proprietario della tabella. Revocarle a `authenticated`
-- romperebbe ogni policy che le usa.
-- Non sono comunque raggiungibili via API: PostgREST espone solo `public`.
revoke all on function private.mia_squadra(bigint)        from public, anon;
revoke all on function private.e_membro(bigint)           from public, anon;
revoke all on function private.e_mia_squadra(bigint)      from public, anon;
revoke all on function private.e_membro_di_team(bigint)   from public, anon;

grant execute on function private.mia_squadra(bigint)      to authenticated, service_role;
grant execute on function private.e_membro(bigint)         to authenticated, service_role;
grant execute on function private.e_mia_squadra(bigint)    to authenticated, service_role;
grant execute on function private.e_membro_di_team(bigint) to authenticated, service_role;

-- ============================================================
--  POLICY: leghe
-- ============================================================

-- Si vede solo la lega a cui si partecipa.
-- NOTA: entrare con un codice invito NON passa da qui. Cercare una lega per
-- codice richiederebbe di renderle tutte leggibili, e a quel punto il codice
-- si trova per tentativi. L'ingresso sara' una RPC SECURITY DEFINER che
-- accetta il codice e restituisce solo l'esito (task 3).
create policy leagues_lettura on leagues
  for select
  to authenticated
  using ((select private.e_membro(id)));

-- ============================================================
--  POLICY: squadre
-- ============================================================

-- Le squadre della propria lega sono tutte visibili: servono per la
-- classifica, il calendario e per guardare le rose degli avversari.
-- Non c'e' niente di riservato in una squadra: il segreto e' la formazione.
create policy teams_lettura on teams
  for select
  to authenticated
  using ((select private.e_membro(league_id)));

-- ============================================================
--  NESSUNA POLICY DI SCRITTURA, QUI E NEL RESTO DELLO SCHEMA
--
--  Con RLS attiva e nessuna policy per INSERT/UPDATE/DELETE, ogni scrittura
--  da parte di un client autenticato viene rifiutata dal database.
--  Si scrive solo attraverso funzioni SECURITY DEFINER che validano prima,
--  e che arrivano coi rispettivi task: entrare in lega e registrare la
--  squadra (task 3), pick del draft (task 4), salvataggio formazione
--  (task 5, con le verifiche elencate in decisioni-fase1 §1).
--
--  La simulazione notturna gira con la service_role, che scavalca RLS per
--  progetto. Quella chiave non deve MAI raggiungere il browser: sta solo
--  nelle variabili d'ambiente della Edge Function.
-- ============================================================
