-- PLAYOFF CON LE CONFERENZE, OPZIONE B (docs/decisioni-conferenze.md, deciso il 14 ottobre 2026). Per ogni conference:
--   Champions League (1a-6a): 1a e 2a dirette ai quarti; play-in incrociato 3E-6W (A), 4E-5W (B), 3W-6E (C), 4W-5E (D);
--     quarti 1E-D, 2W-A, 1W-B, 2E-C; semifinali (1E/D)-(2W/A) e (1W/B)-(2E/C); finale secca in campo neutro.
--   Draft Playoffs (7a-12a), al contrario: 12a e 11a dirette ai quarti; play-in 10E-7W (E), 9E-8W (F), 10W-7E (G), 9W-8E (H);
--     quarti 12E-H, 11W-E, 12W-F, 11E-G; semifinali e finale come sopra.
--   Andata e ritorno in ogni turno tranne la finale; ritorno in casa alla favorita (meglio piazzata in Champions,
--   peggio piazzata nel Draft Playoffs); parita' nella somma -> rigori. 7 serate, i due tabelloni in parallelo.
-- Nel database il tabellone della Champions resta di tipo 'title' (stelle, albo, premi lo riconoscono gia'); il formato B
-- si riconosce da brackets.formato = 'conferenze'. Le teste di serie dei quarti sono create subito con l'avversario da
-- decidere (bracket_ties.da_tie_id = il play-in da cui arriva). L'ordine delle scelte non cambia regola
-- (assegna_posizioni_playoff, "dietro a chi ti ha battuto") e da' 1a-4a Draft Playoffs ... 24a campione di Champions.

alter table public.brackets add column if not exists formato text not null default 'classico';
do $$ begin
  alter table public.brackets add constraint brackets_formato_check check (formato in ('classico', 'conferenze'));
exception when duplicate_object then null; end $$;
alter table public.bracket_ties add column if not exists da_tie_id bigint references public.bracket_ties(id) on delete set null;
alter table public.bracket_ties add column if not exists conferenza_alta text;
alter table public.bracket_ties add column if not exists conferenza_bassa text;

-- La squadra A e' favorita rispetto a B? Champions: meglio piazzata (poi piu' punti, differenza reti, gol fatti).
-- Draft Playoffs: peggio piazzata (poi meno punti, peggior differenza reti, meno gol fatti).
create or replace function private.po_favorita(p_season_id bigint, p_tipo text, p_a bigint, p_b bigint) returns boolean
language sql stable set search_path to '' as $$
  select case when p_tipo = 'draft'
              then (a.posizione, -a.punti, -a.differenza_reti, -a.gol_fatti) > (b.posizione, -b.punti, -b.differenza_reti, -b.gol_fatti)
              else (a.posizione, -a.punti, -a.differenza_reti, -a.gol_fatti) < (b.posizione, -b.punti, -b.differenza_reti, -b.gol_fatti) end
    from public.standings a, public.standings b
   where a.season_id = p_season_id and a.team_id = p_a and b.season_id = p_season_id and b.team_id = p_b
$$;

create or replace function private.crea_tabelloni_conferenze(p_season_id bigint) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_season public.seasons; v_base integer; v_tipo text; v_bracket bigint; v_tie bigint; i int;
  v_e bigint[]; v_w bigint[];          -- squadre per posizione nella conference (1..12)
  v_pi_alta text[]; v_pi_bassa text[]; v_dirette text[];  -- 'E3' = 3a della East, ecc.
  v_playin bigint[]; v_mappa int[] := array[4, 1, 2, 3];  -- quarto i <- vincente del play-in v_mappa[i]
  v_a bigint; v_b bigint; v_creati int := 0;
