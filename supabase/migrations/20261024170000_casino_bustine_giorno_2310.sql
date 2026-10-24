-- Casino': il limite di 15 bustine al giorno dai crediti spesi si azzera alle 23:10, insieme alla ricarica dei 1.000
-- crediti, e non piu' a mezzanotte (24/10/2026, committente). Il "giorno" e' quello dei crediti: private.casino_settimana().
-- Funzioni riscritte dalla definizione viva.

CREATE OR REPLACE FUNCTION private.casino_bustine_speso(p_league_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_oggi date := private.casino_settimana(); v_date int;
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
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  select coalesce(sum(m.speso), 0) into v_speso from private.casino_movimenti(p_league_id) m where m.team_id = v.team_id;
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'bonus_aperto', (select jsonb_build_object('id', b.id, 'tipo', b.tipo) from public.casino_slot_bonus b where b.league_id = p_league_id and b.user_id = v_utente and b.stato = 'aperto' order by b.id limit 1),
    'bustina_spesi', greatest(0, v_speso - v.speso_base - 500 * v.bustine_speso),
    'bustine_oggi', case when v.bustine_giorno = private.casino_settimana() then v.bustine_oggi else 0 end,
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours 10 minutes') at time zone 'Europe/Rome'));
end $function$;
