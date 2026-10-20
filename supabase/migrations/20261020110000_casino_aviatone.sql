-- BetOne Casino': terzo gioco, AviatOne (stile Aviator a tema SpecialOne). Volo personale: si punta (fino a 2 puntate,
-- ognuna con incasso automatico opzionale), l'aereo decolla e il moltiplicatore sale finche' non vola via.
-- Il punto in cui vola via lo estrae il SERVER alla partenza e resta segreto (tabella senza policy di lettura).
-- Il moltiplicatore dipende solo dal tempo trascorso sull'orologio del server: m(t) = e^(0,075·t), 2× a ~9 s, 10× a ~31 s.
-- Distribuzione del punto di crash: P(crash > m) ~ 0,94 / m  ->  qualunque strategia di incasso rende in media il 94%
-- (0,946 nella formula compensa l'arrotondamento per difetto ai centesimi). Circa il 6% dei voli esplode subito a 1,00×.

alter table public.leagues add column if not exists casino_aviatone boolean not null default false;
update public.leagues set casino_aviatone = true where id = 62;

create table if not exists public.casino_av_voli (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntate jsonb not null,            -- [{puntata, auto, incassato}] (incassato = moltiplicatore incassato, null se no)
  totale integer not null check (totale > 0),
  crash numeric(8,2) not null,
  partito_il timestamptz not null default clock_timestamp(),
  finito boolean not null default false,
  vinto bigint not null default 0,
  finito_il timestamptz
);
create index if not exists casino_av_voli_utente_idx on public.casino_av_voli (league_id, user_id, id desc);
create unique index if not exists casino_av_voli_in_volo_idx on public.casino_av_voli (league_id, user_id) where not finito;
alter table public.casino_av_voli enable row level security;
-- Nessuna policy: si legge solo dalle funzioni (il punto di crash non deve trapelare).

create or replace function private.av_molt(p_secondi numeric) returns numeric language sql immutable set search_path to '' as $$
  select least(floor(exp(0.075 * greatest(p_secondi, 0)) * 100) / 100, 1000)::numeric(8,2)
$$;

create or replace function private.av_crash() returns numeric language sql volatile set search_path to '' as $$
  select least(greatest(floor(0.946 / (1 - random()) * 100) / 100, 1), 1000)::numeric(8,2)
$$;

create or replace function private.av_attivo(p_league_id bigint) returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile((select auth.uid())) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_aviatone) then
    raise exception using errcode = '55000', message = 'AviatOne non è attivo in questa lega.';
  end if;
end $$;

