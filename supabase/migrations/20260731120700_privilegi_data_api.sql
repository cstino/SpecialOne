-- ============================================================
--  PRIVILEGI DATA API
--
--  Dal 30 maggio 2026 i nuovi progetti Supabase non espongono piu'
--  automaticamente le tabelle create via SQL. RLS e privilegi sono due
--  livelli distinti: senza questi GRANT le policy di lettura non vengono
--  nemmeno raggiunte.
-- ============================================================

-- Il client autenticato legge solo le tabelle coperte dalle policy RLS.
-- Tutte le scritture applicative passeranno da RPC validate, aggiunte nei
-- rispettivi task; per ora non concediamo INSERT/UPDATE/DELETE al browser.
grant select on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.draft_state,
  public.draft_picks
to authenticated;

-- Il backend notturno usa service_role e deve poter leggere e scrivere.
grant select, insert, update, delete on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.draft_state,
  public.draft_picks
to service_role;

grant usage, select on all sequences in schema public to service_role;

-- Il progetto non espone dati senza autenticazione.
revoke all on table
  public.players,
  public.leagues,
  public.teams,
  public.player_instances,
  public.draft_state,
  public.draft_picks
from anon;
