-- ============================================================
--  ANNUNCIO DELL'ADMIN A TUTTA LA LEGA
--
--  Richiesto dall'utente: un campo testo nel pannello admin che, inviato,
--  manda una notifica (in-app + push, il canale push e' gia' agganciato
--  con un trigger AFTER INSERT su public.notifications, migrazione
--  20260808090000) a tutti i partecipanti della lega. Tocca 'sistema',
--  gia' previsto dalla CHECK di notifications.tipo — nessuna migrazione
--  di schema necessaria oltre a questa RPC.
--
--  Stesso controllo admin gia' in uso per elimina_lega (confronto diretto
--  con leagues.admin_id, non private.e_admin() — quest'ultima e' pensata
--  per le policy RLS, non per le RPC).
-- ============================================================

create or replace function public.invia_annuncio_lega(p_league_id bigint, p_messaggio text)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_messaggio text;
  v_inviate integer := 0;
  v_team record;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per inviare un annuncio.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.admin_id <> v_user_id then
    raise exception using errcode = '42501', message = 'Solo l''amministratore può inviare un annuncio alla lega.';
  end if;

  v_messaggio := btrim(coalesce(p_messaggio, ''));
  if v_messaggio = '' then
    raise exception using errcode = '22023', message = 'Il messaggio non può essere vuoto.';
  end if;
  if char_length(v_messaggio) > 240 then
    raise exception using errcode = '22023', message = 'Il messaggio è troppo lungo (massimo 240 caratteri).';
  end if;

  for v_team in
    select distinct t.user_id
    from public.teams t
    where t.league_id = p_league_id and t.attiva
  loop
    perform private.notifica(v_team.user_id, p_league_id, 'sistema', 'Messaggio dall''admin', v_messaggio, '{}'::jsonb);
    v_inviate := v_inviate + 1;
  end loop;

  return v_inviate;
end;
$$;

revoke all on function public.invia_annuncio_lega(bigint, text) from public, anon;
grant execute on function public.invia_annuncio_lega(bigint, text) to authenticated;
