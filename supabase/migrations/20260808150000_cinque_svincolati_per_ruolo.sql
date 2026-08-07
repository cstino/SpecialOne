-- L'estrazione giornaliera passa da 3 a 5 giocatori per macro-ruolo:
-- 5 GK, 5 DEF, 5 MID e 5 ATT. L'off-season conserva il suo pool piu'
-- ampio da 10 per ruolo.
create or replace function private.svincolati_per_ruolo(p_league_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fase text;
begin
  select fase_carriera into v_fase
  from public.leagues
  where id = p_league_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;

  if v_fase = 'offseason' then
    return 10;
  end if;
  return 5;
end;
$$;
