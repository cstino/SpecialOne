-- ============================================================
--  PRIVILEGI DI SCRITTURA REVOCATI A `authenticated`
--
--  Supabase imposta ALTER DEFAULT PRIVILEGES in modo che ogni tabella creata
--  in `public` conceda automaticamente ALL a anon e authenticated. Le
--  migrazioni del progetto hanno sempre revocato ad anon, ma mai ad
--  authenticated: si e' contato sulla RLS, che in effetti blocca
--  INSERT/UPDATE/DELETE perche' nessuna tabella ha policy di scrittura.
--
--  Il buco e' TRUNCATE: **TRUNCATE non passa dalla RLS**. Un partecipante
--  autenticato con quel privilegio potrebbe svuotare una tabella intera
--  saltando ogni policy. Oggi non e' raggiungibile da PostgREST, che non
--  espone TRUNCATE, ma e' un privilegio che nessuno ha motivo di avere e la
--  sicurezza del progetto non deve dipendere da cosa PostgREST espone.
--
--  Nessun effetto sull'applicazione: si scrive solo tramite funzioni
--  SECURITY DEFINER (crea_lega, entra_in_lega, draft_pick, salva_formazione,
--  aggiorna_profilo_squadra, aggiorna_nome_allenatore, segna_notifiche_lette),
--  che girano come proprietario e non usano questi privilegi. Cambia solo il
--  messaggio d'errore di una scrittura diretta: da violazione di policy a
--  permesso negato.
--
--  Le tabelle create in 20260731121100 (fixtures, lineups, matches,
--  match_stats, seasons, standings, formation_xp, transactions) erano gia'
--  a solo SELECT: qui si allineano le altre.
-- ============================================================

revoke insert, update, delete, truncate, references, trigger on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.profiles,
  public.notifications
from authenticated;

-- Idempotente e difensivo: anon non deve avere nulla, su nessuna di queste.
revoke all on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.profiles,
  public.notifications
from anon;

-- La lettura resta quella che era: la RLS decide *quali* righe, il GRANT
-- decide *se* si puo' interrogare la tabella. Servono entrambi.
grant select on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.profiles,
  public.notifications
to authenticated;

-- ------------------------------------------------------------
--  E soprattutto: che non si ricrei da solo.
--
--  Senza questa riga ogni tabella futura ripartirebbe con ALL concesso, e le
--  prime tabelle nuove saranno quelle del mercato: proposte di scambio e
--  offerte a busta chiusa, cioe' esattamente i dati che i partecipanti hanno
--  interesse a manomettere. Meglio che nascano chiuse e che ogni GRANT sia
--  una scelta esplicita di chi scrive la migrazione.
-- ------------------------------------------------------------

alter default privileges in schema public revoke all on tables from anon, authenticated;
