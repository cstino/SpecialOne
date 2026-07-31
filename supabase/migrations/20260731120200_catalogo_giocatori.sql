-- ============================================================
--  CATALOGO GIOCATORI  (design §2.2, §11)
--  Dataset FC 26 importato una volta sola e CONDIVISO tra tutte le leghe.
--  Qui non c'e' niente che riguardi una lega specifica: la copia per-lega
--  vive in `player_instances`.
-- ============================================================

create table players (
  id            bigint generated always as identity primary key,

  -- id del dataset di origine: rende l'import ri-eseguibile senza duplicare
  fc_id         bigint not null unique,

  nome          text   not null check (length(nome) between 1 and 120),
  nazionalita   text,
  club          text   not null,
  campionato    text   not null,
  foto_url      text,

  overall       smallint not null check (overall between 40 and 99),
  potential     smallint not null check (potential between 40 and 99),
  eta           smallint not null check (eta between 15 and 45),
  data_nascita  date,

  -- ordinate: la prima e' la posizione naturale (design §2.2)
  posizioni     text[] not null
                check (cardinality(posizioni) between 1 and 6)
                check (posizioni <@ private.ruoli_validi()),

  piede         text check (piede in ('destro','sinistro')),
  altezza       smallint check (altezza between 140 and 220),

  -- sottoattributi usati dal motore + quelli di dettaglio (design §2.2).
  -- jsonb perche' il set di attributi del dataset cambia tra un'edizione
  -- e l'altra e non voglio una migrazione per ogni campo nuovo.
  attributi     jsonb not null,

  -- design §11 li prevede entrambi. Restano false in Fase 1: le Icone sono
  -- Fase 4 e i regen la stagione 5. Le colonne ci sono perche' aggiungerle
  -- dopo significherebbe migrare una tabella da ~6.000 righe.
  is_icon       boolean not null default false,
  is_regen      boolean not null default false,

  creato_il     timestamptz not null default now(),

  -- il potenziale non puo' essere sotto l'overall attuale
  constraint players_potential_coerente check (potential >= overall),

  -- il motore legge questi cinque campi da ogni giocatore: se mancano,
  -- `ovrEfficace` e `distribuisci` producono NaN senza sollevare errori.
  -- Meglio rifiutare la riga all'import (decisioni-fase1 §4).
  constraint players_attributi_completi check (
    attributi ?& array['stamina','finishing','short_passing','standing_tackle','dribbling']
  )
);

-- il draft estrae un club a caso e mostra i suoi giocatori: e' la query
-- piu' frequente di tutta la Fase 1
create index players_club_idx on players (club);
create index players_campionato_idx on players (campionato);
create index players_overall_idx on players (overall desc);

comment on table players is
  'Catalogo FC 26 condiviso da tutte le leghe. Sola lettura per i client.';
comment on column players.posizioni is
  'Ordinate. posizioni[1] = naturale (design §2.2). Vincolate ai ruoli del motore.';

-- ------------------------------------------------------------
--  RLS
--  Il catalogo e' pubblico per chi ha un account: serve per il draft e per
--  guardare le rose altrui. Non contiene nulla di riservato.
--  Nessuna policy di scrittura: si importa con la service_role.
-- ------------------------------------------------------------

alter table players enable row level security;

create policy players_lettura on players
  for select
  to authenticated
  using (true);
