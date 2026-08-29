begin;

-- ============================================================
--  Aggiunge il nome allenatore (public.profiles) all'avanzamento del
--  draft, cosi' come gia' mostrato in Lobby e TeamProfile. Null per le
--  squadre PC (user_id null) e per chi non ha ancora impostato un nome.
-- ============================================================

-- CREATE OR REPLACE non permette di cambiare l'elenco di colonne di una
-- RETURNS TABLE esistente: va ricreata da zero, coi permessi.
drop function if exists public.stato_avanzamento_draft(bigint);

create function public.stato_avanzamento_draft(p_league_id bigint)
returns table (
  team_id bigint,
  nome text,
  stemma_url text,
  controllata_da_pc boolean,
  stato text,
  giocatori integer,
  obiettivo integer,
  nome_allenatore text
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
         l.slot_rosa::integer,
         p.nome_allenatore
  from public.leagues l
  join public.teams t on t.league_id = l.id and t.attiva
  left join public.draft_team_state d on d.team_id = t.id
  left join public.player_instances pi
    on pi.league_id = l.id and pi.team_id = t.id
  left join public.profiles p on p.user_id = t.user_id
  where l.id = p_league_id
  group by l.slot_rosa, t.id, t.nome, t.stemma_url, t.controllata_da_pc,
           t.ordine_draft, d.stato, p.nome_allenatore
  order by t.ordine_draft nulls last, t.id;
end;
$$;

revoke all on function public.stato_avanzamento_draft(bigint) from public, anon;
grant execute on function public.stato_avanzamento_draft(bigint) to authenticated;

commit;