-- Mette in pari un volo con l'orologio: incassi automatici raggiunti e, se il moltiplicatore ha superato il crash,
-- fine del volo. p_chiudi = true chiude subito (solo se tutte le puntate sono gia' risolte).
create or replace function private.av_aggiorna(p_id bigint, p_chiudi boolean default false) returns public.casino_av_voli language plpgsql security definer set search_path to '' as $$
declare
  f public.casino_av_voli; v_m numeric; v_p jsonb := '[]'::jsonb; e jsonb; v_extra bigint := 0; v_aperte int := 0; v_nome text;
begin
  select * into f from public.casino_av_voli where id = p_id for update;
  if f.finito then return f; end if;
  v_m := private.av_molt(extract(epoch from clock_timestamp() - f.partito_il));
  for e in select x from jsonb_array_elements(f.puntate) x loop
    if e ->> 'incassato' is null and e ->> 'auto' is not null and (e ->> 'auto')::numeric <= v_m and (e ->> 'auto')::numeric < f.crash then
      e := e || jsonb_build_object('incassato', (e ->> 'auto')::numeric);
      v_extra := v_extra + floor((e ->> 'puntata')::int * (e ->> 'auto')::numeric);
    end if;
    if e ->> 'incassato' is null then v_aperte := v_aperte + 1; end if;
    v_p := v_p || e;
  end loop;
  update public.casino_av_voli set puntate = v_p, vinto = vinto + v_extra,
         finito = (v_m >= crash or (p_chiudi and v_aperte = 0)),
         finito_il = case when v_m >= crash or (p_chiudi and v_aperte = 0) then clock_timestamp() end
   where id = p_id returning * into f;
  if v_extra > 0 then
    update public.casino_saldi set crediti = crediti + v_extra, totale_vinto = totale_vinto + v_extra, max_vincita = greatest(max_vincita, f.vinto), aggiornato_il = now()
     where league_id = f.league_id and user_id = f.user_id;
  end if;
  if f.finito and f.vinto >= 1000 and f.vinto >= 100 * f.totale then
    select nome into v_nome from public.teams where id = f.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (f.league_id, 'aviatone:' || f.id, 'lega', 'BetOne Casinò', f.team_id,
            '✈️ AVIATONE! ' || v_nome || ' incassa ' || to_char(f.vinto, 'FM999G999G999') || ' crediti prima che l''aereo voli via 🤑', now())
    on conflict do nothing;
  end if;
  return f;
end $$;

-- Parte pubblica di un volo: niente crash finche' il volo non e' finito.
create or replace function private.av_pubblico(f public.casino_av_voli) returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object('id', f.id, 'puntate', f.puntate, 'totale', f.totale, 'vinto', f.vinto, 'finito', f.finito,
    'trascorso', extract(epoch from clock_timestamp() - f.partito_il),
    'molt', private.av_molt(extract(epoch from clock_timestamp() - f.partito_il)),
    'crash', case when f.finito then f.crash end)
$$;

create or replace function public.casino_av_stato(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v public.casino_saldi; f public.casino_av_voli;
begin
  perform private.av_attivo(p_league_id);
  select * into f from public.casino_av_voli where league_id = p_league_id and user_id = (select auth.uid()) and not finito;
  if f.id is not null then f := private.av_aggiorna(f.id); end if;
  v := private.casino_saldo(p_league_id, (select auth.uid()));
  return jsonb_build_object('crediti', v.crediti,
    'volo', case when f.id is not null and not f.finito then private.av_pubblico(f) end,
    'storia', coalesce((select jsonb_agg(s.crash order by s.id desc) from (select id, crash from public.casino_av_voli
                         where league_id = p_league_id and user_id = (select auth.uid()) and finito order by id desc limit 20) s), '[]'::jsonb));
end $$;

-- Decollo: p_puntate = [{puntata, auto}] (1 o 2 elementi; auto null = incasso a mano).
create or replace function public.casino_av_parti(p_league_id bigint, p_puntate jsonb) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; f public.casino_av_voli;
  e jsonb; v_p int; v_a numeric; v_tot int := 0; v_lista jsonb := '[]'::jsonb;
begin
  perform private.av_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  select * into f from public.casino_av_voli where league_id = p_league_id and user_id = v_utente and not finito;
  if f.id is not null then
    f := private.av_aggiorna(f.id);
    if not f.finito then raise exception using errcode = '55000', message = 'L''aereo è ancora in volo.'; end if;
  end if;
  if jsonb_typeof(p_puntate) <> 'array' or jsonb_array_length(p_puntate) not between 1 and 2 then
    raise exception using errcode = '22023', message = 'Una o due puntate.';
  end if;
  for e in select x from jsonb_array_elements(p_puntate) x loop
    v_p := (e ->> 'puntata')::int;
    v_a := nullif(e ->> 'auto', '')::numeric;
    if v_p is null or v_p < 10 or v_p > 500 or v_p % 10 <> 0 then raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).'; end if;
    if v_a is not null and (v_a < 1.1 or v_a > 1000) then raise exception using errcode = '22023', message = 'Incasso automatico non valido (da 1,10× a 1000×).'; end if;
    v_tot := v_tot + v_p;
    v_lista := v_lista || jsonb_build_object('puntata', v_p, 'auto', round(v_a, 2), 'incassato', null);
  end loop;
  if v.crediti < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;

  update public.casino_saldi set crediti = crediti - v_tot, giri = giri + 1, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente returning * into v;
  insert into public.casino_av_voli (league_id, user_id, team_id, puntate, totale, crash)
  values (p_league_id, v_utente, v.team_id, v_lista, v_tot, private.av_crash()) returning * into f;
  return private.av_pubblico(f) || jsonb_build_object('crediti', v.crediti);
end $$;

-- Incasso a mano della puntata p_indice (0 o 1) al moltiplicatore di adesso (orologio del server).
create or replace function public.casino_av_incassa(p_league_id bigint, p_indice int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); f public.casino_av_voli; v_m numeric; e jsonb; v_extra bigint; v public.casino_saldi;
begin
  perform private.av_attivo(p_league_id);
  select * into f from public.casino_av_voli where league_id = p_league_id and user_id = v_utente and not finito;
  if f.id is null then raise exception using errcode = '55000', message = 'Nessun aereo in volo.'; end if;
  f := private.av_aggiorna(f.id);
  e := f.puntate -> p_indice;
  if not f.finito and e is not null and e ->> 'incassato' is null then
    v_m := private.av_molt(extract(epoch from clock_timestamp() - f.partito_il));
    if v_m < f.crash then
      v_extra := floor((e ->> 'puntata')::int * v_m);
      update public.casino_av_voli set puntate = jsonb_set(puntate, array[p_indice::text, 'incassato'], to_jsonb(v_m)), vinto = vinto + v_extra
       where id = f.id returning * into f;
      update public.casino_saldi set crediti = crediti + v_extra, totale_vinto = totale_vinto + v_extra, max_vincita = greatest(max_vincita, f.vinto), aggiornato_il = now()
       where league_id = p_league_id and user_id = v_utente;
    else
      f := private.av_aggiorna(f.id);
    end if;
  end if;
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  return private.av_pubblico(f) || jsonb_build_object('crediti', v.crediti);
end $$;

-- Controllo durante il volo (il client lo chiama ogni ~0,4 s): incassi automatici e crash.
-- p_salta = true: se tutte le puntate sono gia' incassate, il volo finisce subito e si vede dove sarebbe esploso.
create or replace function public.casino_av_controlla(p_league_id bigint, p_salta boolean default false) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); f public.casino_av_voli; v public.casino_saldi;
begin
  perform private.av_attivo(p_league_id);
  select * into f from public.casino_av_voli where league_id = p_league_id and user_id = v_utente order by id desc limit 1;
  if f.id is null then raise exception using errcode = '55000', message = 'Nessun volo.'; end if;
  f := private.av_aggiorna(f.id, coalesce(p_salta, false));
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  return private.av_pubblico(f) || jsonb_build_object('crediti', v.crediti);
end $$;

-- La pagina iniziale del casino' deve sapere quali giochi mostrare.
create or replace function public.casino_stato(p_league_id bigint)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;

revoke all on function public.casino_av_stato(bigint), public.casino_av_parti(bigint, jsonb), public.casino_av_incassa(bigint, int), public.casino_av_controlla(bigint, boolean) from public, anon;
grant execute on function public.casino_av_stato(bigint), public.casino_av_parti(bigint, jsonb), public.casino_av_incassa(bigint, int), public.casino_av_controlla(bigint, boolean) to authenticated;
revoke all on function private.av_aggiorna(bigint, boolean) from public, anon, authenticated;
