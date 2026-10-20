-- BetOne Casino': quarto gioco, BlackjackOne (blackjack online classico, tavolo personale contro il banco).
-- Regole: 6 mazzi rimescolati a ogni mano (dal SERVER), blackjack 3:2, vittoria 1:1, il banco sta su tutti i 17
-- (anche soft 17) e guarda la carta coperta se mostra un 10 o un asso. Raddoppio su due carte (anche dopo la divisione),
-- divisione di coppie dello stesso valore fino a 4 mani, assi divisi con una carta sola e senza ridivisione,
-- assicurazione (meta' puntata, paga 2:1) quando il banco mostra un asso. Con gioco perfetto ritorno ~99,5%.
-- Carte: interi 0-51 (valore = c % 13: 0 = A, 1-8 = 2-9, 9 = 10, 10 = J, 11 = Q, 12 = K; seme = c / 13).
-- La scarpa e la carta coperta del banco restano segrete (tabella senza policy; la pagina riceve solo la parte pubblica).

alter table public.leagues add column if not exists casino_blackjack boolean not null default false;
update public.leagues set casino_blackjack = true where id = 62;

create table if not exists public.casino_bj_mani (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  scarpa int[] not null,
  banco int[] not null,
  mani jsonb not null,                    -- [{carte:[], puntata, fatto, raddoppiata, da_split, assi_divisi, vinto}]
  attiva smallint not null default 0,
  stato text not null check (stato in ('assicurazione', 'gioca', 'finita')),
  puntata integer not null check (puntata between 10 and 500),
  assicurazione integer not null default 0,
  vinto bigint not null default 0,
  creato_il timestamptz not null default now(),
  finito_il timestamptz
);
create index if not exists casino_bj_mani_utente_idx on public.casino_bj_mani (league_id, user_id, id desc);
create unique index if not exists casino_bj_mani_in_corso_idx on public.casino_bj_mani (league_id, user_id) where stato <> 'finita';
alter table public.casino_bj_mani enable row level security;
-- Nessuna policy: si legge solo dalle funzioni. Permessi espliciti (regola del 20/10/2026, vedi CLAUDE.md).
grant select on public.casino_bj_mani to anon;
grant select, insert, update, delete on public.casino_bj_mani to authenticated, service_role;

create or replace function private.bj_valore(c int) returns int language sql immutable set search_path to '' as $$
  select case when c % 13 = 0 then 1 when c % 13 >= 9 then 10 else c % 13 + 1 end $$;
create or replace function private.bj_totale(p int[]) returns int language sql immutable set search_path to '' as $$
  select s + case when assi > 0 and s + 10 <= 21 then 10 else 0 end
    from (select coalesce(sum(private.bj_valore(c)), 0)::int s, count(*) filter (where c % 13 = 0) assi from unnest(p) c) x $$;
create or replace function private.bj_carte(m jsonb) returns int[] language sql immutable set search_path to '' as $$
  select coalesce(array(select x::int from jsonb_array_elements_text(m -> 'carte') x), '{}') $$;

create or replace function private.bj_attivo(p_league_id bigint) returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile((select auth.uid())) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_blackjack) then
    raise exception using errcode = '55000', message = 'BlackjackOne non è attivo in questa lega.';
  end if;
end $$;

-- Parte pubblica della mano: la carta coperta del banco si vede solo a mano finita.
create or replace function private.bj_pubblica(r public.casino_bj_mani) returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object('id', r.id, 'stato', r.stato, 'attiva', r.attiva, 'puntata', r.puntata, 'assicurazione', r.assicurazione,
    'vinto', r.vinto, 'mani', r.mani,
    'banco', case when r.stato = 'finita' then to_jsonb(r.banco) else jsonb_build_array(r.banco[1], null) end,
    'puo_raddoppiare', r.stato = 'gioca' and jsonb_array_length(r.mani -> r.attiva -> 'carte') = 2,
    'puo_dividere', r.stato = 'gioca' and jsonb_array_length(r.mani -> r.attiva -> 'carte') = 2 and jsonb_array_length(r.mani) < 4
      and private.bj_valore((r.mani -> r.attiva -> 'carte' ->> 0)::int) = private.bj_valore((r.mani -> r.attiva -> 'carte' ->> 1)::int))
