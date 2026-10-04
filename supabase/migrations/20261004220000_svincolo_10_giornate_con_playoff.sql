-- ============================================================
--  SVINCOLO: il blocco delle 10 giornate conta anche i playoff
--  Segnalazione di un utente, 4 ottobre 2026 (S. Ouaissa, Serie F)
--
--  Il blocco "arrivato da meno di 10 giornate" misura quanto tempo e' passato
--  fra giornata_acquisizione e la prossima giornata in programma. A stagione
--  finita non ce ne sono (off-season), e come tetto si usava giornate_totali + 1
--  (31): ma la stagione prosegue con i playoff, fino alla 35. Un giocatore
--  arrivato alla giornata 22 e che aveva giocato 13 giornate di fatto risultava
--  a 9 e non si poteva svincolare. Ora, senza partite in programma, il tetto e'
--  la giornata successiva all'ultima simulata della stagione corrente.
-- ============================================================

begin;

do $$
declare
  v_def text := pg_get_functiondef('public.svincola_giocatore_cassa_legacy(bigint)'::regprocedure);
  v_a text := 'coalesce(v_prossima, v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione';
  v_b text;
begin
  if position(v_a in v_def) = 0 then
    raise exception 'svincola_giocatore_cassa_legacy: riga del conteggio non trovata, controllare a mano.';
  end if;
  v_b := 'coalesce(v_prossima,' || E'\n'
    || '        (select max(f.giornata) + 1 from public.fixtures f' || E'\n'
    || '           join public.seasons s on s.id = f.season_id' || E'\n'
    || '          where s.league_id = v_lega.id and s.numero = v_lega.stagione_corrente and f.stato = ''simulata''),' || E'\n'
    || '        v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione';
  execute replace(v_def, v_a, v_b);
end;
$$;

commit;
