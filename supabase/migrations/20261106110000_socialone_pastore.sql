-- SocialOne: Giuseppe Pastore tra gli influencer (richiesta del committente, 6/11/2026).
--
-- Il Pastore vero e' famoso per ricordarsi tutte le partite: qui scrive le curiosita' della giornata, prese
-- dalla storia della lega (tutte le stagioni). Per ogni giornata si raccolgono le candidate, in ordine di
-- interesse, e se ne pubblicano al massimo due:
--   1. record della lega: vittoria piu' larga o partita con piu' gol di sempre (almeno 60 partite in archivio);
--   2. prima vittoria di sempre contro un avversario mai battuto (almeno 3 precedenti);
--   3. 25, 50, 75... gol nella lega; serie: 5, 7, 10, 15... vittorie di fila, 10, 15, 20... risultati utili,
--      fine di 4+ sconfitte di fila o di 8+ partite senza vittorie;
--   4. il primo gol nella lega dopo almeno 40 presenze;
--   5. la giornata con piu' o con meno gol della stagione (da 6 giornate in poi).
-- Mai due curiosita' dello stesso livello nella stessa giornata.
-- social_genera_stampa resta com'e' e chiama private.stampa_pastore a fine giornata.

insert into public.social_profili (id, nome, tipo, bio, sigla, colore, colore2, follower_base, ordine)
values ('giuseppepastore', 'Giuseppe Pastore', 'influencer',
        'Ricordo tutte le partite. Precedenti, record e curiosità che nessun altro vi dirà. 📚',
        'GP', '#94a3b8', '#1e293b', 520000, 11);

create or replace function private.stampa_pastore(p_league bigint, p_season bigint, p_giornata integer, p_quando timestamptz)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_num integer;
  v_k text := p_season || ':' || p_giornata;
  v_r record;
  v_q record;
  v_seq text;
  v_serie integer;
  v_archivio integer;
  v_n integer := 0;
