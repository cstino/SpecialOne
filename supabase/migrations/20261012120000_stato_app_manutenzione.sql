-- Interruttore di manutenzione: una sola riga leggibile da tutti (anche da chi non ha
-- ancora fatto login). L'app mostra la pagina "Server in manutenzione" quando e' accesa.
-- Si cambia solo da db query / service_role: nessuna policy di scrittura.
create table if not exists public.stato_app (
  id boolean primary key default true check (id),
  manutenzione boolean not null default false,
  messaggio text
);
insert into public.stato_app (id) values (true) on conflict do nothing;

alter table public.stato_app enable row level security;
drop policy if exists stato_app_lettura on public.stato_app;
create policy stato_app_lettura on public.stato_app for select to anon, authenticated using (true);
grant select on public.stato_app to anon, authenticated;
