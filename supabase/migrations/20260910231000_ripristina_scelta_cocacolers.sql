-- ============================================================
--  RIPRISTINO DELLA SCELTA PERSA DAI COCACOLERS (LegaBot, OFF-Season 3)
--
--  Riparazione dei dati rovinati dal difetto corretto nel file precedente:
--  la finestra si e' aperta e chiusa in due minuti, e l'unica squadra umana
--  della lega e' rimasta con la 6a scelta in stato 'vuota' e zero
--  preferenze. Le sette squadre PC avevano gia' ricevuto il loro giocatore.
--
--  Cosa si fa, e perche' e' sicuro:
--    - la scelta dei Cocacolers torna 'determinata', com'era prima della
--      risoluzione. Non aveva player_instance_id (era 'vuota'), quindi non
--      c'e' nessuna assegnazione da annullare;
--    - la finestra torna aperta con scadenza fra 48 ore, il tempo di
--      comporre la lista. Il promemoria a 24 ore scattera' da solo;
--    - le sette scelte gia' assegnate NON vengono toccate:
--      risolvi_finestra_scelte lavora solo sulle scelte 'determinata',
--      quindi alla prossima risoluzione le ignorera'. I loro giocatori
--      restano dove sono.
--
--  Verificato prima di scrivere: il pool della finestra ha ancora 23
--  giocatori, di cui 16 liberi (i 7 presi sono esclusi in automatico dal
--  controllo su player_instances gia' presente in risolvi_finestra_scelte).
--
--  Solo LegaBot, che e' la lega di test dove il difetto si e' manifestato.
--  Nessun'altra lega ha finestre arretrate.
-- ============================================================

begin;

-- La scelta torna disponibile. Condizione stretta: solo quella riga, solo
-- se e' ancora nello stato prodotto dal difetto.
update public.scelte_draft
set stato = 'determinata', aggiornata_il = now()
where league_id = 62
  and stagione = 3
  and finestra = 'off'
  and stato = 'vuota'
  and player_instance_id is null;

-- La finestra si riapre con 48 ore di tempo.
update public.finestre_scelte
set risolta_il = null,
    estrazione_il = now() + interval '48 hours'
where league_id = 62 and stagione = 3 and finestra = 'off';

commit;
