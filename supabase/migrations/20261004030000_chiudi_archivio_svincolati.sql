-- ============================================================
--  MERCATO SVINCOLATI: CHIUSO L'ARCHIVIO
--  Deciso dal committente il 4 ottobre 2026: il pool delle squadre e' solo
--  l'estrazione del giorno (1 per ruolo) piu' gli svincolati dalle squadre.
--  offri_per_svincolato_archivio permetteva di offrire su qualunque giocatore
--  libero della lega, o di riaprire un'asta andata deserta ("Rioffri"):
--  ora rifiuta sempre. La firma resta per non rompere client vecchi.
-- ============================================================

create or replace function public.offri_per_svincolato_archivio(p_league_id bigint, p_player_id bigint, p_ingaggio bigint)
returns public.free_agent_bids
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception using errcode = '55000',
    message = 'Si puo'' offrire solo sugli svincolati del giorno e su quelli svincolati dalle squadre.';
end;
$$;
