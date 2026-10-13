-- Voto di equilibrio degli scambi conclusi (0 = squilibrato, 10 = equilibrato), sui valori di OGGI.
-- Valore di un giocatore: overall + una quota della crescita che manca al potenziale (piu' e' giovane piu' conta),
-- meno un calo oltre i 30 anni; poi 1,13^(valore-70), cosi' un campione vale piu' di due giocatori discreti.
-- Scelte: come un giocatore da 83,5 (1a scelta) a 77 (ultima), a meta' classifica se la posizione non e' nota,
-- meno 1 punto per ogni stagione di distanza. In un pacchetto il 2o, 3o... pezzo conta un po' meno (11 posti in campo).
create or replace function private.valore_proiettato(p_ovr numeric, p_pot numeric, p_eta numeric)
 returns numeric language sql immutable set search_path to ''
as $$
  select p_ovr
       + (case when p_eta <= 21 then 0.6 when p_eta <= 23 then 0.45 when p_eta <= 26 then 0.3 when p_eta <= 29 then 0.1 else 0 end)
         * greatest(0, coalesce(p_pot, p_ovr) - p_ovr)
       - (case when p_eta <= 30 then 0 when p_eta <= 32 then 1.5 when p_eta <= 34 then 3 else 5 end);
$$;

create or replace function public.valutazione_scambi(p_league_id bigint)
 returns table(proposta_id bigint, voto numeric, valore_da numeric, valore_a numeric, dettaglio jsonb)
 language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_stagione smallint;
  v_nsq integer;
begin
  if not private.e_membro(p_league_id) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  select stagione_corrente into v_stagione from public.leagues where id = p_league_id;
  select greatest(2, count(*)) into v_nsq from public.teams where league_id = p_league_id and attiva;

  return query
  with pezzi as (
    -- lato 'da' = cio' che cede chi ha proposto; lato 'a' = cio' che cede chi ha accettato
    select tp.id, x.lato, 'g'::text as tipo, p.nome as etichetta,
           pi.overall_corrente::numeric as ovr, pi.eta_corrente::numeric as eta,
           private.valore_proiettato(pi.overall_corrente, p.potential, pi.eta_corrente) as proiezione
    from public.trade_proposals tp
    cross join lateral (values ('da', tp.giocatori_offerti), ('a', tp.giocatori_richiesti)) as x(lato, ids)
    cross join lateral unnest(x.ids) as g(id)
    join public.player_instances pi on pi.id = g.id
    join public.players p on p.id = pi.player_id
    where tp.league_id = p_league_id and tp.stato = 'accettata'
    union all
    select tp.id, x.lato, 's', upper(s.finestra) || '-Season ' || s.stagione || coalesce(' · n. ' || s.posizione, '') || ' (' || t.nome || ')',
           null, null,
           83.5 - 6.5 * (coalesce(s.posizione, (v_nsq + 1) / 2.0) - 1) / (v_nsq - 1)
             - greatest(0, s.stagione - v_stagione)
    from public.trade_proposals tp
    cross join lateral (values ('da', tp.scelte_offerte), ('a', tp.scelte_richieste)) as x(lato, ids)
    cross join lateral unnest(x.ids) as g(id)
    join public.scelte_draft s on s.id = g.id
    join public.teams t on t.id = s.team_origine_id
    where tp.league_id = p_league_id and tp.stato = 'accettata'
  ),
  valutati as (
    select pz.*, power(1.13, pz.proiezione - 70) as base,
           row_number() over (partition by pz.id, pz.lato order by pz.proiezione desc) as rango
    from pezzi pz
  ),
  pesati as (
    select v.*, v.base * (case v.rango when 1 then 1 when 2 then 0.8 when 3 then 0.65 when 4 then 0.55 else 0.5 end) as valore
    from valutati v
  ),
  lati as (
    select id,
           coalesce(sum(valore) filter (where lato = 'da'), 0) as vda,
           coalesce(sum(valore) filter (where lato = 'a'), 0) as va,
           jsonb_agg(jsonb_build_object('lato', lato, 'tipo', tipo, 'etichetta', etichetta,
                     'overall', ovr, 'eta', eta, 'valore', round(valore, 2)) order by lato, valore desc) as det
    from pesati group by id
  )
  select l.id,
         case when greatest(l.vda, l.va) = 0 then 10::numeric
              else round(10 * least(l.vda, l.va) / greatest(l.vda, l.va), 1) end,
         round(l.vda, 2), round(l.va, 2), l.det
  from lati l;
end;
$function$;

revoke all on function public.valutazione_scambi(bigint) from public;
grant execute on function public.valutazione_scambi(bigint) to authenticated, service_role;
