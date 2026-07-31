-- ============================================================
--  FORMAZIONI E FAMILIARITA  (design §6; decisioni §1, §2, §7)
-- ============================================================

create table public.lineups (
  id          bigint generated always as identity primary key,
  league_id   bigint not null,
  team_id     bigint not null,
  giornata    smallint not null check (giornata >= 1),
  modulo      text not null check (modulo = any (private.moduli_validi())),

  -- L'ordine e' significativo: titolari[i] occupa lo slot i del modulo.
  titolari    bigint[] not null check (cardinality(titolari) = 11),
  panchina    bigint[] not null default '{}'::bigint[]
              check (cardinality(panchina) between 0 and 9),
  tribuna     bigint[] not null default '{}'::bigint[],
  automatica  boolean not null default false,
  salvata_il  timestamptz not null default now(),

  constraint lineups_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  constraint lineups_giocatori_unici check (
    private.senza_duplicati(titolari || panchina || tribuna)
  ),
  unique (team_id, giornata)
);

create index lineups_league_giornata_idx
  on public.lineups (league_id, giornata);

comment on column public.lineups.titolari is
  'Array ordinato: indice giocatore = indice slot in engine/config.js.';

create table public.formation_xp (
  team_id          bigint not null,
  league_id        bigint not null,
  modulo           text not null check (modulo = any (private.moduli_validi())),
  partite_giocate  smallint not null default 0 check (partite_giocate >= 0),
  aggiornata_il    timestamptz not null default now(),

  constraint formation_xp_team_league_fk
    foreign key (team_id, league_id)
    references public.teams (id, league_id) on delete cascade,
  primary key (team_id, modulo)
);

create index formation_xp_league_idx on public.formation_xp (league_id);

alter table public.lineups      enable row level security;
alter table public.formation_xp enable row level security;

comment on table public.lineups is
  'Una formazione per squadra e giornata; le formazioni avversarie restano segrete fino alla simulazione.';
