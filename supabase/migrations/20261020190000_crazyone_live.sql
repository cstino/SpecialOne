-- CrazyOne LIVE: una sola ruota per lega, uguale per tutti (come il Crazy Time vero).
-- Ciclo: 15 s per puntare -> top slot (2 s) -> ruota (6,5 s) -> esito. Numero: si paga e dopo 4 s riparte.
-- Bonus: tutti lo guardano insieme; Caccia allo Stemma e ruota CrazyOne chiedono a ognuno una scelta (circa 10 s),
-- chi non sceglie riceve una scelta a caso. Tutto il giro (anche il bonus) si estrae alla CREAZIONE, prima che si
-- chiudano le puntate, e resta segreto (tabelle senza policy): le parti si rivelano solo quando la sequenza ci arriva.
-- Niente cron: il giro lo crea o lo fa avanzare la prima richiesta che arriva (come AviatOne live).
-- Probabilita', premi e tetti identici alla versione personale (97%: migrazioni 20261020170000 e 20261020180000).

create table if not exists public.casino_ctl_giri (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  apre_il timestamptz not null,
  chiude_il timestamptz not null,       -- fine delle puntate, parte la top slot
  esito_il timestamptz not null,        -- la ruota si ferma
  scelta_fine_il timestamptz,           -- Caccia allo Stemma / CrazyOne: fine delle scelte
  fine_il timestamptz not null,         -- dopo questo momento si crea il giro successivo
  top_casella text,
  top_molt integer not null,
  spicchio smallint not null,
  esito text not null,
  bonus jsonb,
  regolato boolean not null default false
);
create index if not exists casino_ctl_giri_lega_idx on public.casino_ctl_giri (league_id, id desc);
alter table public.casino_ctl_giri enable row level security;

create table if not exists public.casino_ctl_giocate (
  id bigint generated always as identity primary key,
  giro_id bigint not null references public.casino_ctl_giri(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntate jsonb not null,
  totale integer not null check (totale > 0),
  scelta integer,
  scelta_auto boolean not null default false,
  vinto bigint not null default 0,
  unique (giro_id, user_id)
);
alter table public.casino_ctl_giocate enable row level security;
-- Nessuna policy su entrambe: si legge solo dalle funzioni.

create or replace function private.ctl_attivo(p_league_id bigint) returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile((select auth.uid())) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_crazyone) then
    raise exception using errcode = '55000', message = 'CrazyOne non è attivo in questa lega.';
  end if;
end $$;

