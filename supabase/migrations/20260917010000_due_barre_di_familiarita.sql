-- ============================================================
--  DUE BARRE DI FAMILIARITA', COME IN FOOTBALL MANAGER
--
--  PERCHE'. In FM la familiarita' tattica non e' un numero solo: disposizione,
--  mentalita', ritmo, ampiezza e liberta' creativa hanno ognuna la sua barra, e
--  cambiare un'istruzione muove solo quelle collegate. Da noi era una barra
--  sola e tutto-o-niente: giocare un modulo diverso costava 3,5 punti di
--  overall a tutti e undici per cinque giornate.
--
--  Misurato in Serie F prima di questa migrazione:
--    - familiarita' media di lega 66,1%, 19 combinazioni squadra-modulo su 36
--      sotto soglia;
--    - 23 squadre su 40 hanno usato UN SOLO modulo per tutta la stagione.
--
--  La seconda riga non descrive una scelta tattica, descrive la risposta
--  razionale a una tassa. Con gli schemi personalizzati in arrivo (scegliere il
--  modulo e poi spostare le posizioni, tipo i due CM di un 4-4-2 che diventano
--  CDM) il problema diventerebbe fatale: ogni ritocco azzererebbe la squadra e
--  nessuno userebbe la funzione due volte.
--
--  COSA CAMBIA.
--    barra DISPOSIZIONE  — dove stanno gli undici. Ha memoria: e' indicizzata
--                          sullo schieramento, quindi tornare al vecchio 4-4-2
--                          ritrova il contatore di prima. Uno schieramento mai
--                          visto NON parte da zero: eredita dal piu' simile
--                          gia' giocato (private.semina_disposizione_xp).
--    barra INDICAZIONI   — stile, ruoli e compiti. Non ha memoria ed e' un
--                          contatore solo: cambiare indicazioni lo arretra in
--                          proporzione a quanto e' cambiato, non lo azzera.
--
--  La differenza fra le due e' voluta: uno schieramento e' una cosa discreta a
--  cui si torna, le indicazioni sono un continuo in cui ci si sposta.
--
--  QUESTA MIGRAZIONE E' INERTE. lineups.disposizione, ruoli e compiti nascono
--  NULL; con NULL si ricade sullo schieramento standard del modulo e su nessuna
--  indicazione, cioe' esattamente il comportamento di oggi. Il motore fa lo
--  stesso: engine/engine.js usa le due barre solo se gli vengono passate.
-- ============================================================

-- ------------------------------------------------------------
--  Lo schieramento standard di un modulo
--  Unica verita': generato da MODULI in engine/config.js. Se un modulo cambia
--  la' , va rigenerato anche qui.
-- ------------------------------------------------------------
create or replace function private.disposizione_standard(p_modulo text)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case p_modulo
    when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']::text[]
    when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']::text[]
    when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']::text[]
    when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']::text[]
    when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']::text[]
    when '3-5-2' then array['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST']::text[]
    when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']::text[]
    when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']::text[]
    when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']::text[]
    else null::text[]
  end
$$;

revoke all on function private.disposizione_standard(text) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Quanto due schieramenti si somigliano, da 0 a 1
--  Il portiere conta come gli altri: undici slot, confronto posizionale.
-- ------------------------------------------------------------
create or replace function private.similarita_disposizione(a text[], b text[])
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when a is null or b is null or cardinality(a) <> 11 or cardinality(b) <> 11 then 0
    else (select count(*)::numeric / 11 from generate_series(1, 11) i where a[i] = b[i])
  end
$$;

revoke all on function private.similarita_disposizione(text[], text[]) from public, anon, authenticated;

-- ------------------------------------------------------------
--  La barra DISPOSIZIONE
-- ------------------------------------------------------------
alter table public.formation_xp
  add column if not exists disposizione text[];

update public.formation_xp
set disposizione = private.disposizione_standard(modulo)
where disposizione is null;

alter table public.formation_xp
  alter column disposizione set not null;

-- La chiave passa da (squadra, modulo) a (squadra, modulo, schieramento): due
-- varianti dello stesso modulo sono due apprendimenti diversi. Le righe
-- esistenti hanno lo schieramento standard, quindi nessuna si perde.
alter table public.formation_xp drop constraint if exists formation_xp_pkey;
alter table public.formation_xp add primary key (team_id, modulo, disposizione);

comment on column public.formation_xp.disposizione is
  'I undici slot di questo schieramento. Lo standard del modulo per le formazioni non personalizzate.';

-- ------------------------------------------------------------
--  La barra INDICAZIONI: una riga per squadra
-- ------------------------------------------------------------
create table if not exists public.indicazioni_xp (
  team_id bigint primary key,
  league_id bigint not null,
  partite_giocate smallint not null default 0 check (partite_giocate >= 0),
  stile text,
  ruoli text[],
  compiti text[],
  aggiornata_il timestamptz not null default now(),
  constraint indicazioni_xp_team_league_fk
    foreign key (team_id, league_id) references public.teams(id, league_id) on delete cascade
);

alter table public.indicazioni_xp enable row level security;

-- Stessa apertura di formation_xp: la familiarita' di una squadra non e' un
-- segreto, si vede dal campo. Cio' che resta nascosto e' la formazione prima
-- della simulazione, che sta altrove.
create policy indicazioni_xp_lettura on public.indicazioni_xp
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = indicazioni_xp.team_id
      and t.league_id in (select league_id from public.teams where user_id = (select auth.uid()))
  ));

grant select on public.indicazioni_xp to authenticated;
grant select, insert, update, delete on public.indicazioni_xp to service_role;

comment on table public.indicazioni_xp is
  'Barra INDICAZIONI (stile, ruoli, compiti). Una riga per squadra, senza memoria: cambiare indicazioni arretra il contatore in proporzione a quanto e'' cambiato.';
