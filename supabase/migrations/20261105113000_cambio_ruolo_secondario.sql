-- Season 3, diario §3: cambio di ruolo il 25% piu' rapido verso un ruolo gia' tra quelli in scheda.
-- Funzioni ricostruite dalla definizione live.

CREATE OR REPLACE FUNCTION public.avvia_cambio_ruolo(p_instance_id bigint, p_ruolo_target text)
 RETURNS cambi_ruolo
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_target_validi text[];
  v_livello smallint;
  v_riduzione numeric;
  v_base integer;
  v_durata integer;
  v_prossima integer;
  v_cambio public.cambi_ruolo;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un cambio di ruolo solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un cambio di ruolo in corso.';
  end if;
  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' facendo un allenamento di specializzazione: non puo'' anche cambiare ruolo insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_target_validi := private.ruoli_target_cambio(v_posizioni_attuali);
  if v_target_validi is null or not (p_ruolo_target = any(v_target_validi)) then
    raise exception using errcode = '22023',
      message = 'Ruolo non raggiungibile da un giocatore che gioca ' || v_posizioni_attuali[1] || '.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_base := greatest(6, 14 - 2 * (cardinality(v_posizioni_attuali) - 1));
  -- Season 3 (diario §3): verso un ruolo che il giocatore ha gia' in scheda il 25% in meno, sommato allo
  -- sconto dell'allenamento.
  v_durata := greatest(2, round(v_base * (1 - (v_riduzione
    + case when p_ruolo_target = any(v_posizioni_attuali) then 25 else 0 end) / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.cambi_ruolo (
    league_id, team_id, player_instance_id, ruolo_precedente, ruolo_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_posizioni_attuali[1], p_ruolo_target,
    v_prossima, v_prossima + v_durata
  ) returning * into v_cambio;

  return v_cambio;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.avvia_cambio_ruolo_vivaio(p_vivaio_id bigint, p_ruolo_target text)
 RETURNS cambi_ruolo
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_vp public.vivaio_prospetti;
  v_squadra public.teams;
  v_lega public.leagues;
  v_pos text[];
  v_validi text[];
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_cambio public.cambi_ruolo;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.'; end if;
  select * into v_vp from public.vivaio_prospetti where id = p_vivaio_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Prospetto inesistente.'; end if;
  select * into v_squadra from public.teams where id = v_vp.team_id and user_id = v_utente;
  if not found then raise exception using errcode = '42501', message = 'Questo prospetto non è nel tuo vivaio.'; end if;
  select * into v_lega from public.leagues where id = v_vp.league_id;
  if v_lega.stato <> 'stagione' then raise exception using errcode = '55000', message = 'Puoi avviare un cambio di ruolo solo durante la stagione.'; end if;
  if exists (select 1 from public.cambi_ruolo where vivaio_id = p_vivaio_id and completato_il is null) then
    raise exception using errcode = '55000', message = 'Questo prospetto ha già un cambio di ruolo in corso.';
  end if;
  select coalesce(v_vp.posizioni_override, p.posizioni) into v_pos from public.players p where p.id = v_vp.player_id;
  v_validi := private.ruoli_target_cambio(v_pos);
  if v_validi is null or not (p_ruolo_target = any(v_validi)) then
    raise exception using errcode = '22023', message = 'Ruolo non raggiungibile da un giocatore che gioca ' || v_pos[1] || '.';
  end if;
  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce((private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);
  -- Season 3 (diario §3): verso un ruolo gia' in scheda il 25% in meno, come in avvia_cambio_ruolo.
  v_durata := greatest(2, round(greatest(6, 14 - 2 * (cardinality(v_pos) - 1)) * (1 - (v_riduzione
    + case when p_ruolo_target = any(v_pos) then 25 else 0 end) / 100.0)));
  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';
  insert into public.cambi_ruolo (league_id, team_id, vivaio_id, ruolo_precedente, ruolo_target, avviato_giornata, completa_giornata)
  values (v_lega.id, v_squadra.id, p_vivaio_id, v_pos[1], p_ruolo_target, v_prossima, v_prossima + v_durata)
  returning * into v_cambio;
  return v_cambio;
end $function$

;
