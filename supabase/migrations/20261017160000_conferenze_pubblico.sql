-- Conferenze stampa: l'effetto sul pubblico (docs/decisioni-conferenze-stampa.md §2b).
-- La valutazione dell'AI da' anche un voto al pubblico (-3..+1,5, come il morale): 1 punto di
-- voto = 4 punti di umore del pubblico (0-100). Una brutta conferenza (-3) toglie 12 punti, e
-- da 80 in giu' il bonus casa comincia a calare: e' la leva principale del pubblico.
-- Il post del tifoso (reazione_pubblico) e' il primo seme di SocialOne.

begin;

alter table public.conferenze_domande
  add column if not exists effetto_pubblico numeric(4,1),
  add column if not exists reazione_pubblico text;

create or replace function public.applica_pubblico(p_domanda_id bigint, p_voto numeric)
returns numeric
language plpgsql security definer set search_path = ''
as $$
declare
  v_team bigint;
  v_prima numeric;
  v_dopo numeric;
begin
  select team_id into v_team from public.conferenze_domande where id = p_domanda_id;
  if v_team is null then raise exception 'Domanda % inesistente.', p_domanda_id; end if;

  select pubblico into v_prima from public.teams where id = v_team for update;
  v_dopo := greatest(0, least(100, v_prima + greatest(-3, least(1.5, coalesce(p_voto, 0))) * 4));
  update public.teams set pubblico = v_dopo where id = v_team;
  return round(v_dopo - v_prima, 1);
end;
$$;
revoke all on function public.applica_pubblico(bigint, numeric) from public, anon, authenticated;
grant execute on function public.applica_pubblico(bigint, numeric) to service_role;

commit;
