-- ============================================================
--  UNDER: i volti prestati non devono essere di giocatori veri che stanno nel gioco (18 ottobre 2026).
--  Segnalato dal committente: l'Under Emeka Ouedraogo aveva il volto di Franculino. Il volto in prestito veniva pescato fra
--  gli U23 dei campionati non attivi, ma quei 547 giocatori sono tutti "elite globali" (presenti in ogni lega): ogni
--  Under aveva il volto di un giocatore vero. Ora si prestano solo i volti dei ~500 U23 NON estraibili, che nel gioco
--  non compaiono mai. Poi si riassegna il volto agli Under vivi di ogni lega (Serie F 63, LegaBot 10).
--  Funzione riscritta dalla definizione viva.
-- ============================================================
begin;

CREATE OR REPLACE FUNCTION private.volto_libero_under(p_league_id bigint)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with usati as (
    select q.foto_url, count(*) n
    from private.under_in_lega(p_league_id) u
    join public.players q on q.id = u.player_id
    where q.foto_url is not null
    group by q.foto_url
  )
  select p.foto_url
  from public.players p
  join public.leagues l on l.id = p_league_id
  left join usati on usati.foto_url = p.foto_url
  -- Volti PRESTATI solo da giocatori che nel gioco non compaiono mai: non estraibili (disponibile_estrazione = false,
  -- circa 500 U23 fra 47 e 65 di overall) e mai in una rosa di questa lega. Prima si pescava fra gli U23 dei campionati
  -- non attivi, ma erano tutti elite presenti in ogni lega (es. Franculino): ogni Under aveva il volto di un giocatore vero.
  where p.eta <= 23 and p.foto_url is not null and not p.origine_vivaio
    and not p.disponibile_estrazione
    and not exists (select 1 from public.player_instances pi where pi.player_id = p.id and pi.league_id = p_league_id)
  order by coalesce(usati.n, 0), random()
  limit 1
$function$;

do $$
declare
  v_lega bigint;
  v_p record;
  v_foto text;
begin
  for v_lega in select id from public.leagues loop
    for v_p in
      select q.id from private.under_in_lega(v_lega) u join public.players q on q.id = u.player_id
       where exists (select 1 from public.players r where r.foto_url = q.foto_url and not r.origine_vivaio and r.disponibile_estrazione)
       order by q.id
    loop
      v_foto := private.volto_libero_under(v_lega);
      if v_foto is not null then
        update public.players set foto_url = v_foto where id = v_p.id;
      end if;
    end loop;
  end loop;
end $$;

commit;