$$;

-- Fine mano: il banco gioca (se serve) e si paga ogni mano. Ritorna la riga aggiornata (non ancora salvata).
create or replace function private.bj_chiudi(r public.casino_bj_mani) returns public.casino_bj_mani language plpgsql security definer set search_path to '' as $$
declare
  v_mani jsonb := '[]'::jsonb; m jsonb; v_pt int; v_dt int; v_bj_banco boolean; v_bj boolean; v_vinto bigint; v_tot bigint := 0;
  v_serve boolean := false; v_una boolean := jsonb_array_length(r.mani) = 1; v_nome text;
begin
  -- Il banco pesca solo se c'e' almeno una mano ancora in gioco (non sballata e non blackjack naturale).
  for m in select x from jsonb_array_elements(r.mani) x loop
    v_pt := private.bj_totale(private.bj_carte(m));
    if v_pt <= 21 and not (v_una and not coalesce((m ->> 'da_split')::boolean, false) and jsonb_array_length(m -> 'carte') = 2 and v_pt = 21) then v_serve := true; end if;
  end loop;
  v_bj_banco := array_length(r.banco, 1) = 2 and private.bj_totale(r.banco) = 21;
  if v_serve and not v_bj_banco then
    while private.bj_totale(r.banco) < 17 loop
      r.banco := r.banco || r.scarpa[1]; r.scarpa := r.scarpa[2:];
    end loop;
  end if;
  v_dt := private.bj_totale(r.banco);
  for m in select x from jsonb_array_elements(r.mani) x loop
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
  r.mani := v_mani; r.stato := 'finita'; r.finito_il := now(); r.vinto := r.vinto + v_tot;
  update public.casino_saldi set crediti = crediti + v_tot, totale_vinto = totale_vinto + v_tot, max_vincita = greatest(max_vincita, r.vinto), aggiornato_il = now()
   where league_id = r.league_id and user_id = r.user_id;
  if r.vinto >= 1000 and r.vinto >= 3 * r.puntata then
    select nome into v_nome from public.teams where id = r.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (r.league_id, 'blackjack:' || r.id, 'lega', 'BetOne Casinò', r.team_id,
            '🃏 BLACKJACKONE! ' || v_nome || ' sbanca il tavolo e porta a casa ' || to_char(r.vinto, 'FM999G999G999') || ' crediti 🤑', now())
    on conflict do nothing;
  end if;
  return r;
end $$;

-- Passa alla mano successiva ancora da giocare; se non ce ne sono, chiude.
create or replace function private.bj_avanti(r public.casino_bj_mani) returns public.casino_bj_mani language plpgsql security definer set search_path to '' as $$
declare i int;
begin
  for i in 0..jsonb_array_length(r.mani) - 1 loop
    if not coalesce((r.mani -> i ->> 'fatto')::boolean, false) then r.attiva := i; return r; end if;
  end loop;
  return private.bj_chiudi(r);
end $$;

