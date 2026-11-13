-- Playoff con conference da 14 squadre (Serie F, Season 3). Formato confermato dal committente il 14/11/2026:
-- giocano tutte e 28.
--   * Title Playoff: 1a-7a di ogni conference. La 1a e' diretta ai quarti; 2a-7a al play-in incrociato
--     (2E-7W, 3E-6W, 4E-5W e le stesse a conference invertite).
--   * Draft Playoffs: 8a-14a, lo specchio. La 14a diretta ai quarti; play-in 13E-8W, 12E-9W, 11E-10W e inversi.
--   * Quarti: 1a Est contro la vincente di 4W-5E; vincente 2W-7E contro vincente 3E-6W; 1a Ovest contro la vincente
--     di 4E-5W; vincente 2E-7W contro vincente 3W-6E. Le due prime si incontrano solo in finale, e la 1a e la 2a
--     della stessa conference stanno in meta' opposte.
-- Novita' di struttura: due quarti su quattro sono fra due vincenti del play-in, quindi una sfida puo' aspettare
-- ENTRAMBE le squadre (da_tie_alta_id oltre a da_tie_id). Le conference da 12 restano col formato di prima.

alter table public.bracket_ties add column if not exists da_tie_alta_id bigint references public.bracket_ties(id) on delete set null;
comment on column public.bracket_ties.da_tie_alta_id is 'Come da_tie_id, per la prima squadra: la sfida aspetta la vincente di quel play-in (quarti fra due vincenti).';

