-- ============================================================
--  DUE CORREZIONI ALLA CRESCITA DEI GIOVANI, DECISE CON L'UTENTE IL
--  3 SETTEMBRE 2026.
--
--  1) I prospetti in cantera non crescevano MAI: vivaio_prospetti non e'
--     toccata da applica_progressione_trimestrale (che lavora solo su
--     player_instances). Un giovane restava all'overall di generazione
--     finche' non veniva promosso, anche per un'intera stagione.
--
--     Fix: nuovo checkpoint trimestrale dedicato (stesso ritmo, stesso
--     schema idempotente di applica_progressione_trimestrale/
--     assegna_punti_abilita — registro a parte, funzione a parte, per
--     poter correggere una cosa senza toccare le altre) che fa crescere
--     direttamente players.overall per i prospetti in cantera. E' sicuro
--     mutare la riga condivisa "players" SOLO per l'origine vivaio: un
--     prospetto generato da genera_prospetto_vivaio appartiene sempre e
--     solo a UNA lega (mai al catalogo FC26 condiviso fra piu' leghe),
--     quindi non c'e' nessun rischio di contaminare un'altra lega.
--
--     Curva scelta (piu' ripida di quella dei senior, niente minutaggio:
--     un prospetto in cantera non gioca partite, non ha un "minutaggio"
--     da penalizzare): il TASSO stesso di crescita cresce con la distanza
--     dal potenziale, da 10% a stagione (vicino al potenziale) fino al
--     60% (a 40+ punti di distacco), con una variazione casuale +-25%.
--     Esempio (42 di overall, potenziale 80, quindi 38 di margine):
--     arriva realisticamente sui 55-60 dopo una stagione intera in
--     cantera, molto di piu' dei ~5 punti che darebbe la curva senior
--     use pure per un caso cosi' lontano dal potenziale.
--
--  2) Un giovane (<=22 anni) tenuto sempre in panchina cresceva quasi
--     fermo: il moltiplicatore minutaggio ha un pavimento di 0.8x anche a
--     zero minuti, che su un'intera stagione significa solo +5 punti
--     circa anche con un ampio margine dal potenziale. Nella realta' un
--     prospetto non titolare per una stagione o due (dietro un titolare
--     fisso) non e' un caso raro.
--
--     Fix, solo per la fascia <=22 anni (quella 23-31/32+ non cambia: li'
--     il minutaggio deve continuare a contare, premia chi gioca davvero
--     durante gli anni migliori/il declino): il pavimento sale da 0.8 a
--     0.95, il tetto resta 1.4 (quindi la formula diventa
--     0.95 + 0.45*quota invece di 0.8 + 0.6*quota). Chi non gioca affatto
--     cresce quasi come chi gioca sempre; il minutaggio resta comunque un
--     vantaggio reale, solo meno determinante durante lo sviluppo.
-- ============================================================

begin;

create table public.season_vivaio_checkpoints (
  season_id bigint not null references public.seasons(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  checkpoint smallint not null,
  giornata smallint not null,
  applicato_il timestamptz not null default now(),
  primary key (season_id, checkpoint)
);
comment on table public.season_vivaio_checkpoints is
  'Registro dei quarti di stagione in cui e'' gia'' stata applicata la crescita dei prospetti in cantera: rende cresci_vivaio_checkpoint idempotente se il cron ritenta.';

create function public.cresci_vivaio_checkpoint(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_prospetto record;
  v_headroom numeric;
  v_tasso numeric;
  v_nuovo smallint;
  v_aggiornati integer := 0;
begin
  select l.id, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'prospetti_aggiornati', 0);
  end if;

  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_vivaio_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_lega.season_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;
    if not found then
      continue;
    end if;

    v_applicato := v_step;

    for v_prospetto in
      select p.id, p.overall, p.potential
      from public.vivaio_prospetti vp
      join public.teams t on t.id = vp.team_id and t.attiva
      join public.players p on p.id = vp.player_id
      where vp.league_id = p_league_id
      for update of p
    loop
      v_headroom := v_prospetto.potential - v_prospetto.overall;
      if v_headroom <= 0 then
        continue;
      end if;
      -- Tasso STAGIONALE (non trimestrale): 10% a ridosso del potenziale,
      -- fino al 60% con 40+ punti di margine, +-25% di variazione casuale.
      -- Diviso su 4 per ottenere il delta di questo singolo checkpoint.
      v_tasso := (0.10 + 0.50 * least(1.0, v_headroom / 40.0)) * (0.75 + random() * 0.5);
      v_nuovo := greatest(40, least(v_prospetto.potential, round(v_prospetto.overall + v_headroom * v_tasso / 4.0)))::smallint;
      update public.players set overall = v_nuovo where id = v_prospetto.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'prospetti_aggiornati', v_aggiornati);
end;
$$;

revoke all on function public.cresci_vivaio_checkpoint(bigint, smallint) from public, anon, authenticated;
grant execute on function public.cresci_vivaio_checkpoint(bigint, smallint) to service_role;

-- ------------------------------------------------------------
--  Pavimento minutaggio piu' alto, solo <=22 anni.
-- ------------------------------------------------------------
create or replace function public.applica_progressione_trimestrale(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_player record;
  v_delta numeric;
  v_moltiplicatore numeric;
  v_valore numeric;
  v_ovr smallint;
  v_residuo numeric;
  v_checkpoint_applicati smallint[] := array[]::smallint[];
  v_giocatori_aggiornati integer := 0;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    raise exception using errcode = '55000', message = 'Non esiste una stagione in corso per la progressione overall.';
  end if;
  if p_giornata < 1 or p_giornata > v_lega.giornate_totali then
    raise exception using errcode = '22023', message = 'Giornata non valida per la progressione overall.';
  end if;
  v_stagione_id := v_lega.season_id;

  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_progression_checkpoints(league_id, season_id, checkpoint, giornata)
    values (p_league_id, v_stagione_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;
    if not found then
      continue;
    end if;

    for v_player in
      select
        pi.id, pi.overall_corrente, pi.eta_corrente, pi.progressione_residuo, p.potential,
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- Pavimento standard: 0.8x a zero minuti, 1.4x a minutaggio pieno.
      v_moltiplicatore := 0.8 + 0.6 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));

      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / 4.0;
        -- Pavimento piu' alto per chi e' ancora in sviluppo (deciso con
        -- l'utente, 3 settembre 2026): un giovane tenuto sempre in
        -- panchina non deve restare quasi fermo per anni solo perche'
        -- davanti a lui c'e' un titolare fisso. Tetto invariato (1.4x),
        -- solo il pavimento sale da 0.8 a 0.95.
        v_moltiplicatore := 0.95 + 0.45 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_delta := v_delta * v_moltiplicatore;

      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.player_instances
      set overall_corrente = v_ovr, progressione_residuo = v_residuo
      where id = v_player.id;
      v_giocatori_aggiornati := v_giocatori_aggiornati + 1;
    end loop;

    v_checkpoint_applicati := array_append(v_checkpoint_applicati, v_step);
    exit;
  end loop;

  return jsonb_build_object(
    'checkpoint_applicati', v_checkpoint_applicati,
    'giocatori_aggiornati', v_giocatori_aggiornati
  );
end;
$$;

commit;
