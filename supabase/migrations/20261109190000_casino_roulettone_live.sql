begin;

-- RoulettOne LIVE (richiesta del committente, 9/11/2026): roulette europea (un solo zero), una ruota per lega uguale
-- per tutti, come AviatOne e CrazyOne live. Ciclo: 20 s per puntare -> ruota e pallina (9 s) -> numero (6 s) -> giro
-- successivo. Il numero si estrae alla CREAZIONE del giro, prima che si chiudano le puntate, e resta segreto (tabelle
-- senza policy) finche' la ruota non parte. Niente cron: il giro lo crea o lo fa avanzare la prima richiesta che arriva.
-- Pagamenti classici (pieno 35:1, chance semplici 1:1, dozzine e colonne 2:1): col solo zero il casino' rende il
-- 97,3%, in linea con gli altri giochi. Fiche come CrazyOne: multipli di 10, al massimo 500 a casella e 2.000 a giro.
-- Si accende per lega (leagues.casino_roulette); finche' e' spenta la vede solo il proprietario, per provarla.

alter table public.leagues add column if not exists casino_roulette boolean not null default false;

create table if not exists public.casino_rl_giri (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  apre_il timestamptz not null,
  chiude_il timestamptz not null,       -- fine delle puntate, parte la ruota
  esito_il timestamptz not null,        -- la pallina si ferma
  fine_il timestamptz not null,         -- dopo questo momento si crea il giro successivo
  numero smallint not null check (numero between 0 and 36),
  regolato boolean not null default false
);
create index if not exists casino_rl_giri_lega_idx on public.casino_rl_giri (league_id, id desc);
alter table public.casino_rl_giri enable row level security;

create table if not exists public.casino_rl_giocate (
  id bigint generated always as identity primary key,
  giro_id bigint not null references public.casino_rl_giri(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntate jsonb not null,
  totale integer not null check (totale > 0),
  vinto bigint not null default 0,
  unique (giro_id, user_id)
);
create index if not exists casino_rl_giocate_lega_idx on public.casino_rl_giocate (league_id);
alter table public.casino_rl_giocate enable row level security;
-- Nessuna policy su entrambe: si legge solo dalle funzioni (i grant servono solo a un database ricreato da zero).
grant select on public.casino_rl_giri, public.casino_rl_giocate to anon;
grant select, insert, update, delete on public.casino_rl_giri, public.casino_rl_giocate to authenticated, service_role;

-- Le caselle del tavolo: n0..n36 (pieno), chance semplici, dozzine (d1-d3), colonne (c1-c3).
create or replace function private.rl_caselle() returns text[] language sql immutable set search_path to '' as $$
  select array(select 'n' || x from generate_series(0, 36) x)
         || array['rosso','nero','pari','dispari','manque','passe','d1','d2','d3','c1','c2','c3']
$$;

create or replace function private.rl_rosso(p_n int) returns boolean language sql immutable set search_path to '' as $$
  select p_n = any(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36])
$$;

-- Quanto torna indietro (puntata compresa) una mappa di puntate col numero p_n.
create or replace function private.rl_vincita(p_puntate jsonb, p_n int) returns bigint language plpgsql immutable set search_path to '' as $$
declare v_k text; v_p bigint; v_tot bigint := 0; v_x int;
begin
  for v_k, v_p in select key, (value #>> '{}')::bigint from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    v_x := case
      when v_k = 'n' || p_n then 36
      when p_n = 0 then 0
      when v_k = 'rosso' and private.rl_rosso(p_n) then 2
      when v_k = 'nero' and not private.rl_rosso(p_n) then 2
      when v_k = 'pari' and p_n % 2 = 0 then 2
      when v_k = 'dispari' and p_n % 2 = 1 then 2
      when v_k = 'manque' and p_n <= 18 then 2
      when v_k = 'passe' and p_n >= 19 then 2
      when v_k = 'd1' and p_n <= 12 then 3
      when v_k = 'd2' and p_n between 13 and 24 then 3
      when v_k = 'd3' and p_n >= 25 then 3
      when v_k = 'c1' and p_n % 3 = 1 then 3
      when v_k = 'c2' and p_n % 3 = 2 then 3
      when v_k = 'c3' and p_n % 3 = 0 then 3
      else 0 end;
    v_tot := v_tot + v_p * v_x;
  end loop;
  return v_tot;
end $$;

-- Accesa nella lega, oppure il proprietario che la prova prima che si accenda per tutti.
create or replace function private.rl_attivo(p_league_id bigint) returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile((select auth.uid())) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa
                   and (l.casino_roulette or private.e_proprietario_gioco())) then
    raise exception using errcode = '55000', message = 'RoulettOne non è attivo in questa lega.';
  end if;
