-- BlackjackOne LIVE: tavoli condivisi da massimo 4 giocatori contro un solo banco (decisione del committente).
-- Piu' tavoli per lega: ci si siede a un tavolo scelto o al primo posto libero (se sono tutti pieni se ne apre uno).
-- Giro: puntate 15 s -> distribuzione -> (assicurazione 8 s se il banco mostra un asso) -> turni (15 s per decisione,
-- allo scadere si sta) -> il banco gioca una volta per tutti -> risultati -> giro successivo.
-- Niente cron: il tavolo avanza a ogni richiesta (private.bjl_avanza, con lucchetto per tavolo). Le carte dei giocatori
-- sono pubbliche come al tavolo vero; restano segrete la scarpa e la carta coperta del banco fino ai risultati.
-- Regole e pagamenti come il tavolo personale (20261020260000): 6 mazzi, 3:2, banco su tutti i 17, raddoppio anche
-- dopo la divisione, divisione fino a 4 mani, assi divisi con una carta, assicurazione 2:1.
-- Chi non chiede lo stato da 60 s perde il posto a fine mano. Il tavolo personale resta in archivio, non piu' usato.

create table if not exists public.casino_bjl_tavoli (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  numero integer not null,
  fase text not null default 'attesa' check (fase in ('attesa', 'puntate', 'assicurazione', 'turni', 'risultato')),
  scadenza timestamptz,
  scarpa int[] not null default '{}',
  banco int[] not null default '{}',
  turno_posto smallint,
  turno_mano smallint,
  giro integer not null default 0,
  unique (league_id, numero)
);
alter table public.casino_bjl_tavoli enable row level security;
grant select on public.casino_bjl_tavoli to anon;
grant select, insert, update, delete on public.casino_bjl_tavoli to authenticated, service_role;

