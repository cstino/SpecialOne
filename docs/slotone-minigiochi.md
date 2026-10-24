# SlotOne — minigiochi (24 ottobre 2026)

Richiesta del committente: aggiungere alla slot due minigiochi "come nelle slot moderne".
Scelte: due simboli nuovi, un minigioco ogni circa 100 giri (insieme), premio massimo 500× la puntata.

## Regole

Due simboli nuovi sui rulli, che non pagano sulle linee e le interrompono (come coppa e bustina):

| Simbolo | Id | Con 3 o più ovunque sui rulli |
|---|---|---|
| Pallone | 11 | **Calcio di rigore** |
| Stemma d'oro | 12 | **Scegli lo stemma** |

**Scegli lo stemma.** 9 scudi coperti, se ne scoprono 3, il premio è la **somma** dei valori per la puntata (tetto 500×).
Valori 1, 2, 3, 5, 10, 25, 100, 250 con pesi 38, 30, 15, 8, 5, 3, 0,8, 0,15. Valore atteso **12,77×**.

**Calcio di rigore.** Fino a 5 rigori, il primo parato chiude il bonus. Probabilità di gol 78%, 68%, 58%, 48%, 38%.
Premio per 0, 1, 2, 3, 4, 5 gol segnati: 1, 2, 4, 8, 25, 120 × la puntata. Valore atteso **11,91×**.

Con 4 o 5 simboli il bonus è lo stesso (non ci sono varianti per il numero di simboli). Nei giri gratis i bonus scattano
lo stesso e pagano la puntata normale: il ×2 dei giri gratis non si applica al minigioco. Se scattano insieme (probabilità
trascurabile) si giocano uno dopo l'altro.

## Matematica

Per tenere il ritorno al 97% **in crediti** (le bustine gratis dell'album restano fuori dal conto, come prima):

* pesi dei simboli moltiplicati per 10: `900,900,900,700,700,700,400,400,300,200,220` più `159,159` (pallone e stemma d'oro).
  Ogni minigioco parte con probabilità 0,504% per giro (circa 1 su 198); insieme circa 1 giro su 100;
* scala dei pagamenti **1,0947** (prima 1,033), senza album 1,0537 (prima 1,024);
* ripartizione del ritorno: linee 68,7% + coppe 2,5% + minigiochi 13,5% (giri gratis compresi) = 97,0%.

**Correzione importante rispetto a prima.** La slot *prima* dei minigiochi restituiva circa il **95,9%** in crediti, non il
97% annunciato il 20/10 (modello esatto 95,96%, simulazione di 3 milioni di giri 95,81%). Con i minigiochi è al 97%.
Il vecchio 97% contava probabilmente anche il valore delle bustine: non si sa; da qui in avanti il numero è in crediti.

Verifiche (tutte in `tools/casino/`):
* modello esatto (le 15 caselle sono indipendenti): `python3 tools/casino/calibra_slotone.py`;
* simulazione di 4.000.000 di giri con i minigiochi: ritorno **97,13%** (modello 97,00%), un minigioco ogni 200 giri
  ciascuno; `docker exec -i supabase-db psql -U postgres -At < tools/casino/simula_slotone.sql`;
* prova con 6.000 giri veri in transazione annullata (giri, minigiochi giocati fino in fondo): i crediti tornano
  al centesimo (variazione del saldo = vincite meno puntate).

## Dove sta il codice

* `supabase/migrations/20261024140000_slotone_minigiochi.sql` — tabella `casino_slot_bonus` (con il segreto, nessuna policy:
  si legge solo con le funzioni), estrazione dei bonus, premi, chiusura, cron `casino_slot_bonus` ogni minuto,
  `casino_slot_bonus_stato` e `casino_slot_bonus_gioca`.
* `supabase/migrations/20261024141000_slotone_minigiochi_giro.sql` — `casino_gira` (pesi, scala, creazione dei bonus, blocco
  del giro con un bonus aperto) e `casino_stato` (`bonus_aperto`).
* `src/components/SlotBonus.tsx` (finestra dei due minigiochi, caricata solo quando serve), `SimboliBonus.tsx` (disegni),
  `Casino.tsx` (rulli, ripresa di un bonus lasciato a metà), stili in `src/styles.css` (blocchi `.sb-`, `.sbr__`).

Il server decide tutto prima: all'accensione estrae i 9 valori (o i 5 esiti dei rigori) e li tiene segreti; l'app disegna
quello che il server rivela mossa dopo mossa. Il portiere si tuffa dalla parte opposta del tiro se è gol, dalla stessa se è
parata: è solo scena, l'esito è già deciso.

**Pagamento.** I crediti arrivano a fine minigioco; la vincita del giro (`casino_giri.vinto`, quindi classifiche e "miglior
colpo") comprende anche il minigioco. Se uno se ne va, dopo **3 minuti** il server gioca da solo le mosse rimaste a caso e
paga (cron o primo accesso). Con un minigioco aperto non si può girare. Colpo grosso ≥ 100× la puntata: post su SocialOne,
una sola volta per giro.

## Se si vuole cambiare

Prezzi e probabilità vivono in tre posti da tenere allineati: `casino_bonus_crea` e `casino_bonus_molt` (premi),
`casino_gira` (pesi e scala), `tools/casino/*` (taratura). Dopo ogni modifica rifare `calibra_slotone.py`,
la simulazione, e aggiornare `PESI`/`SCALA_*` in `Casino.tsx` e la scala dei premi in `SlotBonus.tsx`.
