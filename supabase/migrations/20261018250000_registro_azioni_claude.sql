-- Registro delle azioni automatiche di Claude Ranieri (Atletico Neurale, Serie F): ogni formazione, spesa di punti,
-- promozione o rinnovo e' scritta qui, leggibile dall'amministratore della lega (e dall'allenatore della squadra).
begin;

create table public.azioni_claude (
  id        bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id   bigint not null references public.teams(id) on delete cascade,
  tipo      text not null,
  dettaglio jsonb not null default '{}'::jsonb,
  creato_il timestamptz not null default now()
);
create index azioni_claude_team_idx on public.azioni_claude (team_id, creato_il desc);

alter table public.azioni_claude enable row level security;
create policy azioni_claude_lettura on public.azioni_claude
  for select to authenticated
  using (exists (select 1 from public.leagues l where l.id = league_id and l.admin_id = (select auth.uid())));
grant select on public.azioni_claude to authenticated;
grant all on public.azioni_claude to service_role;

commit;
