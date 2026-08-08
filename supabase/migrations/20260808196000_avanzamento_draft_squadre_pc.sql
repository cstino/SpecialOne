-- Il cron resta un fallback, ma chi ha terminato il proprio draft non deve
-- attendere un minuto per ogni squadra PC. La UI può completarne una per
-- chiamata e mostrare, fra una chiamata e l'altra, l'avanzamento reale.

create or replace function public.completa_prossima_squadra_pc(p_league_id bigint)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_team_id bigint;
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from public.leagues l
    left join public.teams t
      on t.league_id = l.id and t.user_id = (select auth.uid()) and t.attiva
    where l.id = p_league_id
      and (l.admin_id = (select auth.uid()) or t.id is not null)
  ) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  -- Un solo worker per lega: due schede aperte non scelgono la stessa
  -- squadra e non si contendono i lock usati dalla procedura di draft.
  perform pg_catalog.pg_advisory_xact_lock(p_league_id);

  select t.id into v_team_id
  from public.teams t
  join public.draft_team_state d on d.team_id = t.id
  where t.league_id = p_league_id
    and t.controllata_da_pc and t.attiva
    and d.stato <> 'concluso'
  order by t.ordine_draft nulls last, t.id
  limit 1;

  if v_team_id is null then
    return false;
  end if;

  perform private.completa_draft_squadra_pc(p_league_id, v_team_id);

  -- Se anche gli umani hanno finito, non aspettiamo il giro successivo del
  -- cron per inizializzare calendario e stagione.
  if not exists (
    select 1 from public.draft_team_state
    where league_id = p_league_id and stato <> 'concluso'
  ) then
    update public.draft_state set stato = 'concluso', aggiornato_il = now()
    where league_id = p_league_id;
    update public.leagues set stato = 'stagione'
    where id = p_league_id and stato = 'draft';
  end if;

  return true;
end;
$$;

revoke all on function public.completa_prossima_squadra_pc(bigint) from public, anon;
grant execute on function public.completa_prossima_squadra_pc(bigint) to authenticated;

-- Espone soltanto dati di avanzamento, mai le carte ancora coperte degli
-- altri partecipanti. SECURITY DEFINER serve a superare la RLS privata di
-- draft_team_state, dopo aver verificato l'appartenenza alla lega.
create or replace function public.stato_avanzamento_draft(p_league_id bigint)
returns table (
  team_id bigint,
  nome text,
  stemma_url text,
  controllata_da_pc boolean,
  stato text,
  giocatori integer,
  obiettivo integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from public.leagues l
    left join public.teams t
      on t.league_id = l.id and t.user_id = (select auth.uid()) and t.attiva
    where l.id = p_league_id
      and (l.admin_id = (select auth.uid()) or t.id is not null)
  ) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  return query
  select t.id,
         t.nome,
         t.stemma_url,
         t.controllata_da_pc,
         coalesce(d.stato, 'in_corso'),
         count(pi.id)::integer,
         l.slot_rosa::integer
  from public.leagues l
  join public.teams t on t.league_id = l.id and t.attiva
  left join public.draft_team_state d on d.team_id = t.id
  left join public.player_instances pi
    on pi.league_id = l.id and pi.team_id = t.id
  where l.id = p_league_id
  group by l.slot_rosa, t.id, t.nome, t.stemma_url, t.controllata_da_pc,
           t.ordine_draft, d.stato
  order by t.ordine_draft nulls last, t.id;
end;
$$;

revoke all on function public.stato_avanzamento_draft(bigint) from public, anon;
grant execute on function public.stato_avanzamento_draft(bigint) to authenticated;
