-- Scambi di figurine: quali dei MIEI doppioni mancano all'altro giocatore (23/10/2026, committente).
-- Restituisce solo le figurine che io ho in doppio e che l'altro non possiede affatto (ne' normale ne' ultra):
-- non svela il resto dell'album altrui.
create or replace function public.album_mancano_a(p_league_id bigint, p_team_id bigint)
 returns table(figurina_id bigint)
 language sql stable security definer set search_path to ''
as $function$
  select m.figurina_id
    from public.album_possesso m
   where m.league_id = p_league_id and m.user_id = (select auth.uid())
     and (m.normali > 1 or m.ultra > 1)
     and (select private.e_membro(p_league_id))
     and not exists (
       select 1 from public.album_possesso a
         join public.teams t on t.user_id = a.user_id and t.league_id = p_league_id and t.id = p_team_id
        where a.league_id = p_league_id and a.figurina_id = m.figurina_id and a.normali + a.ultra > 0)
$function$;

revoke all on function public.album_mancano_a(bigint, bigint) from public, anon;
grant execute on function public.album_mancano_a(bigint, bigint) to authenticated, service_role;
