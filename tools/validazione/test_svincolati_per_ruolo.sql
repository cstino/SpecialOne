begin;

create temp table risultati_svincolati_per_ruolo (
  step text primary key,
  ok boolean not null,
  dettaglio text
) on commit drop;

do $$
declare
  v_league_id bigint := 3;
  v_giorno_normale date := date '2099-10-01';
  v_giorno_offseason date := date '2099-10-02';
  v_creati integer;
  v_json jsonb;
begin
  update public.leagues
  set fase_carriera = 'normale'
  where id = v_league_id;

  v_creati := private.estrai_svincolati_lega(v_league_id, v_giorno_normale);

  select jsonb_object_agg(macro, quanti)
  into v_json
  from (
    select private.macro_ruolo(p.posizioni) as macro, count(*)::integer as quanti
    from public.free_agent_auctions a
    join public.players p on p.id = a.player_id
    where a.league_id = v_league_id
      and a.giorno = v_giorno_normale
      and a.origine = 'estrazione'
    group by 1
  ) c;

  insert into risultati_svincolati_per_ruolo
  values (
    'normale 3 per ruolo',
    v_creati = 12
      and coalesce((v_json->>'GK')::integer, 0) = 3
      and coalesce((v_json->>'DEF')::integer, 0) = 3
      and coalesce((v_json->>'MID')::integer, 0) = 3
      and coalesce((v_json->>'ATT')::integer, 0) = 3,
    v_json::text
  );

  update public.leagues
  set fase_carriera = 'offseason'
  where id = v_league_id;

  v_creati := private.estrai_svincolati_lega(v_league_id, v_giorno_offseason);

  select jsonb_object_agg(macro, quanti)
  into v_json
  from (
    select private.macro_ruolo(p.posizioni) as macro, count(*)::integer as quanti
    from public.free_agent_auctions a
    join public.players p on p.id = a.player_id
    where a.league_id = v_league_id
      and a.giorno = v_giorno_offseason
      and a.origine = 'estrazione'
    group by 1
  ) c;

  insert into risultati_svincolati_per_ruolo
  values (
    'offseason 10 per ruolo',
    v_creati = 40
      and coalesce((v_json->>'GK')::integer, 0) = 10
      and coalesce((v_json->>'DEF')::integer, 0) = 10
      and coalesce((v_json->>'MID')::integer, 0) = 10
      and coalesce((v_json->>'ATT')::integer, 0) = 10,
    v_json::text
  );
end $$;

select * from risultati_svincolati_per_ruolo order by step;

rollback;