create table if not exists public.casino_bjl_posti (
  id bigint generated always as identity primary key,
  tavolo_id bigint not null references public.casino_bjl_tavoli(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  posto smallint not null check (posto between 1 and 4),
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  ultimo_visto timestamptz not null default now(),
  puntata integer not null default 0,
  mani jsonb not null default '[]'::jsonb,
  assicurazione integer not null default 0,
  assicurazione_decisa boolean not null default false,
  vinto bigint,
  unique (tavolo_id, posto),
  unique (league_id, user_id)
);
alter table public.casino_bjl_posti enable row level security;
grant select on public.casino_bjl_posti to anon;
grant select, insert, update, delete on public.casino_bjl_posti to authenticated, service_role;
-- Nessuna policy su entrambe: si legge solo dalle funzioni.

-- Mano attiva da giocare dopo (posto, mano) in ordine; null se non ce ne sono.
create or replace function private.bjl_prossimo(p_tavolo bigint, p_posto int, p_mano int) returns int[] language sql stable set search_path to '' as $$
  select array[s.posto, (e.n - 1)::int] from public.casino_bjl_posti s, jsonb_array_elements(s.mani) with ordinality e(m, n)
   where s.tavolo_id = p_tavolo and s.puntata > 0 and not coalesce((e.m ->> 'fatto')::boolean, false)
     and (s.posto > p_posto or (s.posto = p_posto and e.n - 1 > p_mano))
   order by s.posto, e.n limit 1
$$;

-- Il banco gioca e si paga ogni posto; il tavolo passa ai risultati.
create or replace function private.bjl_chiudi(p_tavolo bigint) returns void language plpgsql security definer set search_path to '' as $$
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
end $$;

-- Passa al turno successivo (o fa giocare il banco se non resta nessuno).
create or replace function private.bjl_turno_dopo(p_tavolo bigint, p_posto int, p_mano int, p_attesa numeric default 15) returns void language plpgsql security definer set search_path to '' as $$
declare v int[];
begin
  v := private.bjl_prossimo(p_tavolo, p_posto, p_mano);
  if v is null then perform private.bjl_chiudi(p_tavolo);
  else update public.casino_bjl_tavoli set fase = 'turni', turno_posto = v[1], turno_mano = v[2], scadenza = clock_timestamp() + make_interval(secs => p_attesa) where id = p_tavolo;
  end if;
end $$;

-- Una carta alla mano i del posto (se arriva a 21 o sballa, la mano e' fatta).
create or replace function private.bjl_carta_a(p_tavolo bigint, p_posto_id bigint, i int) returns void language plpgsql security definer set search_path to '' as $$
declare c int; s public.casino_bjl_posti; v_carte int[]; v_pt int;
begin
  select scarpa[1] into c from public.casino_bjl_tavoli where id = p_tavolo for update;
  update public.casino_bjl_tavoli set scarpa = scarpa[2:] where id = p_tavolo;
  select * into s from public.casino_bjl_posti where id = p_posto_id;
  v_carte := private.bj_carte(s.mani -> i) || c;
  v_pt := private.bj_totale(v_carte);
  update public.casino_bjl_posti set mani = jsonb_set(mani, array[i::text], (mani -> i) || jsonb_build_object('carte', to_jsonb(v_carte), 'fatto', v_pt >= 21 or coalesce((mani -> i ->> 'fatto')::boolean, false)))
   where id = p_posto_id;
end $$;

-- Fa avanzare il tavolo secondo le scadenze (puntate chiuse, assicurazione, turni scaduti, nuovo giro).
create or replace function private.bjl_avanza(p_tavolo bigint) returns void language plpgsql security definer set search_path to '' as $$
declare t public.casino_bjl_tavoli; v_ora timestamptz; v_scarpa int[]; s record; k int; v_cicli int := 0; v_peek boolean;
begin
  loop
    v_cicli := v_cicli + 1; exit when v_cicli > 8;
    select * into t from public.casino_bjl_tavoli where id = p_tavolo for update;
    v_ora := clock_timestamp();
    if t.fase = 'attesa' then
      exit when not exists (select 1 from public.casino_bjl_posti where tavolo_id = p_tavolo);
      update public.casino_bjl_tavoli set fase = 'puntate', scadenza = v_ora + interval '15 seconds' where id = p_tavolo;
    elsif t.fase = 'puntate' then
      exit when v_ora < t.scadenza;
      if not exists (select 1 from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0) then
        update public.casino_bjl_tavoli set fase = case when exists (select 1 from public.casino_bjl_posti where tavolo_id = p_tavolo) then 'puntate' else 'attesa' end,
               scadenza = v_ora + interval '15 seconds' where id = p_tavolo;
        exit;
      end if;
      -- distribuzione: una carta a ogni posto, una al banco, la seconda a ogni posto, la coperta al banco
      v_scarpa := array(select x % 52 from generate_series(0, 311) x order by random());
      k := 1;
      for s in select id from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0 order by posto loop
        update public.casino_bjl_posti set mani = jsonb_build_array(jsonb_build_object('carte', jsonb_build_array(v_scarpa[k]), 'puntata', puntata, 'fatto', false)),
               assicurazione = 0, assicurazione_decisa = false, vinto = null where id = s.id;
        k := k + 1;
      end loop;
      t.banco := array[v_scarpa[k]]; k := k + 1;
      for s in select id from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0 order by posto loop
        update public.casino_bjl_posti set mani = jsonb_set(mani, '{0}', (mani -> 0) || jsonb_build_object('carte', (mani -> 0 -> 'carte') || to_jsonb(v_scarpa[k]),
               'fatto', private.bj_totale(array[(mani -> 0 -> 'carte' ->> 0)::int, v_scarpa[k]]) = 21)) where id = s.id;
        k := k + 1;
      end loop;
      t.banco := t.banco || v_scarpa[k]; k := k + 1;
      update public.casino_bjl_tavoli set scarpa = v_scarpa[k:], banco = t.banco, giro = giro + 1 where id = p_tavolo;
      update public.casino_saldi s2 set giri = giri + 1 from public.casino_bjl_posti p where p.tavolo_id = p_tavolo and p.puntata > 0 and s2.league_id = p.league_id and s2.user_id = p.user_id;
      if t.banco[1] % 13 = 0 then
        update public.casino_bjl_tavoli set fase = 'assicurazione', scadenza = v_ora + interval '10 seconds' where id = p_tavolo;   -- 2 s di distribuzione + 8 s
      elsif private.bj_valore(t.banco[1]) = 10 and private.bj_totale(t.banco) = 21 then
        perform private.bjl_chiudi(p_tavolo);
      else
        perform private.bjl_turno_dopo(p_tavolo, 0, -1, 17);   -- 2 s di distribuzione + 15 s per il primo
      end if;
    elsif t.fase = 'assicurazione' then
      exit when v_ora < t.scadenza and exists (select 1 from public.casino_bjl_posti where tavolo_id = p_tavolo and puntata > 0 and not assicurazione_decisa);
      v_peek := private.bj_totale(t.banco) = 21;
      if v_peek then perform private.bjl_chiudi(p_tavolo); else perform private.bjl_turno_dopo(p_tavolo, 0, -1, 15); end if;
    elsif t.fase = 'turni' then
      exit when v_ora < t.scadenza;
      -- tempo scaduto: la mano di turno sta
      update public.casino_bjl_posti set mani = jsonb_set(mani, array[t.turno_mano::text], (mani -> t.turno_mano::int) || '{"fatto": true, "scaduta": true}'::jsonb)
       where tavolo_id = p_tavolo and posto = t.turno_posto;
      perform private.bjl_turno_dopo(p_tavolo, t.turno_posto, t.turno_mano);
    elsif t.fase = 'risultato' then
      exit when v_ora < t.scadenza;
      -- nuovo giro: si azzera, e chi non si vede da 60 s perde il posto
      delete from public.casino_bjl_posti where tavolo_id = p_tavolo and ultimo_visto < v_ora - interval '60 seconds';
      update public.casino_bjl_posti set puntata = 0, mani = '[]'::jsonb, assicurazione = 0, assicurazione_decisa = false, vinto = null where tavolo_id = p_tavolo;
      update public.casino_bjl_tavoli set banco = '{}', scarpa = '{}', fase = case when exists (select 1 from public.casino_bjl_posti where tavolo_id = p_tavolo) then 'puntate' else 'attesa' end,
             scadenza = v_ora + interval '15 seconds' where id = p_tavolo;
    end if;
  end loop;
end $$;

-- Parte pubblica del tavolo (la coperta del banco solo ai risultati).
create or replace function private.bjl_pubblico(p_league_id bigint, p_tavolo bigint) returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'adesso', floor(extract(epoch from clock_timestamp()) * 1000),
    'tavolo', jsonb_build_object('id', t.id, 'numero', t.numero, 'fase', t.fase, 'giro', t.giro,
      'scadenza', case when t.scadenza is not null then floor(extract(epoch from t.scadenza) * 1000) end,
      'turno_posto', t.turno_posto, 'turno_mano', t.turno_mano,
      'banco', case when t.fase = 'risultato' then to_jsonb(t.banco) when array_length(t.banco, 1) >= 1 then jsonb_build_array(t.banco[1], null) else '[]'::jsonb end),
    'posti', coalesce((select jsonb_agg(jsonb_build_object('posto', s.posto, 'team_id', s.team_id, 'mio', s.user_id = (select auth.uid()),
                        'puntata', s.puntata, 'mani', s.mani, 'assicurazione', s.assicurazione, 'assicurazione_decisa', s.assicurazione_decisa, 'vinto', s.vinto,
                        'assente', s.ultimo_visto < clock_timestamp() - interval '20 seconds') order by s.posto)
                       from public.casino_bjl_posti s where s.tavolo_id = t.id), '[]'::jsonb),
    'crediti', (select c.crediti from public.casino_saldi c where c.league_id = p_league_id and c.user_id = (select auth.uid())))
  from public.casino_bjl_tavoli t where t.id = p_tavolo
$$;

-- Sala: i tavoli della lega con chi c'e' seduto (e quello dove sono io).
create or replace function public.casino_bjl_sala(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v public.casino_saldi;
begin
  perform private.bj_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, (select auth.uid()));
  return jsonb_build_object('crediti', v.crediti,
    'mio_tavolo', (select tavolo_id from public.casino_bjl_posti where league_id = p_league_id and user_id = (select auth.uid())),
    'tavoli', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'numero', t.numero, 'fase', t.fase,
                 'posti', (select coalesce(jsonb_agg(jsonb_build_object('posto', s.posto, 'team_id', s.team_id) order by s.posto), '[]'::jsonb) from public.casino_bjl_posti s where s.tavolo_id = t.id))
               order by t.numero) from public.casino_bjl_tavoli t
               where t.league_id = p_league_id and exists (select 1 from public.casino_bjl_posti s where s.tavolo_id = t.id)), '[]'::jsonb));
