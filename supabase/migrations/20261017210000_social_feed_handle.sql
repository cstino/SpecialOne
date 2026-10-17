-- SocialOne: il feed restituisce anche il @nome dell'autore (i tifosi hanno un @nome proprio).
begin;
drop function if exists public.social_feed(bigint, boolean, integer, integer);
CREATE OR REPLACE FUNCTION public.social_feed(p_league_id bigint, p_per_te boolean DEFAULT true, p_limite integer DEFAULT 40, p_offset integer DEFAULT 0)
 RETURNS TABLE(id bigint, autore_tipo text, autore_nome text, autore_handle text, team_id bigint, team2_id bigint, player_instance_id bigint, in_risposta_a bigint, testo text, creato_il timestamp with time zone, n_mi_piace bigint, mio_mi_piace boolean, riguarda_me boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_mia bigint;
begin
  if not (p_league_id = any (private.mie_leghe())) then return; end if;
  select t.id into v_mia from public.teams t where t.league_id = p_league_id and t.user_id = v_utente;

  return query
    select p.id, p.autore_tipo, p.autore_nome, p.autore_handle, p.team_id, p.team2_id, p.player_instance_id, p.in_risposta_a, p.testo, p.creato_il,
           (select count(*) from public.social_mi_piace l where l.post_id = p.id),
           exists (select 1 from public.social_mi_piace l where l.post_id = p.id and l.user_id = v_utente),
           coalesce(p.team_id = v_mia or p.team2_id = v_mia, false)
    from public.social_posts p
    where p.league_id = p_league_id
    order by case when p_per_te and v_mia is not null and (p.team_id = v_mia or p.team2_id = v_mia)
                       and p.creato_il > now() - interval '3 days' then 0 else 1 end,
             p.creato_il desc, p.id desc
    limit greatest(1, least(p_limite, 100)) offset greatest(0, p_offset);
end;
$function$;
revoke all on function public.social_feed(bigint, boolean, integer, integer) from public, anon;
grant execute on function public.social_feed(bigint, boolean, integer, integer) to authenticated;

-- Il tag @ di una squadra con piu' lettere accentate (anche ā ē ī ō ū, es. "Hage No Dūche"),
-- cosi' coincide con quello calcolato dall'app.
create or replace function private.handle_squadra(p_nome text)
returns text
language sql immutable set search_path = ''
as $$
  select left(trim(both '_' from regexp_replace(lower(translate(coalesce(p_nome, ''),
    'àáâäãåāèéêëēìíîïīòóôöõōùúûüūçñýÿÀÁÂÄÃÅĀÈÉÊËĒÌÍÎÏĪÒÓÔÖÕŌÙÚÛÜŪÇÑÝ',
    'aaaaaaaeeeeeiiiiioooooouuuuucnyyAAAAAAAEEEEEIIIIIOOOOOOUUUUUCNY')), '[^a-z0-9]+', '_', 'g')), 22)
$$;

commit;
