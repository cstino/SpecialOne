-- Casino': una bustina di figurine gratis ogni 500 crediti spesi nei giochi del casino' (21/10/2026, committente).
-- Conta tutto quello che c'e' in private.casino_movimenti (SlotOne, CrazyOne, AviatOne, BlackjackOne; non QuizOne
-- ne' SchedOne), solo da adesso: speso_base fotografa quanto ogni squadra aveva gia' speso. Le bustine finiscono in
-- casino_saldi.bustine_gratis, le stesse vinte allo SlotOne, e si aprono dall'album senza crediti.

alter table public.casino_saldi
  add column speso_base bigint not null default 0,
  add column bustine_speso integer not null default 0;

update public.casino_saldi s set speso_base = m.speso
  from (select l.id as league_id, m.team_id, sum(m.speso) as speso
          from public.leagues l cross join lateral private.casino_movimenti(l.id) m group by l.id, m.team_id) m
 where m.league_id = s.league_id and m.team_id = s.team_id;

-- Assegna le bustine maturate in una lega. Idempotente: bustine_speso tiene il conto di quelle gia' date.
create or replace function private.casino_bustine_speso(p_league_id bigint)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare r record;
begin
  if not private.album_attivo(p_league_id) then return; end if;
  -- skip locked: un saldo occupato da una giocata in corso si salta e si riprende al giro dopo (niente stalli)
  for r in
    select s.user_id, floor((m.speso - s.speso_base) / 500.0)::int as dovute, s.bustine_speso
      from public.casino_saldi s
      join (select team_id, sum(speso) as speso from private.casino_movimenti(p_league_id) group by team_id) m on m.team_id = s.team_id
     where s.league_id = p_league_id and floor((m.speso - s.speso_base) / 500.0)::int > s.bustine_speso
       for update of s skip locked
  loop
    update public.casino_saldi set bustine_gratis = bustine_gratis + (r.dovute - r.bustine_speso), bustine_speso = r.dovute, aggiornato_il = now()
     where league_id = p_league_id and user_id = r.user_id;
  end loop;
end $function$;

create or replace function private.casino_bustine_cron()
 returns void language plpgsql security definer set search_path to ''
as $function$
declare l record;
begin
  for l in select id from public.leagues where conferenze_stampa loop
    perform private.casino_bustine_speso(l.id);
  end loop;
end $function$;

select cron.schedule('casino_bustine', '* * * * *', 'select private.casino_bustine_cron();');

-- Stato del casino': come prima, in piu' assegna le bustine maturate e dice quanto manca alla prossima.
create or replace function public.casino_stato(p_league_id bigint)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
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
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;
