-- ============================================================
--  ROSE  (design §4.2, §4.5, §11)
--  Copia per-lega di un giocatore del catalogo. E' l'oggetto che il draft
--  crea, che la formazione schiera e che (dalla Fase 2) il mercato scambia.
-- ============================================================

create table player_instances (
  id                bigint generated always as identity primary key,
  league_id         bigint not null references leagues (id) on delete cascade,
  player_id         bigint not null references players (id) on delete restrict,

  -- null = svincolato / mai draftato. In Fase 1 vuol dire solo "mai draftato":
  -- non esiste ancora nessun modo di liberare un giocatore.
  team_id           bigint references teams (id) on delete set null,

  -- snapshot al momento dell'ingresso in lega: dalla Fase 3 divergono dal
  -- catalogo, perche' i giocatori crescono e invecchiano per lega
  overall_corrente  smallint not null check (overall_corrente between 40 and 99),
  eta_corrente      smallint not null check (eta_corrente between 15 and 45),

  -- design §5.1: euro interi, floor a 500.000
  ingaggio          bigint not null check (ingaggio >= 500000),

  -- Fase 2. Presenti da subito con i default perche' il motore le legge
  -- sempre: `schiera()` filtra su infortunatoFinoA <= 0 e `ovrEfficace`
  -- moltiplica per fattoreCondizione(condizione). Se l'adapter dovesse
  -- inventarle invece di leggerle, un domani divergerebbero in silenzio
  -- (decisioni-fase1 §4).
  condizione        smallint not null default 100 check (condizione between 0 and 100),
  infortunato_fino_a smallint not null default 0  check (infortunato_fino_a >= 0),

  creata_il         timestamptz not null default now(),

  -- design §4.2: unicita' GLOBALE dentro la lega. E' il vincolo che rende
  -- il draft un gioco a somma zero, ed e' meglio che lo tenga il database:
  -- due pick simultanei sullo stesso giocatore sono uno scenario reale.
  unique (league_id, player_id)
);

create index player_instances_league_idx on player_instances (league_id);
create index player_instances_team_idx   on player_instances (team_id);
create index player_instances_player_idx on player_instances (player_id);

-- i giocatori ancora disponibili al draft, per lega: query calda del draft
create index player_instances_liberi_idx on player_instances (league_id)
  where team_id is null;

comment on table player_instances is
  'Istanza per-lega di un giocatore. unique(league_id, player_id) = unicita'' globale (design §4.2).';

-- ------------------------------------------------------------
--  RLS
--  Le rose sono pubbliche dentro la lega: senza, non si puo' vedere chi ha
--  gia' preso un giocatore, e design §4.2 vuole proprio che si veda
--  (in grigio, con lo stemma di chi lo possiede).
-- ------------------------------------------------------------

alter table player_instances enable row level security;

create policy player_instances_lettura on player_instances
  for select
  to authenticated
  using ((select private.e_membro(league_id)));