begin
  select s.numero into v_num from public.seasons s where s.id = p_season;

  drop table if exists pg_temp.tmp_pastore_storico;
  drop table if exists pg_temp.tmp_pastore_curiosita;
  -- Tutte le partite della lega fino a questa giornata compresa.
  create temp table tmp_pastore_storico as
    select m.id, s.numero, f.giornata, f.home_team_id as casa, f.away_team_id as ospite, m.gol_home as gc, m.gol_away as go,
           (s.numero < v_num or (s.numero = v_num and f.giornata < p_giornata)) as passato,
           (f.season_id = p_season and f.giornata = p_giornata) as oggi
    from public.matches m join public.fixtures f on f.id = m.fixture_id join public.seasons s on s.id = f.season_id
    where f.league_id = p_league and m.gol_home is not null
      and (s.numero < v_num or (s.numero = v_num and f.giornata <= p_giornata));
  create temp table tmp_pastore_curiosita (prio integer, team_id bigint, team2_id bigint, player_instance_id bigint, testo text);

  -- Prima vittoria di sempre contro quell'avversario.
  insert into pg_temp.tmp_pastore_curiosita
  select 2, x.vinc, x.perd, null,
         tv.nome || ' non aveva mai battuto ' || tp.nome || '. Mai. ' || x.prec || ' precedenti: '
           || case when x.pari = 0 then 'tutte sconfitte' when x.pari = x.prec then 'tutti pareggi'
                   else x.pari || case when x.pari = 1 then ' pareggio' else ' pareggi' end || ' e '
                        || (x.prec - x.pari) || case when x.prec - x.pari = 1 then ' sconfitta' else ' sconfitte' end end
           || '. Con questo ' || x.ris || ' arriva la prima volta.'
  from (
    select o.vinc, o.perd, o.ris,
           count(h.id) as prec,
           count(h.id) filter (where h.gc = h.go) as pari,
           count(h.id) filter (where (h.casa = o.vinc and h.gc > h.go) or (h.ospite = o.vinc and h.go > h.gc)) as vinte
    from (select case when gc > go then casa else ospite end as vinc, case when gc > go then ospite else casa end as perd,
                 greatest(gc, go) || '-' || least(gc, go) as ris
          from pg_temp.tmp_pastore_storico where oggi and gc <> go) o
    left join pg_temp.tmp_pastore_storico h on h.passato
      and ((h.casa = o.vinc and h.ospite = o.perd) or (h.casa = o.perd and h.ospite = o.vinc))
    group by o.vinc, o.perd, o.ris
  ) x
  join public.teams tv on tv.id = x.vinc join public.teams tp on tp.id = x.perd
  where x.prec >= 3 and x.vinte = 0;

  -- Record della lega.
  select count(*) into v_archivio from pg_temp.tmp_pastore_storico where passato;
  if v_archivio >= 60 then
    select h.*, abs(h.gc - h.go) as scarto, h.gc + h.go as tot into v_q
    from pg_temp.tmp_pastore_storico h where h.oggi order by abs(h.gc - h.go) desc, h.gc + h.go desc, h.id limit 1;
    select h.*, abs(h.gc - h.go) as scarto into v_r
    from pg_temp.tmp_pastore_storico h where h.passato order by abs(h.gc - h.go) desc, h.numero, h.giornata, h.id limit 1;
    if v_q.id is not null and v_q.scarto > v_r.scarto then
      insert into pg_temp.tmp_pastore_curiosita
      select 1, case when v_q.gc > v_q.go then v_q.casa else v_q.ospite end, case when v_q.gc > v_q.go then v_q.ospite else v_q.casa end, null,
             case when greatest(v_q.gc, v_q.go) in (8, 11) then 'L''' else 'Il ' end || greatest(v_q.gc, v_q.go) || '-' || least(v_q.gc, v_q.go) || ' di '
               || (select nome from public.teams where id = case when v_q.gc > v_q.go then v_q.casa else v_q.ospite end) || ' su '
               || (select nome from public.teams where id = case when v_q.gc > v_q.go then v_q.ospite else v_q.casa end)
               || ' è la vittoria più larga nella storia della lega. Il record precedente era '
               || case when greatest(v_r.gc, v_r.go) in (8, 11) then 'l''' else 'il ' end || greatest(v_r.gc, v_r.go) || '-' || least(v_r.gc, v_r.go) || ' di '
               || (select nome from public.teams where id = case when v_r.gc > v_r.go then v_r.casa else v_r.ospite end) || ' contro '
               || (select nome from public.teams where id = case when v_r.gc > v_r.go then v_r.ospite else v_r.casa end)
               || ', giornata ' || v_r.giornata || ' della Season ' || v_r.numero || '.';
    else
      select h.*, h.gc + h.go as tot into v_q
      from pg_temp.tmp_pastore_storico h where h.oggi order by h.gc + h.go desc, h.id limit 1;
      select h.*, h.gc + h.go as tot into v_r
      from pg_temp.tmp_pastore_storico h where h.passato order by h.gc + h.go desc, h.numero, h.giornata, h.id limit 1;
      if v_q.id is not null and v_q.tot > v_r.tot then
        insert into pg_temp.tmp_pastore_curiosita
        select 1, v_q.casa, v_q.ospite, null,
               (select nome from public.teams where id = v_q.casa) || '-' || (select nome from public.teams where id = v_q.ospite)
                 || ' ' || v_q.gc || '-' || v_q.go || ': ' || v_q.tot || ' gol, mai così tanti in una partita di questa lega. Il record era di '
                 || v_r.tot || ', ' || (select nome from public.teams where id = v_r.casa) || '-' || (select nome from public.teams where id = v_r.ospite)
                 || ' ' || v_r.gc || '-' || v_r.go || ', giornata ' || v_r.giornata || ' della Season ' || v_r.numero || '.';
      end if;
    end if;
  end if;

  -- Traguardi dei giocatori.
  insert into pg_temp.tmp_pastore_curiosita
  select case when c.tot = ms.gol then 4 else 3 end, ms.team_id, null, ms.player_instance_id,
         case when c.tot = ms.gol
              then 'Ci sono volute ' || c.pres || ' partite: ' || p.nome || ' segna il suo primo gol in questa lega, contro '
                   || (select nome from public.teams where id = case when ms.team_id = h.casa then h.ospite else h.casa end) || '. Valeva l''attesa.'
              else p.nome || ' è arrivato a ' || c.tot || ' gol in questa lega, in ' || c.pres || ' partite. Il primo? Giornata '
                   || pr.giornata || ' della Season ' || pr.numero || ', contro ' || (select nome from public.teams where id = pr.avv) || '.' end
  from public.match_stats ms
  join pg_temp.tmp_pastore_storico h on h.id = ms.match_id and h.oggi
  join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
  cross join lateral (
    select sum(m2.gol) as tot, count(*) filter (where m2.minuti > 0) as pres
    from public.match_stats m2 join pg_temp.tmp_pastore_storico h2 on h2.id = m2.match_id
    where m2.player_instance_id = ms.player_instance_id) c
  cross join lateral (
    select h3.numero, h3.giornata, case when m3.team_id = h3.casa then h3.ospite else h3.casa end as avv
    from public.match_stats m3 join pg_temp.tmp_pastore_storico h3 on h3.id = m3.match_id
    where m3.player_instance_id = ms.player_instance_id and m3.gol > 0
    order by h3.numero, h3.giornata limit 1) pr
  where ms.gol > 0
    and ((c.tot >= 25 and c.tot / 25 > (c.tot - ms.gol) / 25) or (c.tot = ms.gol and c.pres >= 40));

  -- Serie (anche a cavallo delle stagioni).
  for v_r in
    select distinct t.id, t.nome
    from pg_temp.tmp_pastore_storico h join public.teams t on t.id in (h.casa, h.ospite)
    where h.oggi
  loop
    select string_agg(case when x.gf > x.gs then 'V' when x.gf = x.gs then 'P' else 'S' end, '' order by x.numero desc, x.giornata desc, x.id desc)
      into v_seq
    from (select h.id, h.numero, h.giornata,
                 case when h.casa = v_r.id then h.gc else h.go end as gf,
                 case when h.casa = v_r.id then h.go else h.gc end as gs
          from pg_temp.tmp_pastore_storico h where v_r.id in (h.casa, h.ospite)) x;
    v_seq := coalesce(v_seq, '');
    v_serie := length(v_seq) - length(ltrim(v_seq, 'V'));
    if v_serie >= 5 and (v_serie = 5 or v_serie = 7 or v_serie % 5 = 0) then
      insert into pg_temp.tmp_pastore_curiosita values (3, v_r.id, null, null,
        v_serie || ' vittorie di fila per ' || v_r.nome || '. L''ultima volta che non ha vinto era la giornata '
          || (select h.giornata || case when h.numero <> v_num then ' della Season ' || h.numero else '' end
              from pg_temp.tmp_pastore_storico h where v_r.id in (h.casa, h.ospite)
              order by h.numero desc, h.giornata desc, h.id desc offset v_serie limit 1)
          || '. Sembra passata una vita.');
      continue;
    end if;
    v_serie := length(v_seq) - length(ltrim(v_seq, 'VP'));
    if v_serie >= 10 and v_serie % 5 = 0 then
      insert into pg_temp.tmp_pastore_curiosita values (3, v_r.id, null, null,
        v_r.nome || ' non perde da ' || v_serie || ' partite. Chi la batte per ultimo se lo ricorderà a lungo.');
      continue;
    end if;
    if left(v_seq, 1) = 'V' then
      v_serie := length(v_seq) - 1 - length(ltrim(substr(v_seq, 2), 'S'));
      if v_serie >= 4 then
        insert into pg_temp.tmp_pastore_curiosita values (3, v_r.id, null, null,
          v_r.nome || ' torna a vincere dopo ' || v_serie || ' sconfitte di fila. Si respira di nuovo.');
        continue;
      end if;
      v_serie := length(v_seq) - 1 - length(ltrim(substr(v_seq, 2), 'PS'));
      if v_serie >= 8 then
        insert into pg_temp.tmp_pastore_curiosita values (3, v_r.id, null, null,
          v_r.nome || ' non vinceva da ' || v_serie || ' partite. Io me la ricordo, l''ultima vittoria: qualcuno dei suoi tifosi forse no.');
      end if;
    end if;
  end loop;

  -- La giornata piu' prolifica o piu' avara della stagione.
  select g.tot, g.giornata, g.rango_alto, g.rango_basso, g.quante into v_q
  from (select h.giornata, sum(h.gc + h.go) as tot,
               rank() over (order by sum(h.gc + h.go) desc) as rango_alto,
               rank() over (order by sum(h.gc + h.go)) as rango_basso,
               count(*) over () as quante
        from pg_temp.tmp_pastore_storico h where h.numero = v_num group by h.giornata) g
  where g.giornata = p_giornata;
  if v_q.quante >= 6 and v_q.rango_alto = 1 then
    insert into pg_temp.tmp_pastore_curiosita values (5, null, null, null,
      v_q.tot || ' gol in questa giornata: è la più prolifica della stagione. Difese in vacanza.');
  elsif v_q.quante >= 6 and v_q.rango_basso = 1 then
    insert into pg_temp.tmp_pastore_curiosita values (5, null, null, null,
      'Solo ' || v_q.tot || ' gol in tutta la giornata: la più avara della stagione. Portieri contenti, tifosi un po'' meno.');
  end if;

  -- Al massimo due curiosita', le piu' interessanti, mai due dello stesso livello.
  for v_r in
    select u.*, row_number() over (order by u.prio) as n
    from (select distinct on (c.prio) c.* from pg_temp.tmp_pastore_curiosita c
          order by c.prio, abs(hashtext(c.testo || v_k))) u
    order by u.prio limit 2
  loop
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, player_instance_id, testo, creato_il)
    values (p_league, 'pastore:' || v_k || ':' || v_r.n, 'influencer', 'Giuseppe Pastore', 'giuseppepastore', 'giuseppepastore',
            v_r.team_id, v_r.team2_id, v_r.player_instance_id,
            '📚 ' || private.social_scegli('gp' || v_k || ':' || v_r.n,
                       array['Me lo ricordo bene: ', 'Curiosità: ', 'Lo sapevate? ', 'Nota per gli archivisti: ', 'Ve lo dico a memoria: '])
              || v_r.testo,
            p_quando + case v_r.n when 1 then interval '110 minutes' else interval '150 minutes' end)
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end loop;

  drop table if exists pg_temp.tmp_pastore_storico;
  drop table if exists pg_temp.tmp_pastore_curiosita;
  return v_n;
