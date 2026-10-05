-- ============================================================
--  CAMPIONE IN CARICA: CORNICE DORATA SULLO STEMMA (5 ottobre 2026)
--  Il campione in carica e' il vincitore del Title Playoff piu' recente tra
--  quelli gia' "assegnati" (stesso momento delle stelle: ingresso in
--  off-season, a playoff chiusi: nessuno spoiler). Resta tale per tutta la
--  stagione successiva, finche' la stagione dopo non incorona un nuovo
--  campione. Un solo campione per lega.
-- ============================================================

alter table public.teams
  add column if not exists campione_in_carica boolean not null default false;
comment on column public.teams.campione_in_carica is
  'Vincitore del Title Playoff piu'' recente gia'' assegnato (cornice dorata sullo stemma). Derivato da brackets.';

create or replace function private.assegna_stelle_title(p_league_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_fino_a smallint;
  v_ultima smallint;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then return; end if;
  v_fino_a := case when v_lega.fase_carriera = 'offseason'
                   then v_lega.stagione_corrente
                   else v_lega.stagione_corrente - 1 end;

  select max(s.numero) into v_ultima
  from public.brackets b
  join public.seasons s on s.id = b.season_id
  where b.league_id = p_league_id and b.tipo = 'title' and b.stato = 'concluso'
    and b.vincitore_team_id is not null and s.numero <= v_fino_a;

  update public.teams t
  set titoli_title = coalesce((
        select count(*) from public.brackets b
        join public.seasons s on s.id = b.season_id
        where b.league_id = p_league_id and b.tipo = 'title' and b.stato = 'concluso'
          and b.vincitore_team_id = t.id and s.numero <= v_fino_a
      ), 0),
      campione_in_carica = exists (
        select 1 from public.brackets b
        join public.seasons s on s.id = b.season_id
        where b.league_id = p_league_id and b.tipo = 'title' and b.stato = 'concluso'
          and b.vincitore_team_id = t.id and s.numero = v_ultima
      )
  where t.league_id = p_league_id;
end;
$$;
revoke all on function private.assegna_stelle_title(bigint) from public, anon, authenticated;

do $$
declare v_id bigint;
begin
  for v_id in select id from public.leagues loop
    perform private.assegna_stelle_title(v_id);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
