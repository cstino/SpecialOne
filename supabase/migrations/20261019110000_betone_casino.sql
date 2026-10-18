-- ============================================================
--  BETONE CASINO' (19/10/2026, deciso con il committente): una slot a tema SpecialOne dentro BetOne. Minigioco interno,
--  nessun effetto sul gioco vero. 5 rulli x 3 righe, 10 linee; i simboli sono 8 stemmi della lega (a rotazione per
--  giornata, pagano di piu' le squadre meglio piazzate), il logo SpecialOne (jolly) e la coppa (scatter: giri gratis
--  con vincite doppie). Crediti che si accumulano: 1.000 gratis a settimana (lunedi', ora di Roma), anche arretrati.
--  Tutte le estrazioni le fa il server (nessuno puo' truccare il giro); ogni giro e' registrato. Classifica per
--  crediti. Ritorno medio tarato con 1 milione di giri simulati: ~97%, una vincita ogni ~3,5 giri.
--  Solo leghe con le novita' (leagues.conferenze_stampa).
-- ============================================================
begin;

create table public.casino_saldi (
  league_id    bigint not null references public.leagues(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  team_id      bigint not null references public.teams(id) on delete cascade,
  crediti      bigint not null default 0 check (crediti >= 0),
  settimana    date not null,
  giri_gratis  smallint not null default 0,
  puntata_gratis smallint,
  giri         integer not null default 0,
  max_vincita  bigint not null default 0,
  totale_vinto bigint not null default 0,
  aggiornato_il timestamptz not null default now(),
  primary key (league_id, user_id)
);
create table public.casino_giri (
  id         bigint generated always as identity primary key,
  league_id  bigint not null references public.leagues(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  team_id    bigint not null references public.teams(id) on delete cascade,
  puntata    integer not null,
  gratis     boolean not null default false,
  vinto      bigint not null,
  griglia    jsonb not null,
  creato_il  timestamptz not null default now()
);
create index casino_giri_utente_idx on public.casino_giri (league_id, user_id, id desc);

alter table public.casino_saldi enable row level security;
alter table public.casino_giri enable row level security;
create policy casino_saldi_lega on public.casino_saldi for select to authenticated using ((select private.e_membro(league_id)));
create policy casino_giri_miei on public.casino_giri for select to authenticated using (user_id = (select auth.uid()));
grant select on public.casino_saldi, public.casino_giri to authenticated;
grant all on public.casino_saldi, public.casino_giri to service_role;

-- Gli 8 stemmi della giornata: scelti a rotazione (cambiano a ogni giornata), ordinati per classifica:
-- indici 0-2 pagano poco (le peggio piazzate), 3-5 medio, 6-7 molto (le migliori).
create or replace function private.casino_simboli(p_league_id bigint)
returns bigint[] language sql stable security definer set search_path = '' as $f$
  with lega as (
    select l.id, se.id as season_id,
           coalesce((select min(f.giornata) from public.fixtures f where f.season_id = se.id and f.stato = 'programmata'), 0) as giornata
    from public.leagues l join public.seasons se on se.league_id = l.id and se.numero = l.stagione_corrente
    where l.id = p_league_id
  ), scelte as (
    select t.id, coalesce(st.posizione, 99) as pos
    from lega join public.teams t on t.league_id = lega.id and t.attiva
    left join public.standings st on st.season_id = lega.season_id and st.team_id = t.id
    order by hashtext(lega.id::text || '-' || lega.giornata::text || '-' || t.id::text)
    limit 8
  )
  select array_agg(id order by pos desc, id) from scelte
$f$;

create or replace function private.casino_settimana()
returns date language sql stable set search_path = '' as $f$
  select date_trunc('week', (now() at time zone 'Europe/Rome'))::date
$f$;

-- Il saldo dell'utente, con la ricarica settimanale (1.000 per ogni lunedi' passato dall'ultima, la prima volta 1.000).
create or replace function private.casino_saldo(p_league_id bigint, p_user uuid)
returns public.casino_saldi language plpgsql security definer set search_path = '' as $f$
declare
  v public.casino_saldi;
  v_team bigint;
  v_sett date := private.casino_settimana();
  v_settimane integer;
begin
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = p_user for update;
  if not found then
    select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = p_user and t.attiva;
    if v_team is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
    insert into public.casino_saldi (league_id, user_id, team_id, crediti, settimana) values (p_league_id, p_user, v_team, 1000, v_sett)
    returning * into v;
    return v;
  end if;
  v_settimane := (v_sett - v.settimana) / 7;
  if v_settimane > 0 then
    update public.casino_saldi set crediti = crediti + 1000 * v_settimane, settimana = v_sett, aggiornato_il = now()
     where league_id = p_league_id and user_id = p_user returning * into v;
  end if;
  return v;
end $f$;

create or replace function public.casino_stato(p_league_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri,
    'prossima_ricarica', ((v.settimana + 7)::timestamp at time zone 'Europe/Rome'));
end $f$;

create or replace function public.casino_gira(p_league_id bigint, p_puntata integer)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  c_pesi constant int[] := array[9,9,9,7,7,7,4,4,3,2];   -- simboli 0-7 stemmi, 8 jolly, 9 coppa
  c_linee constant int[] := array[
    1,1,1,1,1, 0,0,0,0,0, 2,2,2,2,2, 0,1,2,1,0, 2,1,0,1,2,
    0,0,1,2,2, 2,2,1,0,0, 1,0,0,0,1, 1,2,2,2,1, 0,1,1,1,0];
  v_gratis boolean;
  v_puntata integer;
  v_molt integer;
  g int[];            -- griglia 5 rulli x 3 righe, indice (rullo*3 + riga) + 1
  v_r int; v_k int; v_x int; v_cum int; v_tot int := 61;
  v_linea int; v_sim int; v_target int; v_n int; v_paga int; v_vinto_linee numeric := 0;
  v_vinte jsonb := '[]'::jsonb;
  v_coppe int := 0; v_nuovi_gratis int := 0; v_scatter numeric := 0;
  v_vinto bigint;
  v_giro_id bigint;
  v_nome_team text;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  v_gratis := v.giri_gratis > 0;
  if v_gratis then
    v_puntata := v.puntata_gratis; v_molt := 2;
  else
    if p_puntata not in (10, 20, 50, 100) then raise exception using errcode = '22023', message = 'Puntata non valida.'; end if;
    if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni lunedì.'; end if;
    v_puntata := p_puntata; v_molt := 1;
  end if;

  -- Estrazione: ogni casella pescata secondo i pesi (lo fa il server).
  g := array_fill(0, array[15]);
  for v_k in 1..15 loop
    v_x := floor(random() * v_tot)::int; v_cum := 0;
    for v_r in 1..10 loop
      v_cum := v_cum + c_pesi[v_r];
      if v_x < v_cum then g[v_k] := v_r - 1; exit; end if;
    end loop;
    if g[v_k] = 9 then v_coppe := v_coppe + 1; end if;
  end loop;

  -- Linee: da sinistra, simboli uguali (il jolly sostituisce gli stemmi, non la coppa). 5 jolly = jackpot.
  for v_linea in 0..9 loop
    v_target := null; v_n := 0; v_paga := 0;
    for v_r in 0..4 loop
      v_sim := g[v_r * 3 + c_linee[v_linea * 5 + v_r + 1] + 1];
      if v_sim = 9 then exit; end if;
      if v_target is null and v_sim <> 8 then v_target := v_sim; end if;
      if v_sim = 8 or v_sim = v_target then v_n := v_n + 1; else exit; end if;
    end loop;
    if v_target is null and v_n = 5 then v_paga := 400; v_target := 8;
    elsif v_n >= 3 and v_target is not null then
      v_paga := case when v_target <= 2 then (array[8,26,100])[v_n - 2]
                     when v_target <= 5 then (array[14,52,200])[v_n - 2]
                     else (array[26,125,500])[v_n - 2] end;
    end if;
    if v_paga > 0 then
      v_vinto_linee := v_vinto_linee + v_paga;
      v_vinte := v_vinte || jsonb_build_object('linea', v_linea, 'simbolo', v_target, 'n', v_n, 'vinto', round(v_paga * v_puntata / 10.0 * v_molt));
    end if;
  end loop;

  -- Coppe ovunque: 3 = 2x la puntata e 8 giri gratis, 4 = 5x e 12, 5+ = 20x e 20 (vincite doppie nei giri gratis).
  if v_coppe >= 3 then
    v_scatter := (case least(v_coppe, 5) when 3 then 2 when 4 then 5 else 20 end) * v_puntata * v_molt;
    v_nuovi_gratis := case least(v_coppe, 5) when 3 then 8 when 4 then 12 else 20 end;
  end if;
  v_vinto := round(v_vinto_linee * v_puntata / 10.0 * v_molt + v_scatter);

  update public.casino_saldi set
    crediti = crediti - (case when v_gratis then 0 else v_puntata end) + v_vinto,
    giri_gratis = greatest(0, giri_gratis - (case when v_gratis then 1 else 0 end)) + v_nuovi_gratis,
    puntata_gratis = case when v_nuovi_gratis > 0 then v_puntata when giri_gratis - (case when v_gratis then 1 else 0 end) <= 0 then null else puntata_gratis end,
    giri = giri + 1, max_vincita = greatest(max_vincita, v_vinto), totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
  where league_id = p_league_id and user_id = v_utente
  returning * into v;

  insert into public.casino_giri (league_id, user_id, team_id, puntata, gratis, vinto, griglia)
  values (p_league_id, v_utente, v.team_id, v_puntata, v_gratis, v_vinto, to_jsonb(g)) returning id into v_giro_id;

  -- Il colpo grosso (almeno 100 volte la puntata) finisce su SocialOne.
  if v_vinto >= 100 * v_puntata then
    select nome into v_nome_team from public.teams where id = v.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (p_league_id, 'casino:' || v_giro_id, 'lega', 'BetOne Casinò', v.team_id,
            '🎰 COLPO GROSSO al casinò! ' || v_nome_team || ' vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti con un solo giro 🤑', now())
    on conflict do nothing;
  end if;

  return jsonb_build_object('griglia', to_jsonb(g), 'vincite', v_vinte, 'coppe', v_coppe, 'scatter', v_scatter, 'vinto', v_vinto,
    'gratis', v_gratis, 'molt', v_molt, 'puntata', v_puntata, 'nuovi_gratis', v_nuovi_gratis,
    'crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'max_vincita', v.max_vincita);
end $f$;

create or replace function public.casino_classifica(p_league_id bigint)
returns table (team_id bigint, crediti bigint, max_vincita bigint, giri integer)
language sql stable security definer set search_path = '' as $f$
  select s.team_id, s.crediti, s.max_vincita, s.giri from public.casino_saldi s
  where s.league_id = p_league_id and (select private.e_membro(p_league_id))
  order by s.crediti desc, s.max_vincita desc, s.team_id
$f$;

revoke all on function public.casino_stato(bigint), public.casino_gira(bigint, integer), public.casino_classifica(bigint) from public, anon;
grant execute on function public.casino_stato(bigint), public.casino_gira(bigint, integer), public.casino_classifica(bigint) to authenticated;

commit;