end $$;

-- Siediti: al tavolo scelto (se c'e' posto) o al primo posto libero; se sono tutti pieni si apre un tavolo nuovo.
create or replace function public.casino_bjl_siedi(p_league_id bigint, p_tavolo bigint default null) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; v_tavolo bigint; v_posto int; v_attuale bigint;
begin
  perform private.bj_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('bjl-lega:' || p_league_id));
  select tavolo_id into v_attuale from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if v_attuale is not null then return private.bjl_pubblico(p_league_id, v_attuale); end if;
  v := private.casino_saldo(p_league_id, v_utente);
  if p_tavolo is not null then
    select t.id into v_tavolo from public.casino_bjl_tavoli t where t.id = p_tavolo and t.league_id = p_league_id
       and (select count(*) from public.casino_bjl_posti s where s.tavolo_id = t.id) < 4;
    if v_tavolo is null then raise exception using errcode = '55000', message = 'Questo tavolo è pieno: scegline un altro.'; end if;
  else
    select t.id into v_tavolo from public.casino_bjl_tavoli t where t.league_id = p_league_id
       and (select count(*) from public.casino_bjl_posti s where s.tavolo_id = t.id) between 1 and 3 order by t.numero limit 1;
    if v_tavolo is null then
      select t.id into v_tavolo from public.casino_bjl_tavoli t where t.league_id = p_league_id
         and not exists (select 1 from public.casino_bjl_posti s where s.tavolo_id = t.id) order by t.numero limit 1;
    end if;
    if v_tavolo is null then
      insert into public.casino_bjl_tavoli (league_id, numero)
      values (p_league_id, coalesce((select max(numero) from public.casino_bjl_tavoli where league_id = p_league_id), 0) + 1) returning id into v_tavolo;
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || v_tavolo));
  select min(n) into v_posto from generate_series(1, 4) n where not exists (select 1 from public.casino_bjl_posti s where s.tavolo_id = v_tavolo and s.posto = n);
  insert into public.casino_bjl_posti (tavolo_id, league_id, posto, user_id, team_id) values (v_tavolo, p_league_id, v_posto, v_utente, v.team_id);
  perform private.bjl_avanza(v_tavolo);
  return private.bjl_pubblico(p_league_id, v_tavolo);
