-- Casino': i 1.000 crediti giornalieri e i premi partita arrivano alle 23:10 (ora di Roma) invece che alle 23:00
-- (24/10/2026, committente). Il "giorno" dei crediti cambia alle 23:10; un premio partita si puo' incassare solo dalle
-- 23:10 della sera in cui la partita e' stata simulata (prima si pagava appena la si guardava, dalle 23:00).
-- Le funzioni sono riscritte dalla definizione viva.
create or replace function private.casino_settimana()
returns date language sql stable set search_path = '' as $f$ select ((now() at time zone 'Europe/Rome') + interval '50 minutes')::date $f$;

CREATE OR REPLACE FUNCTION private.casino_premi_partita(p_league_id bigint, p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_tot integer := 0; v_esito text; v_crediti integer;
begin
  for r in
    select m.id as match_id, t.id as team_id,
           case when f.home_team_id = t.id then f.away_team_id else f.home_team_id end as avversario,
           case when f.home_team_id = t.id then m.gol_home else m.gol_away end as gf,
           case when f.home_team_id = t.id then m.gol_away else m.gol_home end as gs,
           case when f.home_team_id = t.id then m.rigori_home else m.rigori_away end as rf,
           case when f.home_team_id = t.id then m.rigori_away else m.rigori_home end as rs
      from public.teams t
      join public.fixtures f on f.league_id = t.league_id and t.id in (f.home_team_id, f.away_team_id)
      join public.matches m on m.fixture_id = f.id
     where t.league_id = p_league_id and t.user_id = p_user and t.attiva
       and m.id > 1513
       -- non prima delle 23:10 della sera in cui la partita e' stata simulata (le 6 ore di margine reggono una simulazione in ritardo oltre la mezzanotte)
       and now() >= ((((coalesce(m.simulata_il, 'epoch'::timestamptz) at time zone 'Europe/Rome') - interval '6 hours')::date)::timestamp + interval '23 hours 10 minutes') at time zone 'Europe/Rome'
       and not exists (select 1 from public.casino_premi_partita p where p.match_id = m.id and p.user_id = p_user)
       and (exists (select 1 from public.match_reveals mr where mr.match_id = m.id and mr.user_id = p_user)
            or m.simulata_il < now() - interval '24 hours')
  loop
    v_esito := case when r.gf > r.gs then 'vittoria' when r.gf < r.gs then 'sconfitta'
                    when r.rf is not null and r.rs is not null and r.rf <> r.rs then case when r.rf > r.rs then 'vittoria' else 'sconfitta' end
                    else 'pareggio' end;
    v_crediti := case v_esito when 'vittoria' then 300 when 'pareggio' then 150 else 100 end;
    insert into public.casino_premi_partita (match_id, user_id, league_id, team_id, esito, avversario_id, crediti)
    values (r.match_id, p_user, p_league_id, r.team_id, v_esito, r.avversario, v_crediti)
    on conflict do nothing;
    if found then v_tot := v_tot + v_crediti; end if;
  end loop;
  if v_tot > 0 then
    update public.casino_saldi set crediti = crediti + v_tot, aggiornato_il = now() where league_id = p_league_id and user_id = p_user;
  end if;
  return v_tot;
end $function$;

CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  v_speso bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.casino_bustine_speso(p_league_id);
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  select coalesce(sum(m.speso), 0) into v_speso from private.casino_movimenti(p_league_id) m where m.team_id = v.team_id;
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'bustina_spesi', greatest(0, v_speso - v.speso_base - 500 * v.bustine_speso),
    'bustine_oggi', case when v.bustine_giorno = (now() at time zone 'Europe/Rome')::date then v.bustine_oggi else 0 end,
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours 10 minutes') at time zone 'Europe/Rome'));
end $function$;