end $$;

-- Giro corrente della lega: se l'ultimo e' finito ne estrae uno nuovo, numero compreso.
create or replace function private.rl_giro(p_league_id bigint) returns public.casino_rl_giri language plpgsql security definer set search_path to '' as $$
declare g public.casino_rl_giri; v_ora timestamptz := clock_timestamp(); v_chiude timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('roulettone:' || p_league_id));
  select * into g from public.casino_rl_giri where league_id = p_league_id order by id desc limit 1;
  if g.id is not null and v_ora < g.fine_il then return g; end if;
  v_chiude := v_ora + interval '20 seconds';
  insert into public.casino_rl_giri (league_id, apre_il, chiude_il, esito_il, fine_il, numero)
  values (p_league_id, v_ora, v_chiude, v_chiude + interval '9 seconds', v_chiude + interval '15 seconds', floor(random() * 37)::int)
  returning * into g;
  return g;
end $$;

-- Paga il giro (una volta sola) appena la pallina si ferma.
create or replace function private.rl_regola(p_giro bigint) returns void language plpgsql security definer set search_path to '' as $$
declare g public.casino_rl_giri; q public.casino_rl_giocate; v_vinto bigint; v_nome text;
begin
  select * into g from public.casino_rl_giri where id = p_giro for update;
  if g.regolato or clock_timestamp() < g.esito_il then return; end if;
  for q in select * from public.casino_rl_giocate where giro_id = g.id for update loop
    v_vinto := private.rl_vincita(q.puntate, g.numero);
    if v_vinto > 0 then
      update public.casino_rl_giocate set vinto = v_vinto where id = q.id;
      update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto,
             max_vincita = greatest(max_vincita, v_vinto), aggiornato_il = now()
       where league_id = q.league_id and user_id = q.user_id;
      -- Colpo grosso su SocialOne: almeno 1.000 crediti e 30 volte il puntato (in pratica un pieno centrato).
      if v_vinto >= 1000 and v_vinto >= 30 * q.totale then
        select nome into v_nome from public.teams where id = q.team_id;
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
        values (q.league_id, 'roulettone-live:' || q.id, 'lega', 'BetOne Casinò', q.team_id,
                '🎯 ROULETTONE! ' || v_nome || ' centra il ' || g.numero || ' e vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti 🤑', now())
        on conflict do nothing;
      end if;
    end if;
  end loop;
  update public.casino_rl_giri set regolato = true where id = g.id;
end $$;

