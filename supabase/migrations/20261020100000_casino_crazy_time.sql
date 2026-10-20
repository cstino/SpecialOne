-- BetOne Casino': secondo gioco, CrazyOne (stile Crazy Time: ruota a 54 spicchi + top slot + 4 bonus).
-- Giro personale: ognuno punta e fa girare quando vuole. Tutto lo estrae il SERVER; il client anima soltanto.
-- Tarato al ~94% di ritorno medio per ogni casella (stessa taratura della slot).
-- Cash Hunt e Crazy Time chiedono una scelta al giocatore (bersaglio / bandierina): il risultato e' gia' deciso
-- al momento del giro e sta nascosto nella riga del giro finche' il giocatore non sceglie (tabella senza policy).

-- Acceso lega per lega (per ora solo LegaBot, per provarlo).
alter table public.leagues add column if not exists casino_crazyone boolean not null default false;
update public.leagues set casino_crazyone = true where id = 62;

create table if not exists public.casino_ct_giri (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntate jsonb not null,
  totale integer not null check (totale > 0),
  top_casella text,
  top_molt integer not null,
  spicchio smallint not null,
  esito text not null,
  bonus jsonb,                       -- dati del bonus (segreti finche' il giro e' in attesa)
  in_attesa boolean not null default false,
  vinto bigint not null default 0,
  creato_il timestamptz not null default now(),
  concluso_il timestamptz
);
create index if not exists casino_ct_giri_utente_idx on public.casino_ct_giri (league_id, user_id, id desc);
create unique index if not exists casino_ct_giri_attesa_idx on public.casino_ct_giri (league_id, user_id) where in_attesa;
alter table public.casino_ct_giri enable row level security;
-- Nessuna policy: si legge solo dalle funzioni (i bonus in attesa non devono trapelare).

-- La ruota: 54 spicchi, stesso ordine nel client (src/components/CrazyTime.tsx, RUOTA).
create or replace function private.ct_ruota() returns text[] language sql immutable set search_path to '' as $$
  select array['ct','1','2','1','5','1', 'cf','1','2','1','2','1', 'pa','2','5','10','5','2', 'cf','1','5','1','2','1',
               'ch','1','10','1','2','1', 'cf','1','2','1','5','1', 'pa','2','10','2','5','2', 'cf','1','2','1','10','1',
               'ch','1','5','1','2','1']
$$;

-- Estrazione pesata (pesi anche decimali).
create or replace function private.ct_pesca(p_valori int[], p_pesi numeric[]) returns int language plpgsql volatile set search_path to '' as $$
declare v_x numeric := random() * (select sum(x) from unnest(p_pesi) x); i int;
begin
  for i in 1..array_length(p_valori, 1) loop
    v_x := v_x - p_pesi[i];
    if v_x < 0 then return p_valori[i]; end if;
  end loop;
  return p_valori[array_length(p_valori, 1)];
end $$;

-- Valori dei bonus (moltiplicatori: pagano M a 1 sulla puntata del bonus). -2 = DOUBLE, -3 = TRIPLE.
create or replace function private.ct_val_cf() returns int language sql volatile set search_path to '' as $$
  select private.ct_pesca(array[2,3,4,5,7,10,15,20,25,50,100], array[16,16,14,13,12,11,8,5,3,1.5,0.5]) $$;
create or replace function private.ct_val_ch() returns int language sql volatile set search_path to '' as $$
  select private.ct_pesca(array[5,7,10,15,20,25,50,75,100,200], array[22,19,18,14,10,7,6.5,2,1.5,0.5]) $$;
create or replace function private.ct_val_pa() returns int language sql volatile set search_path to '' as $$
  select private.ct_pesca(array[3,5,7,10,15,20,30,50,100,200], array[14,18,18,17,12,9,5,4,2,1]) $$;
create or replace function private.ct_val_ct() returns int language sql volatile set search_path to '' as $$
  select private.ct_pesca(array[5,7,10,15,20,25,50,75,100,200], array[15,14,15,13,12,10,9,5,4,3]) $$;

