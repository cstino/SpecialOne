-- Il casino' di BetOne e' aperto a tutti (prima solo al committente per i test).
create or replace function private.casino_visibile(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $f$ select p_user is not null $f$;
