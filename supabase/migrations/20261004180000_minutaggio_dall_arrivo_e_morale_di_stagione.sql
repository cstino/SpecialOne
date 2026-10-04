-- ============================================================
--  MINUTAGGIO: si conta dall'arrivo in squadra, anche nel morale
--  Segnalazione del 4 ottobre 2026: chi arriva in corso (draft di meta'
--  stagione, scambi, free agent) si lamentava del poco minutaggio perche' lo
--  si misurava dall'inizio della stagione.
--
--  Due difetti:
--  1. private.minuti_stagione partiva dall'arrivo solo se arrivo_stagione
--     coincideva con la stagione corrente: i giocatori arrivati PRIMA della
--     migrazione del minutaggio hanno quella colonna vuota e contavano dalla
--     giornata 1. Non serve: giornata_acquisizione viene azzerata a ogni inizio
--     stagione (private.inizializza_stagione), quindi se e' valorizzata
--     riguarda sempre la stagione corrente.
--  2. Il morale (applica_morale_checkpoint) sommava i minuti di TUTTE le
--     stagioni e li divideva per le partite della squadra in questa: chi arrivava
--     in corso risultava sotto, e dalla stagione 2 chiunque avrebbe avuto i
--     minuti della stagione 1 in piu'. Ora usa private.minuti_stagione: sola
--     stagione corrente, dall'arrivo, senza le partite da assente. Con meno di
--     3 partite giocabili la voce minuti non pesa.
-- ============================================================

begin;

create or replace function private.minuti_stagione(p_instance_id bigint)
returns table(partite integer, minuti numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with g as (
    select pi.id, pi.team_id, pi.league_id,
           coalesce(pi.giornata_acquisizione, 1) as inizio,
           l.giornate_totali, l.stagione_corrente
    from public.player_instances pi
    join public.leagues l on l.id = pi.league_id
    where pi.id = p_instance_id
  ), f as (
    select fx.id as fixture_id
    from g
    join public.seasons s on s.league_id = g.league_id and s.numero = g.stagione_corrente
    join public.fixtures fx on fx.season_id = s.id and fx.stato = 'simulata'
      and fx.giornata between g.inizio and g.giornate_totali
      and (fx.home_team_id = g.team_id or fx.away_team_id = g.team_id)
    where not exists (select 1 from private.assenze_partita a
                      where a.fixture_id = fx.id and a.player_instance_id = g.id)
  )
  select (select count(*) from f)::integer,
         coalesce((select sum(ms.minuti) from public.match_stats ms
                   join public.matches m on m.id = ms.match_id
                   join f on f.fixture_id = m.fixture_id
                   join g on true
                   where ms.player_instance_id = g.id and ms.team_id = g.team_id), 0)::numeric;
$$;

do $$
declare
  v_def text := pg_get_functiondef('public.applica_morale_checkpoint(bigint, smallint)'::regprocedure);
  v_a text;
  v_b text;
begin
  v_a := E'        coalesce((select sum(ms.minuti)::numeric\n                    from public.match_stats ms\n                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,\n        greatest(1, (select count(*)\n                       from public.fixtures f\n                      where f.season_id = v_stagione_id and f.stato = ''simulata''\n                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate,\n';
  if position(v_a in v_def) = 0 then raise exception 'morale: blocco dei minuti non trovato'; end if;
  v_def := replace(v_def, v_a,
    E'        coalesce((select ms.minuti from private.minuti_stagione(pi.id) ms), 0) as minuti_giocati,\n        coalesce((select ms.partite from private.minuti_stagione(pi.id) ms), 0) as giornate_disputate,\n');

  v_a := E'      v_delta_min := greatest(-12, least(8,\n        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))';
  if position(v_a in v_def) = 0 then raise exception 'morale: formula dei minuti non trovata'; end if;
  v_def := replace(v_def, v_a,
    E'      -- Dall''arrivo in squadra, solo stagione corrente, senza le partite da\n      -- assente; con meno di 3 partite giocabili la voce non pesa.\n      v_delta_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,\n        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))');

  v_b := E'        ) * 30\n      ));\n';
  if position(v_b in v_def) = 0 then raise exception 'morale: chiusura della formula non trovata'; end if;
  v_def := replace(v_def, v_b, E'        ) * 30\n      )) end;\n');

  execute v_def;
end;
$$;

commit;
