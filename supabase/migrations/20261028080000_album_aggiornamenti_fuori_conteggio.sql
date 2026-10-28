-- Album: le figurine dei giocatori arrivati dopo l'apertura dell'album (aggiornamento = true, "AGG.") restano
-- collezionabili e scambiabili ma stanno in una pagina "Aggiornamenti" a parte, fuori dal conteggio: percentuale,
-- classifica dei collezionisti, pagine complete e album completo si calcolano solo sulle figurine di partenza
-- (decisione del committente del 28/10/2026: "le figurine aumentano, così non si arriverà mai alla fine").
-- Funzioni ricostruite dalle definizioni vive.

CREATE OR REPLACE FUNCTION public.album_classifica(p_league_id bigint)
 RETURNS TABLE(team_id bigint, attaccate integer, totale integer, ultra integer, pagine integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with st as (select stagione_corrente s from public.leagues where id = p_league_id),
  tot as (select count(*)::int n from public.album_figurine f, st where f.league_id = p_league_id and f.stagione = st.s and f.tipo in ('stemma','giocatore') and not f.aggiornamento)
  select t.id,
         count(*) filter (where f.tipo in ('stemma','giocatore') and not f.aggiornamento and ap.normali + ap.ultra > 0)::int,
         (select n from tot),
         count(*) filter (where ap.ultra > 0)::int,
         (select count(*)::int from public.album_premi pr, st where pr.league_id = p_league_id and pr.user_id = ap.user_id and pr.stagione = st.s and pr.chiave like 'pagina:%')
  from public.album_possesso ap
  join public.album_figurine f on f.id = ap.figurina_id
  join st on f.stagione = st.s
  join public.teams t on t.league_id = p_league_id and t.user_id = ap.user_id
  where ap.league_id = p_league_id and (select private.e_membro(p_league_id))
  group by t.id, ap.user_id
  order by 2 desc, 4 desc, 1
$function$;

CREATE OR REPLACE FUNCTION private.album_controlla_premi(p_league_id bigint, p_user uuid, p_stagione smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_t record;
  v_nuovi jsonb := '[]'::jsonb;
  v_nome text;
  v_team_mio bigint;
begin
  for v_t in
    select f.team_id from public.album_figurine f
    where f.league_id = p_league_id and f.stagione = p_stagione and f.tipo in ('stemma', 'giocatore') and not f.aggiornamento
    group by f.team_id
    having bool_and(exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.ultra > 0))
  loop
    insert into public.album_premi (league_id, user_id, stagione, chiave) values (p_league_id, p_user, p_stagione, 'pagina:' || v_t.team_id)
    on conflict do nothing;
    if found then
      update public.casino_saldi set crediti = crediti + 200 where league_id = p_league_id and user_id = p_user;
      v_nuovi := v_nuovi || jsonb_build_object('pagina', v_t.team_id);
    end if;
  end loop;
  if not exists (
    select 1 from public.album_figurine f
    where f.league_id = p_league_id and f.stagione = p_stagione and f.tipo in ('stemma', 'giocatore') and not f.aggiornamento
      and not exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.ultra > 0))
  then
    insert into public.album_premi (league_id, user_id, stagione, chiave) values (p_league_id, p_user, p_stagione, 'album') on conflict do nothing;
    if found then
      select t.id, t.nome into v_team_mio, v_nome from public.teams t where t.league_id = p_league_id and t.user_id = p_user;
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
      values (p_league_id, 'album:' || p_stagione || ':' || p_user, 'lega', 'Album SpecialOne', v_team_mio,
              '📒 ALBUM COMPLETATO! ' || coalesce(v_nome, 'Una squadra') || ' ha attaccato l''ultima figurina della stagione ' || p_stagione || ' 👏', now())
      on conflict do nothing;
      v_nuovi := v_nuovi || jsonb_build_object('album', true);
    end if;
  end if;
  return v_nuovi;
end $function$;
