-- Album: a stagione nuova i doppioni dell'album vecchio sono bruciati (segnalazione dell'8/11/2026, Serie F appena
-- passata alla Season 3: i doppioni della Season 2 si potevano ancora riciclare in crediti e scambiare). Riciclo,
-- elenco dei doppioni e scambi contano solo le figurine della stagione in corso; quelle vecchie restano nell'album
-- della loro stagione come collezione. Gli scambi ancora in attesa con figurine di un'altra stagione scadono.

CREATE OR REPLACE FUNCTION public.album_ricicla_doppioni(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_n int; v_crediti int;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  -- Stesso blocco di chi propone scambi; le copie dentro scambi in attesa non si riciclano.
  perform pg_advisory_xact_lock(hashtext('album_scambi'), p_league_id::int);
  with imp as (select * from private.album_impegnate(p_league_id, v_utente)),
  c as (
    select v.ver, greatest(0, private.album_n(p.normali, p.rare, p.ultra, p.ultimate, v.ver) - 1 - coalesce(i.n, 0)) as k
    from public.album_possesso p
    cross join (values ('common'), ('rare'), ('ultra'), ('ultimate')) v(ver)
    left join imp i on i.figurina_id = p.figurina_id and i.versione = v.ver
    where p.league_id = p_league_id and p.user_id = v_utente
      and p.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id)))
  select coalesce(sum(k), 0),
         coalesce(sum(k * case ver when 'rare' then 25 when 'ultra' then 50 when 'ultimate' then 150 else 10 end), 0)
    into v_n, v_crediti
  from c;
  if v_crediti = 0 then return jsonb_build_object('riciclati', 0, 'crediti_guadagnati', 0); end if;
  perform private.casino_saldo(p_league_id, v_utente);
  with imp as (select * from private.album_impegnate(p_league_id, v_utente))
  update public.album_possesso p set
    normali = least(p.normali, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and i.versione = 'common'), 0)),
    rare = least(p.rare, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and i.versione = 'rare'), 0)),
    ultra = least(p.ultra, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and i.versione = 'ultra'), 0)),
    ultimate = least(p.ultimate, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and i.versione = 'ultimate'), 0))
   where p.league_id = p_league_id and p.user_id = v_utente
     and p.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id));
  update public.casino_saldi set crediti = crediti + v_crediti, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('riciclati', v_n, 'crediti_guadagnati', v_crediti,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$

;
CREATE OR REPLACE FUNCTION public.album_doppioni(p_league_id bigint, p_team_id bigint)
 RETURNS TABLE(figurina_id bigint, versione text, copie integer, impegnate integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with d as (
    select ap.figurina_id, v.ver, private.album_n(ap.normali, ap.rare, ap.ultra, ap.ultimate, v.ver) - 1 as copie, t.user_id
      from public.album_possesso ap
      join public.teams t on t.user_id = ap.user_id and t.league_id = p_league_id and t.id = p_team_id
     cross join (values ('common'), ('rare'), ('ultra'), ('ultimate')) v(ver)
     where ap.league_id = p_league_id and (select private.e_membro(p_league_id))
       and ap.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id))
  ), imp as (select * from private.album_impegnate(p_league_id, (select user_id from d limit 1)))
  select d.figurina_id, d.ver, d.copie, coalesce(i.n, 0)::integer
    from d left join imp i on i.figurina_id = d.figurina_id and i.versione = d.ver
   where d.copie > 0
$function$

;
CREATE OR REPLACE FUNCTION public.album_mancano_a(p_league_id bigint, p_team_id bigint)
 RETURNS TABLE(figurina_id bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select m.figurina_id
    from public.album_possesso m
   where m.league_id = p_league_id and m.user_id = (select auth.uid())
     and (m.normali > 1 or m.rare > 1 or m.ultra > 1 or m.ultimate > 1)
     and (select private.e_membro(p_league_id))
     and m.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id))
     and not exists (
       select 1 from public.album_possesso a
         join public.teams t on t.user_id = a.user_id and t.league_id = p_league_id and t.id = p_team_id
        where a.league_id = p_league_id and a.figurina_id = m.figurina_id and a.normali + a.rare + a.ultra + a.ultimate > 0)
$function$

;
CREATE OR REPLACE FUNCTION private.album_ha_doppioni(p_league_id bigint, p_user uuid, p_voci jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(bool_and(
    coalesce((select private.album_n(ap.normali, ap.rare, ap.ultra, ap.ultimate, v.ver) from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id
                 and ap.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id))), 0) - 1 >= v.n), false)
  from (select (x->>'figurina_id')::bigint as figurina_id, private.album_versione(x) as ver, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$function$

;
CREATE OR REPLACE FUNCTION private.album_ha_doppioni_liberi(p_league_id bigint, p_user uuid, p_voci jsonb, p_escludi bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(bool_and(
    coalesce((select private.album_n(ap.normali, ap.rare, ap.ultra, ap.ultimate, v.ver) from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id
                 and ap.figurina_id in (select f.id from public.album_figurine f where f.league_id = p_league_id and f.stagione = (select l.stagione_corrente from public.leagues l where l.id = p_league_id))), 0) - 1
    - coalesce((select i.n from private.album_impegnate(p_league_id, p_user, p_escludi) i where i.figurina_id = v.figurina_id and i.versione = v.ver), 0)
    >= v.n), false)
  from (select (x ->> 'figurina_id')::bigint as figurina_id, private.album_versione(x) as ver, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$function$

;

update public.album_scambi s set stato = 'scaduto'
 where s.stato = 'in_attesa'
   and exists (select 1 from jsonb_array_elements(s.offerte || s.richieste) x
                 join public.album_figurine f on f.id = (x ->> 'figurina_id')::bigint
                 join public.leagues l on l.id = s.league_id
                where f.stagione <> l.stagione_corrente);
