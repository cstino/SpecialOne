-- Classifica del casinò per stagione (9/11/2026): miglior colpo, crediti spesi, profitto e giri contano solo le
-- giocate dall'inizio della stagione in corso (seasons.creata_il dell'ultima stagione della lega). Il saldo crediti
-- resta quello di sempre, non è una statistica.
-- private.casino_movimenti guadagna la colonna "il" (quando la giocata si è chiusa); le bustine continuano a
-- sommare tutto lo speso, come prima.

drop function private.casino_movimenti(bigint);

create function private.casino_movimenti(p_league_id bigint)
 returns table(gioco text, team_id bigint, speso bigint, vinto bigint, il timestamptz)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select 'slot', g.team_id, (case when g.gratis then 0 else g.puntata end)::bigint, g.vinto, g.creato_il from public.casino_giri g where g.league_id = p_league_id
  union all select 'crazy', g.team_id, g.totale::bigint, g.vinto, g.creato_il from public.casino_ct_giri g where g.league_id = p_league_id and not g.in_attesa
  union all select 'crazy', q.team_id, q.totale::bigint, q.vinto, g.esito_il from public.casino_ctl_giocate q join public.casino_ctl_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.regolato
  union all select 'aviat', v.team_id, v.totale::bigint, v.vinto, coalesce(v.finito_il, v.partito_il) from public.casino_av_voli v where v.league_id = p_league_id and v.finito
  union all select 'aviat', q.team_id, q.puntata::bigint, q.vinto, g.finisce_il from public.casino_av_giocate q join public.casino_av_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.finisce_il <= now()
  union all select 'roul', q.team_id, q.totale::bigint, q.vinto, g.esito_il from public.casino_rl_giocate q join public.casino_rl_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.regolato
  union all select 'bj', m.team_id, ((select coalesce(sum((x ->> 'puntata')::int), 0) from jsonb_array_elements(m.mani) x) + m.assicurazione)::bigint, m.vinto, coalesce(m.finito_il, m.creato_il) from public.casino_bj_mani m where m.league_id = p_league_id and m.stato = 'finita'
  union all select 'bj', s.team_id, s.puntato::bigint, s.vinto, s.creato_il from public.casino_bjl_storico s where s.league_id = p_league_id
$function$;

revoke all on function private.casino_movimenti(bigint) from public;

create or replace function public.casino_classifica_giochi(p_league_id bigint, p_gioco text default null)
 returns table(team_id bigint, miglior_colpo bigint, spesi bigint, profitto bigint, giri bigint, crediti bigint)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select m.team_id, max(m.vinto), sum(m.speso), sum(m.vinto) - sum(m.speso), count(*),
         (select s.crediti from public.casino_saldi s join public.teams t on t.user_id = s.user_id and t.league_id = s.league_id where t.id = m.team_id and s.league_id = p_league_id)
    from private.casino_movimenti(p_league_id) m
   where (select private.e_membro(p_league_id)) and (p_gioco is null or m.gioco = p_gioco)
     and m.il >= coalesce((select s.creata_il from public.seasons s where s.league_id = p_league_id order by s.numero desc limit 1), '-infinity')
   group by m.team_id
$function$;
