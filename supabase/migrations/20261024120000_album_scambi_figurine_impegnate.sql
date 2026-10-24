-- Scambi di figurine: una figurina impegnata in uno scambio in attesa non si puo' mettere in un altro (24/10/2026, committente).
-- Prima si potevano proporre piu' scambi con le stesse figurine: appena uno veniva accettato gli altri non erano piu'
-- validi e restavano a meta'. Ora si conta, per ogni utente, quante copie sono gia' dentro proposte in attesa (e non scadute),
-- sia come figurine offerte da lui sia come figurine che altri gli chiedono, e si possono usare solo i doppioni rimasti liberi.
-- Anche il riciclo dei doppioni lascia stare quelli impegnati.

-- Quante copie di ogni figurina un utente ha dentro scambi in attesa. p_escludi: uno scambio da non contare
-- (la proposta originale, quando la si sta controproponendo, perche' viene chiusa).
create or replace function private.album_impegnate(p_league_id bigint, p_user uuid, p_escludi bigint default null)
 returns table(figurina_id bigint, ultra boolean, n integer)
 language sql stable security definer set search_path to ''
as $function$
  select (x ->> 'figurina_id')::bigint, coalesce((x ->> 'ultra')::boolean, false), count(*)::integer
    from public.album_scambi s
   cross join lateral jsonb_array_elements(case when s.da_user = p_user then s.offerte else s.richieste end) x
   where s.league_id = p_league_id and s.stato = 'in_attesa' and s.scade_il > now()
     and (s.da_user = p_user or s.a_user = p_user)
     and (p_escludi is null or s.id <> p_escludi)
   group by 1, 2
$function$;

-- Come album_ha_doppioni, ma tenendo conto delle copie gia' impegnate in altri scambi.
create or replace function private.album_ha_doppioni_liberi(p_league_id bigint, p_user uuid, p_voci jsonb, p_escludi bigint default null)
 returns boolean
 language sql stable security definer set search_path to ''
as $function$
  select coalesce(bool_and(
    coalesce((select case when v.ultra then ap.ultra else ap.normali end from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id), 0) - 1
    - coalesce((select i.n from private.album_impegnate(p_league_id, p_user, p_escludi) i where i.figurina_id = v.figurina_id and i.ultra = v.ultra), 0)
    >= v.n), false)
  from (select (x ->> 'figurina_id')::bigint as figurina_id, coalesce((x ->> 'ultra')::boolean, false) as ultra, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$function$;

-- Doppioni di una squadra, con quanti sono gia' impegnati in scambi in attesa (nuova colonna 'impegnate').
drop function public.album_doppioni(bigint, bigint);
create function public.album_doppioni(p_league_id bigint, p_team_id bigint)
 returns table(figurina_id bigint, ultra boolean, copie integer, impegnate integer)
 language sql stable security definer set search_path to ''
as $function$
  with d as (
    select ap.figurina_id, false as ultra, ap.normali - 1 as copie, t.user_id from public.album_possesso ap
      join public.teams t on t.user_id = ap.user_id and t.league_id = p_league_id and t.id = p_team_id
     where ap.league_id = p_league_id and ap.normali > 1 and (select private.e_membro(p_league_id))
    union all
    select ap.figurina_id, true, ap.ultra - 1, t.user_id from public.album_possesso ap
      join public.teams t on t.user_id = ap.user_id and t.league_id = p_league_id and t.id = p_team_id
     where ap.league_id = p_league_id and ap.ultra > 1 and (select private.e_membro(p_league_id))
  ), imp as (select * from private.album_impegnate(p_league_id, (select user_id from d limit 1)))
  select d.figurina_id, d.ultra, d.copie, coalesce(i.n, 0)::integer
    from d left join imp i on i.figurina_id = d.figurina_id and i.ultra = d.ultra
$function$;
revoke all on function public.album_doppioni(bigint, bigint) from public, anon;
grant execute on function public.album_doppioni(bigint, bigint) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.album_proponi_scambio(p_league_id bigint, p_a_team_id bigint, p_offerte jsonb, p_richieste jsonb, p_controproposta_di bigint DEFAULT NULL::bigint)
 RETURNS album_scambi
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_mia public.teams;
  v_dest public.teams;
  v_s public.album_scambi;
  v_orig public.album_scambi;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  -- Un solo proponente alla volta per lega: due proposte insieme non possono impegnare la stessa figurina.
  perform pg_advisory_xact_lock(hashtext('album_scambi'), p_league_id::int);
  if not private.album_attivo(p_league_id) then raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.'; end if;
  select * into v_mia from public.teams where league_id = p_league_id and user_id = v_utente and attiva;
  select * into v_dest from public.teams where id = p_a_team_id and league_id = p_league_id and attiva;
  if v_mia.id is null or v_dest.id is null or v_dest.user_id is null or v_dest.controllata_da_pc then
    raise exception using errcode = '22023', message = 'Squadra non valida per uno scambio di figurine.';
  end if;
  if v_mia.id = v_dest.id then raise exception using errcode = '22023', message = 'Non puoi scambiare con te stesso.'; end if;
  if jsonb_typeof(p_offerte) <> 'array' or jsonb_typeof(p_richieste) <> 'array' or jsonb_array_length(p_offerte) = 0 or jsonb_array_length(p_richieste) = 0 then
    raise exception using errcode = '22023', message = 'Serve almeno una figurina per parte: niente regali.';
  end if;
  if jsonb_array_length(p_offerte) > 15 or jsonb_array_length(p_richieste) > 15 then
    raise exception using errcode = '22023', message = 'Al massimo 15 figurine per parte.';
  end if;
  if not private.album_ha_doppioni(p_league_id, v_utente, p_offerte) then
    raise exception using errcode = '22023', message = 'Puoi offrire solo i tuoi doppioni.';
  end if;
  if not private.album_ha_doppioni(p_league_id, v_dest.user_id, p_richieste) then
    raise exception using errcode = '22023', message = 'Puoi chiedere solo i doppioni dell''altra squadra.';
  end if;
  if not private.album_ha_doppioni_liberi(p_league_id, v_utente, p_offerte, p_controproposta_di) then
    raise exception using errcode = '22023', message = 'Una o più figurine che offri sono già dentro un altro scambio in attesa: ritira prima quella proposta.';
  end if;
  if not private.album_ha_doppioni_liberi(p_league_id, v_dest.user_id, p_richieste, p_controproposta_di) then
    raise exception using errcode = '22023', message = 'Una o più figurine che chiedi sono già dentro un altro scambio in attesa: riprova più tardi.';
  end if;
  if p_controproposta_di is not null then
    select * into v_orig from public.album_scambi where id = p_controproposta_di for update;
    if v_orig.id is null or v_orig.a_user <> v_utente or v_orig.stato <> 'in_attesa' then
      raise exception using errcode = '22023', message = 'Controproposta non valida.';
    end if;
    update public.album_scambi set stato = 'rifiutato', risolto_il = now() where id = v_orig.id;
  end if;
  insert into public.album_scambi (league_id, da_user, a_user, da_team_id, a_team_id, offerte, richieste, controproposta_di)
  values (p_league_id, v_utente, v_dest.user_id, v_mia.id, v_dest.id, p_offerte, p_richieste, p_controproposta_di)
  returning * into v_s;
  perform private.notifica(v_dest.user_id, p_league_id, 'sistema', 'Scambio di figurine',
    v_mia.nome || ' ti propone uno scambio di figurine: hai 24 ore per rispondere.', jsonb_build_object('view', 'album', 'album_scambio_id', v_s.id));
  return v_s;
end $function$;

CREATE OR REPLACE FUNCTION public.album_ricicla_doppioni(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_n int; v_u int; v_crediti int;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  -- Stesso blocco di chi propone scambi; le copie dentro scambi in attesa non si riciclano.
  perform pg_advisory_xact_lock(hashtext('album_scambi'), p_league_id::int);
  with imp as (select * from private.album_impegnate(p_league_id, v_utente))
  select coalesce(sum(greatest(0, p.normali - 1 - coalesce(i.n, 0))), 0), coalesce(sum(greatest(0, p.ultra - 1 - coalesce(u.n, 0))), 0) into v_n, v_u
  from public.album_possesso p
  left join imp i on i.figurina_id = p.figurina_id and not i.ultra
  left join imp u on u.figurina_id = p.figurina_id and u.ultra
  where p.league_id = p_league_id and p.user_id = v_utente;
  v_crediti := v_n * 10 + v_u * 50;
  if v_crediti = 0 then return jsonb_build_object('riciclati', 0, 'crediti_guadagnati', 0); end if;
  perform private.casino_saldo(p_league_id, v_utente);
  with imp as (select * from private.album_impegnate(p_league_id, v_utente))
  update public.album_possesso p set
    normali = least(p.normali, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and not i.ultra), 0)),
    ultra = least(p.ultra, 1 + coalesce((select i.n from imp i where i.figurina_id = p.figurina_id and i.ultra), 0))
   where p.league_id = p_league_id and p.user_id = v_utente;
  update public.casino_saldi set crediti = crediti + v_crediti, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('riciclati', v_n + v_u, 'crediti_guadagnati', v_crediti,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
