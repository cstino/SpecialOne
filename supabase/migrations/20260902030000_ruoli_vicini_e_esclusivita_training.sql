-- ============================================================
--  Due correzioni segnalate dall'utente sul TRAINING:
--
--  1) Il cambio ruolo raggiungeva chiunque nello stesso reparto o in un
--     reparto adiacente (DEF<->MID, MID<->ATT): un CB puro poteva
--     diventare CAM o esterno di centrocampo, non solo terzino/CDM.
--     Sostituito con un grafo di posizioni "vicine" esplicito, stile
--     EA FC (CB -> terzini + CDM, non l'intero reparto adiacente).
--
--  2) Cambio ruolo e specializzazione erano indipendenti: un giocatore
--     poteva avere entrambi in corso insieme. Deciso con l'utente: sono
--     mutuamente esclusivi, un solo allenamento alla volta per
--     giocatore.
-- ============================================================

begin;

-- ------------------------------------------------------------
--  1) Grafo esplicito di posizioni vicine, non piu' basato sul reparto.
-- ------------------------------------------------------------
create or replace function private.ruoli_target_cambio(p_posizioni_attuali text[])
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_posizioni_attuali[1]
    when 'CB'  then array['LB', 'RB', 'CDM']
    when 'LB'  then array['CB', 'LWB', 'LM']
    when 'RB'  then array['CB', 'RWB', 'RM']
    when 'LWB' then array['LB', 'LM', 'LW']
    when 'RWB' then array['RB', 'RM', 'RW']
    when 'CDM' then array['CB', 'CM']
    when 'CM'  then array['CDM', 'CAM', 'LM', 'RM']
    when 'CAM' then array['CM', 'CF', 'LW', 'RW']
    when 'LM'  then array['LB', 'LWB', 'LW', 'CM']
    when 'RM'  then array['RB', 'RWB', 'RW', 'CM']
    when 'LW'  then array['LWB', 'LM', 'CAM', 'ST']
    when 'RW'  then array['RWB', 'RM', 'CAM', 'ST']
    when 'ST'  then array['CF', 'LW', 'RW']
    when 'CF'  then array['CAM', 'ST']
    else array[]::text[]
  end;
$$;
comment on function private.ruoli_target_cambio(text[]) is
  'Ruoli raggiungibili da un cambio di ruolo: grafo esplicito di posizioni '
  'vicine (non reparto/adiacenza), es. CB -> LB/RB/CDM. Simmetrico per '
  'costruzione. Il portiere non ha voce (else vuoto): non si riqualifica.';

-- ------------------------------------------------------------
--  2) Esclusivita': un solo allenamento (cambio ruolo O specializzazione)
--     alla volta per giocatore.
-- ------------------------------------------------------------
create or replace function public.avvia_cambio_ruolo(p_instance_id bigint, p_ruolo_target text)
returns public.cambi_ruolo
language plpgsql
security definer
set search_path = ''
as $$
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
  v_durata := greatest(2, round(v_base * (1 - v_riduzione / 100.0)));

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
$$;

create or replace function public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
returns public.specializzazioni_giocatore
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_macro text;
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
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
    raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;
  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' cambiando ruolo: non puo'' anche allenare una specializzazione insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_macro := private.macro_ruolo(v_posizioni_attuali);
  v_catalogo := private.specializzazioni_ruolo(v_macro);
  if v_macro = 'GK' or v_catalogo is null or not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = case when v_macro = 'GK'
        then 'Il portiere non ha specializzazioni: il motore riassume le sue qualità in un unico valore.'
        else 'Specializzazione non valida per questo ruolo.' end;
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  -- Base 10 giornate, senza lo sconto-versatilita' del cambio ruolo (qui
  -- non si impara un ruolo nuovo, solo un'inclinazione dentro il proprio):
  -- stessa curva TRAINING del cambio ruolo, minimo 3 giornate.
  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$$;

commit;