create or replace function private.crea_tabelloni_conferenze(p_season_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_season public.seasons; v_base integer; v_tipo text; v_bracket bigint; v_tie bigint; i int;
  v_e bigint[]; v_w bigint[];          -- squadre per posizione nella conference
  v_n int;                             -- squadre per conference: 12 oppure 14
  v_pi_alta text[]; v_pi_bassa text[]; -- 'E3' = 3a della East, ecc.
  v_q_dir text[];                      -- quarto i: la testa di serie gia' al suo posto (null se arrivano due vincenti)
  v_q_a int[]; v_q_b int[];            -- quarto i: da quale play-in arriva la prima squadra (se manca la testa di serie) e la seconda
  v_playin bigint[];
  v_a bigint; v_b bigint; v_creati int := 0;
begin
  select * into v_season from public.seasons where id = p_season_id;
  select array_agg(team_id order by posizione) into v_e from public.standings where season_id = p_season_id and conferenza = 'est' and posizione is not null;
  select array_agg(team_id order by posizione) into v_w from public.standings where season_id = p_season_id and conferenza = 'ovest' and posizione is not null;
  v_n := coalesce(cardinality(v_e), 0);
  if v_n not in (12, 14) or coalesce(cardinality(v_w), 0) <> v_n then
    return jsonb_build_object('creati', 0, 'motivo', 'servono 12 o 14 squadre per conference, lo stesso numero nelle due');
  end if;

  -- Playoff = torneo nuovo: ammonizioni e squalifiche azzerate (stessa regola di crea_tabelloni).
  update public.player_instances pi set ammonizioni_stagione = 0, squalificato_fino_a = 0
    from public.teams t where pi.team_id = t.id and t.league_id = v_season.league_id
     and (pi.ammonizioni_stagione > 0 or pi.squalificato_fino_a > 0);

  select max(giornata) into v_base from public.fixtures where season_id = p_season_id and bracket_tie_id is null;

  foreach v_tipo in array array['title', 'draft'] loop
    if v_n = 12 and v_tipo = 'title' then
      v_pi_alta := array['E3', 'E4', 'W3', 'W4']; v_pi_bassa := array['W6', 'W5', 'E6', 'E5'];
      v_q_dir := array['E1', 'W2', 'W1', 'E2']; v_q_a := array[null, null, null, null]::int[]; v_q_b := array[4, 1, 2, 3];
    elsif v_n = 12 then
      v_pi_alta := array['E10', 'E9', 'W10', 'W9']; v_pi_bassa := array['W7', 'W8', 'E7', 'E8'];
      v_q_dir := array['E12', 'W11', 'W12', 'E11']; v_q_a := array[null, null, null, null]::int[]; v_q_b := array[4, 1, 2, 3];
    elsif v_tipo = 'title' then
      v_pi_alta := array['E2', 'E3', 'E4', 'W2', 'W3', 'W4']; v_pi_bassa := array['W7', 'W6', 'W5', 'E7', 'E6', 'E5'];
      v_q_dir := array['E1', null, 'W1', null]; v_q_a := array[null, 4, null, 1]; v_q_b := array[6, 2, 3, 5];
    else
      -- nel Draft Playoffs la favorita (ritorno in casa) e' la peggio piazzata, come gia' nel formato da 12
      v_pi_alta := array['E13', 'E12', 'E11', 'W13', 'W12', 'W11']; v_pi_bassa := array['W8', 'W9', 'W10', 'E8', 'E9', 'E10'];
      v_q_dir := array['E14', null, 'W14', null]; v_q_a := array[null, 4, null, 1]; v_q_b := array[6, 2, 3, 5];
    end if;
    insert into public.brackets (league_id, season_id, tipo, formato) values (v_season.league_id, p_season_id, v_tipo, 'conferenze')
    on conflict (season_id, tipo) do nothing returning id into v_bracket;
    continue when v_bracket is null;

    -- Turno 1: i play-in (la prima squadra e' la favorita: ritorno in casa sua)
    v_playin := '{}';
    for i in 1..cardinality(v_pi_alta) loop
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

    -- Turno 2: i quarti, creati subito. Dove c'e' la testa di serie e' gia' al suo posto; il resto arriva dal play-in.
    for i in 1..4 loop
      if v_q_dir[i] is not null then
        v_a := case left(v_q_dir[i], 1) when 'E' then v_e[substr(v_q_dir[i], 2)::int] else v_w[substr(v_q_dir[i], 2)::int] end;
        insert into public.bracket_ties (bracket_id, league_id, turno, posizione, alta_team_id, alta_seed, conferenza_alta, da_tie_id, gara_secca)
        values (v_bracket, v_season.league_id, 2, i - 1, v_a, substr(v_q_dir[i], 2)::int, case left(v_q_dir[i], 1) when 'E' then 'est' else 'ovest' end,
                v_playin[v_q_b[i]], false);
      else
        insert into public.bracket_ties (bracket_id, league_id, turno, posizione, da_tie_alta_id, da_tie_id, gara_secca)
        values (v_bracket, v_season.league_id, 2, i - 1, v_playin[v_q_a[i]], v_playin[v_q_b[i]], false);
      end if;
      v_creati := v_creati + 1;
    end loop;
  end loop;
  return jsonb_build_object('creati', v_creati, 'formato', 'conferenze', 'squadre_per_conference', v_n);
end
$function$;

-- L'avanzamento: oltre al quarto con la testa di serie gia' piazzata, ora c'e' quello che aspetta due vincenti.
CREATE OR REPLACE FUNCTION private.avanza_bracket_conferenze(p_bracket_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
            where q.bracket_id = p_bracket_id and q.bassa_team_id is null and q.da_tie_alta_id is null
              and p.stato = 'concluso' and p.vincitore_team_id is not null loop
    update public.bracket_ties set bassa_team_id = r.vinc, bassa_seed = r.seed, conferenza_bassa = r.conf where id = r.id;
    perform private.crea_fixtures_tie(r.id, private.giornata_turno(v_base, r.turno));
  end loop;

  -- 1b) quarti fra due vincenti del play-in (conference da 14): si riempiono quando sono finiti tutti e due.
  --     La favorita (ritorno in casa) la decide po_favorita, come nei turni successivi.
  for r in select q.id, q.turno,
                  pa.vincitore_team_id as va, case when pa.vincitore_team_id = pa.alta_team_id then pa.alta_seed else pa.bassa_seed end as sa,
                  case when pa.vincitore_team_id = pa.alta_team_id then pa.conferenza_alta else pa.conferenza_bassa end as ca,
                  pb.vincitore_team_id as vb, case when pb.vincitore_team_id = pb.alta_team_id then pb.alta_seed else pb.bassa_seed end as sb,
                  case when pb.vincitore_team_id = pb.alta_team_id then pb.conferenza_alta else pb.conferenza_bassa end as cb
             from public.bracket_ties q
             join public.bracket_ties pa on pa.id = q.da_tie_alta_id
             join public.bracket_ties pb on pb.id = q.da_tie_id
            where q.bracket_id = p_bracket_id and q.alta_team_id is null and q.bassa_team_id is null
              and pa.stato = 'concluso' and pa.vincitore_team_id is not null
              and pb.stato = 'concluso' and pb.vincitore_team_id is not null loop
    if private.po_favorita(b.season_id, b.tipo, r.va, r.vb) then
      update public.bracket_ties set alta_team_id = r.va, alta_seed = r.sa, conferenza_alta = r.ca, bassa_team_id = r.vb, bassa_seed = r.sb, conferenza_bassa = r.cb where id = r.id;
    else
      update public.bracket_ties set alta_team_id = r.vb, alta_seed = r.sb, conferenza_alta = r.cb, bassa_team_id = r.va, bassa_seed = r.sa, conferenza_bassa = r.ca where id = r.id;
    end if;
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
end $function$;