begin
  select * into v_season from public.seasons where id = p_season_id;
  select array_agg(team_id order by posizione) into v_e from public.standings where season_id = p_season_id and conferenza = 'est' and posizione between 1 and 12;
  select array_agg(team_id order by posizione) into v_w from public.standings where season_id = p_season_id and conferenza = 'ovest' and posizione between 1 and 12;
  if coalesce(cardinality(v_e), 0) < 12 or coalesce(cardinality(v_w), 0) < 12 then
    return jsonb_build_object('creati', 0, 'motivo', 'servono 12 squadre per conference');
  end if;

  -- Playoff = torneo nuovo: ammonizioni e squalifiche azzerate (stessa regola di crea_tabelloni).
  update public.player_instances pi set ammonizioni_stagione = 0, squalificato_fino_a = 0
    from public.teams t where pi.team_id = t.id and t.league_id = v_season.league_id
     and (pi.ammonizioni_stagione > 0 or pi.squalificato_fino_a > 0);

  select max(giornata) into v_base from public.fixtures where season_id = p_season_id and bracket_tie_id is null;

  foreach v_tipo in array array['title', 'draft'] loop
    if v_tipo = 'title' then
      v_pi_alta := array['E3', 'E4', 'W3', 'W4']; v_pi_bassa := array['W6', 'W5', 'E6', 'E5']; v_dirette := array['E1', 'W2', 'W1', 'E2'];
    else
      v_pi_alta := array['E10', 'E9', 'W10', 'W9']; v_pi_bassa := array['W7', 'W8', 'E7', 'E8']; v_dirette := array['E12', 'W11', 'W12', 'E11'];
    end if;
    insert into public.brackets (league_id, season_id, tipo, formato) values (v_season.league_id, p_season_id, v_tipo, 'conferenze')
    on conflict (season_id, tipo) do nothing returning id into v_bracket;
    continue when v_bracket is null;

    -- Turno 1: i quattro play-in (la prima squadra e' la favorita: ritorno in casa sua)
    v_playin := '{}';
    for i in 1..4 loop
      v_a := case left(v_pi_alta[i], 1) when 'E' then v_e[substr(v_pi_alta[i], 2)::int] else v_w[substr(v_pi_alta[i], 2)::int] end;
      v_b := case left(v_pi_bassa[i], 1) when 'E' then v_e[substr(v_pi_bassa[i], 2)::int] else v_w[substr(v_pi_bassa[i], 2)::int] end;
      insert into public.bracket_ties (bracket_id, league_id, turno, posizione, alta_team_id, bassa_team_id, alta_seed, bassa_seed,
                                       conferenza_alta, conferenza_bassa, gara_secca)
      values (v_bracket, v_season.league_id, 1, i - 1, v_a, v_b, substr(v_pi_alta[i], 2)::int, substr(v_pi_bassa[i], 2)::int,
              case left(v_pi_alta[i], 1) when 'E' then 'est' else 'ovest' end, case left(v_pi_bassa[i], 1) when 'E' then 'est' else 'ovest' end, false)
      returning id into v_tie;
      perform private.crea_fixtures_tie(v_tie, private.giornata_turno(v_base, 1));
      v_playin := v_playin || v_tie;
      v_creati := v_creati + 1;
    end loop;

    -- Turno 2: i quarti, con la testa di serie gia' al suo posto e l'avversario che arriva dal play-in
    for i in 1..4 loop
      v_a := case left(v_dirette[i], 1) when 'E' then v_e[substr(v_dirette[i], 2)::int] else v_w[substr(v_dirette[i], 2)::int] end;
      insert into public.bracket_ties (bracket_id, league_id, turno, posizione, alta_team_id, alta_seed, conferenza_alta, da_tie_id, gara_secca)
      values (v_bracket, v_season.league_id, 2, i - 1, v_a, substr(v_dirette[i], 2)::int, case left(v_dirette[i], 1) when 'E' then 'est' else 'ovest' end,
              v_playin[v_mappa[i]], false);
      v_creati := v_creati + 1;
    end loop;
  end loop;
  return jsonb_build_object('creati', v_creati, 'formato', 'conferenze');
end $$;

-- Avanzamento del formato B: riempie i quarti con le vincenti dei play-in, poi semifinali e finale accoppiando i
-- vincitori adiacenti (la favorita e' "alta": ritorno in casa sua), e chiude il tabellone dopo la finale.
create or replace function private.avanza_bracket_conferenze(p_bracket_id bigint) returns void
language plpgsql security definer set search_path to '' as $$
declare
  b public.brackets; r record; v_base integer; v_turno integer; v_n integer; v_aperti integer;
  v_vinc bigint[]; v_seed int[]; v_conf text[]; v_tie bigint; i int; v_finalista bigint; v_stagione smallint;
  v_a bigint; v_b bigint; v_sa int; v_sb int; v_ca text; v_cb text;
begin
  select * into b from public.brackets where id = p_bracket_id for update;
  if b.stato = 'concluso' then return; end if;
  select max(giornata) into v_base from public.fixtures where season_id = b.season_id and bracket_tie_id is null;

  -- 1) quarti in attesa dell'avversario: arriva la vincente del play-in
  for r in select q.id, q.turno, p.vincitore_team_id as vinc,
                  case when p.vincitore_team_id = p.alta_team_id then p.alta_seed else p.bassa_seed end as seed,
                  case when p.vincitore_team_id = p.alta_team_id then p.conferenza_alta else p.conferenza_bassa end as conf
             from public.bracket_ties q join public.bracket_ties p on p.id = q.da_tie_id
            where q.bracket_id = p_bracket_id and q.bassa_team_id is null and p.stato = 'concluso' and p.vincitore_team_id is not null loop
    update public.bracket_ties set bassa_team_id = r.vinc, bassa_seed = r.seed, conferenza_bassa = r.conf where id = r.id;
    perform private.crea_fixtures_tie(r.id, private.giornata_turno(v_base, r.turno));
  end loop;

  -- 2) turno piu' alto tutto concluso: semifinali, finale o fine del tabellone
  select max(turno) into v_turno from public.bracket_ties where bracket_id = p_bracket_id;
  select count(*) filter (where stato <> 'concluso'), count(*) into v_aperti, v_n from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;
  if v_aperti > 0 then return; end if;

  if v_n = 1 then
    select vincitore_team_id, case when alta_team_id = vincitore_team_id then bassa_team_id else alta_team_id end
      into b.vincitore_team_id, v_finalista from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;
    update public.brackets set stato = 'concluso', concluso_il = now(), vincitore_team_id = b.vincitore_team_id, finalista_team_id = v_finalista
     where id = p_bracket_id;
    if not exists (select 1 from public.brackets where season_id = b.season_id and stato <> 'concluso') then
      begin
        select s.numero into v_stagione from public.seasons s where s.id = b.season_id;
        perform private.assegna_posizioni_playoff(b.league_id, v_stagione);
      exception when others then
        raise warning 'playoff conferenze: assegnazione posizioni fallita per lega % stagione %: % (%)', b.league_id, v_stagione, sqlerrm, sqlstate;
      end;
    end if;
    return;
  end if;

  select array_agg(vincitore_team_id order by posizione),
         array_agg(case when vincitore_team_id = alta_team_id then alta_seed else bassa_seed end order by posizione),
         array_agg(case when vincitore_team_id = alta_team_id then conferenza_alta else conferenza_bassa end order by posizione)
    into v_vinc, v_seed, v_conf from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;
  for i in 1..(v_n / 2) loop
    if private.po_favorita(b.season_id, b.tipo, v_vinc[i * 2 - 1], v_vinc[i * 2]) then
      v_a := v_vinc[i * 2 - 1]; v_sa := v_seed[i * 2 - 1]; v_ca := v_conf[i * 2 - 1]; v_b := v_vinc[i * 2]; v_sb := v_seed[i * 2]; v_cb := v_conf[i * 2];
    else
      v_a := v_vinc[i * 2]; v_sa := v_seed[i * 2]; v_ca := v_conf[i * 2]; v_b := v_vinc[i * 2 - 1]; v_sb := v_seed[i * 2 - 1]; v_cb := v_conf[i * 2 - 1];
    end if;
    insert into public.bracket_ties (bracket_id, league_id, turno, posizione, alta_team_id, bassa_team_id, alta_seed, bassa_seed,
                                     conferenza_alta, conferenza_bassa, gara_secca)
    values (p_bracket_id, b.league_id, v_turno + 1, i - 1, v_a, v_b, v_sa, v_sb, v_ca, v_cb, (v_n / 2) = 1)
    returning id into v_tie;
    perform private.crea_fixtures_tie(v_tie, private.giornata_turno(v_base, v_turno + 1));
  end loop;
