-- ============================================================
--  COMPLETAMENTO DELLA CHIUSURA DEI PRIVILEGI
--
--  La migrazione precedente elencava le tabelle a mano e ne ha mancate tre:
--  `draft_state`, `draft_picks` e `draft_team_state`, nate dopo
--  20260731120700_privilegi_data_api.sql e mai coperte da nessun revoke.
--
--  Su `draft_team_state` i privilegi pieni erano concessi anche ad **anon**,
--  cioe' alla chiave pubblicabile che viaggia dentro il bundle del frontend.
--  Nulla trapelava davvero — la RLS e' attiva su tutte e 15 le tabelle di
--  `public`, verificato, e nessuna policy si applica ad anon — ma TRUNCATE
--  non passa dalla RLS e non deve essere concesso a nessuno dei due ruoli.
--
--  Qui l'elenco non si scrive: si itera. Un elenco a mano ha gia' sbagliato
--  una volta, e la prossima tabella dimenticata sarebbe una del mercato.
-- ============================================================

do $$
declare
  v_tabella record;
begin
  for v_tabella in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
    order by c.relname
  loop
    -- Prima si toglie tutto a entrambi i ruoli...
    execute format('revoke all on table public.%I from anon, authenticated', v_tabella.relname);
    -- ...poi si restituisce la sola lettura a chi ha fatto l'accesso.
    -- Quali righe vedra' lo decide la RLS: il GRANT dice solo che puo'
    -- interrogare la tabella, e servono entrambi i livelli.
    execute format('grant select on table public.%I to authenticated', v_tabella.relname);
  end loop;
end;
$$;

-- service_role non viene toccato: e' il ruolo del backend notturno, deve
-- continuare a leggere e scrivere, e non raggiunge mai il browser.
