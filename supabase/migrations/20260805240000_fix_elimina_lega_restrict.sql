-- ============================================================
--  FIX: elimina_lega falliva sempre — due FK RESTRICT non coperte da cascade
--
--  Verificato con un test reale (rollback su lega 29): la delete falliva su
--  "transactions_team_league_fk". Cercando sistematicamente ogni foreign key
--  NON cascade che punta a una tabella per-lega, ne sono emerse due, entrambe
--  volute (CLAUDE.md: "Registro append-only dei movimenti economici nella
--  tabella transactions. Non è opzionale"):
--
--    match_stats.player_instance_id -> player_instances  ON DELETE RESTRICT
--    transactions.team_id           -> teams              ON DELETE RESTRICT
--
--  Impediscono di cancellare un giocatore o una squadra SINGOLARMENTE
--  mentre esiste ancora storico economico o statistico — è la protezione
--  giusta per l'uso normale dell'app. Ma bloccano anche una cancellazione
--  totale e deliberata della lega, perché né transactions né match_stats
--  hanno una propria cascade diretta da leagues (transactions non ha
--  nemmeno una FK su league_id, solo la colonna).
--
--  Soluzione: dentro elimina_lega, svuotare esplicitamente le due tabelle
--  per quella lega PRIMA di cancellare la lega, invece di allentare il
--  vincolo RESTRICT (che resta a protezione di tutti gli altri percorsi).
-- ============================================================

create or replace function public.elimina_lega(
  p_league_id bigint,
  p_conferma_nome text
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di eliminare una lega.';
  end if;

  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_user_id then
    raise exception using errcode = '42501', message = 'Solo l''amministratore può eliminare la lega.';
  end if;
  if p_conferma_nome is null or trim(p_conferma_nome) <> v_league.nome then
    raise exception using errcode = '22023', message = 'Il nome digitato non corrisponde a quello della lega.';
  end if;

  -- Le due tabelle con vincolo RESTRICT (protezione voluta per l'uso
  -- normale) vanno svuotate a mano prima della cascade generale.
  delete from public.match_stats where league_id = p_league_id;
  delete from public.transactions where league_id = p_league_id;

  -- Tutto il resto ha league_id con ON DELETE CASCADE: una sola delete basta
  -- (squadre, rose, calendario, stagioni, mercato, notifiche, morale...).
  delete from public.leagues where id = p_league_id;
end;
$$;
