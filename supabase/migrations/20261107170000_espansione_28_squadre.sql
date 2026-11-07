-- Espansione della Serie F a 28 squadre (7/11/2026, docs/DIARIO-SEASON3.md voce 13): due conference da 14.
-- 1) Il tetto delle squadre per lega sale da 24 a 28 (vincolo e modifica delle squadre in off-season).
-- 2) Serie F (lega 63): 4 posti nuovi e chiusura dell'off-season spostata a domenica 8/11 alle 11:00 Roma, per dare
--    tempo alle squadre nuove di fare il draft d'ingresso (il sorteggio East/West vuole un numero pari di squadre).
--    offseason_fine trascina con se' la finestra 'off' delle scelte (trigger sincronizza_estrazione_off).

alter table public.leagues drop constraint leagues_n_squadre_check;
alter table public.leagues add constraint leagues_n_squadre_check check (n_squadre between 4 and 28);

CREATE OR REPLACE FUNCTION public.modifica_squadre_offseason(p_league_id bigint, p_squadre_rimuovi bigint[] DEFAULT '{}'::bigint[], p_nuovi_posti_aperti smallint DEFAULT NULL::smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_off public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può modificare le squadre dell''off-season.';
  end if;
  if v_lega.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non è aperta.';
  end if;

  select * into v_off from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Nessuna off-season aperta trovata.';
  end if;
  if v_off.scade_il <= clock_timestamp() then
    raise exception using errcode = '55000', message = 'L''off-season è già scaduta, non è più modificabile.';
  end if;

  if p_nuovi_posti_aperti is not null and p_nuovi_posti_aperti not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimuovi, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimuovi, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre da rimuovere contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimuovi, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimuovi, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  v_rimosse := cardinality(coalesce(p_squadre_rimuovi, '{}'::bigint[]));

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimuovi) or a_team_id = any(p_squadre_rimuovi));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimuovi);

    -- Una squadra entrante appena invitata (entrata_stagione = stagione_a)
    -- non ha ancora "vissuto" la stagione corrente: greatest() evita di
    -- violare il vincolo uscita_stagione >= entrata_stagione.
    update public.teams
    set attiva = false, uscita_stagione = greatest(v_lega.stagione_corrente, entrata_stagione)
    where league_id = p_league_id and id = any(p_squadre_rimuovi);
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;

  if p_nuovi_posti_aperti is not null then
    v_target := v_attive + p_nuovi_posti_aperti;
  else
    v_target := v_lega.n_squadre - v_rimosse;
  end if;
  if v_target not between 4 and 28 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 28 squadre.';
  end if;
  if v_target < v_attive then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto le squadre già attive: rimuovine altre prima.';
  end if;

  update public.leagues set n_squadre = v_target where id = p_league_id;
  update public.offseasons set posti_nuovi = v_target - v_attive where id = v_off.id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'squadre_attive', v_attive,
    'squadre_attese', v_target,
    'posti_aperti', v_target - v_attive
  );
end;
$function$;

update public.leagues
set n_squadre = 28,
    offseason_fine = timestamp '2026-11-08 11:00:00' at time zone 'Europe/Rome'
where id = 63 and fase_carriera = 'offseason';

update public.offseasons
set posti_nuovi = 28 - (select count(*) from public.teams where league_id = 63 and attiva),
    scade_il = timestamp '2026-11-08 11:00:00' at time zone 'Europe/Rome'
where league_id = 63 and stato = 'aperta';
