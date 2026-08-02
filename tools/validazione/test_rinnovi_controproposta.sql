begin;

create temp table risultati_rinnovi_controproposta (
  step text primary key,
  ok boolean not null,
  dettaglio text
) on commit drop;

grant insert, select on risultati_rinnovi_controproposta to authenticated;

do $$
declare
  v_user uuid := '5ef47be9-3b4f-40c3-86e4-03a7bb3ec266';
  v_rinnovo_counter bigint;
  v_rinnovo_accept bigint;
  v_team_id bigint;
  v_player_instance_id bigint;
  v_state jsonb;
  v_stato text;
  v_richiesta_min bigint;
  v_richiesta_max bigint;
  v_richiesta_esatta bigint;
  v_team_after bigint;
  v_offerta_bassa bigint;
  v_offerta_accettata bigint;
  v_ingaggio bigint;
begin
  select cr.id, cr.team_id, cr.player_instance_id, crt.richiesta_esatta
  into v_rinnovo_counter, v_team_id, v_player_instance_id, v_richiesta_esatta
  from public.contract_renewals cr
  join private.contract_renewal_terms crt on crt.renewal_id = cr.id
  join public.player_instances pi on pi.id = cr.player_instance_id and pi.team_id = cr.team_id
  where cr.team_id = 4
    and crt.richiesta_esatta > 500000
    and cr.stato in ('in_attesa', 'accettato')
  order by cr.id
  limit 1;

  select cr.id, cr.richiesta_max
  into v_rinnovo_accept, v_offerta_accettata
  from public.contract_renewals cr
  join public.player_instances pi on pi.id = cr.player_instance_id and pi.team_id = cr.team_id
  where cr.team_id = 4
    and cr.id <> v_rinnovo_counter
    and cr.richiesta_max >= 500000
    and cr.stato in ('in_attesa', 'accettato')
  order by cr.id
  limit 1;

  if v_rinnovo_counter is null or v_rinnovo_accept is null then
    raise exception using errcode = 'P0002', message = 'Servono almeno due rinnovi disponibili per il test.';
  end if;

  update public.contract_renewals
  set stato = 'in_attesa', offerta = null, durata = null, risolta_il = null
  where id in (v_rinnovo_counter, v_rinnovo_accept);

  update public.player_instances
  set team_id = v_team_id
  where id = v_player_instance_id;

  v_offerta_bassa := greatest(500000, v_richiesta_esatta - 100000);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  v_state := public.rispondi_rinnovo(v_rinnovo_counter, v_offerta_bassa, 1::smallint);

  select stato, richiesta_min, richiesta_max
  into v_stato, v_richiesta_min, v_richiesta_max
  from public.contract_renewals
  where id = v_rinnovo_counter;

  insert into risultati_rinnovi_controproposta
  values (
    'prima offerta bassa',
    coalesce((v_state->>'controproposta')::boolean, false)
      and v_stato = 'controproposta'
      and v_richiesta_min = v_richiesta_max,
    v_state::text
  );

  v_state := public.rispondi_rinnovo(v_rinnovo_counter, v_offerta_bassa, 1::smallint);

  select cr.stato, pi.team_id
  into v_stato, v_team_after
  from public.contract_renewals cr
  join public.player_instances pi on pi.id = cr.player_instance_id
  where cr.id = v_rinnovo_counter;

  insert into risultati_rinnovi_controproposta
  values (
    'ultima offerta bassa',
    v_stato = 'rifiutato' and v_team_after is null,
    v_state::text
  );

  v_state := public.rispondi_rinnovo(v_rinnovo_accept, v_offerta_accettata, 3::smallint);

  select cr.stato, pi.ingaggio
  into v_stato, v_ingaggio
  from public.contract_renewals cr
  join public.player_instances pi on pi.id = cr.player_instance_id
  where cr.id = v_rinnovo_accept;

  insert into risultati_rinnovi_controproposta
  values (
    'offerta accettata',
    coalesce((v_state->>'accettato')::boolean, false)
      and v_stato = 'accettato'
      and v_ingaggio = v_offerta_accettata
      and (v_state->>'ingaggio')::bigint = v_offerta_accettata,
    v_state::text
  );
end $$;

select * from risultati_rinnovi_controproposta order by step;

rollback;
