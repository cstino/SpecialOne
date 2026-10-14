-- Scelte al draft valutate meglio negli scambi (deciso il 15/10/2026):
-- 1) curva piu' ripida e convessa: la 1a scelta vale come un giocatore da 86, l'ultima come uno da 74
--    (prima: retta da 83,5 a 77, troppo piatta: la 12a valeva solo il 40% in piu' della 21a);
-- 2) una scelta di questa stagione senza posizione decisa si stima dalla classifica ATTUALE della squadra
--    d'origine (chi e' in fondo da' una scelta alta); per le stagioni successive resta a meta' classifica.
-- I voti congelati vengono ricalcolati tutti con il nuovo metro.

create or replace function private.posizione_attesa_scelta(p_team bigint, p_stagione integer, p_stagione_corrente integer, p_nsq integer)
 returns numeric language sql stable security definer set search_path to ''
as $$
  select coalesce(
    (select case when p_stagione = p_stagione_corrente then (
       -- 1 = la squadra con meno punti della lega (sceglie per prima)
       select count(*) + 1 from public.standings o
       where o.season_id = st.season_id
         and (o.punti < st.punti or (o.punti = st.punti and o.differenza_reti < st.differenza_reti))
     ) end
     from public.standings st
     join public.seasons se on se.id = st.season_id and se.stato = 'in_corso'
     where st.team_id = p_team
     limit 1),
    (p_nsq + 1) / 2.0)::numeric;
$$;

CREATE OR REPLACE FUNCTION private.calcola_valutazione_scambio(p_proposta_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tp public.trade_proposals;
  v_stagione smallint;
  v_nsq integer;
  v_da numeric; v_a numeric; v_det jsonb;
begin
  select * into v_tp from public.trade_proposals where id = p_proposta_id;
  if not found then return; end if;
  select stagione_corrente into v_stagione from public.leagues where id = v_tp.league_id;
  select greatest(2, count(*)) into v_nsq from public.teams where league_id = v_tp.league_id and attiva;

  with pezzi as (
    select x.lato, 'g'::text as tipo, p.nome as etichetta,
           pi.overall_corrente::numeric as ovr, pi.eta_corrente::numeric as eta,
           private.valore_proiettato(pi.overall_corrente, p.potential, pi.eta_corrente) as proiezione
    from (values ('da', v_tp.giocatori_offerti), ('a', v_tp.giocatori_richiesti)) as x(lato, ids)
    cross join lateral unnest(x.ids) as g(id)
    join public.player_instances pi on pi.id = g.id
    join public.players p on p.id = pi.player_id
    union all
    select x.lato, 's', upper(s.finestra) || '-Season ' || s.stagione || coalesce(' · n. ' || s.posizione, '') || ' (' || t.nome || ')',
           null, null,
           74 + 12 * power(1 - (coalesce(s.posizione, private.posizione_attesa_scelta(s.team_origine_id, s.stagione, v_stagione, v_nsq)) - 1) / (v_nsq - 1.0), 1.3)
             - greatest(0, s.stagione - v_stagione)
    from (values ('da', v_tp.scelte_offerte), ('a', v_tp.scelte_richieste)) as x(lato, ids)
    cross join lateral unnest(x.ids) as g(id)
    join public.scelte_draft s on s.id = g.id
    join public.teams t on t.id = s.team_origine_id
  ), valutati as (
    select pz.*, power(1.13, pz.proiezione - 70) as valore from pezzi pz
  )
  select coalesce(sum(valore) filter (where lato = 'da'), 0), coalesce(sum(valore) filter (where lato = 'a'), 0),
         coalesce(jsonb_agg(jsonb_build_object('lato', lato, 'tipo', tipo, 'etichetta', etichetta,
                  'overall', ovr, 'eta', eta, 'valore', round(valore, 2)) order by lato, valore desc), '[]'::jsonb)
  into v_da, v_a, v_det
  from valutati;

  insert into public.valutazioni_scambi (proposta_id, league_id, voto, valore_da, valore_a, dettaglio)
  values (p_proposta_id, v_tp.league_id,
          case when greatest(v_da, v_a) = 0 then 10 else round(10 * least(v_da, v_a) / greatest(v_da, v_a), 1) end,
          round(v_da, 2), round(v_a, 2), v_det)
  on conflict (proposta_id) do nothing;   -- calcolata una volta sola
end;
$function$;

delete from public.valutazioni_scambi;
select private.calcola_valutazione_scambio(id) from public.trade_proposals where stato = 'accettata';
