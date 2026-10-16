-- Conferenze stampa: l'effetto sul morale non si perde piu' negli arrotondamenti.
--
-- Il morale e' un intero (smallint): un +0,5 di voto valeva circa +0,2 per giocatore
-- su una rosa a morale 86 e si arrotondava a zero ("Morale della rosa 0,0" dopo una
-- risposta "convincente"). Ora:
--  * arrotondamento a sorte: 3,2 diventa 3 con l'80% e 4 con il 20%, quindi la media
--    della rosa resta quella vera e nessun effetto sparisce;
--  * scala: 1 punto di voto = 3 punti di morale (era 1,5);
--  * lo smorzamento vicino agli estremi non scende sotto 0,35 (era 0 a morale 100).
-- Sempre una spezia: 50 punti di morale valgono ~3,6 punti su 38 giornate
-- (docs/decisioni-tattiche.md, punto 18).

create or replace function public.applica_conferenza(p_domanda_id bigint, p_voto numeric, p_giocatori jsonb)
returns numeric
language plpgsql security definer set search_path = ''
as $$
declare
  v_team bigint;
  v_voto numeric := greatest(-3, least(1.5, coalesce(p_voto, 0)));
  v_media numeric;
begin
  select team_id into v_team from public.conferenze_domande where id = p_domanda_id;
  if v_team is null then raise exception 'Domanda % inesistente.', p_domanda_id; end if;

  with effetti as (
    select pi.id, pi.morale,
           (v_voto + coalesce((
              select greatest(-3, least(1.5, (g->>'effetto')::numeric))
              from jsonb_array_elements(coalesce(p_giocatori, '[]'::jsonb)) g
              where (g->>'id')::bigint = pi.id limit 1), 0)) * 3 as grezzo
    from public.player_instances pi
    where pi.team_id = v_team and not pi.ritirato
  ), calcolo as (
    select id, morale,
           morale + grezzo * case when grezzo > 0 then greatest(0.35, least(1, (100 - morale) / 50.0))
                                  else greatest(0.35, least(1, morale / 50.0)) end as esatto
    from effetti
  ), nuovi as (
    update public.player_instances pi
       set morale = greatest(0, least(100,
             floor(c.esatto) + case when random() < c.esatto - floor(c.esatto) then 1 else 0 end))::smallint
      from calcolo c
     where pi.id = c.id
    returning pi.morale - c.morale as delta
  )
  select avg(delta) into v_media from nuovi;
  return round(coalesce(v_media, 0), 1);
end;
$$;

revoke all on function public.applica_conferenza(bigint, numeric, jsonb) from public, anon, authenticated;
grant execute on function public.applica_conferenza(bigint, numeric, jsonb) to service_role;
