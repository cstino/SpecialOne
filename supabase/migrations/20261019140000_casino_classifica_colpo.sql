-- Classifica del casino': per miglior colpo (vincita piu' alta in un giro), poi crediti; solo chi ha giocato almeno un giro.
begin;
CREATE OR REPLACE FUNCTION public.casino_classifica(p_league_id bigint)
 RETURNS TABLE(team_id bigint, crediti bigint, max_vincita bigint, giri integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.team_id, s.crediti, s.max_vincita, s.giri from public.casino_saldi s
  where s.league_id = p_league_id and (select private.e_membro(p_league_id)) and s.giri > 0
  order by s.max_vincita desc, s.crediti desc, s.team_id
$function$;
commit;