end $$;

revoke all on function private.crea_tabelloni_conferenze(bigint), private.avanza_bracket_conferenze(bigint), private.po_favorita(bigint, text, bigint, bigint) from public, anon, authenticated;

-- Ingressi: nelle leghe con le conferenze si usa il formato B; le altre restano come prima.
CREATE OR REPLACE FUNCTION private.crea_tabelloni(p_season_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season public.seasons;
  v_lega public.leagues;
  v_squadre bigint[];
  v_n integer;
  v_n_alta integer;
  v_n_bassa integer;
  v_turni_max integer;
  v_base integer;
  v_tipo text;
  v_gruppo bigint[];
  v_m integer;
  v_posti integer;
  v_turni integer;
  v_ordine integer[];
  v_bracket_id bigint;
  v_tie_id bigint;
  v_alta bigint; v_bassa bigint;
  v_seed_a integer; v_seed_b integer;
  v_pos integer;
  v_turno_globale integer;
  v_creati integer := 0;
begin
  select * into v_season from public.seasons where id = p_season_id;
  select * into v_lega from public.leagues where id = v_season.league_id;

  -- Leghe con le conferenze: formato B (21/10/2026), Champions e Draft Playoffs per conference.
  if v_lega.conferenze_attive and exists (select 1 from public.standings where season_id = p_season_id and conferenza is not null) then
    return private.crea_tabelloni_conferenze(p_season_id);
  end if;

  -- I playoff sono un torneo nuovo: ci si entra con la fedina pulita, sia
  -- per il conto delle ammonizioni sia per le squalifiche gia' maturate.
  -- Un giocatore espulso all'ultima di campionato gioca la prima di playoff.
  --
  -- Fino all'11 settembre 2026 qui si azzeravano SOLO le ammonizioni, e un
  -- commento spiegava che una squalifica gia' maturata andava scontata anche
  -- ai playoff. Regola rovesciata su richiesta esplicita dell'utente:
  -- stagione regolare e playoff sono due competizioni distinte, e le
  -- pendenze disciplinari dell'una non passano all'altra.
  update public.player_instances pi
  set ammonizioni_stagione = 0,
      squalificato_fino_a = 0
  from public.teams t
  where pi.team_id = t.id and t.league_id = v_season.league_id
    and (pi.ammonizioni_stagione > 0 or pi.squalificato_fino_a > 0);

  -- Classifica finale, dalla prima all'ultima.
  select array_agg(st.team_id order by st.posizione)
    into v_squadre
  from public.standings st
  join public.teams t on t.id = st.team_id and t.attiva
  where st.season_id = p_season_id and st.posizione is not null;

  v_n := coalesce(cardinality(v_squadre), 0);
  if v_n < 8 then
    -- Sotto la soglia di §10.7 non si gioca nessun tabellone.
    return jsonb_build_object('creati', 0, 'motivo', 'meno di 8 squadre');
  end if;

  -- Title Playoff: sempre le prime 8, punto fisso (§1.1). Draft Playoff:
  -- il resto, puo' essere vuoto (v_n = 8) o anche una sola squadra.
  v_n_alta := 8;
  v_n_bassa := v_n - v_n_alta;
  v_turni_max := private.turni_tabellone(v_n_alta);
  if v_n_bassa >= 1 then
    v_turni_max := greatest(v_turni_max, private.turni_tabellone(v_n_bassa));
  end if;
  select max(giornata) into v_base from public.fixtures
  where season_id = p_season_id and bracket_tie_id is null;

  foreach v_tipo in array array['title', 'draft'] loop
    if v_tipo = 'title' then
      v_gruppo := v_squadre[1:v_n_alta];
    else
      if v_n_bassa < 1 then continue; end if;
      -- Ordinato al contrario: la testa di serie del Draft Playoff e'
      -- l'ultima in classifica assoluta, stesso principio di prima.
      select array_agg(x order by ord desc)
        into v_gruppo
      from unnest(v_squadre[v_n_alta + 1:v_n]) with ordinality as u(x, ord);
    end if;

    v_m := cardinality(v_gruppo);
    v_posti := private.posti_tabellone(v_m);
    v_turni := private.turni_tabellone(v_m);
    v_ordine := case when v_tipo = 'title'
      then private.ordine_tabellone(v_posti)
      else private.ordine_draft_playoff(v_m)
    end;

    insert into public.brackets (league_id, season_id, tipo)
    values (v_season.league_id, p_season_id, v_tipo)
    on conflict (season_id, tipo) do nothing
    returning id into v_bracket_id;
    if v_bracket_id is null then continue; end if;

    -- Turno 1: le coppie dell'ordine (incrociato per il title, adiacente
    -- per il draft). Un seed oltre v_m non esiste, quindi l'altro passa
    -- senza giocare.
    v_pos := 0;
    v_turno_globale := v_turni_max - v_turni + 1;
    for i in 1..(v_posti / 2) loop
      v_seed_a := v_ordine[i * 2 - 1];
      v_seed_b := v_ordine[i * 2];
      v_alta := case when v_seed_a <= v_m then v_gruppo[v_seed_a] end;
      v_bassa := case when v_seed_b <= v_m then v_gruppo[v_seed_b] end;

      insert into public.bracket_ties (
        bracket_id, league_id, turno, posizione,
        alta_team_id, bassa_team_id, alta_seed, bassa_seed,
        gara_secca, vincitore_team_id, stato
      ) values (
        v_bracket_id, v_season.league_id, 1, v_pos,
        v_alta, v_bassa,
        case when v_seed_a <= v_m then v_seed_a end,
        case when v_seed_b <= v_m then v_seed_b end,
        v_turni = 1,
        -- Bye: se manca un lato, l'altro e' gia' qualificato.
        case when v_bassa is null then v_alta when v_alta is null then v_bassa end,
        case when v_alta is null or v_bassa is null then 'concluso' else 'in_attesa' end
      ) returning id into v_tie_id;

      if v_alta is not null and v_bassa is not null then
        perform private.crea_fixtures_tie(v_tie_id, private.giornata_turno(v_base, v_turno_globale));
      end if;
      v_pos := v_pos + 1;
      v_creati := v_creati + 1;
    end loop;

    -- Se il primo turno era tutto bye (gruppo gia' potenza di 2 con byes,
    -- o gruppo da una sola squadra), si avanza subito.
    perform private.avanza_bracket(v_bracket_id);
  end loop;

  return jsonb_build_object('creati', v_creati, 'squadre', v_n, 'turni_max', v_turni_max);
