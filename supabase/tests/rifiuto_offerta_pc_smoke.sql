begin;

do $$
declare
  v_proposta public.trade_proposals;
  v_proposta_id bigint;
  v_user uuid;
  v_esito public.trade_proposals;
  v_notifiche_prima bigint;
  v_notifiche_dopo bigint;
begin
  select tp.id, destinataria.user_id
  into v_proposta_id, v_user
  from public.trade_proposals tp
  join public.teams mittente on mittente.id = tp.da_team_id
  join public.teams destinataria on destinataria.id = tp.a_team_id
  where mittente.controllata_da_pc
    and not destinataria.controllata_da_pc
    and destinataria.user_id is not null
    and tp.stato = 'in_attesa'
  order by tp.id desc
  limit 1;

  if v_proposta_id is null then
    raise exception 'Smoke test: nessuna proposta PC in attesa disponibile.';
  end if;
  select * into v_proposta from public.trade_proposals where id = v_proposta_id;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );
  select count(*) into v_notifiche_prima from public.notifications;

  v_esito := public.rispondi_a_proposta(v_proposta.id, false);
  if v_esito.stato <> 'rifiutata' or v_esito.risolta_il is null then
    raise exception 'Smoke test: la proposta PC non e stata rifiutata correttamente.';
  end if;

  select count(*) into v_notifiche_dopo from public.notifications;
  if v_notifiche_dopo <> v_notifiche_prima then
    raise exception 'Smoke test: e stata creata una notifica senza destinatario.';
  end if;
end;
$$;

rollback;