-- Giro corrente della lega: se l'ultimo e' finito ne estrae uno nuovo, completo di esito e bonus.
create or replace function private.ctl_giro(p_league_id bigint) returns public.casino_ctl_giri language plpgsql security definer set search_path to '' as $$
declare
  g public.casino_ctl_giri;
  v_ora timestamptz := clock_timestamp();
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  c_top_pesi constant numeric[] := array[98,102,59,42,96,85,94,97, 327];
  v_x int; v_b int; v_slot int; v_top text; v_molt int; v_sp int; v_esito text; v_bonus jsonb;
  v_tavola int[]; v_pos int[]; v_lanci jsonb := '[]'::jsonb; v_mm int; v_ruota int[]; v_rot int[]; i int; v_gmax int := 1;
  v_chiude timestamptz; v_esito_il timestamptz; v_scelta timestamptz; v_fine timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('crazyone:' || p_league_id));
  select * into g from public.casino_ctl_giri where league_id = p_league_id order by id desc limit 1;
  if g.id is not null and v_ora < g.fine_il then return g; end if;

  v_x := private.ct_pesca(array[1,2,3,4,5,6,7,8,9], c_top_pesi);
  v_top := case when v_x <= 8 then c_caselle[v_x] end;
  v_molt := private.ct_pesca(array[2,3,5,10,15,25,50], array[35,25,18,12,5,3,2]);
  v_sp := floor(random() * 54)::int;
  v_esito := (private.ct_ruota())[v_sp + 1];
  v_chiude := v_ora + interval '15 seconds';
  v_esito_il := v_chiude + interval '8.5 seconds';

  if v_esito in ('1', '2', '5', '10') then
    v_fine := v_esito_il + interval '4 seconds';
  elsif v_esito = 'cf' then
    v_x := private.ct_val_cf(); v_b := private.ct_val_cf();
    v_slot := case when random() < 0.5 then 0 else 1 end;
    v_bonus := jsonb_build_object('rosso', v_x, 'blu', v_b, 'lato', case v_slot when 0 then 'rosso' else 'blu' end, 'valore', case v_slot when 0 then v_x else v_b end);
    v_fine := v_esito_il + interval '10 seconds';
  elsif v_esito = 'pa' then
    v_tavola := array(select private.ct_val_pa() from generate_series(1, 16));
    v_pos := array(select x from generate_series(1, 16) x order by random() limit 2);
    v_tavola[v_pos[1]] := -2; v_tavola[v_pos[2]] := -2;
    v_mm := 1; v_b := null;
    for i in 1..4 loop
      v_slot := floor(random() * 16)::int;
      v_lanci := v_lanci || to_jsonb(v_slot);
      if v_tavola[v_slot + 1] = -2 then v_mm := v_mm * 2;
      else v_b := least(v_tavola[v_slot + 1] * v_mm, 1000); exit; end if;
    end loop;
    if v_b is null then v_b := least(100 * v_mm, 1000); end if;
    v_bonus := jsonb_build_object('tavola', to_jsonb(v_tavola), 'lanci', v_lanci, 'valore', v_b);
    v_fine := v_esito_il + make_interval(secs => 6 + jsonb_array_length(v_lanci) * 3.6);
  elsif v_esito = 'ch' then
    v_bonus := jsonb_build_object('tavola', to_jsonb(array(select private.ct_val_ch() from generate_series(1, 108))));
    v_scelta := v_esito_il + interval '16.5 seconds';
    v_fine := v_scelta + interval '5 seconds';
  else
    v_ruota := array(select private.ct_val_ct() from generate_series(1, 64));
    v_pos := array(select x from generate_series(1, 64) x order by random() limit 10);
    for i in 1..8 loop v_ruota[v_pos[i]] := -2; end loop;
    v_ruota[v_pos[9]] := -3; v_ruota[v_pos[10]] := -3;
    v_rot := array(select floor(random() * 64)::int from generate_series(1, 6));
    for i in 0..2 loop v_gmax := greatest(v_gmax, (private.ct_cammino_crazy(v_ruota, v_rot, i) ->> 'giri')::int); end loop;
    v_bonus := jsonb_build_object('ruota', to_jsonb(v_ruota), 'rotazioni', to_jsonb(v_rot), 'giri_max', v_gmax);
    v_scelta := v_esito_il + interval '12 seconds';
    v_fine := v_scelta + make_interval(secs => 1 + v_gmax * 9 + 4);
  end if;

  insert into public.casino_ctl_giri (league_id, apre_il, chiude_il, esito_il, scelta_fine_il, fine_il, top_casella, top_molt, spicchio, esito, bonus)
  values (p_league_id, v_ora, v_chiude, v_esito_il, v_scelta, v_fine, v_top, v_molt, v_sp, v_esito, v_bonus)
  returning * into g;
  return g;
end $$;

-- Paga il giro (una volta sola): ai numeri e a Testa o Croce / Mischia appena la ruota si ferma, a Caccia allo Stemma
-- e CrazyOne quando finiscono le scelte (chi non ha scelto riceve una scelta a caso).
create or replace function private.ctl_regola(p_giro bigint) returns void language plpgsql security definer set search_path to '' as $$
declare
  g public.casino_ctl_giri; q public.casino_ctl_giocate; v_p int; v_m int; v_b int; v_vinto bigint; v_scelta int; v_nome text;
  v_ruota int[]; v_rot int[];
