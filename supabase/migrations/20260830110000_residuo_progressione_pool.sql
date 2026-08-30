begin;

-- ============================================================
--  BUG trovato testando dal vivo su LegaBot (30 agosto 2026): il delta
--  trimestrale e' minuscolo (diviso per 4 e poi per il moltiplicatore
--  0.8) e arrotonda quasi sempre a zero in un singolo trimestre. Per i
--  giocatori in rosa questo e' innocuo perche' player_instances tiene
--  progressione_residuo, che porta avanti il resto frazionario da un
--  trimestre all'altro finche' non supera 0.5 e produce un punto vero.
--  free_agent_progression non aveva l'equivalente: ogni trimestre
--  perdeva il resto, quindi uno svincolato sarebbe evoluto molto piu'
--  lentamente di un giocatore identico in rosa — l'opposto di "stessa
--  formula".
-- ============================================================

alter table public.free_agent_progression
  add column progressione_residuo numeric not null default 0;

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

    -- Chi ha (o ha avuto) una squadra: player_instances. Il join sulla
    -- squadra attiva e' stato tolto (deciso il 30 agosto 2026): uno
    -- svincolato (team_id nullo) deve continuare a evolvere esattamente
    -- come chi gioca, solo al ritmo minimo perche' minuti_giocati resta
    -- 0 — lo stesso moltiplicatore che la formula gia' applica a chi non
    -- scende mai in campo pur restando in rosa.
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
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / 4.0;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_moltiplicatore := 0.8 + 0.6 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));
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

    -- Chi non e' mai stato scelto in questa lega: free_agent_progression.
    -- Stessa formula per fascia d'eta' e stesso residuo frazionario di
    -- player_instances (aggiunto il 30 agosto 2026, trovato testando su
    -- LegaBot: senza, un delta minuscolo arrotondava a zero ogni singolo
    -- trimestre e andava perso, invece di accumularsi). Moltiplicatore
    -- fisso al minimo (0.8): non hanno mai la possibilita' di giocare un
    -- minuto, quindi restano sempre alla velocita' piu' bassa della
    -- curva, mai a zero.
    for v_player in
      select fap.league_id, fap.player_id, fap.overall_corrente, fap.eta_corrente,
             fap.progressione_residuo, p.potential
      from public.free_agent_progression fap
      join public.players p on p.id = fap.player_id
      where fap.league_id = p_league_id
      for update of fap
    loop
      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / 4.0;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / 4.0;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / 4.0;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / 4.0;
      else
        v_delta := -(1.5 + random() * 2.5) / 4.0;
      end if;

      v_delta := v_delta * 0.8;
      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.free_agent_progression
      set overall_corrente = v_ovr, progressione_residuo = v_residuo, aggiornato_il = now()
      where league_id = v_player.league_id and player_id = v_player.player_id;
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

revoke all on function public.applica_progressione_trimestrale(bigint, smallint)
  from public, anon, authenticated;
grant execute on function public.applica_progressione_trimestrale(bigint, smallint)
  to service_role;

commit;