end;
$$;

CREATE OR REPLACE FUNCTION private.social_genera_stampa()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- Solo gli eventi da oggi in poi: niente valanga di articoli sugli scambi delle settimane scorse.
  v_dal timestamptz := greatest(now() - interval '3 days', timestamptz '2026-11-06 12:00:00+00');
  v_n integer := 0;
  v_r record;
  v_g record;
  v_m record;
  v_s record;
  v_post bigint;
  v_k text;
  v_tab text;
  v_adani bigint;
  v_cassano bigint;
  v_f record;
begin
  -- 1. Scambi.
  for v_r in
    select tp.id from public.trade_proposals tp
    join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
    where tp.stato = 'accettata' and tp.risolta_il > v_dal
      and not exists (select 1 from public.social_posts sp where sp.league_id = tp.league_id and sp.chiave = 'pagelle-scambio:' || tp.id)
    order by tp.risolta_il
  loop
    v_n := v_n + private.stampa_scambio(v_r.id);
  end loop;

  -- 2. Aste degli svincolati: Sky Sport 24.
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
  select a.league_id, 'stampa-asta:' || a.id, 'testata', 'Sky Sport 24', 'skysport24', 'skysport24', a.vincitore_team_id, pi.id,
         private.social_scegli('ss' || a.id, array[
           '⚡ BREAKING | ' || p.nome || ' è di ' || t.nome || '. Lo svincolato (' || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1]) || ', '
             || coalesce(pi.eta_corrente, p.eta) || ' anni) firma per ' || private.milioni(a.ingaggio_finale) || ': '
             || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id) || '.',
           '⚡ ULTIM''ORA | Colpo dagli svincolati per ' || t.nome || ': preso ' || p.nome || ', ' || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1])
             || ' di ' || coalesce(pi.eta_corrente, p.eta) || ' anni, ' || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id)
             || '. Ingaggio da ' || private.milioni(a.ingaggio_finale) || '.',
           '⚡ BREAKING | ' || t.nome || ' vince l''asta per ' || p.nome || '. ' || coalesce(pi.eta_corrente, p.eta) || ' anni, '
             || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id) || ': arriva a ' || private.milioni(a.ingaggio_finale) || ' a stagione.']),
         a.risolta_il + interval '2 minutes'
  from public.free_agent_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  left join public.player_instances pi on pi.league_id = a.league_id and pi.player_id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > v_dal and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_post = row_count; v_n := v_n + v_post;

  -- 3. UNDER: TuttoMercatoWeb.
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
  select a.league_id, 'stampa-under:' || a.id, 'testata', 'TuttoMercatoWeb', 'tuttomercatoweb', 'tuttomercatoweb', a.vincitore_team_id, pi.id,
         private.social_scegli('tm' || a.id, array[
           '👀 TALENTO | ' || t.nome || ' si assicura ' || p.nome || ', ' || coalesce(pi.eta_corrente, p.eta) || ' anni, '
             || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1]) || '. Oggi è ancora acerbo, ma ' || private.stampa_prospetto(p.potential, 'tm' || a.id)
             || '. Nome da segnare sul taccuino.',
           '👀 OCCHIO A LUI | ' || p.nome || ' (' || coalesce(pi.eta_corrente, p.eta) || ') è un nuovo giocatore di ' || t.nome
             || '. Gli osservatori ne parlano un gran bene: ' || private.stampa_prospetto(p.potential, 'tm' || a.id) || '. Tra un paio di stagioni potrebbe valere molto più di quanto è costato ('
             || private.milioni(a.ingaggio_finale) || ').']),
         a.risolta_il + interval '4 minutes'
  from public.under_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  left join public.player_instances pi on pi.league_id = a.league_id and pi.player_id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > v_dal and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_post = row_count; v_n := v_n + v_post;

  -- 4. Gli influencer, una volta per giornata giocata.
  for v_g in
    select f.league_id, f.season_id, f.giornata, max(m.simulata_il) as quando
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa
    where m.simulata_il > v_dal
    group by f.league_id, f.season_id, f.giornata
    having not exists (select 1 from public.social_posts sp where sp.league_id = f.league_id
                        and sp.chiave = 'omino:' || f.season_id || ':' || f.giornata)
  loop
    v_k := v_g.season_id || ':' || v_g.giornata;

    -- L'Ultimo Uomo: la partita con la storia tattica piu' forte (chi vince col pallone agli altri, o chi domina).
    select x.*, case when x.gol_v = x.gol_p then 'pari' when x.poss_v < 0.45 then 'rimessa' else 'dominio' end as storia
      into v_m
    from (
      select m.id, th.nome as casa, ta.nome as ospite, m.gol_home, m.gol_away,
             case when m.gol_home >= m.gol_away then th.nome else ta.nome end as vinc,
             case when m.gol_home >= m.gol_away then ta.nome else th.nome end as perd,
             case when m.gol_home >= m.gol_away then f.home_team_id else f.away_team_id end as vinc_id,
             case when m.gol_home >= m.gol_away then f.away_team_id else f.home_team_id end as perd_id,
             greatest(m.gol_home, m.gol_away) as gol_v, least(m.gol_home, m.gol_away) as gol_p,
             case when m.gol_home >= m.gol_away then m.modulo_home else m.modulo_away end as mod_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'possesso')::numeric as poss_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'tiri')::integer as tiri_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'away' else 'home' end ->> 'tiri')::integer as tiri_p,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'inPorta')::integer as porta_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'passaggiPct')::numeric as pass_v
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
      where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
        and m.stats_squadra ? 'home'
    ) x
    order by case when x.gol_v > x.gol_p and x.poss_v < 0.45 then (0.5 - x.poss_v) * 200 + (x.gol_v - x.gol_p)
                  else abs(x.poss_v - 0.5) * 100 + abs(x.tiri_v - x.tiri_p) end desc, x.id
    limit 1;
    if found then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
      values (v_g.league_id, 'omino:' || v_k, 'influencer', 'L''Ultimo Uomo', 'ultimouomo', 'ultimouomo', v_m.vinc_id, v_m.perd_id,
        '🧠 ANALISI | ' || v_m.casa || ' ' || v_m.gol_home || '-' || v_m.gol_away || ' ' || v_m.ospite || chr(10) || chr(10) || case v_m.storia
          when 'rimessa' then private.social_scegli('om' || v_k, array[
            v_m.vinc || ' vince con appena il ' || round(v_m.poss_v * 100) || '% di possesso. Blocco basso, ripartenze e ' || v_m.porta_v
              || ' tiri in porta: il ' || coalesce(v_m.mod_v, 'modulo') || ' ha fatto esattamente quello che doveva. Il possesso non vince le partite.',
            'Partita da manuale del contropiede. ' || v_m.perd || ' tiene il pallone (' || round((1 - v_m.poss_v) * 100) || '%) ma non punge, '
              || v_m.vinc || ' aspetta e colpisce. Cinismo puro.'])
          when 'dominio' then private.social_scegli('om' || v_k, array[
            'Dominio totale di ' || v_m.vinc || ': ' || round(v_m.poss_v * 100) || '% di possesso, ' || v_m.tiri_v || ' tiri contro ' || v_m.tiri_p
              || ', ' || round(coalesce(v_m.pass_v, 0) * 100) || '% di passaggi riusciti. Il ' || coalesce(v_m.mod_v, 'modulo') || ' ha tenuto pallone e partita.',
            v_m.vinc || ' ha schiacciato ' || v_m.perd || ' nella sua metà campo. ' || v_m.tiri_v || ' tiri a ' || v_m.tiri_p
              || ': quando il pressing funziona così, il risultato è una conseguenza.'])
          else private.social_scegli('om' || v_k, array[
            'Pareggio bugiardo? Tiri ' || v_m.tiri_v || '-' || v_m.tiri_p || ', possesso ' || round(v_m.poss_v * 100) || '-' || round((1 - v_m.poss_v) * 100)
              || '. Chi ha creato di più non ha trovato la giocata giusta negli ultimi metri.',
            'Due squadre che si annullano. Linee strette, pochi spazi tra le linee, ' || (v_m.tiri_v + v_m.tiri_p) || ' tiri in tutto. Partita a scacchi.']) end,
        v_g.quando + interval '40 minutes')
      on conflict (league_id, chiave) do nothing;
      v_n := v_n + 1;
    end if;

    -- Lele Adani: il giocatore della giornata.
    v_adani := null;
    select p.nome, ms.gol, ms.assist, ms.team_id, ms.player_instance_id,
           case when ms.team_id = f.home_team_id then ta.nome else th.nome end as avv
      into v_s
    from public.match_stats ms
    join public.matches m on m.id = ms.match_id join public.fixtures f on f.id = m.fixture_id
    join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
    join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
    where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
      and ms.gol + ms.assist >= 2
    order by ms.gol * 3 + ms.assist * 2 + ms.tiri_porta * 0.3 + ms.dribbling * 0.1 desc, ms.player_instance_id
    limit 1;
    if found then
      v_tab := case v_s.gol when 0 then '' when 1 then 'un gol' when 2 then 'una doppietta' when 3 then 'una tripletta' else v_s.gol || ' gol' end
        || case when v_s.gol > 0 and v_s.assist > 0 then ' e ' else '' end
        || case v_s.assist when 0 then '' when 1 then 'un assist' else v_s.assist || ' assist' end;
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
      values (v_g.league_id, 'adami:' || v_k, 'influencer', 'Lele Adani', 'leleadani', 'leleadani', v_s.team_id, v_s.player_instance_id,
        private.social_scegli('la' || v_k, array[
          'Ragazzi, ' || v_s.nome || '! ' || initcap(left(v_tab, 1)) || substr(v_tab, 2) || ' contro ' || v_s.avv || '. Questo è calcio, questa è poesia, questa è libertà di interpretare il ruolo! 🎙️',
          'Io mi alzo in piedi per ' || v_s.nome || '. ' || initcap(left(v_tab, 1)) || substr(v_tab, 2) || ': non gioca a calcio, lo racconta. Chi non si emoziona così ha sbagliato sport.',
          v_s.nome || ' è un giocatore che ti riconcilia col pallone. Contro ' || v_s.avv || ' ha fatto ' || v_tab
            || ', ma soprattutto ha fatto innamorare. Il calcio è dei romantici! ❤️']),
        v_g.quando + interval '65 minutes')
      on conflict (league_id, chiave) do nothing
      returning id into v_adani;
      v_n := v_n + 1;
    end if;

    -- Antonio Cassano: risponde ad Adani sul giocatore della giornata (e a volte Lele gli ribatte), poi
    -- attacca il flop della giornata. Scrive come parla: accenti mancanti, "a" per "ha", "ke".
    if v_adani is not null then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, in_risposta_a, testo, creato_il)
      values (v_g.league_id, 'cassano-adani:' || v_k, 'influencer', 'Antonio Cassano', 'antoniocassano', 'antoniocassano', v_s.team_id, v_s.player_instance_id, v_adani,
        private.social_scegli('ca' || v_k, array[
          'Lele ma ke stai dicendo?? ' || v_s.nome || ' a fatto ' || v_tab || ' contro ' || v_s.avv || ', e allora? Contro quelli segnava pure mio zio. Poesia... ma quale poesia 🙄',
          'Lele tu ti innamori di tutti. ' || v_s.nome || ' e un buon giocatore e basta. I fenomeni sono un altra cosa, io lo so perche lo ero.',
          'Ma basta Lele!! Ogni settimana un nuovo fenomeno. ' || v_s.nome || ' fra un mese non se lo ricorda nessuno, segnatelo.',
          'Ok Lele stavolta ai ragione te, ' || v_s.nome || ' oggi a giocato bene. Ma non ti ci abituare 😂']),
        v_g.quando + interval '82 minutes')
      on conflict (league_id, chiave) do nothing
      returning id into v_cassano;
      v_n := v_n + 1;
      if v_cassano is not null and abs(hashtext('ac' || v_k)) % 2 = 0 then
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, in_risposta_a, testo, creato_il)
        values (v_g.league_id, 'adani-cassano:' || v_k, 'influencer', 'Lele Adani', 'leleadani', 'leleadani', v_s.team_id, v_s.player_instance_id, v_cassano,
          private.social_scegli('ac' || v_k, array[
            'Antonio, tu guardi il tabellino ma non vedi il gesto. ' || v_s.nome || ' interpreta il ruolo con una libertà che oggi non ha nessuno.',
            'Antonio ti voglio bene, ma il calcio non è solo talento: è lettura, è sacrificio, è cultura. E ' || v_s.nome || ' ce l''ha.',
            'Antonio, lo dico con affetto: se non ti emoziona ' || v_s.nome || ', il problema non è lui. 🎙️']),
          v_g.quando + interval '96 minutes')
        on conflict (league_id, chiave) do nothing;
        v_n := v_n + 1;
      end if;
    end if;

    -- Il flop: chi ha tirato tanto senza segnare, o ha regalato piu' palloni.
    select p.nome, ms.tiri, ms.passaggi_tentati - ms.passaggi_riusciti as persi, ms.team_id, ms.player_instance_id,
           case when ms.team_id = f.home_team_id then ta.nome else th.nome end as avv
      into v_f
    from public.match_stats ms
    join public.matches m on m.id = ms.match_id join public.fixtures f on f.id = m.fixture_id
    join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
    join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
    where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
      and ms.gol = 0 and ms.assist = 0 and (ms.tiri >= 4 or ms.passaggi_tentati - ms.passaggi_riusciti >= 12)
    order by greatest(ms.tiri * 3, ms.passaggi_tentati - ms.passaggi_riusciti) desc, ms.player_instance_id
    limit 1;
    if found then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
      values (v_g.league_id, 'cassano:' || v_k, 'influencer', 'Antonio Cassano', 'antoniocassano', 'antoniocassano', v_f.team_id, v_f.player_instance_id,
        case when v_f.tiri * 3 >= v_f.persi then private.social_scegli('cf' || v_k, array[
          v_f.nome || ' a tirato ' || v_f.tiri || ' volte contro ' || v_f.avv || ' e non a fatto neanke un gol. Uno cosi nella mia squadra non giocava neanke in porta. Scarso.',
          'Ma ' || v_f.nome || ' ki lo a messo in campo?? ' || v_f.tiri || ' tiri e zero gol. Io alla sua eta ne facevo tre a partita e non mi allenavo neanke 😂',
          'Ve lo dico io ke di calcio ci capisco: ' || v_f.nome || ' e un giocatore normalissimo. Oggi ' || v_f.tiri || ' tiri buttati via. NORMALE.'])
        else private.social_scegli('cf' || v_k, array[
          v_f.nome || ' a sbagliato ' || v_f.persi || ' passaggi. ' || v_f.persi || '!!! Ma come si fa, il pallone basta darlo al compagno vicino.',
          'Stasera ' || v_f.nome || ' sembrava ke giocava per ' || v_f.avv || '. ' || v_f.persi || ' palloni regalati. Io lo mandavo in tribuna e basta.',
          'Ki allena ' || v_f.nome || ' dovrebbe fargli vedere la partita di oggi. ' || v_f.persi || ' passaggi sbagliati, roba da oratorio.']) end,
        v_g.quando + interval '75 minutes')
      on conflict (league_id, chiave) do nothing;
      v_n := v_n + 1;
    end if;

    -- Calciatori Brutti: la batosta della giornata (almeno 3 gol di scarto), e un tifoso che non la prende bene.
    select m.id, case when m.gol_home > m.gol_away then ta.nome else th.nome end as perd,
           case when m.gol_home > m.gol_away then th.nome else ta.nome end as vinc,
           case when m.gol_home > m.gol_away then f.away_team_id else f.home_team_id end as perd_id,
           case when m.gol_home > m.gol_away then f.home_team_id else f.away_team_id end as vinc_id,
           greatest(m.gol_home, m.gol_away) as presi, least(m.gol_home, m.gol_away) as fatti
      into v_m
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
    where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
      and abs(m.gol_home - m.gol_away) >= 3
    order by abs(m.gol_home - m.gol_away) desc, greatest(m.gol_home, m.gol_away) desc, m.id
    limit 1;
    if found then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
      values (v_g.league_id, 'bruttini:' || v_k, 'influencer', 'Calciatori Brutti', 'calciatoribrutti', 'calciatoribrutti', v_m.perd_id, v_m.vinc_id,
        private.social_scegli('cb' || v_k, array[
          '📸 La difesa di ' || v_m.perd || ' stasera: 🚪🚪🚪 ' || v_m.presi || ' gol presi da ' || v_m.vinc || '. Qualcuno avvisi il mister.',
          '📸 ' || v_m.perd || ' ha provato una nuova tattica: lasciar passare tutti. ' || v_m.vinc || ' ringrazia e ne fa ' || v_m.presi || '.',
          '📸 Ultime notizie: la retroguardia di ' || v_m.perd || ' è ancora in cerca del pallone. ' || v_m.vinc || ' ' || v_m.presi || '-' || v_m.fatti || '.',
          '📸 ' || v_m.presi || ' gol presi. Il portiere di ' || v_m.perd || ' a fine partita ha chiesto il rimborso del biglietto.']),
        v_g.quando + interval '90 minutes')
      on conflict (league_id, chiave) do nothing
      returning id into v_post;
      v_n := v_n + 1;
      if v_post is not null then
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
        values (v_g.league_id, 'bruttini-tifoso:' || v_k, 'tifosi',
                (private.tifoso_finto('cbt' || v_k, v_m.perd)).nome, (private.tifoso_finto('cbt' || v_k, v_m.perd)).handle, v_m.perd_id, v_post,
                private.social_scegli('cbt' || v_k, array['ridete ridete, a fine anno vediamo 😤', 'non fa ridere. non oggi.', 'ok questa fa male ma è vera 💀', 'bloccato. bloccati tutti.']),
                v_g.quando + interval '97 minutes')
        on conflict (league_id, chiave) do nothing;
      end if;
    end if;

    -- Giuseppe Pastore: le curiosita' della giornata.
    v_n := v_n + private.stampa_pastore(v_g.league_id, v_g.season_id, v_g.giornata, v_g.quando);
  end loop;

  return v_n;
end;
$function$;
