-- ============================================================
--  ELIMINAZIONE LEGA — riservata all'amministratore
--
--  Richiesta dell'utente, 5 agosto 2026: dal pannello admin, un modo per
--  cancellare definitivamente la lega. Irreversibile e a impatto su TUTTI i
--  partecipanti, non solo sull'admin: la conferma richiesta è più severa di
--  un semplice "sei sicuro?" — il chiamante deve ripetere il nome esatto
--  della lega, stesso pattern di sicurezza usato altrove per le cancellazioni
--  irreversibili (es. repository su GitHub). Un doppio clic distratto non
--  basta a cancellare la lega di sette persone.
--
--  Verificato che ogni tabella con league_id abbia ON DELETE CASCADE:
--  bastava eliminare la riga in leagues e lasciare fare al database.
--
--  Corretto anche un difetto trovato durante questa verifica, non causato da
--  questa modifica: season_morale_checkpoints (20260805150000) non aveva
--  ALCUNA foreign key, ne' su season_id ne' su league_id — a differenza di
--  season_progression_checkpoints, che le ha entrambe ON DELETE CASCADE. Non
--  bloccava l'eliminazione (senza FK non c'e' nulla da controllare), ma
--  avrebbe lasciato righe orfane per sempre. Corretto qui perche' e' lo
--  stesso posto dove si verificano tutte le cascade della lega.
-- ============================================================

alter table public.season_morale_checkpoints
  add constraint season_morale_checkpoints_league_fk
    foreign key (league_id) references public.leagues(id) on delete cascade,
  add constraint season_morale_checkpoints_season_fk
    foreign key (season_id) references public.seasons(id) on delete cascade;

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

  -- Una sola delete: tutte le tabelle figlie hanno league_id con ON DELETE
  -- CASCADE (squadre, rose, calendario, stagioni, mercato, notifiche...).
  delete from public.leagues where id = p_league_id;
end;
$$;

revoke all on function public.elimina_lega(bigint, text) from public, anon;
grant execute on function public.elimina_lega(bigint, text) to authenticated;

comment on function public.elimina_lega(bigint, text) is
  'Elimina definitivamente una lega e tutti i suoi dati (cascade). Solo l''admin, e solo ripetendo il nome esatto della lega.';