begin
  select * into g from public.casino_ctl_giri where id = p_giro for update;
  if g.regolato or clock_timestamp() < coalesce(g.scelta_fine_il, g.esito_il) then return; end if;
  if g.esito = 'ct' then
    v_ruota := array(select x::int from jsonb_array_elements_text(g.bonus -> 'ruota') x);
    v_rot := array(select x::int from jsonb_array_elements_text(g.bonus -> 'rotazioni') x);
  end if;
  for q in select * from public.casino_ctl_giocate where giro_id = g.id for update loop
    v_p := coalesce((q.puntate ->> g.esito)::int, 0);
    v_vinto := 0;
    if v_p > 0 then
      v_m := case when g.top_casella = g.esito then g.top_molt else 1 end;
      if g.esito in ('1', '2', '5', '10') then
        v_vinto := v_p::bigint * g.esito::int * v_m + v_p;
      elsif g.esito in ('cf', 'pa') then
        v_vinto := v_p::bigint * least((g.bonus ->> 'valore')::int * v_m, 2500) + v_p;
      else
        v_scelta := q.scelta;
        if v_scelta is null then
          v_scelta := case when g.esito = 'ch' then floor(random() * 108)::int else floor(random() * 3)::int end;
          update public.casino_ctl_giocate set scelta = v_scelta, scelta_auto = true where id = q.id;
        end if;
        v_b := case when g.esito = 'ch' then (g.bonus -> 'tavola' ->> v_scelta)::int
                    else (private.ct_cammino_crazy(v_ruota, v_rot, v_scelta) ->> 'valore')::int end;
        v_vinto := v_p::bigint * least(v_b * v_m, 2500) + v_p;
      end if;
    end if;
    if v_vinto > 0 then
      update public.casino_ctl_giocate set vinto = v_vinto where id = q.id;
      update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto,
             max_vincita = greatest(max_vincita, v_vinto), aggiornato_il = now()
       where league_id = q.league_id and user_id = q.user_id;
      if v_vinto >= 1000 and v_vinto >= 100 * q.totale then
        select nome into v_nome from public.teams where id = q.team_id;
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
        values (q.league_id, 'crazyone-live:' || q.id, 'lega', 'BetOne Casinò', q.team_id,
                '🎡 CRAZYONE! ' || v_nome || ' vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti con un solo giro di ruota 🤑', now())
        on conflict do nothing;
      end if;
    end if;
  end loop;
  update public.casino_ctl_giri set regolato = true where id = g.id;
end $$;

-- Stato del giro per la pagina: rivela ogni parte solo quando la sequenza del giro ci e' arrivata.
create or replace function private.ctl_stato(p_league_id bigint, p_giro bigint) returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare g public.casino_ctl_giri; v_ora timestamptz := clock_timestamp(); v_giro jsonb;
begin
  select * into g from public.casino_ctl_giri where id = p_giro;
  v_giro := jsonb_build_object('id', g.id,
    'apre', floor(extract(epoch from g.apre_il) * 1000), 'chiude', floor(extract(epoch from g.chiude_il) * 1000),
    'esito_il', floor(extract(epoch from g.esito_il) * 1000), 'fine', floor(extract(epoch from g.fine_il) * 1000),
    'scelta_fine', case when g.scelta_fine_il is not null then floor(extract(epoch from g.scelta_fine_il) * 1000) end,
    'regolato', g.regolato);
  if v_ora >= g.chiude_il then
    v_giro := v_giro || jsonb_build_object('top_casella', g.top_casella, 'top_molt', g.top_molt, 'spicchio', g.spicchio, 'esito', g.esito);
  end if;
  if v_ora >= g.esito_il then
    if g.esito in ('cf', 'pa') then v_giro := v_giro || jsonb_build_object('bonus', g.bonus); end if;
    if g.esito = 'ch' then
      v_giro := v_giro || jsonb_build_object('valori', (select jsonb_agg(x::int order by x::int) from jsonb_array_elements_text(g.bonus -> 'tavola') x));
      if v_ora >= g.scelta_fine_il then v_giro := v_giro || jsonb_build_object('tavola', g.bonus -> 'tavola'); end if;
    end if;
    if g.esito = 'ct' then
      v_giro := v_giro || jsonb_build_object('ruota', g.bonus -> 'ruota');
      if v_ora >= g.scelta_fine_il then v_giro := v_giro || jsonb_build_object('rotazioni', g.bonus -> 'rotazioni'); end if;
    end if;
  end if;
  return jsonb_build_object(
    'adesso', floor(extract(epoch from v_ora) * 1000),
    'giro', v_giro,
    'giocate', coalesce((select jsonb_agg(jsonb_build_object('team_id', q.team_id, 'totale', q.totale, 'mia', q.user_id = (select auth.uid()),
                          'vinto', case when g.regolato then q.vinto end,
                          'puntate', case when q.user_id = (select auth.uid()) then q.puntate end,
                          'scelta', case when q.user_id = (select auth.uid()) or g.regolato then q.scelta end,
                          'scelta_auto', q.scelta_auto) order by q.totale desc, q.id)
                        from public.casino_ctl_giocate q where q.giro_id = g.id), '[]'::jsonb),
    'crediti', (select s.crediti from public.casino_saldi s where s.league_id = p_league_id and s.user_id = (select auth.uid())),
    'storia', coalesce((select jsonb_agg(x.esito order by x.id desc) from (select id, esito from public.casino_ctl_giri
                         where league_id = p_league_id and esito_il <= v_ora order by id desc limit 14) x), '[]'::jsonb));
