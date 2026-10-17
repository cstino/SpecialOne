-- ============================================================
--  Storico del pubblico (docs/decisioni-conferenze-stampa.md §2b): ogni volta che teams.pubblico cambia
--  si registra una riga, cosi' la pagina Pubblico puo' disegnare l'andamento della propria squadra.
--  Un trigger sulla colonna prende tutte le cause (conferenze, risultati, rivalita', scontri accesi) senza
--  toccare le funzioni che lo muovono. "giornata" = ultima giornata di campionato gia' simulata nella
--  stagione corrente (0 prima della prima). Ognuno legge solo lo storico della propria squadra.
-- ============================================================

begin;

create table public.pubblico_storico (
  id        bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id   bigint not null references public.teams(id) on delete cascade,
  stagione  smallint not null,
  giornata  smallint not null default 0,
  prima     numeric(4,1) not null,
  valore    numeric(4,1) not null,
  creato_il timestamptz not null default now()
);
create index pubblico_storico_team_idx on public.pubblico_storico (team_id, stagione, id);

alter table public.pubblico_storico enable row level security;
create policy pubblico_storico_mio on public.pubblico_storico
  for select to authenticated
  using (exists (select 1 from public.teams t where t.id = team_id and t.user_id = (select auth.uid())));

create or replace function private.registra_pubblico_storico()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare
  v_stagione smallint;
  v_giornata smallint;
begin
  select l.stagione_corrente into v_stagione from public.leagues l where l.id = new.league_id;
  if v_stagione is null then return new; end if;
  select coalesce(max(f.giornata), 0) into v_giornata
    from public.fixtures f join public.seasons s on s.id = f.season_id
   where s.league_id = new.league_id and s.numero = v_stagione and f.stato = 'simulata' and f.bracket_tie_id is null;
  insert into public.pubblico_storico (league_id, team_id, stagione, giornata, prima, valore)
  values (new.league_id, new.id, v_stagione, v_giornata, old.pubblico, new.pubblico);
  return new;
end $f$;

create trigger teams_pubblico_storico
  after update of pubblico on public.teams
  for each row when (old.pubblico is distinct from new.pubblico)
  execute function private.registra_pubblico_storico();

commit;