end;
$function$;

CREATE OR REPLACE FUNCTION private.avanza_bracket(p_bracket_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_bracket public.brackets;
  v_lega public.leagues;
  v_turno integer;
  v_rimasti integer;
  v_vincitori bigint[];
  v_seeds integer[];
  v_n_ties integer;
  v_base integer;
  v_turni_max integer;
  v_turno_globale integer;
  v_tie_id bigint;
  v_alta bigint; v_bassa bigint;
  v_seed_a integer; v_seed_b integer;
  v_finalista bigint;
  v_stagione_giocata smallint;
  v_altri_aperti integer;
begin
  select * into v_bracket from public.brackets where id = p_bracket_id for update;
  if v_bracket.stato = 'concluso' then return; end if;
  if v_bracket.formato = 'conferenze' then perform private.avanza_bracket_conferenze(p_bracket_id); return; end if;
  select * into v_lega from public.leagues where id = v_bracket.league_id;

  select max(turno) into v_turno from public.bracket_ties where bracket_id = p_bracket_id;
  select count(*) into v_rimasti from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno and stato <> 'concluso';
  if v_rimasti > 0 then return; end if;

  select count(*) into v_n_ties from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno;

  -- Turno finale concluso: si assegna il vincitore. Nessun premio in
  -- denaro (ne' per il title ne' per il draft playoff): il primo da'
  -- il titolo, il secondo determina l'ordine di scelta della prossima
  -- stagione.
  if v_n_ties = 1 then
    select vincitore_team_id,
           case when alta_team_id = vincitore_team_id then bassa_team_id else alta_team_id end
      into v_bracket.vincitore_team_id, v_finalista
    from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

    update public.brackets
    set stato = 'concluso', concluso_il = now(),
        vincitore_team_id = v_bracket.vincitore_team_id,
        finalista_team_id = v_finalista
    where id = p_bracket_id;

    -- Se questo era l'ultimo tabellone ancora aperto della stagione,
    -- l'ordine di scelta della prossima si puo' calcolare.
    select count(*) into v_altri_aperti
    from public.brackets where season_id = v_bracket.season_id and stato <> 'concluso';
    if v_altri_aperti = 0 then
      begin
        select s.numero into v_stagione_giocata from public.seasons s where s.id = v_bracket.season_id;
        perform private.assegna_posizioni_playoff(v_bracket.league_id, v_stagione_giocata);
      exception when others then
        raise warning 'mercato a scelte: assegnazione posizioni fallita per lega % stagione %: % (%)',
          v_bracket.league_id, v_stagione_giocata, sqlerrm, sqlstate;
      end;
    end if;

    return;
  end if;

  -- Altrimenti si costruisce il turno successivo accoppiando i vincitori
  -- adiacenti: 0 con 1, 2 con 3, e cosi' via.
  select array_agg(vincitore_team_id order by posizione),
         array_agg(coalesce(
           case when vincitore_team_id = alta_team_id then alta_seed else bassa_seed end,
           999) order by posizione)
    into v_vincitori, v_seeds
  from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

  select max(giornata) into v_base from public.fixtures
  where season_id = v_bracket.season_id and bracket_tie_id is null;
  select greatest(
      private.turni_tabellone(least(8, count(*))::integer),
      private.turni_tabellone(greatest(count(*) - 8, 0)::integer))
    into v_turni_max
  from public.standings st join public.teams t on t.id = st.team_id and t.attiva
  where st.season_id = v_bracket.season_id and st.posizione is not null;

  -- Quanti turni restano a questo tabellone, per allineare la finale.
  v_turno_globale := v_turni_max - (ceil(log(2, greatest(v_n_ties, 2)::numeric))::integer);

  for i in 1..(v_n_ties / 2) loop
    -- Fra i due qualificati, il seed migliore (numero piu' basso) e' la "alta".
    if v_seeds[i * 2 - 1] <= v_seeds[i * 2] then
      v_alta := v_vincitori[i * 2 - 1]; v_seed_a := v_seeds[i * 2 - 1];
      v_bassa := v_vincitori[i * 2];     v_seed_b := v_seeds[i * 2];
    else
      v_alta := v_vincitori[i * 2];     v_seed_a := v_seeds[i * 2];
      v_bassa := v_vincitori[i * 2 - 1]; v_seed_b := v_seeds[i * 2 - 1];
    end if;

    insert into public.bracket_ties (
      bracket_id, league_id, turno, posizione,
      alta_team_id, bassa_team_id, alta_seed, bassa_seed, gara_secca
    ) values (
      p_bracket_id, v_bracket.league_id, v_turno + 1, i - 1,
      v_alta, v_bassa, v_seed_a, v_seed_b,
      (v_n_ties / 2) = 1
    ) returning id into v_tie_id;

    perform private.crea_fixtures_tie(v_tie_id, private.giornata_turno(v_base, v_turno_globale + 1));
  end loop;
end;
$function$;