end $$;

-- Alzati: si puo' solo se non si ha una mano in gioco (durante le puntate la puntata viene restituita).
create or replace function public.casino_bjl_alzati(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); s public.casino_bjl_posti; t public.casino_bjl_tavoli;
begin
  perform private.bj_attivo(p_league_id);
  select * into s from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if s.id is null then return public.casino_bjl_sala(p_league_id); end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || s.tavolo_id));
  select * into t from public.casino_bjl_tavoli where id = s.tavolo_id;
  if s.puntata > 0 and t.fase not in ('puntate', 'attesa', 'risultato') then
    raise exception using errcode = '55000', message = 'Hai una mano in gioco: alzati alla fine della mano.';
  end if;
  if s.puntata > 0 and t.fase in ('puntate', 'attesa') then
    update public.casino_saldi set crediti = crediti + s.puntata where league_id = p_league_id and user_id = v_utente;
  end if;
  delete from public.casino_bjl_posti where id = s.id;
  return public.casino_bjl_sala(p_league_id);
end $$;

-- Stato del mio tavolo (la pagina lo chiede ogni secondo): segna che ci sono e fa avanzare il tavolo.
create or replace function public.casino_bjl_stato(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v_tavolo bigint;
begin
  perform private.bj_attivo(p_league_id);
  select tavolo_id into v_tavolo from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if v_tavolo is null then return jsonb_build_object('seduto', false); end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || v_tavolo));
  perform private.casino_saldo(p_league_id, v_utente);
  update public.casino_bjl_posti set ultimo_visto = now() where league_id = p_league_id and user_id = v_utente;
  perform private.bjl_avanza(v_tavolo);
  return private.bjl_pubblico(p_league_id, v_tavolo) || jsonb_build_object('seduto', true);
