-- ============================================================
--  RISULTATI, CLASSIFICA E REGISTRO ECONOMICO  (design §7, §10, §11)
-- ============================================================

create table public.matches (
  id             bigint generated always as identity primary key,
  fixture_id     bigint not null unique,
  league_id      bigint not null,
  gol_home       smallint not null check (gol_home >= 0),
  gol_away       smallint not null check (gol_away >= 0),
  modulo_home    text not null check (modulo_home = any (private.moduli_validi())),
  modulo_away    text not null check (modulo_away = any (private.moduli_validi())),
  seed           bigint not null check (seed between 1 and 4294967295),
  blocchi        jsonb not null default '[]'::jsonb
                 check (jsonb_typeof(blocchi) = 'array'),
  stats_squadra  jsonb not null
                 check (jsonb_typeof(stats_squadra) = 'object'),
  simulata_il    timestamptz not null default now(),

  constraint matches_fixture_league_fk
    foreign key (fixture_id, league_id)
    references public.fixtures (id, league_id) on delete cascade,
  unique (id, league_id)
);

create index matches_league_idx on public.matches (league_id);

create table public.match_stats (
  id                   bigint generated always as identity primary key,
  match_id             bigint not null,
  league_id            bigint not null,
  team_id              bigint not null,
  player_instance_id   bigint not null,
  minuti               smallint not null default 0 check (minuti between 0 and 90),
  gol                  smallint not null default 0 check (gol >= 0),
  assist               smallint not null default 0 check (assist >= 0),
  tiri                 smallint not null default 0 check (tiri >= 0),
  tiri_porta           smallint not null default 0 check (tiri_porta between 0 and tiri),
  passaggi_tentati     smallint not null default 0 check (passaggi_tentati >= 0),
  passaggi_riusciti    smallint not null default 0
                       check (passaggi_riusciti between 0 and passaggi_tentati),
  contrasti_vinti      smallint not null default 0 check (contrasti_vinti >= 0),
  contrasti_persi      smallint not null default 0 check (contrasti_persi >= 0),
  dribbling            smallint not null default 0 check (dribbling >= 0),

  constraint match_stats_match_league_fk
    foreign key (match_id, league_id)
    references public.matches (id, league_id) on delete cascade,
  constraint match_stats_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  constraint match_stats_player_league_fk
    foreign key (player_instance_id, league_id)
    references public.player_instances (id, league_id) on delete restrict,
  unique (match_id, player_instance_id)
);

create index match_stats_league_idx on public.match_stats (league_id);
create index match_stats_match_idx on public.match_stats (match_id);
create index match_stats_team_idx on public.match_stats (team_id);
create index match_stats_player_idx on public.match_stats (player_instance_id);

create table public.standings (
  season_id     bigint not null,
  league_id     bigint not null,
  team_id       bigint not null,
  punti         smallint not null default 0 check (punti >= 0),
  vittorie      smallint not null default 0 check (vittorie >= 0),
  pareggi       smallint not null default 0 check (pareggi >= 0),
  sconfitte     smallint not null default 0 check (sconfitte >= 0),
  gol_fatti     smallint not null default 0 check (gol_fatti >= 0),
  gol_subiti    smallint not null default 0 check (gol_subiti >= 0),
  differenza_reti smallint generated always as (gol_fatti - gol_subiti) stored,
  giocate       smallint generated always as (vittorie + pareggi + sconfitte) stored,
  posizione     smallint check (posizione >= 1),
  aggiornata_il timestamptz not null default now(),

  constraint standings_punti_coerenti check (punti = vittorie * 3 + pareggi),
  constraint standings_season_league_fk
    foreign key (season_id, league_id)
    references public.seasons (id, league_id) on delete cascade,
  constraint standings_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  primary key (season_id, team_id)
);

create index standings_league_idx on public.standings (league_id);
create index standings_ordinamento_idx
  on public.standings (season_id, punti desc, differenza_reti desc, gol_fatti desc);

-- La posizione finale e' unica solo quando e' stata calcolata.
create unique index standings_posizione_unique_idx
  on public.standings (season_id, posizione)
  where posizione is not null;

create table public.transactions (
  id           bigint generated always as identity primary key,
  league_id    bigint not null,
  team_id      bigint not null,
  tipo         text not null check (length(tipo) between 1 and 40),
  importo      bigint not null check (importo <> 0),
  descrizione  text not null check (length(descrizione) between 1 and 240),
  saldo_dopo   bigint not null check (saldo_dopo >= 0),
  creata_il    timestamptz not null default now(),

  constraint transactions_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete restrict
);

create index transactions_league_idx on public.transactions (league_id);
create index transactions_team_created_idx
  on public.transactions (team_id, creata_il desc, id desc);

alter table public.matches      enable row level security;
alter table public.match_stats  enable row level security;
alter table public.standings    enable row level security;
alter table public.transactions enable row level security;

comment on table public.transactions is
  'Registro economico append-only: service_role puo solo leggere e inserire.';