end $$;

create or replace function public.casino_ctl_live(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare g public.casino_ctl_giri; v_prec bigint;
begin
  perform private.ctl_attivo(p_league_id);
  perform private.casino_saldo(p_league_id, (select auth.uid()));
  -- Il giro precedente si regola anche se nessuno era collegato al momento giusto.
  for v_prec in select id from public.casino_ctl_giri where league_id = p_league_id and not regolato
                  and coalesce(scelta_fine_il, esito_il) <= clock_timestamp() order by id loop
    perform private.ctl_regola(v_prec);
  end loop;
  g := private.ctl_giro(p_league_id);
  perform private.ctl_regola(g.id);
  return private.ctl_stato(p_league_id, g.id);
end $$;

-- Puntate del giro: p_puntate e' la mappa completa (sostituisce la precedente; {} = nessuna puntata).
create or replace function public.casino_ctl_punta(p_league_id bigint, p_puntate jsonb) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_ctl_giri; q public.casino_ctl_giocate;
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  v_k text; v_p int; v_tot int := 0; v_mappa jsonb := '{}'::jsonb; v_vecchio int := 0;
begin
  perform private.ctl_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  g := private.ctl_giro(p_league_id);
  if clock_timestamp() >= g.chiude_il then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo giro.'; end if;
  for v_k, v_p in select key, (value #>> '{}')::int from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    if not (v_k = any(c_caselle)) or v_p < 0 or v_p % 10 <> 0 or v_p > 500 then raise exception using errcode = '22023', message = 'Puntata non valida.'; end if;
    if v_p > 0 then v_mappa := v_mappa || jsonb_build_object(v_k, v_p); v_tot := v_tot + v_p; end if;
  end loop;
  if v_tot > 2000 then raise exception using errcode = '22023', message = 'Al massimo 2.000 crediti a giro.'; end if;
  select * into q from public.casino_ctl_giocate where giro_id = g.id and user_id = v_utente for update;
  if q.id is not null then v_vecchio := q.totale; end if;
  if v.crediti + v_vecchio < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti + v_vecchio - v_tot,
         giri = giri + (case when q.id is null and v_tot > 0 then 1 when q.id is not null and v_tot = 0 then -1 else 0 end), aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;
  if v_tot = 0 then
    delete from public.casino_ctl_giocate where id = q.id;
  elsif q.id is null then
    insert into public.casino_ctl_giocate (giro_id, league_id, user_id, team_id, puntate, totale) values (g.id, p_league_id, v_utente, v.team_id, v_mappa, v_tot);
  else
    update public.casino_ctl_giocate set puntate = v_mappa, totale = v_tot where id = q.id;
  end if;
  return private.ctl_stato(p_league_id, g.id);
end $$;

-- Scelta nel bonus: Caccia allo Stemma = bersaglio 0-107, CrazyOne = bandierina 0-2 (solo chi ha puntato su quel bonus).
create or replace function public.casino_ctl_scegli(p_league_id bigint, p_scelta int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); g public.casino_ctl_giri; v_ora timestamptz := clock_timestamp();
begin
  perform private.ctl_attivo(p_league_id);
  g := private.ctl_giro(p_league_id);
  if g.esito not in ('ch', 'ct') or v_ora < g.esito_il or v_ora >= g.scelta_fine_il then
    raise exception using errcode = '55000', message = 'Non è il momento di scegliere.';
  end if;
  if p_scelta is null or p_scelta < 0 or p_scelta > (case g.esito when 'ch' then 107 else 2 end) then
    raise exception using errcode = '22023', message = 'Scelta non valida.';
  end if;
  update public.casino_ctl_giocate set scelta = p_scelta, scelta_auto = false
   where giro_id = g.id and user_id = v_utente and coalesce((puntate ->> g.esito)::int, 0) > 0;
  if not found then raise exception using errcode = '55000', message = 'Non hai puntato su questo bonus.'; end if;
  return private.ctl_stato(p_league_id, g.id);
end $$;

revoke all on function public.casino_ctl_live(bigint), public.casino_ctl_punta(bigint, jsonb), public.casino_ctl_scegli(bigint, int) from public, anon;
grant execute on function public.casino_ctl_live(bigint), public.casino_ctl_punta(bigint, jsonb), public.casino_ctl_scegli(bigint, int) to authenticated;
revoke all on function private.ctl_giro(bigint), private.ctl_regola(bigint) from public, anon, authenticated;
