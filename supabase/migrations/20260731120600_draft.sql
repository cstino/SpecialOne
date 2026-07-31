-- ============================================================
--  DRAFT  (design §4)
--  Il design doc non prevede tabelle per il draft: descrive la meccanica ma
--  si ferma allo schema di §11. Queste sono aggiunte, non deviazioni.
-- ============================================================

-- Ordine a serpentina (design §4.1): 1..N, poi N..1, poi 1..N.
-- Derivato dal numero di pick invece che memorizzato, cosi' non puo'
-- desincronizzarsi. Restituisce la posizione 0-based di chi deve scegliere.
create or replace function private.turno_serpentina(p_n_squadre int, p_pick int)
returns int
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when (p_pick / p_n_squadre) % 2 = 0
      then  p_pick % p_n_squadre                    -- giro dispari: 1 -> N
      else  p_n_squadre - 1 - (p_pick % p_n_squadre) -- giro pari:    N -> 1
  end;
$$;

grant execute on function private.turno_serpentina(int, int) to authenticated, service_role;

-- ------------------------------------------------------------

create table draft_state (
  league_id       bigint primary key references leagues (id) on delete cascade,

  -- contatore globale dei pick della lega, 0-based.
  -- Chi deve scegliere = private.turno_serpentina(n_squadre, pick_numero).
  pick_numero     int not null default 0 check (pick_numero >= 0),

  -- club estratto dallo spin e ancora da risolvere. null = si deve spinnare.
  club_corrente   text,

  -- design §4.4, caso limite: se il club estratto non ha nessun giocatore
  -- ingaggiabile lo spin si ripete senza consumare reroll. Il contatore
  -- serve solo a diagnosticare: se schizza, il vincolo di solvibilita' e'
  -- tarato male e il draft e' vicino allo stallo.
  spin_a_vuoto    int not null default 0 check (spin_a_vuoto >= 0),

  stato           text not null default 'in_corso'
                  check (stato in ('in_corso','concluso')),
  aggiornato_il   timestamptz not null default now()
);

-- ------------------------------------------------------------

create table draft_picks (
  id                 bigint generated always as identity primary key,
  league_id          bigint not null references leagues (id) on delete cascade,
  team_id            bigint not null references teams (id) on delete cascade,
  player_instance_id bigint not null references player_instances (id) on delete cascade,

  pick_numero        int    not null check (pick_numero >= 0),
  club_estratto      text   not null,
  -- ingaggio al momento del pick: `player_instances.ingaggio` puo' cambiare
  -- dalla Fase 3 in poi, questo resta la cifra effettivamente pagata
  ingaggio_pagato    bigint not null check (ingaggio_pagato >= 500000),

  creato_il          timestamptz not null default now(),

  unique (league_id, pick_numero),
  unique (player_instance_id)
);

create index draft_picks_league_idx on draft_picks (league_id);
create index draft_picks_team_idx   on draft_picks (team_id);
create index draft_picks_pi_idx     on draft_picks (player_instance_id);

comment on table draft_picks is
  'Registro append-only dei pick. Ricostruisce l''intero draft in ordine.';

-- ------------------------------------------------------------
--  RLS: il draft e' pubblico dentro la lega — e' uno spettacolo,
--  si guarda mentre gli altri scelgono.
-- ------------------------------------------------------------

alter table draft_state enable row level security;
alter table draft_picks enable row level security;

create policy draft_state_lettura on draft_state
  for select
  to authenticated
  using ((select private.e_membro(league_id)));

create policy draft_picks_lettura on draft_picks
  for select
  to authenticated
  using ((select private.e_membro(league_id)));
