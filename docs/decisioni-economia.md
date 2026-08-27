# Decisioni — Economia a tetto salariale

Riprogettazione dell'economia decisa il 26 agosto 2026, dopo l'analisi finanziaria
di Real Fampionato (9 squadre su 12 non in grado di coprire gli ingaggi della
stagione 2, 39 giocatori in procinto di essere svincolati d'ufficio).

Questo file è **vincolante** quanto `CLAUDE.md`. Dove contraddice `docs/design.md`,
vince questo file: è più recente.

**Stato: approvato, non ancora implementato.**

---

## 0. Perché il modello a cassa è fallito

Non è stato un bug isolato, erano tre difetti che si sommavano.

**Lo sfasamento di un anno.** Gli stipendi si pagano a rate per giornata
(`20260806190000_ingaggi_a_rate.sql`) e i premi partita si incassano giornata per
giornata (`20260806184515_premi_partita_per_giornata.sql`). Ma il controllo di
insolvenza a inizio stagione pretende l'intero monte ingaggi annuo **in cassa**.
Risultato: le entrate della stagione N possono finanziare solo gli ingaggi della
stagione N+1. Una squadra con flusso di cassa perfettamente sano risulta insolvente.

**Il rinnovo non costava nulla al momento della firma.** Le 141 transazioni
`rinnovo_in_stagione` del 25 agosto hanno quasi tutte `importo = 0`: impegnavano
stipendi per anni senza muovere un euro subito. Nessuna interfaccia poteva mostrare
il costo, perché contabilmente non c'era.

**Il freno progettato non è mai stato costruito.** La tassa anti-spirale di
design §5.6 non è implementata: `grep -r tassa supabase/migrations/` non trova nulla.

Il tetto di sostenibilità del 26 agosto (`20260826180000`, `20260826240000`) è una
patch corretta ma tardiva: arriva dopo l'ondata di rinnovi e per costruzione non
tocca chi è già oltre (`if p_delta_ingaggio <= 0 then return`).

---

## 1. La decisione

L'economia passa da un modello **a cassa** (un portafoglio che si riempie e si
svuota) a un modello **a tetto salariale fisso**.

> **Invariante unico:** per ogni squadra e per ogni stagione,
> la somma degli ingaggi attivi non supera il tetto.
>
> ```
> Σ ingaggi ≤ tetto
> ```

Il tetto è **identico per tutte le squadre** e **non cambia mai**: né tra stagioni,
né in base ai risultati.

### Non esistono entrate

Spariscono sponsor, premi partita, premio classifica, premio di partecipazione,
dotazione iniziale. Non c'è denaro che entra, quindi non c'è denaro che si accumula.

### Non esiste cassa

Il `budget` come portafoglio non serve più. Non si "paga" un ingaggio: lo si
**occupa**. Uno stipendio è spazio impegnato sotto il tetto, non una spesa.

### Vincere non dà nulla di economico

Il premio è **solo sportivo**. Questo elimina alla radice la spirale
ricchi-più-ricchi che design §5.6 cercava di contenere con una tassa.

> Se in futuro si vorrà premiare la vittoria, la ricompensa dovrà essere
> **non monetaria** (ordine di scelta al draft, reroll aggiuntivi, precedenza
> sugli svincolati). Il tetto deve restare uguale per tutti: alterarlo
> reintrodurrebbe esattamente il problema che questo documento chiude.

---

## 2. Contratti annuali

**I contratti durano una stagione. Il rinnovo estende di un anno, mai di più.**

È la scelta che rende il controllo *esatto* invece che *prudenziale*: al momento
del rinnovo il sistema conosce già tetto e stipendi della stagione successiva, e
può rispondere sì o no senza stimare nulla.

```
al rinnovo:
    Σ ingaggi che coprono la prossima stagione  +  nuovo ingaggio  ≤  tetto
    altrimenti rifiuta
```

Niente casi peggiori, niente entrate garantite da indovinare, niente proiezioni.
La funzione `private.entrata_minima_garantita` diventa inutile e va rimossa.

### Conseguenza accettata

Ogni off-season si rinegozia **l'intera rosa**. È una scelta consapevole: costa
ripetitività (25 decisioni a squadra ogni stagione) e toglie il gioco di prospettiva
del contratto lungo firmato prima che il giovane cresca. In cambio l'insolvenza
diventa impossibile per costruzione, non per controllo.

### Lo svincolo libera lo spazio, senza penalità

Non serve alcun *dead cap*. La penalità per il taglio esisterebbe solo per impedire
di firmare lungo e tagliare a piacere: con contratti annuali quell'impegno non
esiste, quindi non c'è nulla da penalizzare.

Spariscono `svincolo_buonuscita` e `svincolo_ingaggio_residuo`.

---

## 3. Effetto sui singoli sottosistemi