end $$;

-- Puntata del giro (solo durante le puntate; sostituisce la precedente, 0 = nessuna).
create or replace function public.casino_bjl_punta(p_league_id bigint, p_puntata int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; s public.casino_bjl_posti; t public.casino_bjl_tavoli;
begin
  perform private.bj_attivo(p_league_id);
  select * into s from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if s.id is null then raise exception using errcode = '55000', message = 'Siediti a un tavolo per giocare.'; end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || s.tavolo_id));
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.bjl_avanza(s.tavolo_id);
  select * into t from public.casino_bjl_tavoli where id = s.tavolo_id;
  select * into s from public.casino_bjl_posti where id = s.id;
  if t.fase not in ('puntate', 'attesa') then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo giro.'; end if;
  if p_puntata is null or p_puntata < 0 or p_puntata > 500 or p_puntata % 10 <> 0 or (p_puntata > 0 and p_puntata < 10) then
    raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).';
  end if;
  if v.crediti + s.puntata < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti + s.puntata - p_puntata, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  update public.casino_bjl_posti set puntata = p_puntata, ultimo_visto = now() where id = s.id;
  return private.bjl_pubblico(p_league_id, s.tavolo_id) || jsonb_build_object('seduto', true);
end $$;

create or replace function public.casino_bjl_assicura(p_league_id bigint, p_si boolean) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; s public.casino_bjl_posti; t public.casino_bjl_tavoli; v_costo int;
begin
  perform private.bj_attivo(p_league_id);
  select * into s from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if s.id is null then raise exception using errcode = '55000', message = 'Siediti a un tavolo per giocare.'; end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || s.tavolo_id));
  v := private.casino_saldo(p_league_id, v_utente);
  select * into t from public.casino_bjl_tavoli where id = s.tavolo_id;
  select * into s from public.casino_bjl_posti where id = s.id;
  if t.fase <> 'assicurazione' or s.puntata = 0 or s.assicurazione_decisa then raise exception using errcode = '55000', message = 'Non è il momento dell''assicurazione.'; end if;
  if p_si then
    v_costo := s.puntata / 2;
    if v.crediti < v_costo then raise exception using errcode = '22023', message = 'Crediti insufficienti per l''assicurazione.'; end if;
    update public.casino_saldi set crediti = crediti - v_costo where league_id = p_league_id and user_id = v_utente;
  end if;
  update public.casino_bjl_posti set assicurazione = case when p_si then s.puntata / 2 else 0 end, assicurazione_decisa = true, ultimo_visto = now() where id = s.id;
  perform private.bjl_avanza(s.tavolo_id);
  return private.bjl_pubblico(p_league_id, s.tavolo_id) || jsonb_build_object('seduto', true);
end $$;

-- Mossa del giocatore di turno: 'carta', 'stai', 'raddoppia', 'dividi'.
create or replace function public.casino_bjl_azione(p_league_id bigint, p_azione text) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; s public.casino_bjl_posti; t public.casino_bjl_tavoli;
  i int; m jsonb; v_carte int[]; v_p int; v_assi boolean;
