-- Il voto di equilibrio di uno scambio si calcola UNA volta, quando lo scambio viene accettato, e resta quello:
-- deve dire se lo scambio era equo nel momento in cui e' stato fatto, non come sono andati i giocatori dopo.
-- Gli scambi gia' conclusi vengono congelati ora, sui valori di oggi (per gli scambi della stagione in corso
-- coincidono con quelli del giorno dello scambio: nessun checkpoint di crescita e' ancora passato).

create table if not exists public.valutazioni_scambi (
  proposta_id bigint primary key references public.trade_proposals(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  voto numeric not null,
  valore_da numeric not null,
  valore_a numeric not null,
  dettaglio jsonb not null,
  calcolata_il timestamptz not null default now()
);
alter table public.valutazioni_scambi enable row level security;
drop policy if exists valutazioni_scambi_lettura on public.valutazioni_scambi;
create policy valutazioni_scambi_lettura on public.valutazioni_scambi for select to authenticated
  using (private.e_membro(league_id));
grant select on public.valutazioni_scambi to authenticated;

-- Calcolo per una proposta, sui valori del momento (stessa formula di prima: somma dei pezzi, niente sconti).
create or replace function private.calcola_valutazione_scambio(p_proposta_id bigint)
 returns void language plpgsql security definer set search_path to ''
as $function$
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
           83.5 - 6.5 * (coalesce(s.posizione, (v_nsq + 1) / 2.0) - 1) / (v_nsq - 1) - greatest(0, s.stagione - v_stagione)
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

-- Quando una proposta diventa 'accettata' si fotografa il voto.
create or replace function private.trg_valuta_scambio_accettato()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.stato = 'accettata' and old.stato is distinct from 'accettata' then
    perform private.calcola_valutazione_scambio(new.id);
  end if;
  return new;
end;
$function$;
drop trigger if exists valuta_scambio_accettato on public.trade_proposals;
create trigger valuta_scambio_accettato after update of stato on public.trade_proposals
  for each row execute function private.trg_valuta_scambio_accettato();

-- L'app continua a chiamare questa funzione: ora legge i voti congelati.
create or replace function public.valutazione_scambi(p_league_id bigint)
 returns table(proposta_id bigint, voto numeric, valore_da numeric, valore_a numeric, dettaglio jsonb)
 language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not private.e_membro(p_league_id) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  return query
  select v.proposta_id, v.voto, v.valore_da, v.valore_a, v.dettaglio
  from public.valutazioni_scambi v where v.league_id = p_league_id;
end;
$function$;

-- Congela ora gli scambi gia' conclusi.
select private.calcola_valutazione_scambio(id) from public.trade_proposals where stato = 'accettata';