-- Stato del giro per la pagina: il numero si rivela solo quando la ruota parte (puntate gia' chiuse).
create or replace function private.rl_stato(p_league_id bigint, p_giro bigint) returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare g public.casino_rl_giri; v_ora timestamptz := clock_timestamp(); v_giro jsonb;
begin
  select * into g from public.casino_rl_giri where id = p_giro;
  v_giro := jsonb_build_object('id', g.id,
    'apre', floor(extract(epoch from g.apre_il) * 1000), 'chiude', floor(extract(epoch from g.chiude_il) * 1000),
    'esito_il', floor(extract(epoch from g.esito_il) * 1000), 'fine', floor(extract(epoch from g.fine_il) * 1000),
    'regolato', g.regolato);
  if v_ora >= g.chiude_il then v_giro := v_giro || jsonb_build_object('numero', g.numero); end if;
  return jsonb_build_object(
    'adesso', floor(extract(epoch from v_ora) * 1000),
    'giro', v_giro,
    'giocate', coalesce((select jsonb_agg(jsonb_build_object('team_id', q.team_id, 'totale', q.totale, 'mia', q.user_id = (select auth.uid()),
                          'vinto', case when g.regolato then q.vinto end,
                          'puntate', case when q.user_id = (select auth.uid()) then q.puntate end) order by q.totale desc, q.id)
                        from public.casino_rl_giocate q where q.giro_id = g.id), '[]'::jsonb),
    'crediti', (select s.crediti from public.casino_saldi s where s.league_id = p_league_id and s.user_id = (select auth.uid())),
    'storia', coalesce((select jsonb_agg(x.numero order by x.id desc) from (select id, numero from public.casino_rl_giri
                         where league_id = p_league_id and esito_il <= v_ora order by id desc limit 16) x), '[]'::jsonb));
end $$;

create or replace function public.casino_rl_live(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare g public.casino_rl_giri; v_prec bigint;
begin
  perform private.rl_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('roulettone:' || p_league_id));   -- prima del saldo: evita i deadlock
  perform private.casino_saldo(p_league_id, (select auth.uid()));
  -- I giri precedenti si regolano anche se nessuno era collegato al momento giusto.
  for v_prec in select id from public.casino_rl_giri where league_id = p_league_id and not regolato
                  and esito_il <= clock_timestamp() order by id loop
    perform private.rl_regola(v_prec);
  end loop;
  g := private.rl_giro(p_league_id);
  perform private.rl_regola(g.id);
  return private.rl_stato(p_league_id, g.id);
end $$;

-- Puntate del giro: p_puntate e' la mappa completa (sostituisce la precedente; {} = nessuna puntata).
create or replace function public.casino_rl_punta(p_league_id bigint, p_puntate jsonb) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_rl_giri; q public.casino_rl_giocate;
  v_k text; v_p int; v_tot int := 0; v_mappa jsonb := '{}'::jsonb; v_vecchio int := 0;
begin
  perform private.rl_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('roulettone:' || p_league_id));   -- prima del saldo: evita i deadlock
  v := private.casino_saldo(p_league_id, v_utente);
  g := private.rl_giro(p_league_id);
  if clock_timestamp() >= g.chiude_il then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo giro.'; end if;
  for v_k, v_p in select key, (value #>> '{}')::int from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    if not (v_k = any(private.rl_caselle())) or v_p < 0 or v_p % 10 <> 0 or v_p > 500 then raise exception using errcode = '22023', message = 'Puntata non valida.'; end if;
    if v_p > 0 then v_mappa := v_mappa || jsonb_build_object(v_k, v_p); v_tot := v_tot + v_p; end if;
  end loop;
  if v_tot > 2000 then raise exception using errcode = '22023', message = 'Al massimo 2.000 crediti a giro.'; end if;
  select * into q from public.casino_rl_giocate where giro_id = g.id and user_id = v_utente for update;
  if q.id is not null then v_vecchio := q.totale; end if;
  if v.crediti + v_vecchio < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti + v_vecchio - v_tot,
         giri = giri + (case when q.id is null and v_tot > 0 then 1 when q.id is not null and v_tot = 0 then -1 else 0 end), aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;
  if v_tot = 0 then
    delete from public.casino_rl_giocate where id = q.id;
  elsif q.id is null then
    insert into public.casino_rl_giocate (giro_id, league_id, user_id, team_id, puntate, totale) values (g.id, p_league_id, v_utente, v.team_id, v_mappa, v_tot);
  else
    update public.casino_rl_giocate set puntate = v_mappa, totale = v_tot where id = q.id;
  end if;
  return private.rl_stato(p_league_id, g.id);
end $$;

revoke all on function public.casino_rl_live(bigint), public.casino_rl_punta(bigint, jsonb) from public, anon;
grant execute on function public.casino_rl_live(bigint), public.casino_rl_punta(bigint, jsonb) to authenticated;
revoke all on function private.rl_giro(bigint), private.rl_regola(bigint) from public, anon, authenticated;

-- Chat della roulette.
alter table public.casino_chat drop constraint if exists casino_chat_canale_check;
alter table public.casino_chat add constraint casino_chat_canale_check check (canale ~ '^(crazy|aviat|roul|bj:[0-9]+)$');

-- Chat, classifica e bustine (casino_movimenti), interruttore nella pagina del casino'.
CREATE OR REPLACE FUNCTION private.casino_chat_accesso(p_league_id bigint, p_canale text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); v_team bigint; v_ok boolean;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = v_utente and t.attiva;
  if v_team is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  if p_canale = 'crazy' then
    select l.casino_crazyone into v_ok from public.leagues l where l.id = p_league_id;
  elsif p_canale = 'aviat' then
    select l.casino_aviatone into v_ok from public.leagues l where l.id = p_league_id;
  elsif p_canale = 'roul' then
    select l.casino_roulette or private.e_proprietario_gioco() into v_ok from public.leagues l where l.id = p_league_id;
  elsif p_canale ~ '^bj:[0-9]+$' then
    -- La chat del tavolo la vedono solo i giocatori seduti.
    select exists (select 1 from public.casino_bjl_posti p
                    where p.tavolo_id = split_part(p_canale, ':', 2)::bigint and p.league_id = p_league_id and p.user_id = v_utente) into v_ok;
  else
    raise exception using errcode = '22023', message = 'Canale non valido.';
  end if;
  if not coalesce(v_ok, false) then raise exception using errcode = '42501', message = 'Chat non disponibile.'; end if;
  return v_team;
end $function$;

CREATE OR REPLACE FUNCTION private.casino_movimenti(p_league_id bigint)
 RETURNS TABLE(gioco text, team_id bigint, speso bigint, vinto bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select 'slot', g.team_id, (case when g.gratis then 0 else g.puntata end)::bigint, g.vinto from public.casino_giri g where g.league_id = p_league_id
  union all select 'crazy', g.team_id, g.totale::bigint, g.vinto from public.casino_ct_giri g where g.league_id = p_league_id and not g.in_attesa
  union all select 'crazy', q.team_id, q.totale::bigint, q.vinto from public.casino_ctl_giocate q join public.casino_ctl_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.regolato
  union all select 'aviat', v.team_id, v.totale::bigint, v.vinto from public.casino_av_voli v where v.league_id = p_league_id and v.finito
  union all select 'aviat', q.team_id, q.puntata::bigint, q.vinto from public.casino_av_giocate q join public.casino_av_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.finisce_il <= now()
  union all select 'roul', q.team_id, q.totale::bigint, q.vinto from public.casino_rl_giocate q join public.casino_rl_giri g on g.id = q.giro_id where q.league_id = p_league_id and g.regolato
  union all select 'bj', m.team_id, ((select coalesce(sum((x ->> 'puntata')::int), 0) from jsonb_array_elements(m.mani) x) + m.assicurazione)::bigint, m.vinto from public.casino_bj_mani m where m.league_id = p_league_id and m.stato = 'finita'
  union all select 'bj', s.team_id, s.puntato::bigint, s.vinto from public.casino_bjl_storico s where s.league_id = p_league_id
$function$;

CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  v_speso bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.casino_bustine_speso(p_league_id);
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  select coalesce(sum(m.speso), 0) into v_speso from private.casino_movimenti(p_league_id) m where m.team_id = v.team_id;
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'bonus_aperto', (select jsonb_build_object('id', b.id, 'tipo', b.tipo) from public.casino_slot_bonus b where b.league_id = p_league_id and b.user_id = v_utente and b.stato = 'aperto' order by b.id limit 1),
    'bustina_spesi', greatest(0, v_speso - v.speso_base - 500 * v.bustine_speso),
    'bustine_oggi', case when v.bustine_giorno = private.casino_settimana() then v.bustine_oggi else 0 end,
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'roulette', (select l.casino_roulette or private.e_proprietario_gioco() from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '22 hours 10 minutes') at time zone 'Europe/Rome'));
end $function$;

commit;
