-- ============================================================
--  DIFFIDE, SQUALIFICHE E INFORTUNI AI CONFINI DI COMPETIZIONE
--
--  Segnalato dall'utente l'11 settembre 2026, con uno screenshot: in
--  LegaBot, gia' nella stagione 4, arrivava "Unai Hernandez saltera' la
--  prossima giornata - diffidato dopo 5 ammonizioni in stagione". Quelle
--  ammonizioni erano della stagione 3.
--
--  STATO TROVATO, verificato sui dati prima di toccare niente:
--                        inizio playoff        nuova stagione
--    ammonizioni         azzerate (ok)         NON azzerate  <- il bug
--    squalifiche         NON azzerate          NON azzerate
--    infortuni           non toccati (ok)      azzerati del tutto
--
--  In LegaBot, a due giornate dall'inizio della stagione 4, c'erano ancora
--  68 giocatori con ammonizioni (fino a 4) e 5 squalificati.
--
--  TRE CORREZIONI
--
--  1. Squalifiche azzerate all'inizio dei playoff. Rovescia una decisione
--     presa in precedenza e documentata nel codice ("una squalifica gia'
--     maturata resta da scontare anche ai playoff"): l'utente ha chiesto
--     esplicitamente il contrario, perche' stagione regolare e playoff sono
--     due competizioni distinte. Lo si scrive qui perche' chi legge quel
--     commento domani sappia che e' stato cambiato apposta, non per svista.
--
--  2. Fedina pulita anche fra due stagioni: ne' ammonizioni ne' squalifiche
--     attraversano il confine. E' il bug della segnalazione.
--
--  3. Infortuni: la pausa fra due stagioni vale 6 giornate di recupero.
--     ATTENZIONE, questa e' piu' SEVERA di prima, non piu' permissiva.
--     L'utente pensava che gli infortuni si trascinassero per intero; in
--     realta' prepara_offseason li azzerava tutti, quindi chi si rompeva
--     per 10 giornate all'ultima di playoff ripartiva sano e un infortunio
--     grave di fine stagione non costava nulla. Con 6 giornate di sconto
--     quel giocatore ne ha ora 4 da scontare, che e' il valore chiesto.
--
--  Entrambe le funzioni modificate per sostituzione mirata sul testo live,
--  verificata con diff: nessuna riga persa oltre a quelle sostituite.
-- ============================================================

begin;

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
$function$
;

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 20 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 20 squadre.';
  end if;

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + interval '7 days') at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Invecchiamento di fine stagione: il join sulla squadra attiva e'
  -- stato tolto (deciso il 30 agosto 2026), cosi' uno svincolato reale
  -- invecchia esattamente come chi e' in rosa.
  for v_player in
    select pi.id, pi.eta_corrente, pi.infortunato_fino_a
    from public.player_instances pi
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        -- La pausa fra due stagioni vale 6 giornate di recupero, non una
        -- guarigione completa (deciso con l'utente l'11 settembre 2026).
        -- Prima qui si azzerava: chi si rompeva per 10 giornate all'ultima
        -- di playoff ripartiva sano, e un infortunio grave di fine stagione
        -- non costava niente. Ora se ne porta dietro 4.
        infortunato_fino_a = greatest(0, v_player.infortunato_fino_a - 6),
        -- Fedina pulita a ogni nuova stagione, come all'inizio dei playoff:
        -- ne' il conto delle ammonizioni ne' una squalifica gia' maturata
        -- attraversano il confine fra due stagioni.
        ammonizioni_stagione = 0,
        squalificato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  -- Stesso invecchiamento per chi non e' mai stato scelto in questa lega,
  -- residuo azzerato come per player_instances.
  update public.free_agent_progression
  set eta_corrente = least(45, eta_corrente + 1), progressione_residuo = 0, aggiornato_il = now()
  where league_id = p_league_id;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$
;

-- ------------------------------------------------------------
--  Ripulitura dello stato gia' sporco.
--  Solo le leghe che hanno gia' cominciato una nuova stagione: li' ogni
--  pendenza disciplinare e' per definizione ereditata da quella prima.
--  In LegaBot si perdono le ammonizioni prese nelle 2 giornate gia'
--  giocate della stagione 4 (al massimo una o due a testa): non c'e' modo
--  di distinguerle da quelle vecchie, e lasciare 68 giocatori con pendenze
--  fantasma sarebbe peggio.
-- ------------------------------------------------------------
update public.player_instances pi
set ammonizioni_stagione = 0,
    squalificato_fino_a = 0
from public.leagues l
where l.id = pi.league_id
  and l.stato = 'stagione'
  and (pi.ammonizioni_stagione > 0 or pi.squalificato_fino_a > 0)
  and exists (
    select 1 from public.seasons s
    where s.league_id = l.id and s.numero = l.stagione_corrente and s.numero > 1
  );

commit;