-- Crazy Time: bandierina p_flag (0 verde, 1 blu, 2 gialla) sulla ruota p_ruota (64 spicchi) con le rotazioni gia' estratte.
-- Ritorna il moltiplicatore finale (cap 2000) e quanti giri sono serviti.
create or replace function private.ct_cammino_crazy(p_ruota int[], p_rot int[], p_flag int) returns jsonb language plpgsql immutable set search_path to '' as $$
declare v_off int := (array[0, 21, 43])[p_flag + 1]; v_m int := 1; v_s int; i int;
begin
  for i in 1..array_length(p_rot, 1) loop
    v_s := p_ruota[((p_rot[i] + v_off) % 64) + 1];
    if v_s = -2 then v_m := v_m * 2;
    elsif v_s = -3 then v_m := v_m * 3;
    else return jsonb_build_object('valore', least(v_s * v_m, 2000), 'giri', i);
    end if;
  end loop;
  return jsonb_build_object('valore', least(200 * v_m, 2000), 'giri', array_length(p_rot, 1));
end $$;

-- Paga e chiude il giro: aggiorna il saldo (classifica casino' unica: miglior colpo) e il colpo grosso su SocialOne.
create or replace function private.ct_chiudi(p_giro_id bigint, p_extra bigint) returns public.casino_saldi language plpgsql security definer set search_path to '' as $$
declare g public.casino_ct_giri; v public.casino_saldi; v_nome text;
begin
  update public.casino_ct_giri set vinto = vinto + p_extra, in_attesa = false, concluso_il = now() where id = p_giro_id returning * into g;
  update public.casino_saldi set crediti = crediti + p_extra, max_vincita = greatest(max_vincita, g.vinto),
         totale_vinto = totale_vinto + p_extra, aggiornato_il = now()
   where league_id = g.league_id and user_id = g.user_id returning * into v;
  if g.vinto >= 1000 and g.vinto >= 100 * g.totale then
    select nome into v_nome from public.teams where id = g.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (g.league_id, 'crazytime:' || g.id, 'lega', 'BetOne Casinò', g.team_id,
            '🎡 CRAZYONE! ' || v_nome || ' vince ' || to_char(g.vinto, 'FM999G999G999') || ' crediti con un solo giro di ruota 🤑', now())
    on conflict do nothing;
  end if;
  return v;
end $$;

-- Parte pubblica di un bonus in attesa (niente risultati, niente posizioni dei moltiplicatori del Cash Hunt).
create or replace function private.ct_attesa_pubblica(g public.casino_ct_giri) returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object('id', g.id, 'esito', g.esito, 'puntata', (g.puntate ->> g.esito)::int,
    'molt', case when g.top_casella = g.esito then g.top_molt else 1 end,
    'valori', case when g.esito = 'ch' then (select jsonb_agg(x::int order by x::int) from jsonb_array_elements_text(g.bonus -> 'tavola') x) end,
    'ruota', case when g.esito = 'ct' then g.bonus -> 'ruota' end)
$$;

create or replace function public.casino_ct_stato(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_ct_giri;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_crazyone) then
    raise exception using errcode = '55000', message = 'CrazyOne non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  select * into g from public.casino_ct_giri where league_id = p_league_id and user_id = v_utente and in_attesa;
  return jsonb_build_object('crediti', v.crediti,
    'attesa', case when g.id is not null then private.ct_attesa_pubblica(g) end,
    'storia', coalesce((select jsonb_agg(s.esito order by s.id desc) from (select id, esito from public.casino_ct_giri
                         where league_id = p_league_id and user_id = v_utente order by id desc limit 14) s), '[]'::jsonb));
end $$;

create or replace function public.casino_ct_gira(p_league_id bigint, p_puntate jsonb) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  -- Top slot: su quale casella si accende (per mille, il resto = nessuna) e con che moltiplicatore.
  c_top_pesi constant numeric[] := array[83,90,50,34,86,69,82,73, 433];
  v_puntate jsonb := '{}'::jsonb;
  v_k text; v_p int; v_tot int := 0;
  v_top text; v_molt int; v_sp int; v_esito text; v_m int;
  v_vinto bigint := 0; v_bonus jsonb; v_attesa boolean := false; v_b int;
  v_tavola int[]; v_slot int; v_lanci jsonb := '[]'::jsonb; v_x int; i int; v_mm int;
  v_ruota int[]; v_rot int[]; v_pos int[];
  v_risultato jsonb;
  g public.casino_ct_giri;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_crazyone) then
    raise exception using errcode = '55000', message = 'CrazyOne non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  if exists (select 1 from public.casino_ct_giri where league_id = p_league_id and user_id = v_utente and in_attesa) then
    raise exception using errcode = '55000', message = 'Hai un bonus da giocare: finiscilo prima di girare di nuovo.';
  end if;

  -- Puntate: multipli di 10, al massimo 500 per casella e 2.000 in tutto.
  for v_k, v_p in select key, (value #>> '{}')::int from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    if not (v_k = any(c_caselle)) or v_p < 0 or v_p % 10 <> 0 or v_p > 500 then
      raise exception using errcode = '22023', message = 'Puntata non valida.';
    end if;
    if v_p > 0 then v_puntate := v_puntate || jsonb_build_object(v_k, v_p); v_tot := v_tot + v_p; end if;
  end loop;
  if v_tot = 0 then raise exception using errcode = '22023', message = 'Metti almeno una fiche.'; end if;
  if v_tot > 2000 then raise exception using errcode = '22023', message = 'Al massimo 2.000 crediti a giro.'; end if;
  if v.crediti < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;

  -- Top slot e ruota.
  v_x := private.ct_pesca(array[1,2,3,4,5,6,7,8,9], c_top_pesi);
  v_top := case when v_x <= 8 then c_caselle[v_x] end;
  v_molt := private.ct_pesca(array[2,3,5,10,15,25,50], array[35,25,18,12,5,3,2]);
  v_sp := floor(random() * 54)::int;
  v_esito := (private.ct_ruota())[v_sp + 1];
  v_m := case when v_top = v_esito then v_molt else 1 end;
  v_p := coalesce((v_puntate ->> v_esito)::int, 0);

  if v_esito in ('1', '2', '5', '10') then
    if v_p > 0 then v_vinto := v_p::bigint * v_esito::int * v_m + v_p; end if;
  elsif v_esito = 'cf' then
    v_x := private.ct_val_cf(); v_b := private.ct_val_cf();
    v_slot := case when random() < 0.5 then 0 else 1 end;   -- 0 rosso, 1 blu
    v_bonus := jsonb_build_object('rosso', v_x, 'blu', v_b, 'lato', case v_slot when 0 then 'rosso' else 'blu' end,
                                  'valore', case v_slot when 0 then v_x else v_b end);
    if v_p > 0 then v_vinto := v_p::bigint * least((v_bonus ->> 'valore')::int * v_m, 2500) + v_p; end if;
  elsif v_esito = 'pa' then
    -- Pachinko: 16 buche, 2 DOUBLE (raddoppiano tutta la tavola e si rilancia), al massimo 4 lanci.
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
    if v_p > 0 then v_vinto := v_p::bigint * least(v_b * v_m, 2500) + v_p; end if;
  elsif v_esito = 'ch' then
    v_bonus := jsonb_build_object('tavola', to_jsonb(array(select private.ct_val_ch() from generate_series(1, 108))));
    v_attesa := v_p > 0;
  else
    -- Crazy Time: 64 spicchi, 8 DOUBLE e 2 TRIPLE; rotazioni gia' estratte (la bandierina la sceglie il giocatore).
    v_ruota := array(select private.ct_val_ct() from generate_series(1, 64));
    v_pos := array(select x from generate_series(1, 64) x order by random() limit 10);
    for i in 1..8 loop v_ruota[v_pos[i]] := -2; end loop;
    v_ruota[v_pos[9]] := -3; v_ruota[v_pos[10]] := -3;
    v_rot := array(select floor(random() * 64)::int from generate_series(1, 6));
    v_bonus := jsonb_build_object('ruota', to_jsonb(v_ruota), 'rotazioni', to_jsonb(v_rot));
    v_attesa := v_p > 0;
  end if;

  update public.casino_saldi set crediti = crediti - v_tot + v_vinto, giri = giri + 1,
         max_vincita = greatest(max_vincita, v_vinto), totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente returning * into v;
  insert into public.casino_ct_giri (league_id, user_id, team_id, puntate, totale, top_casella, top_molt, spicchio, esito, bonus, in_attesa, vinto, concluso_il)
  values (p_league_id, v_utente, v.team_id, v_puntate, v_tot, v_top, v_molt, v_sp, v_esito, v_bonus, v_attesa, v_vinto,
          case when v_attesa then null else now() end)
  returning * into g;
  if not v_attesa and v_vinto > 0 then v := private.ct_chiudi(g.id, 0); end if;

  v_risultato := jsonb_build_object('id', g.id, 'spicchio', v_sp, 'esito', v_esito, 'top_casella', v_top, 'top_molt', v_molt,
    'puntate', v_puntate, 'totale', v_tot, 'vinto', v_vinto, 'crediti', v.crediti, 'max_vincita', v.max_vincita);
  if v_attesa then
    v_risultato := v_risultato || jsonb_build_object('attesa', private.ct_attesa_pubblica(g));
  elsif v_esito in ('cf', 'pa') then
    v_risultato := v_risultato || jsonb_build_object('bonus', v_bonus);
  end if;
  return v_risultato;
end $$;

-- Scelta nel bonus in attesa: Cash Hunt = indice del bersaglio (0-107), Crazy Time = bandierina (0-2).
create or replace function public.casino_ct_scegli(p_league_id bigint, p_scelta int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid());
  g public.casino_ct_giri; v public.casino_saldi;
  v_p int; v_m int; v_b int; v_c jsonb; v_extra bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  select * into g from public.casino_ct_giri where league_id = p_league_id and user_id = v_utente and in_attesa for update;
  if not found then raise exception using errcode = '55000', message = 'Nessun bonus da giocare.'; end if;
  v_p := (g.puntate ->> g.esito)::int;
  v_m := case when g.top_casella = g.esito then g.top_molt else 1 end;
  if g.esito = 'ch' then
    if p_scelta is null or p_scelta < 0 or p_scelta > 107 then raise exception using errcode = '22023', message = 'Bersaglio non valido.'; end if;
    v_b := (g.bonus -> 'tavola' ->> p_scelta)::int;
    v_c := jsonb_build_object('scelta', p_scelta, 'tavola', g.bonus -> 'tavola', 'valore', v_b);
  else
    if p_scelta is null or p_scelta not in (0, 1, 2) then raise exception using errcode = '22023', message = 'Bandierina non valida.'; end if;
    v_c := private.ct_cammino_crazy(array(select x::int from jsonb_array_elements_text(g.bonus -> 'ruota') x),
                                    array(select x::int from jsonb_array_elements_text(g.bonus -> 'rotazioni') x), p_scelta);
    v_b := (v_c ->> 'valore')::int;
    v_c := v_c || jsonb_build_object('scelta', p_scelta, 'ruota', g.bonus -> 'ruota',
      'rotazioni', (select jsonb_agg(x order by n) from jsonb_array_elements(g.bonus -> 'rotazioni') with ordinality t(x, n) where n <= (v_c ->> 'giri')::int));
  end if;
  v_extra := v_p::bigint * least(v_b * v_m, 2500) + v_p;
  update public.casino_ct_giri set bonus = bonus || jsonb_build_object('scelta', p_scelta) where id = g.id;
  v := private.ct_chiudi(g.id, v_extra);
  return v_c || jsonb_build_object('molt', v_m, 'puntata', v_p, 'vinto', v_extra, 'crediti', v.crediti, 'max_vincita', v.max_vincita);
end $$;

revoke all on function public.casino_ct_stato(bigint), public.casino_ct_gira(bigint, jsonb), public.casino_ct_scegli(bigint, int) from public, anon;
grant execute on function public.casino_ct_stato(bigint), public.casino_ct_gira(bigint, jsonb), public.casino_ct_scegli(bigint, int) to authenticated;
revoke all on function private.ct_chiudi(bigint, bigint) from public, anon, authenticated;

-- La pagina iniziale del casino' deve sapere se mostrare la copertina di CrazyOne.
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
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;