-- Pesca una carta per la mano i (se arriva a 21 o sballa, la mano e' fatta).
create or replace function private.bj_carta_a(r public.casino_bj_mani, i int) returns public.casino_bj_mani language plpgsql security definer set search_path to '' as $$
declare v_carte int[]; v_pt int;
begin
  v_carte := private.bj_carte(r.mani -> i) || r.scarpa[1]; r.scarpa := r.scarpa[2:];
  v_pt := private.bj_totale(v_carte);
  r.mani := jsonb_set(r.mani, array[i::text], (r.mani -> i) || jsonb_build_object('carte', to_jsonb(v_carte), 'fatto', v_pt >= 21 or coalesce((r.mani -> i ->> 'fatto')::boolean, false)));
  return r;
end $$;

create or replace function public.casino_bj_stato(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v public.casino_saldi; r public.casino_bj_mani;
begin
  perform private.bj_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, (select auth.uid()));
  select * into r from public.casino_bj_mani where league_id = p_league_id and user_id = (select auth.uid()) order by id desc limit 1;
  return jsonb_build_object('crediti', v.crediti, 'mano', case when r.id is not null then private.bj_pubblica(r) end);
end $$;

-- Nuova mano: si punta e si distribuisce (giocatore, banco scoperta, giocatore, banco coperta).
create or replace function public.casino_bj_punta(p_league_id bigint, p_puntata int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; r public.casino_bj_mani; v_scarpa int[];
begin
  perform private.bj_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  if exists (select 1 from public.casino_bj_mani where league_id = p_league_id and user_id = v_utente and stato <> 'finita') then
    raise exception using errcode = '55000', message = 'Hai una mano in corso: finiscila prima.';
  end if;
  if p_puntata is null or p_puntata < 10 or p_puntata > 500 or p_puntata % 10 <> 0 then raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).'; end if;
  if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti - p_puntata, giri = giri + 1, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  v_scarpa := array(select x % 52 from generate_series(0, 311) x order by random());
  insert into public.casino_bj_mani (league_id, user_id, team_id, scarpa, banco, mani, stato, puntata)
  values (p_league_id, v_utente, v.team_id, v_scarpa[5:], array[v_scarpa[2], v_scarpa[4]],
          jsonb_build_array(jsonb_build_object('carte', jsonb_build_array(v_scarpa[1], v_scarpa[3]), 'puntata', p_puntata, 'fatto', false)), 'gioca', p_puntata)
  returning * into r;
  if r.banco[1] % 13 = 0 then
    r.stato := 'assicurazione';                         -- il banco mostra un asso: si offre l'assicurazione
  elsif private.bj_valore(r.banco[1]) = 10 and private.bj_totale(r.banco) = 21 then
    r := private.bj_chiudi(r);                          -- il banco guarda la coperta: blackjack
  elsif private.bj_totale(private.bj_carte(r.mani -> 0)) = 21 then
    r := private.bj_chiudi(r);                          -- blackjack del giocatore
  end if;
  update public.casino_bj_mani set scarpa = r.scarpa, banco = r.banco, mani = r.mani, attiva = r.attiva, stato = r.stato, vinto = r.vinto, finito_il = r.finito_il where id = r.id;
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('crediti', v.crediti, 'mano', private.bj_pubblica(r));
end $$;

-- Assicurazione (si/no) quando il banco mostra un asso: costa meta' puntata e paga 2:1 se il banco ha blackjack.
create or replace function public.casino_bj_assicura(p_league_id bigint, p_si boolean) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; r public.casino_bj_mani; v_costo int;
begin
  perform private.bj_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  select * into r from public.casino_bj_mani where league_id = p_league_id and user_id = v_utente and stato = 'assicurazione' for update;
  if r.id is null then raise exception using errcode = '55000', message = 'Nessuna assicurazione da decidere.'; end if;
  if p_si then
    v_costo := r.puntata / 2;
    if v.crediti < v_costo then raise exception using errcode = '22023', message = 'Crediti insufficienti per l''assicurazione.'; end if;
    update public.casino_saldi set crediti = crediti - v_costo where league_id = p_league_id and user_id = v_utente;
    r.assicurazione := v_costo;
  end if;
  if private.bj_totale(r.banco) = 21 then
    if r.assicurazione > 0 then                          -- assicurazione pagata 2:1 (piu' la posta)
      r.vinto := 3 * r.assicurazione;
      update public.casino_saldi set crediti = crediti + r.vinto, totale_vinto = totale_vinto + r.vinto where league_id = p_league_id and user_id = v_utente;
    end if;
    r := private.bj_chiudi(r);
  elsif private.bj_totale(private.bj_carte(r.mani -> 0)) = 21 then
    r := private.bj_chiudi(r);
  else
    r.stato := 'gioca';
  end if;
  update public.casino_bj_mani set scarpa = r.scarpa, banco = r.banco, mani = r.mani, attiva = r.attiva, stato = r.stato, vinto = r.vinto,
         assicurazione = r.assicurazione, finito_il = r.finito_il where id = r.id;
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('crediti', v.crediti, 'mano', private.bj_pubblica(r));
end $$;

-- Mosse: 'carta', 'stai', 'raddoppia', 'dividi'.
create or replace function public.casino_bj_azione(p_league_id bigint, p_azione text) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; r public.casino_bj_mani; m jsonb; i int; v_carte int[]; v_p int; v_assi boolean;
begin
  perform private.bj_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  select * into r from public.casino_bj_mani where league_id = p_league_id and user_id = v_utente and stato = 'gioca' for update;
  if r.id is null then raise exception using errcode = '55000', message = 'Nessuna mano da giocare.'; end if;
  i := r.attiva; m := r.mani -> i; v_carte := private.bj_carte(m); v_p := (m ->> 'puntata')::int;
  if p_azione = 'carta' then
    r := private.bj_carta_a(r, i);
  elsif p_azione = 'stai' then
    r.mani := jsonb_set(r.mani, array[i::text], m || '{"fatto": true}'::jsonb);
  elsif p_azione = 'raddoppia' then
    if array_length(v_carte, 1) <> 2 then raise exception using errcode = '22023', message = 'Si raddoppia solo con due carte.'; end if;
    if v.crediti < v_p then raise exception using errcode = '22023', message = 'Crediti insufficienti per raddoppiare.'; end if;
    update public.casino_saldi set crediti = crediti - v_p where league_id = p_league_id and user_id = v_utente;
    r.mani := jsonb_set(r.mani, array[i::text], m || jsonb_build_object('puntata', 2 * v_p, 'raddoppiata', true));
    r := private.bj_carta_a(r, i);
    r.mani := jsonb_set(r.mani, array[i::text], (r.mani -> i) || '{"fatto": true}'::jsonb);
  elsif p_azione = 'dividi' then
    if array_length(v_carte, 1) <> 2 or private.bj_valore(v_carte[1]) <> private.bj_valore(v_carte[2]) or jsonb_array_length(r.mani) >= 4 then
      raise exception using errcode = '22023', message = 'Questa mano non si può dividere.';
    end if;
    if v.crediti < v_p then raise exception using errcode = '22023', message = 'Crediti insufficienti per dividere.'; end if;
    update public.casino_saldi set crediti = crediti - v_p where league_id = p_league_id and user_id = v_utente;
    v_assi := v_carte[1] % 13 = 0;
    -- la mano i diventa due mani da una carta; ognuna riceve subito la seconda carta
    r.mani := (select jsonb_agg(x order by n) from (
                 select e as x, n * 2 as n from jsonb_array_elements(r.mani) with ordinality t(e, n) where n - 1 <> i
                 union all select jsonb_build_object('carte', jsonb_build_array(v_carte[1]), 'puntata', v_p, 'fatto', false, 'da_split', true, 'assi_divisi', v_assi), (i + 1) * 2
                 union all select jsonb_build_object('carte', jsonb_build_array(v_carte[2]), 'puntata', v_p, 'fatto', false, 'da_split', true, 'assi_divisi', v_assi), (i + 1) * 2 + 1) s);
    r := private.bj_carta_a(r, i);
    r := private.bj_carta_a(r, i + 1);
    if v_assi then   -- assi divisi: una carta sola per mano
      r.mani := jsonb_set(r.mani, array[i::text], (r.mani -> i) || '{"fatto": true}'::jsonb);
      r.mani := jsonb_set(r.mani, array[(i + 1)::text], (r.mani -> (i + 1)) || '{"fatto": true}'::jsonb);
    end if;
  else
    raise exception using errcode = '22023', message = 'Mossa non valida.';
  end if;
  if coalesce((r.mani -> r.attiva ->> 'fatto')::boolean, false) then r := private.bj_avanti(r); end if;
  update public.casino_bj_mani set scarpa = r.scarpa, banco = r.banco, mani = r.mani, attiva = r.attiva, stato = r.stato, vinto = r.vinto, finito_il = r.finito_il where id = r.id;
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('crediti', v.crediti, 'mano', private.bj_pubblica(r));
end $$;

-- La pagina iniziale del casino' deve sapere se mostrare la locandina di BlackjackOne.
CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;

revoke all on function public.casino_bj_stato(bigint), public.casino_bj_punta(bigint, int), public.casino_bj_assicura(bigint, boolean), public.casino_bj_azione(bigint, text) from public, anon;
grant execute on function public.casino_bj_stato(bigint), public.casino_bj_punta(bigint, int), public.casino_bj_assicura(bigint, boolean), public.casino_bj_azione(bigint, text) to authenticated;
revoke all on function private.bj_chiudi(public.casino_bj_mani), private.bj_avanti(public.casino_bj_mani), private.bj_carta_a(public.casino_bj_mani, int) from public, anon, authenticated;
