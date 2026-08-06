-- ============================================================
--  NOTIFICHE PUSH DEL BROWSER
--
--  Richiesta dell'utente. Secondo canale di consegna per una riga che deve
--  comunque esistere in public.notifications (commento gia' presente in
--  20260802120000_notifiche.sql, che anticipava esattamente questo): non si
--  tocca la tabella notifications, si aggiunge solo la sottoscrizione e un
--  trigger che, a ogni riga inserita, chiama una Edge Function via pg_net —
--  stesso schema gia' in uso per il cron notturno (private.notifica() resta
--  l'unico punto di scrittura, quindi ogni RPC che gia' notifica in-app
--  ottiene la push gratis, senza toccare i chiamanti).
--
--  Le chiavi VAPID (coppia di firma) stanno nei secret della Edge Function,
--  non nel database: la privata non deve mai essere leggibile da SQL.
-- ============================================================

create table public.push_subscriptions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,

  -- L'endpoint identifica univocamente il dispositivo/browser presso il
  -- push service (Google, Mozilla, Apple...): stesso utente su piu'
  -- dispositivi ha piu' righe, e ri-sottoscriversi sullo stesso browser
  -- aggiorna la riga invece di duplicarla.
  endpoint   text not null unique,
  p256dh     text not null,
  auth_key   text not null,
  user_agent text,
  creata_il  timestamptz not null default now(),

  check (char_length(endpoint) between 1 and 500)
);

create index push_subscriptions_utente_idx on public.push_subscriptions (user_id);

comment on table public.push_subscriptions is
  'Sottoscrizioni Web Push per utente/dispositivo. Scritte dal browser stesso: a differenza di notifications, qui e'' l''utente ad autogestire le proprie righe.';

alter table public.push_subscriptions enable row level security;

-- A differenza di notifications, qui e' il browser a scrivere: la
-- sottoscrizione nasce lato client (pushManager.subscribe) e va salvata da
-- li'. Un utente vede/gestisce solo le proprie.
create policy push_subscriptions_proprie on public.push_subscriptions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on table public.push_subscriptions to authenticated;
grant select, insert, update, delete on table public.push_subscriptions to service_role;
revoke all on table public.push_subscriptions from anon;

-- ------------------------------------------------------------
--  Trigger: ogni notifica in-app prova anche a diventare una push.
--  Fire-and-forget: pg_net e' asincrono, un push service lento o
--  irraggiungibile non deve mai rallentare o far fallire l'insert su
--  notifications (quella riga e' la fonte di verita', la push e' un extra).
-- ------------------------------------------------------------

create or replace function private.notifica_invia_push()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_chiave text;
begin
  select decrypted_secret into v_chiave
  from vault.decrypted_secrets
  where name = 'chiave_simulazione';

  if v_chiave is null then
    return new;
  end if;

  -- Il progetto e' hhvyyjpbsgjcaaaizgwb: se cambia, cambia anche questo URL
  -- (stessa nota gia' presente per il cron in 20260801203000).
  perform net.http_post(
    url     := 'https://hhvyyjpbsgjcaaaizgwb.supabase.co/functions/v1/invia-push',
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
$$;

create trigger notifications_invia_push
  after insert on public.notifications
  for each row execute function private.notifica_invia_push();

comment on function private.notifica_invia_push() is
  'Trigger su notifications: avvisa la Edge Function invia-push (fire-and-forget via pg_net). Non fa mai fallire l''insert.';
