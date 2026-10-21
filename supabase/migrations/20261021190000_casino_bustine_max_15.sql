-- Casino': al massimo 15 bustine al giorno (Europe/Rome) da crediti spesi (21/10/2026, committente).
-- Oltre il limite i 500 crediti spesi non si accumulano per il giorno dopo: bustine_speso avanza comunque.
-- Le bustine vinte allo SlotOne non contano nel limite. Oggi contano anche quelle gia' date (tutte del 21/10).

alter table public.casino_saldi
  add column bustine_giorno date,
  add column bustine_oggi integer not null default 0;

update public.casino_saldi set bustine_giorno = date '2026-10-21', bustine_oggi = bustine_speso where bustine_speso > 0;

create or replace function private.casino_bustine_speso(p_league_id bigint)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare r record; v_oggi date := (now() at time zone 'Europe/Rome')::date; v_date int;
begin
  if not private.album_attivo(p_league_id) then return; end if;
  -- skip locked: un saldo occupato da una giocata in corso si salta e si riprende al giro dopo (niente stalli)
  for r in
    select s.user_id, floor((m.speso - s.speso_base) / 500.0)::int as dovute, s.bustine_speso,
           case when s.bustine_giorno = v_oggi then s.bustine_oggi else 0 end as gia_oggi
      from public.casino_saldi s
      join (select team_id, sum(speso) as speso from private.casino_movimenti(p_league_id) group by team_id) m on m.team_id = s.team_id
     where s.league_id = p_league_id and floor((m.speso - s.speso_base) / 500.0)::int > s.bustine_speso
       for update of s skip locked
  loop
    v_date := least(r.dovute - r.bustine_speso, greatest(0, 15 - r.gia_oggi));
    update public.casino_saldi set bustine_gratis = bustine_gratis + v_date, bustine_speso = r.dovute,
           bustine_giorno = v_oggi, bustine_oggi = r.gia_oggi + v_date, aggiornato_il = now()
     where league_id = p_league_id and user_id = r.user_id;
  end loop;
end $function$;

-- Stato del casino': in piu' quante bustine da crediti spesi sono gia' arrivate oggi (limite 15).
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
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;
