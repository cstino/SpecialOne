-- ============================================================
--  LEGHE E SQUADRE  (design §3.1, §3.2, §11)
-- ============================================================

create table leagues (
  id                bigint generated always as identity primary key,
  nome              text not null check (length(nome) between 3 and 60),
  admin_id          uuid not null references auth.users (id) on delete restrict,

  -- design §3.2: 6 caratteri. Maiuscolo e senza caratteri ambigui
  -- (niente O/0, I/1) perche' verra' dettato a voce o su WhatsApp.
  codice_invito     text not null unique
                    check (codice_invito ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),

  -- Impostazioni admin. design §11 le metteva in un `settings jsonb`;
  -- qui sono colonne esplicite per poterci mettere sopra i CHECK dei range
  -- di design §3.1. Un jsonb non impedisce di salvare 400 squadre.
  n_squadre         smallint not null default 8  check (n_squadre between 4 and 20),
  n_gironi          smallint not null default 4  check (n_gironi between 2 and 6),
  budget_iniziale   bigint   not null default 100000000
                    check (budget_iniziale between 50000000 and 200000000),
  reroll_draft      smallint not null default 12 check (reroll_draft between 0 and 30),
  slot_rosa         smallint not null default 25 check (slot_rosa between 20 and 30),
  portieri_minimi   smallint not null default 3  check (portieri_minimi between 2 and 4),
  campionati_attivi text[]   not null check (cardinality(campionati_attivi) >= 1),

  -- decisioni-fase1 §7: con una giornata per turno, P e' contemporaneamente
  -- il numero di partite e il numero di GIORNI di calendario. Calcolato dal
  -- database cosi' l'anteprima nella creazione lega non puo' divergere.
  partite_totali    smallint generated always as ((n_squadre - 1) * n_gironi) stored,

  stato             text not null default 'setup'
                    check (stato in ('setup','draft','stagione','conclusa')),
  stagione_corrente smallint not null default 1 check (stagione_corrente >= 1),

  creata_il         timestamptz not null default now()
);

create index leagues_admin_idx on leagues (admin_id);

comment on column leagues.partite_totali is
  'P = (N-1)*G. Con una giornata per turno e'' anche la durata in giorni (decisioni-fase1 §7).';

-- ------------------------------------------------------------

create table teams (
  id             bigint generated always as identity primary key,
  league_id      bigint not null references leagues (id) on delete cascade,
  user_id        uuid   not null references auth.users (id) on delete restrict,

  nome           text not null check (length(nome) between 2 and 40),
  stemma_url     text,

  -- euro interi. Mai float: gli ingaggi sono multipli di 100.000 e un
  -- arrotondamento binario su un budget diventa un bug irriproducibile.
  budget         bigint not null check (budget >= 0),

  -- design §4.1: rerolls residui del draft, inizializzati da leagues.reroll_draft
  reroll_rimasti smallint not null default 0 check (reroll_rimasti >= 0),

  -- posizione nell'ordine di draft, 0-based. Determina la serpentina.
  ordine_draft   smallint check (ordine_draft >= 0),

  creata_il      timestamptz not null default now(),

  -- una squadra per persona per lega, nomi distinti dentro la lega
  unique (league_id, user_id),
  unique (league_id, nome),
  unique (league_id, ordine_draft)
);

create index teams_league_idx on teams (league_id);
create index teams_user_idx on teams (user_id);

comment on table teams is
  'Una squadra per partecipante per lega. budget in euro interi.';

-- ------------------------------------------------------------
--  RLS: abilitata qui, policy nella migrazione successiva
--  (le policy hanno bisogno delle funzioni helper, che a loro volta
--  hanno bisogno di questa tabella: l'ordine non e' evitabile).
-- ------------------------------------------------------------

alter table leagues enable row level security;
alter table teams   enable row level security;
