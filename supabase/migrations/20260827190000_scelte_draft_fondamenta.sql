-- ============================================================
--  PLAYOFF A DOPPIO TABELLONE E SCELTE SCAMBIABILI — passo 1: fondamenta
--  docs/decisioni-draft-picks.md
--
--  Solo lo schema e la generazione dell'inventario di scelte. Non tocca
--  ancora i tabelloni playoff/playout esistenti (brackets/bracket_ties,
--  scritti ieri e gia' live): quella riscrittura — Title/Draft Playoff al
--  posto di Playoff/Playout, soglia 8 fissa, seeding ad accoppiamento
--  adiacente per il Draft Playoff — e' il passo successivo. Farla di fretta
--  nella stessa migrazione rischierebbe di rompere un sistema che funziona
--  gia' in produzione.
-- ============================================================

-- ------------------------------------------------------------
--  Una riga = una scelta di una finestra di mercato (ON o OFF-Season) di
--  una data stagione, per una data squadra di ORIGINE.
--
--  squadra_origine non cambia mai: e' quella il cui piazzamento nei playoff
--  della stagione precedente determina la posizione (1..N) di questa
--  scelta. squadra_proprietaria e' chi la possiede ORA e la user gramma per
--  scegliere il giocatore — cambia con gli scambi, parte identica
--  all'origine.
--
--  posizione e' NULL finche' i playoff della stagione precedente non sono
--  conclusi (docs/decisioni-draft-picks.md §2): una scelta "futura" esiste
--  gia' come asset scambiabile prima ancora di sapere che numero avra'.
-- ------------------------------------------------------------

create table public.scelte_draft (
  id                    bigint generated always as identity primary key,
  league_id             bigint not null references public.leagues(id) on delete cascade,
  team_origine_id       bigint not null,
  team_proprietario_id  bigint not null,
  stagione              smallint not null check (stagione >= 1),
  finestra              text not null check (finestra in ('on', 'off')),
  posizione             smallint check (posizione >= 1),
  stato                 text not null default 'futura'
                        check (stato in ('futura', 'determinata', 'usata', 'vuota')),
  player_instance_id    bigint references public.player_instances(id) on delete set null,
  creata_il             timestamptz not null default now(),
  aggiornata_il         timestamptz not null default now(),
  unique (league_id, team_origine_id, stagione, finestra),
  constraint scelte_draft_origine_fk
    foreign key (team_origine_id, league_id) references public.teams(id, league_id) on delete cascade,
  constraint scelte_draft_proprietario_fk
    foreign key (team_proprietario_id, league_id) references public.teams(id, league_id) on delete cascade
);

comment on table public.scelte_draft is
  'Una scelta per squadra di origine, stagione e finestra (ON/OFF-Season). team_origine determina la posizione (via playoff), team_proprietario e'' chi la usa ora — cambiano con gli scambi. docs/decisioni-draft-picks.md';
comment on column public.scelte_draft.stato is
  'futura: posizione non ancora determinata. determinata: posizione nota (1..N), non ancora usata. usata: un giocatore e'' stato assegnato. vuota: la finestra si e'' chiusa senza che la lista di preferenze producesse un giocatore.';

create index scelte_draft_league_idx on public.scelte_draft(league_id, stagione, finestra);
create index scelte_draft_proprietario_idx on public.scelte_draft(team_proprietario_id, stagione, finestra);

alter table public.scelte_draft enable row level security;

create policy scelte_draft_lettura on public.scelte_draft
  for select to authenticated
  using ((select private.e_membro(league_id)));

-- ------------------------------------------------------------
--  Genera l'inventario di partenza: per ogni squadra attiva, una scelta
--  ON e una OFF per ciascuna delle p_stagioni successive alla corrente
--  (default 4, docs/decisioni-draft-picks.md §3.2). Idempotente: una
--  squadra che ha gia' le sue scelte per una stagione non le duplica.
-- ------------------------------------------------------------

create or replace function private.genera_scelte_draft(
  p_league_id bigint,
  p_stagioni smallint default 4
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_inserite integer;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  insert into public.scelte_draft (league_id, team_origine_id, team_proprietario_id, stagione, finestra)
  select p_league_id, t.id, t.id, s.stagione, f.finestra
  from public.teams t
  cross join generate_series(v_lega.stagione_corrente + 1, v_lega.stagione_corrente + p_stagioni) as s(stagione)
  cross join (values ('on'), ('off')) as f(finestra)
  where t.league_id = p_league_id and t.attiva
  on conflict (league_id, team_origine_id, stagione, finestra) do nothing;

  get diagnostics v_inserite = row_count;
  return v_inserite;
end;
$$;

comment on function private.genera_scelte_draft(bigint, smallint) is
  'Crea l''inventario di scelte (ON+OFF per le prossime N stagioni) per ogni squadra attiva della lega. Idempotente.';

revoke all on function private.genera_scelte_draft(bigint, smallint) from public, anon, authenticated;
grant execute on function private.genera_scelte_draft(bigint, smallint) to service_role;
