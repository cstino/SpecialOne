-- ============================================================
--  RINNOVO: il gradino che il giocatore CHIEDE lo accetta sempre
--  Segnalazione di un utente, 4 ottobre 2026 (D. Léon, Serie F)
--
--  Il giocatore apriva la trattativa scrivendo "vorrei lo spazio di uno
--  sporadico", ma poi rifiutava proprio lo sporadico perche' "e' tra i
--  migliori della rosa". Le due regole si contraddicevano: la richiesta si
--  misura sulla LEGA (private.gradino_richiesto), il rifiuto sulla ROSA. Il
--  confronto con la rosa vale solo per un gradino SOTTO la sua richiesta: se
--  gli dai quello che chiede, o di piu', accetta. Resta il rifiuto della
--  promessa futura sopra i 21 anni e quello di due gradini sotto la richiesta.
-- ============================================================

begin;

create or replace function private.gradino_rifiutato(p_gradino text, p_richiesto text, p_eta smallint, p_overall smallint, p_media_rosa numeric)
returns text
language sql
immutable parallel safe
set search_path = ''
as $$
  select case
    when p_gradino = 'promessa' and p_eta >= 21 then 'Ha già compiuto 21 anni: non è più una promessa.'
    when private.livello_gradino(p_richiesto) - private.livello_gradino(p_gradino) >= 2 then 'Chiede molto più spazio: così non firma.'
    when private.livello_gradino(p_gradino) < private.livello_gradino(p_richiesto)
         and p_gradino = 'sporadico' and p_overall - coalesce(p_media_rosa, p_overall) >= 3 then 'È tra i migliori della rosa: non accetta di giocare così poco.'
    when private.livello_gradino(p_gradino) < private.livello_gradino(p_richiesto)
         and p_gradino = 'turnover' and p_overall - coalesce(p_media_rosa, p_overall) >= 6 then 'È uno dei leader della squadra: vuole il posto da titolare.'
    else null
  end;
$$;

revoke all on function private.gradino_rifiutato(text, text, smallint, smallint, numeric) from public, anon, authenticated;

commit;
