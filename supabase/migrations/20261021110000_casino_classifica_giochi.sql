-- Classifica del casino' a tre viste (miglior colpo, crediti spesi, profitto) filtrabile per gioco (richiesta del committente).
-- Il blackjack a tavoli non teneva lo storico delle mani (i posti si azzerano a ogni giro): da ora c'e' casino_bjl_storico.
create table if not exists public.casino_bjl_storico (
  id bigint generated always as identity primary key,
  tavolo_id bigint not null references public.casino_bjl_tavoli(id) on delete cascade,
  giro integer not null,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntato integer not null,
  vinto bigint not null,
  creato_il timestamptz not null default now()
);
create index if not exists casino_bjl_storico_lega_idx on public.casino_bjl_storico (league_id);
alter table public.casino_bjl_storico enable row level security;
grant select on public.casino_bjl_storico to anon;
grant select, insert, update, delete on public.casino_bjl_storico to authenticated, service_role;

CREATE OR REPLACE FUNCTION private.bjl_chiudi(p_tavolo bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  t public.casino_bjl_tavoli; s public.casino_bjl_posti; m jsonb; v_mani jsonb; v_pt int; v_dt int; v_bj boolean; v_bj_banco boolean;
  v_vinto bigint; v_tot bigint; v_serve boolean := false; v_una boolean; v_pescate int := 0; v_nome text;
begin
  select * into t from public.casino_bjl_tavoli where id = p_tavolo for update;
  -- il banco pesca solo se c'e' almeno una mano ancora in gioco (non sballata e non blackjack naturale)
  for s in select * from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0 loop
    v_una := jsonb_array_length(s.mani) = 1;
    for m in select x from jsonb_array_elements(s.mani) x loop
      v_pt := private.bj_totale(private.bj_carte(m));
      if v_pt <= 21 and not (v_una and not coalesce((m ->> 'da_split')::boolean, false) and jsonb_array_length(m -> 'carte') = 2 and v_pt = 21) then v_serve := true; end if;
    end loop;
  end loop;
  v_bj_banco := array_length(t.banco, 1) = 2 and private.bj_totale(t.banco) = 21;
  if v_serve and not v_bj_banco then
    while private.bj_totale(t.banco) < 17 loop
      t.banco := t.banco || t.scarpa[1]; t.scarpa := t.scarpa[2:]; v_pescate := v_pescate + 1;
    end loop;
  end if;
  v_dt := private.bj_totale(t.banco);
  for s in select * from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0 for update loop
    v_una := jsonb_array_length(s.mani) = 1; v_mani := '[]'::jsonb; v_tot := 0;
    for m in select x from jsonb_array_elements(s.mani) x loop
      v_pt := private.bj_totale(private.bj_carte(m));
      v_bj := v_una and not coalesce((m ->> 'da_split')::boolean, false) and jsonb_array_length(m -> 'carte') = 2 and v_pt = 21;
      v_vinto := case
        when v_pt > 21 then 0
        when v_bj and not v_bj_banco then floor((m ->> 'puntata')::int * 2.5)
        when v_bj_banco and not v_bj then 0
        when v_bj and v_bj_banco then (m ->> 'puntata')::int
        when v_dt > 21 or v_pt > v_dt then 2 * (m ->> 'puntata')::int
        when v_pt = v_dt then (m ->> 'puntata')::int
        else 0 end;
      v_tot := v_tot + v_vinto;
      v_mani := v_mani || (m || jsonb_build_object('fatto', true, 'vinto', v_vinto, 'blackjack', v_bj));
    end loop;
    if v_bj_banco and s.assicurazione > 0 then v_tot := v_tot + 3 * s.assicurazione; end if;
    update public.casino_bjl_posti set mani = v_mani, vinto = v_tot where id = s.id;
    -- registro delle mani (per la classifica del casino': crediti spesi, profitto, miglior colpo)
    insert into public.casino_bjl_storico (tavolo_id, giro, league_id, user_id, team_id, puntato, vinto)
    values (t.id, t.giro, s.league_id, s.user_id, s.team_id,
            (select coalesce(sum((x ->> 'puntata')::int), 0) from jsonb_array_elements(s.mani) x) + s.assicurazione, v_tot);
    update public.casino_saldi set crediti = crediti + v_tot, totale_vinto = totale_vinto + v_tot, max_vincita = greatest(max_vincita, v_tot), aggiornato_il = now()
     where league_id = s.league_id and user_id = s.user_id;
    if v_tot >= 1000 and v_tot >= 3 * s.puntata then
      select nome into v_nome from public.teams where id = s.team_id;
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
      values (s.league_id, 'blackjack-live:' || t.id || ':' || t.giro || ':' || s.posto, 'lega', 'BetOne Casinò', s.team_id,
              '🃏 BLACKJACKONE! ' || v_nome || ' sbanca il tavolo ' || t.numero || ' e porta a casa ' || to_char(v_tot, 'FM999G999G999') || ' crediti 🤑', now())
      on conflict do nothing;
    end if;
  end loop;
  update public.casino_bjl_tavoli set banco = t.banco, scarpa = t.scarpa, fase = 'risultato', turno_posto = null, turno_mano = null,
         scadenza = clock_timestamp() + make_interval(secs => 5 + v_pescate * 0.8) where id = p_tavolo;
end $function$;

-- Una riga per ogni giro/mano giocato da un giocatore: gioco, crediti puntati, crediti restituiti (puntata compresa).
create or replace function private.casino_movimenti(p_league_id bigint) returns table(gioco text, team_id bigint, speso bigint, vinto bigint)
language sql stable security definer set search_path to '' as $$
  select 'slot', g.team_id, (case when g.gratis then 0 else g.puntata end)::bigint, g.vinto from public.casino_giri g where g.league_id = p_league_id
  union all select 'crazy', g.team_id, g.totale::bigint, g.vinto from public.casino_ct_giri g where g.league_id = p_league_id and not g.in_attesa
  union all select 'crazy', q.team_id, q.totale::bigint, q.vinto from public.casino_ctl_giocate q join public.casino_ctl_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.regolato
  union all select 'aviat', v.team_id, v.totale::bigint, v.vinto from public.casino_av_voli v where v.league_id = p_league_id and v.finito
  union all select 'aviat', q.team_id, q.puntata::bigint, q.vinto from public.casino_av_giocate q join public.casino_av_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.finisce_il <= now()
  union all select 'bj', m.team_id, ((select coalesce(sum((x ->> 'puntata')::int), 0) from jsonb_array_elements(m.mani) x) + m.assicurazione)::bigint, m.vinto from public.casino_bj_mani m where m.league_id = p_league_id and m.stato = 'finita'
  union all select 'bj', s.team_id, s.puntato::bigint, s.vinto from public.casino_bjl_storico s where s.league_id = p_league_id
$$;

-- Classifica: per squadra miglior colpo, crediti spesi, profitto (vinto - speso) e giri, per un gioco o per tutti (p_gioco null).
create or replace function public.casino_classifica_giochi(p_league_id bigint, p_gioco text default null)
returns table(team_id bigint, miglior_colpo bigint, spesi bigint, profitto bigint, giri bigint, crediti bigint)
language sql stable security definer set search_path to '' as $$
  select m.team_id, max(m.vinto), sum(m.speso), sum(m.vinto) - sum(m.speso), count(*),
         (select s.crediti from public.casino_saldi s join public.teams t on t.user_id = s.user_id and t.league_id = s.league_id where t.id = m.team_id and s.league_id = p_league_id)
    from private.casino_movimenti(p_league_id) m
   where (select private.e_membro(p_league_id)) and (p_gioco is null or m.gioco = p_gioco)
   group by m.team_id
$$;
revoke all on function public.casino_classifica_giochi(bigint, text) from public, anon;
grant execute on function public.casino_classifica_giochi(bigint, text) to authenticated;
revoke all on function private.casino_movimenti(bigint) from public, anon, authenticated;
