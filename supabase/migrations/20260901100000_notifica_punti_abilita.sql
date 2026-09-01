begin;

-- ============================================================
--  NOTIFICA SUI PUNTI ABILITA' RICEVUTI
--  Deciso il 1 settembre 2026, in conversazione con l'utente: prima
--  arriva la notifica, poi il segnalino nel menu — GameNav lo calcola
--  dalle notifiche non lette taggate 'view':'risorse' (vedi il
--  prossimo passo lato frontend). assegna_punti_abilita non avvisava
--  nessuno: una squadra scopriva i punti solo aprendo la pagina
--  Risorse per caso.
-- ============================================================

create or replace function public.assegna_punti_abilita(p_league_id bigint, p_giornata smallint)
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
  v_squadre integer := 0;
  v_team record;
begin
  select l.id, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'squadre_aggiornate', 0);
  end if;

  -- Stessa scansione di morale e progressione: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_punti_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_lega.season_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    insert into public.team_risorse (team_id, league_id)
    select t.id, t.league_id
    from public.teams t
    where t.league_id = p_league_id and t.attiva
    on conflict (team_id) do nothing;

    -- Notifica solo a chi riceve davvero i punti (esclude chi ha gia'
    -- raggiunto il tetto, e le squadre PC senza user_id: private.notifica
    -- e' gia' un no-op su user_id null, ma evitiamo il giro a vuoto).
    for v_team in
      update public.team_risorse r
      set punti_ricevuti = least(
            private.punti_abilita_massimi(),
            (r.punti_ricevuti + private.punti_per_checkpoint())::smallint
          ),
          aggiornata_il = now()
      from public.teams t
      where t.id = r.team_id
        and t.league_id = p_league_id
        and t.attiva
        and r.punti_ricevuti < private.punti_abilita_massimi()
      returning t.id as team_id, t.user_id
    loop
      v_squadre := v_squadre + 1;
      if v_team.user_id is not null then
        perform private.notifica(
          v_team.user_id, p_league_id, 'sistema', 'Punti abilità disponibili',
          'Hai ricevuto ' || private.punti_per_checkpoint() || ' punti abilità da spendere su Vivaio, Training o Reparto medico.',
          jsonb_build_object('view', 'risorse')
        );
      end if;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'squadre_aggiornate', v_squadre);
end;
$$;

commit;