begin
  perform private.bj_attivo(p_league_id);
  select * into s from public.casino_bjl_posti where league_id = p_league_id and user_id = v_utente;
  if s.id is null then raise exception using errcode = '55000', message = 'Siediti a un tavolo per giocare.'; end if;
  perform pg_advisory_xact_lock(hashtext('bjl:' || s.tavolo_id));
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.bjl_avanza(s.tavolo_id);
  select * into t from public.casino_bjl_tavoli where id = s.tavolo_id;
  select * into s from public.casino_bjl_posti where id = s.id;
  if t.fase <> 'turni' or t.turno_posto <> s.posto then raise exception using errcode = '55000', message = 'Non è il tuo turno.'; end if;
  i := t.turno_mano; m := s.mani -> i; v_carte := private.bj_carte(m); v_p := (m ->> 'puntata')::int;
  if p_azione = 'carta' then
    perform private.bjl_carta_a(t.id, s.id, i);
  elsif p_azione = 'stai' then
    update public.casino_bjl_posti set mani = jsonb_set(mani, array[i::text], (mani -> i) || '{"fatto": true}'::jsonb) where id = s.id;
  elsif p_azione = 'raddoppia' then
    if array_length(v_carte, 1) <> 2 then raise exception using errcode = '22023', message = 'Si raddoppia solo con due carte.'; end if;
    if v.crediti < v_p then raise exception using errcode = '22023', message = 'Crediti insufficienti per raddoppiare.'; end if;
    update public.casino_saldi set crediti = crediti - v_p where league_id = p_league_id and user_id = v_utente;
    update public.casino_bjl_posti set mani = jsonb_set(mani, array[i::text], (mani -> i) || jsonb_build_object('puntata', 2 * v_p, 'raddoppiata', true)) where id = s.id;
    perform private.bjl_carta_a(t.id, s.id, i);
    update public.casino_bjl_posti set mani = jsonb_set(mani, array[i::text], (mani -> i) || '{"fatto": true}'::jsonb) where id = s.id;
  elsif p_azione = 'dividi' then
    if array_length(v_carte, 1) <> 2 or private.bj_valore(v_carte[1]) <> private.bj_valore(v_carte[2]) or jsonb_array_length(s.mani) >= 4 then
      raise exception using errcode = '22023', message = 'Questa mano non si può dividere.';
    end if;
    if v.crediti < v_p then raise exception using errcode = '22023', message = 'Crediti insufficienti per dividere.'; end if;
    update public.casino_saldi set crediti = crediti - v_p where league_id = p_league_id and user_id = v_utente;
    v_assi := v_carte[1] % 13 = 0;
    update public.casino_bjl_posti set mani = (select jsonb_agg(x order by n) from (
        select e as x, n * 2 as n from jsonb_array_elements(mani) with ordinality q(e, n) where n - 1 <> i
        union all select jsonb_build_object('carte', jsonb_build_array(v_carte[1]), 'puntata', v_p, 'fatto', false, 'da_split', true, 'assi_divisi', v_assi), (i + 1) * 2
        union all select jsonb_build_object('carte', jsonb_build_array(v_carte[2]), 'puntata', v_p, 'fatto', false, 'da_split', true, 'assi_divisi', v_assi), (i + 1) * 2 + 1) z)
     where id = s.id;
    perform private.bjl_carta_a(t.id, s.id, i);
    perform private.bjl_carta_a(t.id, s.id, i + 1);
    if v_assi then
      update public.casino_bjl_posti set mani = jsonb_set(jsonb_set(mani, array[i::text], (mani -> i) || '{"fatto": true}'::jsonb), array[(i + 1)::text], (mani -> (i + 1)) || '{"fatto": true}'::jsonb) where id = s.id;
    end if;
  else
    raise exception using errcode = '22023', message = 'Mossa non valida.';
  end if;
  update public.casino_bjl_posti set ultimo_visto = now() where id = s.id;
  select * into s from public.casino_bjl_posti where id = s.id;
  if coalesce((s.mani -> i ->> 'fatto')::boolean, false) then
    perform private.bjl_turno_dopo(t.id, s.posto, i);
  else
    update public.casino_bjl_tavoli set scadenza = clock_timestamp() + interval '15 seconds' where id = t.id;
  end if;
  return private.bjl_pubblico(p_league_id, s.tavolo_id) || jsonb_build_object('seduto', true);
end $$;

revoke all on function public.casino_bjl_sala(bigint), public.casino_bjl_siedi(bigint, bigint), public.casino_bjl_alzati(bigint), public.casino_bjl_stato(bigint),
  public.casino_bjl_punta(bigint, int), public.casino_bjl_assicura(bigint, boolean), public.casino_bjl_azione(bigint, text) from public, anon;
grant execute on function public.casino_bjl_sala(bigint), public.casino_bjl_siedi(bigint, bigint), public.casino_bjl_alzati(bigint), public.casino_bjl_stato(bigint),
  public.casino_bjl_punta(bigint, int), public.casino_bjl_assicura(bigint, boolean), public.casino_bjl_azione(bigint, text) to authenticated;
revoke all on function private.bjl_chiudi(bigint), private.bjl_turno_dopo(bigint, int, int, numeric), private.bjl_carta_a(bigint, bigint, int), private.bjl_avanza(bigint) from public, anon, authenticated;
