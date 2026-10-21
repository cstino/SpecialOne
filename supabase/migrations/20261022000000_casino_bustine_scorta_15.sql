-- Casino': oltre al limite di 15 al giorno, al massimo 15 bustine gratis non aperte (22/10/2026, committente).
-- Finche' se ne hanno 15 da aprire non se ne ricevono altre, anche se passano i giorni: i crediti spesi intanto
-- non si accumulano. Chi ne aveva piu' di 15 scende a 15.

update public.casino_saldi set bustine_gratis = 15 where bustine_gratis > 15;

create or replace function private.casino_bustine_speso(p_league_id bigint)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare r record; v_oggi date := (now() at time zone 'Europe/Rome')::date; v_date int;
begin
  if not private.album_attivo(p_league_id) then return; end if;
  -- skip locked: un saldo occupato da una giocata in corso si salta e si riprende al giro dopo (niente stalli)
  for r in
    select s.user_id, floor((m.speso - s.speso_base) / 500.0)::int as dovute, s.bustine_speso, s.bustine_gratis,
           case when s.bustine_giorno = v_oggi then s.bustine_oggi else 0 end as gia_oggi
      from public.casino_saldi s
      join (select team_id, sum(speso) as speso from private.casino_movimenti(p_league_id) group by team_id) m on m.team_id = s.team_id
     where s.league_id = p_league_id and floor((m.speso - s.speso_base) / 500.0)::int > s.bustine_speso
       for update of s skip locked
  loop
    -- limite al giorno (15) e scorta massima da aprire (15); quello che eccede si perde
    v_date := greatest(0, least(r.dovute - r.bustine_speso, 15 - r.gia_oggi, 15 - r.bustine_gratis));
    update public.casino_saldi set bustine_gratis = bustine_gratis + v_date, bustine_speso = r.dovute,
           bustine_giorno = v_oggi, bustine_oggi = r.gia_oggi + v_date, aggiornato_il = now()
     where league_id = p_league_id and user_id = r.user_id;
  end loop;
end $function$;
