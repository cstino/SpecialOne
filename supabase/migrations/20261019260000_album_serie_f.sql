-- Album (con bustine, scambi di figurine e combo bustina al casino') attivo in tutte le leghe con le novita', Serie F compresa.
create or replace function private.album_attivo(p_league_id bigint)
returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa)
$f$;
