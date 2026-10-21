-- Notifiche push spegnibili lega per lega (richiesta del committente: nessuna push da LegaBot, solo dalla Serie F).
-- Con teams.notifiche_push = false la notifica resta nell'app (campanella) ma non arriva sul telefono.
alter table public.teams add column if not exists notifiche_push boolean not null default true;
update public.teams set notifiche_push = false where id = 260;   -- Cocacolers, la squadra del committente in LegaBot
CREATE OR REPLACE FUNCTION private.notifica_invia_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chiave text;
begin
  -- Notifiche push spente per questa lega (teams.notifiche_push = false): resta solo la notifica nell'app.
  if new.league_id is not null and exists (select 1 from public.teams t where t.league_id = new.league_id and t.user_id = new.user_id and not t.notifiche_push) then
    return new;
  end if;

  select decrypted_secret into v_chiave
  from vault.decrypted_secrets
  where name = 'chiave_simulazione';

  if v_chiave is null then
    return new;
  end if;

  -- Il progetto e' hhvyyjpbsgjcaaaizgwb: se cambia, cambia anche questo URL
  -- (stessa nota gia' presente per il cron in 20260801203000).
  perform net.http_post(
    url     := 'http://api-gw:8000/functions/v1/invia-push',
    body    := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_chiave
    ),
    timeout_milliseconds := 15000
  );

  return new;
exception
  -- Difensivo per lo stesso motivo del blocco Realtime in 20260802120000:
  -- una notifica in-app deve scriversi sempre, anche se pg_net non e'
  -- disponibile in un ambiente di test.
  when others then
    return new;
end;
$function$;
