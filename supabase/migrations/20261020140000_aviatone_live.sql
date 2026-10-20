-- AviatOne LIVE: un solo aereo per lega, uguale per tutti (come l'Aviator vero).
-- Ciclo continuo: 7 s per puntare -> volo (m = e^(0,075·t)) fino al crash -> 3 s di pausa -> giro successivo.
-- Niente cron: il giro corrente lo crea (o lo fa avanzare) la prima richiesta che arriva; per chi guarda il ciclo e'
-- continuo, e quando nessuno e' collegato non serve che giri. Il crash si estrae alla creazione del giro, quindi PRIMA
-- che si chiudano le puntate, e resta segreto (tabella senza policy) finche' l'aereo non vola via.
-- I voli personali (casino_av_voli e funzioni) restano in archivio ma la pagina non li usa piu'.

create table if not exists public.casino_av_giri (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  apre_il timestamptz not null,
  parte_il timestamptz not null,
  crash numeric(8,2) not null,
  finisce_il timestamptz not null
);
create index if not exists casino_av_giri_lega_idx on public.casino_av_giri (league_id, id desc);
alter table public.casino_av_giri enable row level security;

create table if not exists public.casino_av_giocate (
  id bigint generated always as identity primary key,
  giro_id bigint not null references public.casino_av_giri(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntata integer not null check (puntata between 10 and 500),
  auto numeric(8,2),
  incassato numeric(8,2),
  vinto bigint not null default 0,
  creato_il timestamptz not null default now(),
  unique (giro_id, user_id)
);
alter table public.casino_av_giocate enable row level security;
-- Nessuna policy su entrambe: si legge solo dalle funzioni.

-- Giro corrente della lega (lo crea se l'ultimo e' finito da piu' di 3 secondi).
create or replace function private.av_giro(p_league_id bigint) returns public.casino_av_giri language plpgsql security definer set search_path to '' as $$
declare g public.casino_av_giri; v_ora timestamptz := clock_timestamp(); v_crash numeric;
begin
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));
  select * into g from public.casino_av_giri where league_id = p_league_id order by id desc limit 1;
  if g.id is null or v_ora > g.finisce_il + interval '3 seconds' then
    v_crash := private.av_crash();
    insert into public.casino_av_giri (league_id, apre_il, parte_il, crash, finisce_il)
    values (p_league_id, v_ora, v_ora + interval '7 seconds', v_crash,
            v_ora + interval '7 seconds' + make_interval(secs => ln(v_crash) / 0.075))
    returning * into g;
  end if;
  return g;
end $$;

-- Paga i vincitori di una giocata (saldo, miglior colpo, colpo grosso su SocialOne).
create or replace function private.av_paga(p_giocata bigint, p_molt numeric) returns void language plpgsql security definer set search_path to '' as $$
declare q public.casino_av_giocate; v_vinto bigint; v_nome text;
begin
  update public.casino_av_giocate set incassato = p_molt, vinto = floor(puntata * p_molt)
   where id = p_giocata and incassato is null returning * into q;
  if q.id is null then return; end if;
  v_vinto := q.vinto;
  update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto,
         max_vincita = greatest(max_vincita, v_vinto), aggiornato_il = now()
   where league_id = q.league_id and user_id = q.user_id;
  if v_vinto >= 1000 and v_vinto >= 100 * q.puntata then
    select nome into v_nome from public.teams where id = q.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (q.league_id, 'aviatone-live:' || q.id, 'lega', 'BetOne Casinò', q.team_id,
            '✈️ AVIATONE! ' || v_nome || ' incassa a ' || to_char(p_molt, 'FM9990D00') || '× e porta a casa ' || to_char(v_vinto, 'FM999G999G999') || ' crediti 🤑', now())
    on conflict do nothing;
  end if;
end $$;

-- Incassi automatici raggiunti finora nel giro (li applica chiunque faccia una richiesta).
create or replace function private.av_regola(g public.casino_av_giri) returns void language plpgsql security definer set search_path to '' as $$
declare v_m numeric; q record;
begin
  if clock_timestamp() < g.parte_il then return; end if;
  v_m := private.av_molt(extract(epoch from least(clock_timestamp(), g.finisce_il) - g.parte_il));
  for q in select id, auto from public.casino_av_giocate
            where giro_id = g.id and incassato is null and auto is not null and auto <= v_m and auto < g.crash for update loop
    perform private.av_paga(q.id, q.auto);
  end loop;
end $$;

-- Stato del giro per la pagina (la chiama ogni ~0,5 s chi ha AviatOne aperto).
create or replace function private.av_live_stato(p_league_id bigint, g public.casino_av_giri) returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'adesso', floor(extract(epoch from clock_timestamp()) * 1000),
    'giro', jsonb_build_object('id', g.id, 'apre', floor(extract(epoch from g.apre_il) * 1000), 'parte', floor(extract(epoch from g.parte_il) * 1000),
      'finito', clock_timestamp() >= g.finisce_il,
      'crash', case when clock_timestamp() >= g.finisce_il then g.crash end),
    'giocate', coalesce((select jsonb_agg(jsonb_build_object('team_id', q.team_id, 'puntata', q.puntata, 'incassato', q.incassato, 'vinto', q.vinto,
                          'mia', q.user_id = (select auth.uid()), 'auto', case when q.user_id = (select auth.uid()) then q.auto end) order by q.puntata desc, q.id)
                        from public.casino_av_giocate q where q.giro_id = g.id), '[]'::jsonb),
    'crediti', (select s.crediti from public.casino_saldi s where s.league_id = p_league_id and s.user_id = (select auth.uid())),
    'storia', coalesce((select jsonb_agg(x.crash order by x.id desc) from (select id, crash from public.casino_av_giri
                         where league_id = p_league_id and finisce_il <= clock_timestamp() order by id desc limit 20) x), '[]'::jsonb))
