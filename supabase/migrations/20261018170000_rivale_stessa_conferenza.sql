-- Il rivale dichiarato, nelle leghe a conferenze, e' della stessa conferenza. Riscritta dalla definizione viva.
begin;
CREATE OR REPLACE FUNCTION public.scegli_rivale(p_team_id bigint, p_rivale_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_t record;
  v_r record;
  v_stagione smallint;
begin
  select t.id, t.league_id, t.user_id, t.rivale_id, t.rivale_stagione, l.conferenze_stampa, l.stagione_corrente
    into v_t from public.teams t join public.leagues l on l.id = t.league_id where t.id = p_team_id;
  if not found or v_t.user_id is distinct from (select auth.uid()) then raise exception 'Non è la tua squadra.'; end if;
  if not v_t.conferenze_stampa then raise exception 'Le rivalità non sono attive in questa lega.'; end if;
  select id, league_id into v_r from public.teams where id = p_rivale_id;
  if not found or v_r.league_id <> v_t.league_id or v_r.id = v_t.id then raise exception 'Squadra rivale non valida.'; end if;
  v_stagione := v_t.stagione_corrente;
  -- Nelle leghe a due conferenze (Serie F) si gioca solo contro la propria conferenza: anche il rivale e' li'.
  if exists (select 1 from public.leagues l where l.id = v_t.league_id and l.conferenze_attive) then
    if (select st.conferenza from public.standings st join public.seasons se on se.id = st.season_id
         where st.team_id = p_team_id and se.league_id = v_t.league_id and se.numero = v_stagione)
       is distinct from
       (select st.conferenza from public.standings st join public.seasons se on se.id = st.season_id
         where st.team_id = p_rivale_id and se.league_id = v_t.league_id and se.numero = v_stagione) then
      raise exception 'Il rivale deve essere della tua conferenza.';
    end if;
  end if;
  if v_t.rivale_id is not null and v_t.rivale_stagione = v_stagione and v_t.rivale_id <> p_rivale_id then
    raise exception 'Hai già scelto il rivale in questa stagione: potrai cambiarlo dalla prossima.';
  end if;
  update public.teams set rivale_id = p_rivale_id, rivale_stagione = v_stagione where id = p_team_id;
  perform private.sposta_rivalita(v_t.league_id, p_team_id, p_rivale_id, 91);
end $function$;
commit;
