-- Rinnovi: la cifra offerta e accettata e' l'ingaggio annuo firmato.
-- La durata blocca quell'ingaggio per piu' stagioni, non lo maggiora.

update public.player_instances pi
set ingaggio = cr.offerta
from public.contract_renewals cr
where cr.player_instance_id = pi.id
  and cr.league_id = pi.league_id
  and cr.stato = 'accettato'
  and cr.offerta is not null
  and pi.team_id = cr.team_id
  and pi.ingaggio <> cr.offerta;

create or replace function public.rispondi_rinnovo(
  p_rinnovo_id bigint,
  p_offerta bigint,
  p_durata smallint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_rinnovo public.contract_renewals;
  v_offseason public.offseasons;
  v_richiesta bigint;
  v_accetta boolean := false;
  v_controproposta boolean := false;
  v_ingaggio bigint;
  v_nome text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per rispondere al rinnovo.';
  end if;
  if p_offerta < 500000 or p_offerta % 100000 <> 0 then
    raise exception using errcode = '22023', message = 'L''offerta deve essere almeno 0,5 M€ e a scatti di 0,1 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 anni.';
  end if;

  select * into v_rinnovo from public.contract_renewals where id = p_rinnovo_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Rinnovo non trovato.';
  end if;
  if not (select private.e_mia_squadra(v_rinnovo.team_id)) then
    raise exception using errcode = '42501', message = 'Questo rinnovo non appartiene alla tua squadra.';
  end if;
  if v_rinnovo.stato not in ('in_attesa', 'controproposta') then
    raise exception using errcode = '55000', message = 'Questo rinnovo è già stato risolto.';
  end if;

  select * into v_offseason from public.offseasons where id = v_rinnovo.offseason_id;
  if v_offseason.stato <> 'aperta' or now() >= v_offseason.scade_il then
    raise exception using errcode = '55000', message = 'La finestra dei rinnovi è terminata.';
  end if;

  select richiesta_esatta into v_richiesta
  from private.contract_renewal_terms
  where renewal_id = v_rinnovo.id;

  select p.nome into v_nome
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = v_rinnovo.player_instance_id;

  if p_offerta >= v_richiesta then
    v_accetta := true;
  elsif v_rinnovo.stato = 'in_attesa' then
    v_controproposta := true;
  end if;

  if v_accetta then
    v_ingaggio := p_offerta;
    update public.player_instances
    set ingaggio = v_ingaggio,
        contratto_scadenza = v_offseason.stagione_a + p_durata - 1
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'accettato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo accettato',
      v_nome || ' ha firmato per ' || p_durata || case when p_durata = 1 then ' anno.' else ' anni.' end,
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));

  elsif v_controproposta then
    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        richiesta_min = v_richiesta,
        richiesta_max = v_richiesta,
        stato = 'controproposta',
        risolta_il = null
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Controproposta rinnovo',
      v_nome || ' chiede l''ultima offerta prima di liberarsi.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id, 'richiesta', v_richiesta));

  else
    update public.player_instances
    set team_id = null
    where id = v_rinnovo.player_instance_id and team_id = v_rinnovo.team_id;

    update public.contract_renewals
    set offerta = p_offerta,
        durata = p_durata,
        stato = 'rifiutato',
        risolta_il = now()
    where id = v_rinnovo.id;

    perform private.notifica(v_user, v_rinnovo.league_id, 'sistema',
      'Rinnovo rifiutato',
      v_nome || ' non ha accettato l''ultima offerta ed è ora svincolato.',
      jsonb_build_object('player_instance_id', v_rinnovo.player_instance_id, 'rinnovo_id', v_rinnovo.id));
  end if;

  return jsonb_build_object(
    'id', v_rinnovo.id,
    'accettato', v_accetta,
    'controproposta', v_controproposta,
    'ingaggio', case when v_accetta then v_ingaggio else null end,
    'richiesta', case when v_controproposta then v_richiesta else null end
  );
end;
$$;

revoke all on function public.rispondi_rinnovo(bigint, bigint, smallint) from public, anon, authenticated;
grant execute on function public.rispondi_rinnovo(bigint, bigint, smallint) to authenticated;
