-- ============================================================
--  NOTIFICHE IN-APP
--
--  Serve al mercato: una proposta di scambio che scade in giornata e' inutile
--  se il destinatario non sa che esiste. La tabella nasce prima del mercato
--  proprio perche' e' il pezzo su cui il mercato scrive: farla dopo vorrebbe
--  dire tornare a modificare ogni RPC gia' scritta.
--
--  Le push del browser arriveranno sopra questa stessa tabella e non
--  richiederanno di rifarla: una push e' solo un secondo canale di consegna
--  per una riga che comunque deve esistere, altrimenti chi tocca la notifica
--  non atterra da nessuna parte.
-- ============================================================

create table public.notifications (
  id        bigint generated always as identity primary key,

  -- destinatario. Le notifiche sono per-utente e non per-squadra: la stessa
  -- persona puo' avere piu' squadre in piu' leghe e la campanella e' una sola.
  user_id   uuid not null references auth.users (id) on delete cascade,

  -- null = notifica di account, non legata a una lega (nessuna ancora, ma
  -- l'insolvenza di design §5.5 e i futuri avvisi di sistema lo saranno).
  league_id bigint references public.leagues (id) on delete cascade,

  tipo      text not null check (tipo in (
    -- gia' emesse
    'giornata_simulata',
    'formazione_mancante',
    -- riservate al mercato: elencate ora per non dover migrare la CHECK
    -- a ogni pezzo del mercato che entra
    'mercato_proposta',
    'mercato_esito',
    'mercato_asta',
    'sistema'
  )),

  titolo    text not null check (char_length(btrim(titolo)) between 1 and 80),
  corpo     text check (char_length(corpo) between 1 and 240),

  -- payload per il collegamento profondo: { "match_id": 12 } porta la
  -- notifica direttamente sul tabellino invece che sulla home della lega.
  dati      jsonb not null default '{}'::jsonb check (jsonb_typeof(dati) = 'object'),

  letta_il  timestamptz,
  creata_il timestamptz not null default now()
);

-- L'elenco: sempre filtrato per utente e ordinato dal piu' recente.
create index notifications_utente_idx
  on public.notifications (user_id, creata_il desc, id desc);

-- Il pallino sulla campanella: e' la query piu' frequente dell'app e va
-- servita da un indice parziale, non da una scansione dell'archivio.
create index notifications_non_lette_idx
  on public.notifications (user_id)
  where letta_il is null;

comment on table public.notifications is
  'Notifiche in-app per utente. Scritte solo da service_role e dalle RPC del mercato.';

-- ------------------------------------------------------------
--  RLS
-- ------------------------------------------------------------

alter table public.notifications enable row level security;

-- Si leggono solo le proprie. Non esiste una vista di lega: una notifica
-- riguarda una persona, e sapere cosa e' stato notificato a un avversario
-- rivelerebbe che ha ricevuto una proposta.
create policy notifications_lettura on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Nessuna policy di scrittura, coerentemente con helper_rls.sql: il browser
-- non inserisce e non aggiorna. Segnare come letta passa dalla RPC sotto.
grant select on table public.notifications to authenticated;
grant select, insert, update, delete on table public.notifications to service_role;
revoke all on table public.notifications from anon;

-- ------------------------------------------------------------
--  Scrittura dal database: la usano le RPC del mercato
--
--  Solo service_role puo' eseguirla direttamente. Le RPC del mercato sono
--  SECURITY DEFINER e girano come proprietario, che ha comunque l'EXECUTE:
--  cosi' possono notificare la controparte senza che un client autenticato
--  possa fabbricare notifiche a nome di qualcun altro.
-- ------------------------------------------------------------

create or replace function private.notifica(
  p_user_id   uuid,
  p_league_id bigint,
  p_tipo      text,
  p_titolo    text,
  p_corpo     text default null,
  p_dati      jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
  values (p_user_id, p_league_id, p_tipo, btrim(p_titolo),
          nullif(btrim(coalesce(p_corpo, '')), ''), coalesce(p_dati, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function private.notifica(uuid, bigint, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function private.notifica(uuid, bigint, text, text, text, jsonb)
  to service_role;

comment on function private.notifica(uuid, bigint, text, text, text, jsonb) is
  'Inserisce una notifica. Chiamata dalle RPC del mercato e dal backend notturno.';

-- ------------------------------------------------------------
--  Segnare come lette
--
--  Column-level grant non basta: con UPDATE su `letta_il` un utente potrebbe
--  comunque rimettere a null una notifica altrui se la policy sbagliasse.
--  Una RPC che filtra su auth.uid() e' piu' corta da verificare.
-- ------------------------------------------------------------

create or replace function public.segna_notifiche_lette(p_ids bigint[] default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_aggiornate integer;
begin
  if v_utente is null then
    raise exception using
      errcode = '42501',
      message = 'Devi accedere per leggere le notifiche.';
  end if;

  -- p_ids null = "segna tutte lette", il gesto normale quando si apre il
  -- pannello. Con un array, solo quelle indicate.
  update public.notifications
  set letta_il = now()
  where user_id = v_utente
    and letta_il is null
    and (p_ids is null or id = any(p_ids));

  get diagnostics v_aggiornate = row_count;
  return v_aggiornate;
end;
$$;

revoke all on function public.segna_notifiche_lette(bigint[]) from public, anon;
grant execute on function public.segna_notifiche_lette(bigint[]) to authenticated;

comment on function public.segna_notifiche_lette(bigint[]) is
  'Segna come lette le notifiche dell''utente corrente. Senza argomenti, tutte.';

-- ------------------------------------------------------------
--  Realtime
--
--  Senza, la campanella si aggiorna solo quando si ricarica la pagina. Con
--  la RLS attiva Realtime consegna a ciascuno solo le proprie righe.
--  Il blocco e' difensivo: su un database senza la publication di Supabase
--  la migrazione non deve fallire per questo.
-- ------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications;
  end if;
exception
  when duplicate_object then null;
end;
$$;
