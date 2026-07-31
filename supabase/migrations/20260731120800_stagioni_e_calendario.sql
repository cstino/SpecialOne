-- ============================================================
--  STAGIONI E CALENDARIO  (design §3.1, §11; decisioni §7)
-- ============================================================

-- `partite_totali` era corretto come numero di partite per squadra, ma non
-- come durata per N dispari: il metodo del cerchio aggiunge un riposo e usa
-- N giornate per girone. Separiamo quindi le due grandezze.
alter table public.leagues
  rename column partite_totali to partite_per_squadra;

alter table public.leagues
  add column giornate_totali smallint
    generated always as (
      (n_squadre - 1 + (n_squadre % 2)) * n_gironi
    ) stored;

comment on column public.leagues.partite_per_squadra is
  'Partite giocate da ogni squadra: (N-1)*G.';
comment on column public.leagues.giornate_totali is
  'Durata reale: (N-1)*G con N pari, N*G con N dispari per i turni di riposo.';

-- Le chiavi composte permettono alle tabelle figlie di garantire che tutti
-- gli oggetti appartengano alla stessa lega, non solo che gli id esistano.
alter table public.teams
  add constraint teams_id_league_unique unique (id, league_id);

alter table public.player_instances
  add constraint player_instances_id_league_unique unique (id, league_id);

create table public.seasons (
  id            bigint generated always as identity primary key,
  league_id     bigint not null references public.leagues (id) on delete cascade,
  numero        smallint not null check (numero >= 1),
  stato         text not null default 'preparazione'
                check (stato in ('preparazione','in_corso','conclusa')),
  data_inizio   date,
  data_fine     date,
  creata_il     timestamptz not null default now(),

  constraint seasons_date_coerenti check (
    data_fine is null or data_inizio is null or data_fine >= data_inizio
  ),
  unique (league_id, numero),
  unique (id, league_id)
);

create index seasons_league_idx on public.seasons (league_id);

create table public.fixtures (
  id             bigint generated always as identity primary key,
  season_id      bigint not null,
  league_id      bigint not null,
  giornata       smallint not null check (giornata >= 1),
  home_team_id   bigint not null,
  away_team_id   bigint not null,
  data_sim       timestamptz not null,
  stato          text not null default 'programmata'
                 check (stato in ('programmata','in_corso','simulata','annullata')),
  creata_il      timestamptz not null default now(),

  constraint fixtures_squadre_diverse check (home_team_id <> away_team_id),
  constraint fixtures_season_league_fk
    foreign key (season_id, league_id)
    references public.seasons (id, league_id) on delete cascade,
  constraint fixtures_home_league_fk
    foreign key (home_team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  constraint fixtures_away_league_fk
    foreign key (away_team_id, league_id)
    references public.teams (id, league_id) on delete cascade,

  unique (season_id, giornata, home_team_id),
  unique (season_id, giornata, away_team_id),
  unique (id, league_id)
);

create index fixtures_league_idx on public.fixtures (league_id);
create index fixtures_season_giornata_idx
  on public.fixtures (season_id, giornata);
create index fixtures_home_idx on public.fixtures (home_team_id);
create index fixtures_away_idx on public.fixtures (away_team_id);
create index fixtures_da_simulare_idx
  on public.fixtures (data_sim, id)
  where stato = 'programmata';

-- Le due UNIQUE separate non intercettano il caso in cui la stessa squadra
-- sia casa in una partita e ospite in un'altra nella medesima giornata.
create or replace function private.verifica_fixture_unica()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.fixtures f
    where f.season_id = new.season_id
      and f.giornata = new.giornata
      and f.id <> coalesce(new.id, -1)
      and (
        f.home_team_id in (new.home_team_id, new.away_team_id)
        or f.away_team_id in (new.home_team_id, new.away_team_id)
      )
  ) then
    raise exception 'Una squadra non puo giocare due volte nella stessa giornata';
  end if;
  return new;
end;
$$;

revoke all on function private.verifica_fixture_unica() from public, anon, authenticated;

create trigger fixtures_squadra_unica
  before insert or update of season_id, giornata, home_team_id, away_team_id
  on public.fixtures
  for each row execute function private.verifica_fixture_unica();

alter table public.seasons  enable row level security;
alter table public.fixtures enable row level security;

comment on table public.fixtures is
  'Calendario: un solo turno al giorno, data_sim calcolata esplicitamente in Europe/Rome.';
