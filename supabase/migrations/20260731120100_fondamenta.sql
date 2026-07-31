-- ============================================================
--  FONDAMENTA
--  Schema privato per le funzioni di supporto alle policy RLS,
--  piu' i vocabolari controllati condivisi da piu' tabelle.
-- ============================================================

-- Lo schema `private` non e' esposto da PostgREST: le funzioni che sta dentro
-- non sono chiamabili via API, ma restano usabili dentro le policy.
create schema if not exists private;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- ------------------------------------------------------------
--  Vocabolari controllati
--  Sono gli stessi identificatori usati da engine/config.js.
--  Tenerli come CHECK sul database non e' pedanteria: `penalitaRuolo()`
--  restituisce 0.58 (reparto opposto) per qualsiasi stringa che non
--  riconosce, quindi un ruolo scritto male nell'import NON darebbe errore,
--  darebbe un giocatore silenziosamente piu' scarso per tutta la stagione.
-- ------------------------------------------------------------

-- ruoli ammessi: le chiavi di REPARTO in engine/config.js
create or replace function private.ruoli_validi()
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select array[
    'GK',
    'CB','LB','RB','LWB','RWB',
    'CDM','CM','CAM','LM','RM',
    'LW','RW','ST','CF'
  ]::text[];
$$;

-- moduli ammessi: le chiavi di MODULI in engine/config.js
create or replace function private.moduli_validi()
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select array[
    '4-3-3','4-4-2','4-2-3-1','3-5-2','3-4-3','5-3-2','4-2-4'
  ]::text[];
$$;

-- ------------------------------------------------------------
--  Utility per i vincoli sugli array
--  Devono essere IMMUTABLE per poter comparire in un CHECK.
-- ------------------------------------------------------------

create or replace function private.senza_duplicati(a bigint[])
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select a is null
      or cardinality(a) = (select count(distinct x) from unnest(a) as x);
$$;

comment on schema private is
  'Funzioni di supporto a RLS e ai vincoli. Non esposto da PostgREST.';
