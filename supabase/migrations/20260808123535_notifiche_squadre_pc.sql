-- Le squadre PC non hanno un account Auth e quindi non hanno un destinatario
-- per le notifiche personali. Le operazioni devono comunque concludersi.
create or replace function private.notifica(
  p_user_id uuid,
  p_league_id bigint,
  p_tipo text,
  p_titolo text,
  p_corpo text default null,
  p_dati jsonb default '{}'::jsonb
)
returns bigint
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_id bigint;
begin
  if p_user_id is null then
    return null;
  end if;

  insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
  values (
    p_user_id, p_league_id, p_tipo, btrim(p_titolo),
    nullif(btrim(coalesce(p_corpo, '')), ''), coalesce(p_dati, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.notifica(uuid,bigint,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function private.notifica(uuid,bigint,text,text,text,jsonb)
  to service_role;

comment on function private.notifica(uuid,bigint,text,text,text,jsonb) is
  'Inserisce una notifica per un utente umano; senza destinatario (squadra PC) non esegue scritture.';