$$;

create or replace function public.casino_av_live(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare g public.casino_av_giri;
begin
  perform private.av_attivo(p_league_id);
  perform private.casino_saldo(p_league_id, (select auth.uid()));
  g := private.av_giro(p_league_id);
  perform private.av_regola(g);
  return private.av_live_stato(p_league_id, g);
end $$;

create or replace function public.casino_av_punta(p_league_id bigint, p_puntata int, p_auto numeric) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_av_giri;
begin
  perform private.av_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  g := private.av_giro(p_league_id);
  if clock_timestamp() >= g.parte_il then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo volo.'; end if;
  if p_puntata is null or p_puntata < 10 or p_puntata > 500 or p_puntata % 10 <> 0 then raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).'; end if;
  if p_auto is not null and (p_auto < 1.1 or p_auto > 1000) then raise exception using errcode = '22023', message = 'Incasso automatico non valido (da 1,10× a 1000×).'; end if;
  if exists (select 1 from public.casino_av_giocate where giro_id = g.id and user_id = v_utente) then
    raise exception using errcode = '55000', message = 'Hai già puntato su questo volo.';
  end if;
  if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti - p_puntata, giri = giri + 1, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;
  insert into public.casino_av_giocate (giro_id, league_id, user_id, team_id, puntata, auto)
  values (g.id, p_league_id, v_utente, v.team_id, p_puntata, round(p_auto, 2));
  return private.av_live_stato(p_league_id, g);
end $$;

-- Ritira la puntata finche' le puntate sono aperte (crediti restituiti).
create or replace function public.casino_av_ritira(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); g public.casino_av_giri; q public.casino_av_giocate;
begin
  perform private.av_attivo(p_league_id);
  g := private.av_giro(p_league_id);
  if clock_timestamp() < g.parte_il then
    delete from public.casino_av_giocate where giro_id = g.id and user_id = v_utente returning * into q;
    if q.id is not null then
      update public.casino_saldi set crediti = crediti + q.puntata, giri = greatest(0, giri - 1), aggiornato_il = now()
       where league_id = p_league_id and user_id = v_utente;
    end if;
  end if;
  return private.av_live_stato(p_league_id, g);
end $$;

-- Incasso a mano al moltiplicatore del momento in cui la richiesta arriva al server.
create or replace function public.casino_av_incassa_live(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); g public.casino_av_giri; q public.casino_av_giocate; v_ora timestamptz; v_m numeric;
begin
  perform private.av_attivo(p_league_id);
  g := private.av_giro(p_league_id);
  perform private.av_regola(g);
  v_ora := clock_timestamp();
  select * into q from public.casino_av_giocate where giro_id = g.id and user_id = v_utente and incassato is null for update;
  if q.id is not null and v_ora >= g.parte_il and v_ora < g.finisce_il then
    v_m := private.av_molt(extract(epoch from v_ora - g.parte_il));
    if v_m < g.crash then perform private.av_paga(q.id, v_m); end if;
  end if;
  return private.av_live_stato(p_league_id, g);
end $$;

revoke all on function public.casino_av_live(bigint), public.casino_av_punta(bigint, int, numeric), public.casino_av_ritira(bigint), public.casino_av_incassa_live(bigint) from public, anon;
grant execute on function public.casino_av_live(bigint), public.casino_av_punta(bigint, int, numeric), public.casino_av_ritira(bigint), public.casino_av_incassa_live(bigint) to authenticated;
revoke all on function private.av_giro(bigint), private.av_paga(bigint, numeric), private.av_regola(public.casino_av_giri) from public, anon, authenticated;
