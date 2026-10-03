-- ============================================================
--  ALBO D'ORO: RIVELAZIONE A SCOPERTA, UNA VOLTA PER UTENTE E STAGIONE
--
--  A mezzanotte (Europe/Rome) dopo l'ultima partita di una stagione l'app
--  presenta il campione del Title Playoff e i premi individuali con una
--  rivelazione a scoperta. Si vede una sola volta: quando la presentazione
--  finisce (o viene saltata) il client scrive qui il "visto".
--
--  private.albo_rivelazione_pendente() restituisce la stagione da rivelare a
--  questo utente, oppure null. Una stagione e' rivelabile se:
--    - e' conclusa;
--    - e' passata la mezzanotte di Roma successiva alla sua ultima partita;
--    - l'ultima partita e' di meno di 4 giorni fa (le stagioni vecchie non
--      si riproiettano a chi non le ha mai viste: restano nell'albo);
--    - l'utente non l'ha ancora vista.
--  Si guarda solo la stagione conclusa piu' recente.
-- ============================================================

create table if not exists public.albo_rivelazioni (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  season_id bigint not null references public.seasons(id) on delete cascade,
  visto_il timestamptz not null default now(),
  primary key (user_id, season_id)
);

alter table public.albo_rivelazioni enable row level security;

grant select, insert on public.albo_rivelazioni to authenticated;
grant all on public.albo_rivelazioni to service_role;

create policy albo_rivelazioni_lettura_propri on public.albo_rivelazioni
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy albo_rivelazioni_inserimento_proprio on public.albo_rivelazioni
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.seasons s
      where s.id = season_id and (select private.e_membro(s.league_id))
    )
  );

create or replace function public.albo_rivelazione_pendente(p_league_id bigint)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_stagione public.seasons;
  v_ultima timestamptz;
  v_apertura timestamptz;
begin
  if not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  select * into v_stagione
  from public.seasons s
  where s.league_id = p_league_id and s.stato = 'conclusa'
  order by s.numero desc
  limit 1;
  if not found then return null; end if;

  select max(m.simulata_il) into v_ultima
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  where f.season_id = v_stagione.id;
  if v_ultima is null or v_ultima < now() - interval '4 days' then return null; end if;

  -- Mezzanotte di Roma del giorno dopo l'ultima partita.
  v_apertura := (date_trunc('day', v_ultima at time zone 'Europe/Rome') + interval '1 day') at time zone 'Europe/Rome';
  if clock_timestamp() < v_apertura then return null; end if;

  if exists (
    select 1 from public.albo_rivelazioni r
    where r.user_id = (select auth.uid()) and r.season_id = v_stagione.id
  ) then return null; end if;

  return v_stagione.id;
end;
$$;

revoke all on function public.albo_rivelazione_pendente(bigint) from public, anon;
grant execute on function public.albo_rivelazione_pendente(bigint) to authenticated;
