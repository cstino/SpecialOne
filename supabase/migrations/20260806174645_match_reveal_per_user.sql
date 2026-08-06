-- Il reveal e' personale: evita localStorage e resta uguale su tutti i
-- dispositivi dell'utente. Non contiene alcun dato di gioco, solo il fatto
-- che il risultato di una partita e' gia' stato guardato.
create table public.match_reveals (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  match_id bigint not null references public.matches(id) on delete cascade,
  revealed_at timestamptz not null default now(),
  primary key (user_id, match_id)
);

alter table public.match_reveals enable row level security;

grant select, insert on public.match_reveals to authenticated;
grant all on public.match_reveals to service_role;

create policy match_reveals_lettura_propri on public.match_reveals
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy match_reveals_inserimento_proprio on public.match_reveals
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.matches m
      where m.id = match_id
        and (select private.e_membro(m.league_id))
    )
  );
