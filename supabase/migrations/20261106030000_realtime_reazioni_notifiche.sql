-- Tempo reale di nuovo acceso per reazioni e notifiche (segnalato il 6/11/2026: nel sorteggio delle conference ognuno
-- vedeva solo le proprie reazioni). Col passaggio del database sul Mac (12/10/2026) la publication supabase_realtime e'
-- arrivata vuota: le migrazioni 20260802120000 e 20261006170000 ci avevano aggiunto notifications e reazioni_live, ma
-- l'elenco delle tabelle non e' passato. L'app ascolta solo queste due (postgres_changes in lib/reazioni.ts e
-- lib/notifiche.ts); chi legge cosa resta deciso dalla RLS.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reazioni_live') then
      alter publication supabase_realtime add table public.reazioni_live;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
      alter publication supabase_realtime add table public.notifications;
    end if;
  end if;
end $$;