| Sottosistema | Prima | Dopo |
|---|---|---|
| **Draft** | ogni pick scala cassa; tetto all'80% del budget (design §4.4) | il pick occupa solo spazio salariale; il vincolo di solvibilità **resta** ma diventa `Σ ingaggi ≤ tetto` |
| **Aste svincolati** | offerta = ingaggio, con cassa impegnata a garanzia | offerta = ingaggio; l'unico vincolo è la capienza sotto il tetto |
| **Scambi** | muovono contanti (visto a registro: `mercato_scambio` ±8.89 M€) | scambio di **spazio salariale**: cedi 8 M€ di ingaggio e ne prendi 5, liberi 3 di capienza |
| **Rinnovi** | durata 1–5 anni, costo immediato zero | durata fissa 1 anno, verificati sul tetto della stagione entrante |
| **Svincolo** | costava buonuscita + ingaggio residuo | libera lo spazio, nessun costo |
| **Insolvenza** (§5.5) | svincolo forzato dagli ingaggi più alti | **eliminata**: non può verificarsi |
| **Tassa anti-spirale** (§5.6) | mai implementata | **non serve più** |

---

## 4. Cosa viene rimosso

Questa riprogettazione **toglie più codice di quanto ne aggiunga**.

- `teams.budget` e `teams.budget_ingaggi_riservato`
- pagamento rateale degli stipendi: `private.pagamenti_ingaggi_giornata`,
  `private.quota_ingaggio_giornata`, `private.ingaggio_residuo_stagione`
  (2.417 transazioni `stipendio_giornata` in una sola stagione)
- accredito dei premi: `private.premi_partita_giornata`,
  `private.accredita_premi_partite_giornata`, il trigger
  `fixtures_paga_premi_giornata` e il trigger correttivo
  `transactions_annulla_premio_partite_stagionale`
- `private.entrata_minima_garantita`, `private.monte_ingaggi_prossima_stagione`,
  `private.verifica_sostenibilita`, `private.budget_impegnato`
- il loop di insolvenza dentro `finalizza_offseason`
- la proiezione finanziaria della pagina Finanza

### Il registro `transactions` resta

`CLAUDE.md` §6 lo impone e la ragione vale ancora: senza, il primo bug di capienza
è indiagnosticabile. Cambia solo cosa registra — non più movimenti di denaro ma
**movimenti di spazio salariale** (ingaggio occupato, liberato, rinegoziato).
Resta append-only.

---

## 5. Cosa sopravvive di `design.md` §5

- **§5.1 Scala ingaggi** — invariata. Gli ingaggi restano euro interi, multipli di
  100.000, con floor a 500.000.
- **§5.2 Entrate** — eliminata.
- **§5.3 Bilancio strutturale** — eliminata.
- **§5.4 Pagamento ingaggi** — eliminata (non si paga, si occupa).
- **§5.5 Insolvenza** — eliminata.
- **§5.6 Anti-spirale** — eliminata (mai implementata).

La trappola di `CLAUDE.md` §7 — *«i 100 M€ iniziali sono una dotazione una tantum,
se li ricarichi ogni stagione il denaro smette di essere una risorsa entro la
stagione 3»* — **non si applica** a questo modello e va riscritta. Quella trappola
descriveva una dotazione ricorrente **sommata alle entrate**, che genera inflazione
perché il denaro si accumula. Un tetto fisso non si accumula: non è un portafoglio,
è un limite. Senza stock non c'è inflazione.

---

## 6. Il valore del tetto

Impostato dall'admin alla creazione della lega, **da tarare** al prossimo campionato.

Riferimenti utili:

- pavimento tecnico: 25 slot × 500.000 = **12,5 M€**
- il vecchio `budget_iniziale` di Real Fampionato era 70 M€ → media 2,8 M€ per
  giocatore su 25 slot
- monti ingaggi reali a fine stagione 1: da 19 M€ (Giampiero) a 99 M€ (Regginho FC)

Un tetto **troppo alto** rende il vincolo inerte e il gioco torna a essere "prendi i
migliori". Un tetto **troppo basso** costringe a rose di riserve. Il numero va scelto
guardando la distribuzione degli ingaggi del dataset, non a intuito.

---

## 7. Punti aperti

1. **Il valore del tetto** (§6) — da decidere alla creazione della nuova lega.
2. **Migrazione delle leghe esistenti.** Il modello nasce per un campionato nuovo.
   Real Fampionato ha `budget`, ingaggi riservati e contratti fino alla stagione 5:
   va deciso se convertirla (troncando tutti i contratti a un anno) o archiviarla.
   Finché non è deciso, **non toccare** `offseason_fine` di quella lega.
3. **Ritmo del mercato.** Senza costo di taglio e con contratti annuali, la rosa può
   essere rimescolata liberamente. Se emergesse churn eccessivo, il freno naturale
   non è economico ma **procedurale**: finestre di mercato, numero massimo di
   operazioni per finestra.
