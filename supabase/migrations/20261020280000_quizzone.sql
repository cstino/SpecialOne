-- QUIZZONE, il quiz di SpecialOne (idea del committente, 20/10/2026). Una domanda ogni ora piena, 24 al giorno,
-- SINCRONIZZATA per tutti: da :00:00 a :00:10 si sceglie se giocare gratis o puntare (10-500), da :00:10 a :00:25
-- compare la domanda con 4 risposte (15 s, cosi' non si fa in tempo a cercare), poi si scopre la risposta e si paga.
-- Risposta giusta = 100 crediti del casino'; se si e' puntato, in piu' il doppio della puntata (puntata persa se si sbaglia).
-- Le domande non si accumulano: finita l'ora, quella domanda non si gioca piu'.
-- Le domande le genera il SERVER dai dati veri della stagione in corso (gol, assist, classifica, risultati) nel momento
-- in cui partono, quindi la risposta giusta e' sempre esatta e aggiornata. Testo nascosto fino a :00:10, risposta fino
-- alla fine (tabelle senza policy). Notifica un minuto prima, solo per le domande dalle 9 alle 23 (ora di Roma).

alter table public.leagues add column if not exists quizzone boolean not null default false;
update public.leagues set quizzone = true where id = 62;   -- prova su LegaBot

create table if not exists public.quizzone_domande (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  ora timestamptz not null,               -- ora piena di partenza
  tipo text not null,
  testo text not null,
  risposte jsonb not null,                -- 4 testi
  corretta smallint not null check (corretta between 0 and 3),
  regolata boolean not null default false,
  creata_il timestamptz not null default now(),
  unique (league_id, ora)
);
alter table public.quizzone_domande enable row level security;
grant select on public.quizzone_domande to anon;
grant select, insert, update, delete on public.quizzone_domande to authenticated, service_role;

create table if not exists public.quizzone_giocate (
  id bigint generated always as identity primary key,
  domanda_id bigint not null references public.quizzone_domande(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  puntata integer not null default 0 check (puntata = 0 or puntata between 10 and 500),
  risposta smallint check (risposta between 0 and 3),
  risposta_il timestamptz,
  corretta boolean,
  vinto bigint not null default 0,
  unique (domanda_id, user_id)
);
alter table public.quizzone_giocate enable row level security;
grant select on public.quizzone_giocate to anon;
grant select, insert, update, delete on public.quizzone_giocate to authenticated, service_role;
-- Nessuna policy su entrambe: si legge solo dalle funzioni.

-- Mescola la risposta giusta con le 3 sbagliate.
create or replace function private.quiz_mescola(p_giusta text, p_sbagliate text[]) returns jsonb language plpgsql volatile set search_path to '' as $$
declare v text[]; v_pos int;
begin
  v := array(select x from unnest(p_sbagliate[1:3] || p_giusta) x order by random());
  v_pos := array_position(v, p_giusta) - 1;
  return jsonb_build_object('risposte', to_jsonb(v), 'corretta', v_pos);
end $$;

-- Tre numeri sbagliati credibili vicino a quello giusto (mai negativi, tutti diversi).
create or replace function private.quiz_numeri(p_giusto int, p_minimo int default 0) returns text[] language sql volatile set search_path to '' as $$
  select array(select x::text from (select p_giusto + d as x from unnest(array[-3,-2,-1,1,2,3,4]) d where p_giusto + d >= p_minimo order by random() limit 3) s)
$$;

-- Genera la domanda di un'ora per una lega (null se non c'e' una stagione in corso o mancano i dati).
create or replace function private.quiz_genera(p_league_id bigint, p_ora timestamptz) returns public.quizzone_domande language plpgsql security definer set search_path to '' as $$
declare
  v_stagione bigint; v_tipi text[] := array['gol','assist','punti','posizione','vittorie','subiti','risultato','capocannoniere','capolista','attacco','difesa'];
  v_recenti text[]; v_tipo text; v_tentativo int; r record; v_testo text; v_giusta text; v_sbagliate text[]; v_mix jsonb; d public.quizzone_domande;
  v_lega text; v_gruppo text; v_n int;
begin
  select id into v_stagione from public.seasons where league_id = p_league_id and stato = 'in_corso' order by id desc limit 1;
  if v_stagione is null then return null; end if;
  select nome into v_lega from public.leagues where id = p_league_id;
  v_recenti := array(select tipo from public.quizzone_domande where league_id = p_league_id order by ora desc limit 4);
  for v_tentativo in 1..30 loop
    v_tipo := v_tipi[1 + floor(random() * array_length(v_tipi, 1))::int];
    continue when v_tipo = any(v_recenti) and v_tentativo < 25;
    v_testo := null;
    if v_tipo in ('gol', 'assist') then
      select p.nome as giocatore, t.nome as squadra, sum(case when v_tipo = 'gol' then ms.gol else ms.assist end)::int as n into r
        from public.match_stats ms join public.matches m on m.id = ms.match_id join public.fixtures f on f.id = m.fixture_id
        join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id join public.teams t on t.id = ms.team_id
       where ms.league_id = p_league_id and f.season_id = v_stagione
       group by pi.id, p.nome, t.nome having sum(case when v_tipo = 'gol' then ms.gol else ms.assist end) >= 2 order by random() limit 1;
      if r.n is not null then
        v_testo := case v_tipo when 'gol' then format('Quanti gol ha segnato %s (%s) in questa stagione?', r.giocatore, r.squadra)
                               else format('Quanti assist ha fatto %s (%s) in questa stagione?', r.giocatore, r.squadra) end;
        v_giusta := r.n::text; v_sbagliate := private.quiz_numeri(r.n, 0);
      end if;
    elsif v_tipo in ('punti', 'vittorie', 'subiti') then
      select t.nome as squadra, s.punti, s.vittorie, s.gol_subiti into r from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null then
        v_testo := case v_tipo when 'punti' then format('Quanti punti ha in classifica %s?', r.squadra)
                               when 'vittorie' then format('Quante partite ha vinto %s in questa stagione?', r.squadra)
                               else format('Quanti gol ha subito %s in questa stagione?', r.squadra) end;
        v_n := case v_tipo when 'punti' then r.punti when 'vittorie' then r.vittorie else r.gol_subiti end;
        v_giusta := v_n::text; v_sbagliate := private.quiz_numeri(v_n, 0);
      end if;
    elsif v_tipo = 'posizione' then
      select t.nome as squadra, s.posizione, s.conferenza,
             (select count(*) from public.standings s2 where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza)::int as tot into r
        from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.posizione is not null and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null and r.tot >= 4 then
        v_gruppo := case r.conferenza when 'est' then ' nella Conference Est' when 'ovest' then ' nella Conference Ovest' else '' end;
        v_testo := format('In che posizione è %s in classifica%s?', r.squadra, v_gruppo);
        v_giusta := r.posizione || 'º';
        v_sbagliate := array(select x || 'º' from (select r.posizione + dd as x from unnest(array[-3,-2,-1,1,2,3]) dd where r.posizione + dd between 1 and r.tot order by random() limit 3) s);
      end if;
    elsif v_tipo = 'risultato' then
      select th.nome as casa, ta.nome as ospite, f.giornata, m.gol_home as gh, m.gol_away as ga into r
        from public.matches m join public.fixtures f on f.id = m.fixture_id join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
       where m.league_id = p_league_id and f.season_id = v_stagione and m.simulata_il < now() - interval '30 minutes' order by random() limit 1;
      if r.casa is not null then
        v_testo := format('Com''è finita %s - %s della giornata %s?', r.casa, r.ospite, r.giornata);
        v_giusta := r.gh || '-' || r.ga;
        v_sbagliate := array(select x from (select distinct x from unnest(array[r.ga || '-' || r.gh, (r.gh + 1) || '-' || r.ga, r.gh || '-' || (r.ga + 1),
                               greatest(r.gh - 1, 0) || '-' || r.ga, (r.gh + 1) || '-' || (r.ga + 1), r.gh || '-' || greatest(r.ga - 1, 0)]) x
                             where x <> r.gh || '-' || r.ga) s order by random() limit 3);
      end if;
    elsif v_tipo = 'capocannoniere' then
      with marcatori as (
        select p.nome, sum(ms.gol)::int as g from public.match_stats ms join public.matches m on m.id = ms.match_id join public.fixtures f on f.id = m.fixture_id
          join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
         where ms.league_id = p_league_id and f.season_id = v_stagione group by pi.id, p.nome having sum(ms.gol) > 0 order by g desc limit 6)
      select (select nome from marcatori order by g desc limit 1) as primo,
             (select count(*) from marcatori where g = (select max(g) from marcatori))::int as pari,
             (select array_agg(nome) from (select nome from marcatori order by g desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 then
        v_testo := format('Chi è il capocannoniere di %s in questa stagione?', v_lega);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo = 'capolista' then
      select s.conferenza, (select t.nome from public.standings s1 join public.teams t on t.id = s1.team_id where s1.season_id = v_stagione and s1.conferenza is not distinct from s.conferenza and s1.posizione = 1) as primo,
             (select array_agg(t.nome order by s2.posizione) from public.standings s2 join public.teams t on t.id = s2.team_id where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza and s2.posizione between 2 and 4) as altri into r
        from public.standings s where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.primo is not null and array_length(r.altri, 1) = 3 then
        v_gruppo := case r.conferenza when 'est' then 'della Conference Est' when 'ovest' then 'della Conference Ovest' else 'in classifica' end;
        v_testo := format('Chi è prima %s in questo momento?', v_gruppo);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo in ('attacco', 'difesa') then
      with ordine as (select t.nome, case when v_tipo = 'attacco' then s.gol_fatti else s.gol_subiti end as n from public.standings s join public.teams t on t.id = s.team_id
                       where s.season_id = v_stagione and s.giocate > 0 order by 2 desc limit 5)
      select (select nome from ordine order by n desc limit 1) as primo, (select count(*) from ordine where n = (select max(n) from ordine))::int as pari,
             (select array_agg(nome) from (select nome from ordine order by n desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 then
        v_testo := case v_tipo when 'attacco' then format('Quale squadra ha segnato più gol in %s?', v_lega) else format('Quale squadra ha subito più gol in %s?', v_lega) end;
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    end if;
    if v_testo is not null and array_length(v_sbagliate, 1) = 3 then
      v_mix := private.quiz_mescola(v_giusta, v_sbagliate);
      insert into public.quizzone_domande (league_id, ora, tipo, testo, risposte, corretta)
      values (p_league_id, p_ora, v_tipo, v_testo, v_mix -> 'risposte', (v_mix ->> 'corretta')::int)
      on conflict (league_id, ora) do nothing returning * into d;
      if d.id is null then select * into d from public.quizzone_domande where league_id = p_league_id and ora = p_ora; end if;
      return d;
    end if;
  end loop;
  return null;
end $$;

-- Ogni minuto: a un minuto dall'ora piena prepara la domanda successiva e manda la notifica (solo 9-23 ora di Roma).
create or replace function private.quizzone_cron() returns void language plpgsql security definer set search_path to '' as $$
declare l record; v_ora timestamptz := date_trunc('hour', now()) + interval '1 hour'; d public.quizzone_domande; v_h int;
begin
  if now() < v_ora - interval '70 seconds' then return; end if;
  v_h := extract(hour from v_ora at time zone 'Europe/Rome');
  for l in select id from public.leagues where quizzone loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 9 and 23 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'Quizzone', format('Tra un minuto la domanda delle %s! Apri il Quizzone: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $$;

-- Paga una domanda finita (una volta sola): 100 crediti a chi ha risposto giusto, piu' il doppio della puntata.
create or replace function private.quiz_regola(p_domanda bigint) returns void language plpgsql security definer set search_path to '' as $$
declare d public.quizzone_domande; q record; v_ok boolean; v_vinto bigint;
begin
  select * into d from public.quizzone_domande where id = p_domanda for update;
  if d.regolata or now() < d.ora + interval '26 seconds' then return; end if;
  for q in select * from public.quizzone_giocate where domanda_id = d.id for update loop
    v_ok := q.risposta is not null and q.risposta = d.corretta;
    v_vinto := case when v_ok then 100 + 2 * q.puntata else 0 end;
    update public.quizzone_giocate set corretta = v_ok, vinto = v_vinto where id = q.id;
    if v_vinto > 0 then
      update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
       where league_id = q.league_id and user_id = q.user_id;
    end if;
  end loop;
  update public.quizzone_domande set regolata = true where id = d.id;
end $$;

create or replace function private.quiz_attivo(p_league_id bigint) returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.quizzone) then
    raise exception using errcode = '55000', message = 'Il Quizzone non è attivo in questa lega.';
  end if;
  if not exists (select 1 from public.teams t where t.league_id = p_league_id and t.user_id = (select auth.uid()) and t.attiva) then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;
end $$;

create or replace function public.quizzone_attivo(p_league_id bigint) returns boolean language sql stable security definer set search_path to '' as $$
  select coalesce((select l.quizzone from public.leagues l where l.id = p_league_id), false) and (select private.e_membro(p_league_id))
$$;

-- Stato del Quizzone: domanda dell'ora (testo da :10, risposta da :26), la mia giocata, gli esiti, la giornata.
create or replace function public.quizzone_stato(p_league_id bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_utente uuid := (select auth.uid()); v_ora timestamptz := clock_timestamp(); v_inizio timestamptz := date_trunc('hour', clock_timestamp());
  d public.quizzone_domande; v public.casino_saldi; q public.quizzone_giocate; v_d jsonb; v_prec bigint;
begin
  perform private.quiz_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  -- se il cron non l'ha preparata, la domanda dell'ora si genera adesso (solo finche' si puo' ancora entrare)
  if v_ora < v_inizio + interval '10 seconds' and not exists (select 1 from public.quizzone_domande where league_id = p_league_id and ora = v_inizio) then
    perform private.quiz_genera(p_league_id, v_inizio);
  end if;
  for v_prec in select id from public.quizzone_domande where league_id = p_league_id and not regolata and ora + interval '26 seconds' <= v_ora loop
    perform private.quiz_regola(v_prec);
  end loop;
  select * into d from public.quizzone_domande where league_id = p_league_id and ora <= v_ora and ora > v_ora - interval '1 hour' order by ora desc limit 1;
  if d.id is not null then
    select * into q from public.quizzone_giocate where domanda_id = d.id and user_id = v_utente;
    v_d := jsonb_build_object('id', d.id, 'ora', floor(extract(epoch from d.ora) * 1000), 'regolata', d.regolata,
      'testo', case when v_ora >= d.ora + interval '10 seconds' then d.testo end,
      'risposte', case when v_ora >= d.ora + interval '10 seconds' then d.risposte end,
      'corretta', case when d.regolata then d.corretta end,
      'giocatori', (select count(*) from public.quizzone_giocate where domanda_id = d.id),
      'esiti', case when d.regolata then coalesce((select jsonb_agg(jsonb_build_object('team_id', g.team_id, 'corretta', g.corretta, 'puntata', g.puntata, 'vinto', g.vinto) order by g.corretta desc nulls last, g.risposta_il nulls last)
                                                   from public.quizzone_giocate g where g.domanda_id = d.id), '[]'::jsonb) end);
  end if;
  return jsonb_build_object('adesso', floor(extract(epoch from v_ora) * 1000), 'crediti', v.crediti,
    'prossima', floor(extract(epoch from v_inizio + interval '1 hour') * 1000),
    'domanda', v_d,
    'mia', case when q.id is not null then jsonb_build_object('puntata', q.puntata, 'risposta', q.risposta, 'corretta', q.corretta, 'vinto', q.vinto) end,
    'oggi', coalesce((select jsonb_agg(jsonb_build_object('ora', floor(extract(epoch from x.ora) * 1000), 'testo', x.testo, 'risposta', x.risposte ->> x.corretta) order by x.ora desc)
                      from public.quizzone_domande x where x.league_id = p_league_id and x.regolata
                       and x.ora >= date_trunc('day', v_ora at time zone 'Europe/Rome') at time zone 'Europe/Rome'), '[]'::jsonb),
    'classifica', coalesce((select jsonb_agg(c order by (c ->> 'giuste')::int desc, (c ->> 'vinto')::bigint desc) from (
                      select jsonb_build_object('team_id', g.team_id, 'giuste', count(*) filter (where g.corretta), 'giocate', count(*), 'vinto', sum(g.vinto)) c
                        from public.quizzone_giocate g join public.quizzone_domande x on x.id = g.domanda_id
                       where g.league_id = p_league_id and x.ora >= date_trunc('day', v_ora at time zone 'Europe/Rome') at time zone 'Europe/Rome'
                       group by g.team_id) s), '[]'::jsonb));
end $$;

-- Entra nella domanda dell'ora (solo nei primi 10 secondi): gratis (0) o puntando da 10 a 500.
create or replace function public.quizzone_entra(p_league_id bigint, p_puntata int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; d public.quizzone_domande; v_ora timestamptz := clock_timestamp();
begin
  perform private.quiz_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  select * into d from public.quizzone_domande where league_id = p_league_id and ora <= v_ora and ora > v_ora - interval '1 hour' order by ora desc limit 1;
  if d.id is null or v_ora >= d.ora + interval '11 seconds' then raise exception using errcode = '55000', message = 'Troppo tardi: si entra solo nei primi 10 secondi. Ci vediamo alla prossima ora!'; end if;
  if p_puntata is null or (p_puntata <> 0 and (p_puntata < 10 or p_puntata > 500 or p_puntata % 10 <> 0)) then raise exception using errcode = '22023', message = 'Puntata non valida (gratis, oppure da 10 a 500).'; end if;
  if exists (select 1 from public.quizzone_giocate where domanda_id = d.id and user_id = v_utente) then raise exception using errcode = '55000', message = 'Sei già dentro a questa domanda.'; end if;
  if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti per questa puntata.'; end if;
  if p_puntata > 0 then update public.casino_saldi set crediti = crediti - p_puntata, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente; end if;
  insert into public.quizzone_giocate (domanda_id, league_id, user_id, team_id, puntata) values (d.id, p_league_id, v_utente, v.team_id, p_puntata);
  return public.quizzone_stato(p_league_id);
end $$;

-- Risposta (una sola, tra :00:10 e :00:25, con un secondo di tolleranza per la rete).
create or replace function public.quizzone_rispondi(p_league_id bigint, p_risposta int) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_utente uuid := (select auth.uid()); d public.quizzone_domande; v_ora timestamptz := clock_timestamp();
begin
  perform private.quiz_attivo(p_league_id);
  select * into d from public.quizzone_domande where league_id = p_league_id and ora <= v_ora and ora > v_ora - interval '1 hour' order by ora desc limit 1;
  if d.id is null or v_ora < d.ora + interval '10 seconds' or v_ora >= d.ora + interval '26 seconds' then
    raise exception using errcode = '55000', message = 'Tempo scaduto per rispondere.';
  end if;
  if p_risposta is null or p_risposta not between 0 and 3 then raise exception using errcode = '22023', message = 'Risposta non valida.'; end if;
  update public.quizzone_giocate set risposta = p_risposta, risposta_il = v_ora where domanda_id = d.id and user_id = v_utente and risposta is null;
  if not found then raise exception using errcode = '55000', message = 'Non sei entrato in questa domanda, o hai già risposto.'; end if;
  return public.quizzone_stato(p_league_id);
end $$;

revoke all on function public.quizzone_stato(bigint), public.quizzone_entra(bigint, int), public.quizzone_rispondi(bigint, int), public.quizzone_attivo(bigint) from public, anon;
grant execute on function public.quizzone_stato(bigint), public.quizzone_entra(bigint, int), public.quizzone_rispondi(bigint, int), public.quizzone_attivo(bigint) to authenticated;
revoke all on function private.quiz_genera(bigint, timestamptz), private.quiz_regola(bigint), private.quizzone_cron() from public, anon, authenticated;

-- Le notifiche del Quizzone aprono la pagina del Quizzone.
select cron.schedule('quizzone', '* * * * *', 'select private.quizzone_cron();');
