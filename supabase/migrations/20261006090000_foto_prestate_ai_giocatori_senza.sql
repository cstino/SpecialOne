-- Foto "prestate": i giocatori senza ritratto (quasi tutti inventati dal vivaio)
-- usano la foto di un giocatore reale di basso livello che nessuna lega usa.
--
--  * Donatore: ha una foto, overall <= 55 e non compare in nessuna lega
--    (rose, svincolati, pool delle scelte, ritirati, vivaio): nessuno lo vedra' mai.
--  * Un donatore presta la foto a una sola persona.
--  * foto_url del beneficiario punta allo stesso file nello Storage (nessun upload).
--  * private.foto_prestate tiene il registro, cosi' si puo' annullare.
--  * Un trigger fa lo stesso per i giocatori futuri (nuovi prospetti del vivaio).

create table if not exists private.foto_prestate (
  player_id    bigint primary key references public.players(id) on delete cascade,
  donatore_id  bigint not null unique references public.players(id) on delete cascade,
  creato_il    timestamptz not null default now()
);

create or replace function private.donatore_foto_libero()
returns bigint
language sql
stable
set search_path = public, private
as $$
  select p.id
  from public.players p
  where p.foto_url is not null
    and p.overall <= 55
    and not exists (select 1 from private.foto_prestate f where f.player_id = p.id or f.donatore_id = p.id)
    and not exists (select 1 from public.player_instances x where x.player_id = p.id)
    and not exists (select 1 from public.free_agent_progression x where x.player_id = p.id)
    and not exists (select 1 from public.scelte_pool x where x.player_id = p.id)
    and not exists (select 1 from public.retired_players x where x.player_id = p.id)
    and not exists (select 1 from public.vivaio_prospetti x where x.player_id = p.id)
  order by p.overall, p.id
  limit 1
$$;

-- Giocatori gia' presenti senza foto.
do $$
declare r record; d bigint;
begin
  for r in select id from public.players where foto_url is null order by id loop
    d := private.donatore_foto_libero();
    exit when d is null;
    insert into private.foto_prestate (player_id, donatore_id) values (r.id, d);
    update public.players set foto_url = (select foto_url from public.players where id = d) where id = r.id;
  end loop;
end $$;

-- Giocatori futuri: se nasce senza foto, ne prende una in prestito (se ce ne sono).
create or replace function private.players_foto_prestata()
returns trigger
language plpgsql
set search_path = public, private
as $$
declare d bigint;
begin
  if new.foto_url is null then
    d := private.donatore_foto_libero();
    if d is not null then
      new.foto_url := (select foto_url from public.players where id = d);
      -- il registro si scrive dopo l'insert (serve l'id del nuovo giocatore)
      perform set_config('private.foto_donatore', d::text, true);
    end if;
  end if;
  return new;
end $$;

create or replace function private.players_foto_prestata_registro()
returns trigger
language plpgsql
set search_path = public, private
as $$
declare d text := nullif(current_setting('private.foto_donatore', true), '');
begin
  if d is not null then
    insert into private.foto_prestate (player_id, donatore_id) values (new.id, d::bigint) on conflict do nothing;
    perform set_config('private.foto_donatore', '', true);
  end if;
  return null;
end $$;

drop trigger if exists players_foto_prestata on public.players;
create trigger players_foto_prestata before insert on public.players
  for each row execute function private.players_foto_prestata();

drop trigger if exists players_foto_prestata_registro on public.players;
create trigger players_foto_prestata_registro after insert on public.players
  for each row execute function private.players_foto_prestata_registro();
