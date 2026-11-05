-- Season 3, diario §8: figurine in quattro rarità (common, rare, ultrarara, ultimate).
-- * Lo stesso giocatore esiste in piu' versioni, secondo l'overall: common per tutti, rare da 70, ultrarara da 78,
--   ultimate da 83. Stemmi e conference esistono solo ultimate.
-- * Per ogni figurina: 5% stemma o conference (le conference al 10% di quel 5%, dove esistono); 95% giocatore, di cui
--   common 75%, rare 18%, ultrarara 6%, ultimate 1% (se nessun giocatore ha quella versione si scende alla precedente).
-- * album_possesso: normali = common e ultra = ultrarara come prima, piu' rare e ultimate. Le figurine gia' possedute
--   restano dove sono (normali -> common, ultra -> ultrarara).
-- * Negli scambi una voce e' {figurina_id, versione}; le voci vecchie {figurina_id, ultra} valgono ancora.
-- * Riciclo dei doppioni: common 10, rare 25, ultrarara 50, ultimate 150 crediti.
-- Funzioni ricostruite dalla definizione live.

alter table public.album_possesso add column if not exists rare integer not null default 0 check (rare >= 0);
alter table public.album_possesso add column if not exists ultimate integer not null default 0 check (ultimate >= 0);

-- Versione di una voce di scambio, anche nel formato vecchio.
create or replace function private.album_versione(p_voce jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select coalesce(nullif(p_voce ->> 'versione', ''),
                  case when coalesce((p_voce ->> 'ultra')::boolean, false) then 'ultra' else 'common' end)
$$;

-- Copie possedute di una versione.
create or replace function private.album_n(p_normali integer, p_rare integer, p_ultra integer, p_ultimate integer, p_versione text)
returns integer
language sql
immutable
set search_path to ''
as $$
  select case p_versione when 'rare' then p_rare when 'ultra' then p_ultra when 'ultimate' then p_ultimate else p_normali end
$$;
revoke all on function private.album_versione(jsonb) from public, anon, authenticated;
revoke all on function private.album_n(integer, integer, integer, integer, text) from public, anon, authenticated;

drop function private.album_impegnate(bigint, uuid, bigint);
create function private.album_impegnate(p_league_id bigint, p_user uuid, p_escludi bigint DEFAULT NULL::bigint)
 RETURNS TABLE(figurina_id bigint, versione text, n integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (x ->> 'figurina_id')::bigint, private.album_versione(x), count(*)::integer
    from public.album_scambi s
   cross join lateral jsonb_array_elements(case when s.da_user = p_user then s.offerte else s.richieste end) x
   where s.league_id = p_league_id and s.stato = 'in_attesa' and s.scade_il > now()
     and (s.da_user = p_user or s.a_user = p_user)
     and (p_escludi is null or s.id <> p_escludi)
   group by 1, 2
$function$;

CREATE OR REPLACE FUNCTION private.album_sposta(p_league_id bigint, p_da uuid, p_a uuid, p_voci jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;
begin
  for v in select (x->>'figurina_id')::bigint as figurina_id, private.album_versione(x) as ver from jsonb_array_elements(p_voci) x loop
    update public.album_possesso set
      normali = normali - (v.ver = 'common')::int, rare = rare - (v.ver = 'rare')::int,
      ultra = ultra - (v.ver = 'ultra')::int, ultimate = ultimate - (v.ver = 'ultimate')::int
     where user_id = p_da and figurina_id = v.figurina_id;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, rare, ultra, ultimate)
    values (p_league_id, p_a, v.figurina_id, (v.ver = 'common')::int, (v.ver = 'rare')::int, (v.ver = 'ultra')::int, (v.ver = 'ultimate')::int)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + (v.ver = 'common')::int,
      rare = public.album_possesso.rare + (v.ver = 'rare')::int,
      ultra = public.album_possesso.ultra + (v.ver = 'ultra')::int,
      ultimate = public.album_possesso.ultimate + (v.ver = 'ultimate')::int;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION private.album_ha_doppioni(p_league_id bigint, p_user uuid, p_voci jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(bool_and(
    coalesce((select private.album_n(ap.normali, ap.rare, ap.ultra, ap.ultimate, v.ver) from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id), 0) - 1 >= v.n), false)
  from (select (x->>'figurina_id')::bigint as figurina_id, private.album_versione(x) as ver, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$function$;

CREATE OR REPLACE FUNCTION private.album_ha_doppioni_liberi(p_league_id bigint, p_user uuid, p_voci jsonb, p_escludi bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(bool_and(
    coalesce((select private.album_n(ap.normali, ap.rare, ap.ultra, ap.ultimate, v.ver) from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id), 0) - 1
    - coalesce((select i.n from private.album_impegnate(p_league_id, p_user, p_escludi) i where i.figurina_id = v.figurina_id and i.versione = v.ver), 0)
    >= v.n), false)
  from (select (x ->> 'figurina_id')::bigint as figurina_id, private.album_versione(x) as ver, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$function$;

drop function public.album_doppioni(bigint, bigint);
create function public.album_doppioni(p_league_id bigint, p_team_id bigint)
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
  ), imp as (select * from private.album_impegnate(p_league_id, (select user_id from d limit 1)))
  select d.figurina_id, d.ver, d.copie, coalesce(i.n, 0)::integer
    from d left join imp i on i.figurina_id = d.figurina_id and i.versione = d.ver
   where d.copie > 0
$function$;
revoke all on function public.album_doppioni(bigint, bigint) from public;
grant execute on function public.album_doppioni(bigint, bigint) to authenticated, service_role;

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
     and not exists (
       select 1 from public.album_possesso a
         join public.teams t on t.user_id = a.user_id and t.league_id = p_league_id and t.id = p_team_id
        where a.league_id = p_league_id and a.figurina_id = m.figurina_id and a.normali + a.rare + a.ultra + a.ultimate > 0)
$function$;

-- Classifica: "ultra" ora conta le figurine possedute in versione ultrarara o ultimate.
CREATE OR REPLACE FUNCTION public.album_classifica(p_league_id bigint)
 RETURNS TABLE(team_id bigint, attaccate integer, totale integer, ultra integer, pagine integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with st as (select stagione_corrente s from public.leagues where id = p_league_id),
  tot as (select count(*)::int n from public.album_figurine f, st where f.league_id = p_league_id and f.stagione = st.s and f.tipo in ('stemma','giocatore') and not f.aggiornamento)
  select t.id,
         count(*) filter (where f.tipo in ('stemma','giocatore') and not f.aggiornamento and ap.normali + ap.rare + ap.ultra + ap.ultimate > 0)::int,
         (select n from tot),
         count(*) filter (where ap.ultra > 0 or ap.ultimate > 0)::int,
         (select count(*)::int from public.album_premi pr, st where pr.league_id = p_league_id and pr.user_id = ap.user_id and pr.stagione = st.s and pr.chiave like 'pagina:%')
  from public.album_possesso ap
  join public.album_figurine f on f.id = ap.figurina_id
  join st on f.stagione = st.s
  join public.teams t on t.league_id = p_league_id and t.user_id = ap.user_id
  where ap.league_id = p_league_id and (select private.e_membro(p_league_id))
  group by t.id, ap.user_id
  order by 2 desc, 4 desc, 1
$function$;

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
    where p.league_id = p_league_id and p.user_id = v_utente)
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
   where p.league_id = p_league_id and p.user_id = v_utente;
  update public.casino_saldi set crediti = crediti + v_crediti, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('riciclati', v_n, 'crediti_guadagnati', v_crediti,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;

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
    having bool_and(exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.rare + ap.ultra + ap.ultimate > 0))
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
      and not exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.rare + ap.ultra + ap.ultimate > 0))
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

CREATE OR REPLACE FUNCTION public.album_compra_bustina(p_league_id bigint, p_gratis boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_saldo public.casino_saldi;
  v_stag smallint;
  v_k int;
  v_r numeric;
  v_ver text;
  v_min smallint;
  v_fig public.album_figurine;
  v_nuova boolean;
  v_out jsonb := '[]'::jsonb;
  c_prezzo constant int := 250;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.album_attivo(p_league_id) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  -- Bustina gratis (vinta al casino'): non costa crediti.
  if p_gratis then
    if v_saldo.bustine_gratis < 1 then raise exception using errcode = '22023', message = 'Non hai bustine gratis.'; end if;
  elsif v_saldo.crediti < c_prezzo then raise exception using errcode = '22023', message = 'Crediti insufficienti: una bustina costa 250 crediti.'; end if;
  v_stag := private.album_sincronizza(p_league_id);
  update public.casino_saldi set
    crediti = crediti - (case when p_gratis then 0 else c_prezzo end),
    bustine_gratis = bustine_gratis - (case when p_gratis then 1 else 0 end), aggiornato_il = now()
  where league_id = p_league_id and user_id = v_utente;

  for v_k in 1..3 loop
    v_fig := null;
    if random() < 0.05 then
      -- Stemma o conference, sempre ultimate. Le conference (dove esistono) sono un decimo di questo 5%.
      v_ver := 'ultimate';
      if exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
      end if;
    end if;
    if v_fig.id is null then
      -- Giocatore: prima la rarita', poi il giocatore fra quelli che hanno quella versione (overall minimo).
      v_r := random();
      v_ver := case when v_r < 0.75 then 'common' when v_r < 0.93 then 'rare' when v_r < 0.99 then 'ultra' else 'ultimate' end;
      loop
        v_min := case v_ver when 'ultimate' then 83 when 'ultra' then 78 when 'rare' then 70 else 0 end;
        -- I piu' forti escono piu' di rado: peso = 100 - overall (minimo 5). Estrazione pesata con chiave esponenziale.
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
          and coalesce(overall, 0) >= v_min
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
        exit when v_fig.id is not null or v_ver = 'common';
        v_ver := case v_ver when 'ultimate' then 'ultra' when 'ultra' then 'rare' else 'common' end;
      end loop;
    end if;
    if v_fig.id is null then continue; end if;
    select not exists (select 1 from public.album_possesso where user_id = v_utente and figurina_id = v_fig.id
                        and private.album_n(normali, rare, ultra, ultimate, v_ver) > 0) into v_nuova;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, rare, ultra, ultimate)
    values (p_league_id, v_utente, v_fig.id, (v_ver = 'common')::int, (v_ver = 'rare')::int, (v_ver = 'ultra')::int, (v_ver = 'ultimate')::int)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + (v_ver = 'common')::int,
      rare = public.album_possesso.rare + (v_ver = 'rare')::int,
      ultra = public.album_possesso.ultra + (v_ver = 'ultra')::int,
      ultimate = public.album_possesso.ultimate + (v_ver = 'ultimate')::int;
    v_out := v_out || jsonb_build_object('figurina_id', v_fig.id, 'tipo', v_fig.tipo, 'team_id', v_fig.team_id, 'player_id', v_fig.player_id,
      'conferenza', v_fig.conferenza, 'versione', v_ver, 'ultra', v_ver in ('ultra', 'ultimate'), 'nuova', v_nuova);
  end loop;

  insert into public.album_bustine (league_id, user_id, contenuto) values (p_league_id, v_utente, v_out);
  return jsonb_build_object('figurine', v_out, 'premi', private.album_controlla_premi(p_league_id, v_utente, v_stag),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente),
    'bustine_gratis', (select bustine_gratis from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
