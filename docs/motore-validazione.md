# Fase 0 — Validazione del motore

## Verdetto: **GO**

Tutti e 13 i target sono rientrati. Il modello a blocchi funziona, ma **non nella forma descritta nel design doc**: due parti del motore sono state riscritte perché nella versione originale non convergevano. Dettagli nella sezione "Correzioni".

```
node simulate.js                 # suite completa (test 1-5)
node simulate.js --sweep         # sensibilita del campionato al parametro chiave
node simulate.js --sens 0.12     # override al volo
```

Nessuna dipendenza. Solo Node ≥ 18.

---

## Risultati

### Baseline — due squadre identiche, 10.000 partite

| Metrica | Valore | Target |
|---|---|---|
| Gol per partita | 2,50 | 2,50 – 2,90 |
| Vittorie casa | 45,3% | 43 – 47% |
| Pareggi | 25,7% | 23 – 27% |
| Vittorie ospite | 28,4% | 28 – 33% |
| Tiri per squadra | 12,6 | 11 – 14 |
| Passaggi riusciti | 80,0% | 76 – 88% |
| Possesso casa | 52,8% | 49 – 54% |

Distribuzione dei gol: 8% di 0-0, picco sul 2, coda fino a 8. Forma corretta.

### Campionato — 500 stagioni, 8 squadre, 4 gironi

| Metrica | Valore | Target |
|---|---|---|
| Punti del vincitore | 58,4 | 58 – 68 |
| Punti dell'ultimo | 20,7 | 15 – 28 |
| Spread primo-ultimo | 38,8 | 35 – 50 |
| Gol per partita | 2,73 | 2,50 – 2,90 |
| Condizione titolari a fine stagione | 83,7 | 55 – 85 |

Punti del vincitore: p10 = 51, mediana = 58, p90 = 65.

**Titoli vinti per forza di rosa** (spread nominale OVR 79 → 84):

```
T0  79.0   0.0%
T1  79.7   0.2%
T2  80.4   1.2%
T3  81.1   2.8%
T4  81.9   8.2%
T5  82.6  15.6%
T6  83.3  26.2%
T7  84.0  45.8%
```

Gradiente monotono. La squadra più forte vince meno di una volta su due: la forza conta chiaramente, ma non decide. È il comportamento cercato.

### Equilibrio tra moduli

Torneo all-play-all, ogni modulo con rosa costruita su misura (altrimenti il confronto è viziato: una rosa a forma di 4-3-3 fa giocare tutti gli altri moduli fuori ruolo).

| Modulo | Punti/partita | GF | GS |
|---|---|---|---|
| 3-5-2 | 1,417 | 1,32 | 1,25 |
| 3-4-3 | 1,416 | 1,47 | 1,43 |
| 5-3-2 | 1,395 | 1,26 | 1,21 |
| 4-3-3 | 1,385 | 1,41 | 1,40 |
| 4-2-4 | 1,374 | 1,50 | 1,53 |
| 4-4-2 | 1,348 | 1,35 | 1,39 |
| 4-2-3-1 | 1,295 | 1,31 | 1,42 |

Scarto max-min: **0,122 punti/partita** — su 28 partite sono 3,2 punti di classifica. Percepibile ma non dominante.

I profili si differenziano correttamente: 4-2-4 segna di più e subisce di più, 5-3-2 il contrario. Nessun modulo domina.

### Sensibilità al divario di overall

| Gap OVR | Vitt. forte | Pareggi | Vitt. debole |
|---|---|---|---|
| 0 | 35,7% | 26,8% | 37,5% |
| 2 | 50,3% | 26,0% | 23,7% |
| 4 | 60,8% | 22,9% | 16,4% |
| 6 | 72,6% | 17,9% | 9,4% |
| 8 | 81,6% | 12,7% | 5,7% |
| 12 | 93,8% | 4,6% | 1,6% |

---

## Correzioni al design doc

### 1. La formula xG era sbagliata (ratio → esponenziale)

**Nel doc**: `xG = BASE × (ctrl/0.5) × (ATT/DEF)^2.0`

**Problema**: un divario di 5 punti di overall vale il 6% come rapporto; al quadrato, il 12%. Troppo poco. Nel campionato produceva 50 punti al vincitore, spread di 23, e la squadra più debole vinceva il titolo nel 3,6% dei casi. Lo sweep dell'esponente da 1,2 a 3,5 **non risolveva**: anche a 3,5 lo spread arrivava solo a 28.

**Sostituita con**:
```
xG = BASE × (ctrl/0.5) × exp(SENSIBILITA_FORZA × clamp(ATT − DEF, ±10))
```

Forma esponenziale sulla **differenza** invece che sul rapporto. Un punto di overall di vantaggio vale circa +9% di occasioni, indipendentemente dal livello assoluto. È anche molto più interpretabile.

Il `clamp` a ±10 serve perché l'esponenziale è illimitato: senza, un mismatch estremo produceva 4 gol a partita.

**Conseguenza**: tutti i bonus e malus tattici sono diventati **additivi in punti di overall** invece che moltiplicativi in percentuale. Il vantaggio del campo non è più "+3%" ma "+2,0 punti di overall su attacco e centrocampo". La familiarità non è più "×0,94" ma "−3,5 punti di overall". Molto più leggibile quando dovrai spiegarlo ai tuoi amici.

### 2. La matrice counter era ridondante e i moduli difensivi erano puro svantaggio

**Nel doc**: formula generativa che modificava solo l'attacco in base ai conteggi nominali del modulo.

**Problema**: le linee sono medie pesate, quindi schierare cinque difensori invece di quattro **non aumentava la solidità**. Un 5-3-2 perdeva attacco senza guadagnare difesa: era una scelta strettamente inferiore. Empiricamente perdeva contro tutto.

**Sostituita con un modello strutturale** derivato direttamente dai pesi slot:
```
ATT_eff = media_ATT + K × (Σ pesi_ATT − baseline_4-3-3)
MID_eff = media_MID + K × (Σ pesi_MID − baseline_4-3-3)
DEF_eff = media_DEF + K × (Σ pesi_DEF − baseline_4-3-3)
```

Un parametro (`K_STRUTTURA = 2.2`) al posto di tre. Il counter emerge da solo dal confronto `ATT_A` vs `DEF_B` nell'esponenziale, e i profili risultanti sono corretti senza tuning manuale:

```
modulo        ATT     MID     DEF
4-3-3        0.00    0.00    0.00
4-4-2       -0.55   -0.11    0.22
4-2-3-1     -0.11   -1.87    0.66
3-5-2       -1.10   -0.33    1.32
3-4-3        0.55    0.22   -0.66
5-3-2       -1.54   -0.99    1.98
4-2-4        1.65   -2.09   -0.66
```

Funziona automaticamente con qualsiasi modulo aggiunto in futuro: basta definire gli slot.

### 3. Bug: i tiri erano derivati dai gol realizzati

`tiri = gol / conversione` con `conversione ~ N(0.105, 0.03)`. La disuguaglianza di Jensen faceva esplodere la media: con conversione estratta a 0,05 e 2 gol, la partita registrava 40 tiri. Media risultante 15,6 contro un target di 11–14.

**Corretto**: i tiri derivano dall'**xG accumulato**, non dai gol. È anche più corretto concettualmente — una squadra può tirare 20 volte e non segnare.

### 4. 3-5-2 e 5-3-2 erano lo stesso modulo

Avevano gli stessi slot (3 CB + 2 wing-back + 3 CM + 2 ST). Il 5-3-2 ora usa terzini bassi (LB/RB) invece di wing-back alti (LWB/RWB), che è la differenza reale tra i due sistemi.

### 5. Metrica della condizione

Il doc misurava la condizione media dell'intera rosa. È una metrica inutile: 14 giocatori su 25 non giocano mai, quindi la media resta sopra 90 qualunque cosa succeda. La metrica corretta è la **condizione media degli 11 migliori**, che a fine stagione si assesta a 83,7.

---

## Costanti finali

```js
SENSIBILITA_FORZA   = 0.090   // il parametro chiave
XG_BASE_BLOCCO      = 0.252
DIFF_CLAMP          = 10
AMPLIFICA_CONTROLLO = 1.4
BONUS_CASA_ATT      = 2.0     // punti di overall
BONUS_CASA_MID      = 2.0
K_STRUTTURA         = 2.2
FAM_MALUS_MAX       = 3.5     // punti di overall al primo utilizzo
DIVISORE_PORTIERE   = 180
DAMPING_MARCATORE   = 0.45
```

---

## Nota successiva — troppa varianza sui tiri per partita (4 agosto 2026)

Segnalato dall'utente guardando i tabellini reali di "Lega di Prova": alcune partite
registravano 35-37 tiri per una squadra, contro un target medio di 11-14. La media validata
in Fase 0 (`docs/risultati-fase0.txt`) era corretta — il difetto era nella **varianza**, che
`tools/validazione/simulate.js` non misura (controlla solo la media su migliaia di partite).

**Causa**: `tiri = xG_totale / conversione`, con `conversione ~ N(0.105, 0.03)` clampata fra
0,07 e 0,17 (punto 3 sopra). Con sigma 0,03 la gaussiana finisce sul tetto basso (0,07) circa
il **12% delle volte** — quasi una partita su otto — e dividere per 0,07 invece che per la
media 0,105 moltiplica i tiri per oltre 2 volte a parità di xG. Non serviva nemmeno un xG
anomalo: xG_totale = 2,5 (una prestazione offensiva normale) con conversione al tetto basso fa
già 36 tiri.

**Corretto**: `CONVERSIONE_SIGMA` ridotta da `0.03` a `0.015` in `engine/config.js`. Dimezzando
la sigma la gaussiana finisce sul tetto basso solo l'1% delle volte circa, senza spostare la
media (`CONVERSIONE_MEDIA` resta 0,105, invariata). Verificato su 10.000 partite simulate con
`creaRosa`: la quota di prestazioni-squadra con 30+ tiri scende dal ~12% teorico (coerente con
la quota di partite sul tetto basso) allo 0,14% osservato — un evento raro come nel calcio
vero, non più un caso ogni 8 partite.

**Rilanciata la suite completa** (`node tools/validazione/simulate.js`): tutti gli altri 12
target restano invariati byte per byte rispetto a `docs/risultati-fase0.txt` — `conversione`
alimenta solo `tiri` e `inPorta`, non gol, risultati, punti o equilibrio moduli. Il file dei
risultati grezzi è stato aggiornato con il nuovo output (tiri per squadra: 12,4 → 12,1, sempre
dentro 11-14).

Nota per chi tocca ancora questa costante: il paragrafo "Cosa NON è stato validato" qui sotto
avvertiva che le rose reali avrebbero potuto spostare la **media** dei tiri, con
`XG_BASE_BLOCCO` come unica leva prevista. Questo non è quel caso — la media era ed è corretta,
il problema era la coda della distribuzione. Se in futuro dovesse spostarsi anche la media coi
dati reali, la leva resta `XG_BASE_BLOCCO`; per la sola varianza dei tiri, la leva è
`CONVERSIONE_SIGMA`.

---

## Cosa NON è stato validato

- **Rose reali.** Le rose sintetiche hanno distribuzioni ragionevoli ma non sono il dataset FC 26. Quando importerai i dati veri, rilancia `test1` e `test3`: se i numeri si spostano, l'unica costante da ritoccare è `XG_BASE_BLOCCO`.
- **Lo spread di forza dopo un draft reale.** Ho assunto 79 → 84 (5 punti). Se i tuoi amici draftano con abilità molto diverse, lo spread potrebbe essere 8-10 punti e il campionato diventerebbe più squilibrato di quanto mostrato. Da rimisurare dopo il primo draft vero.
- **Mercato, contratti, progressione.** Fuori dallo scope della Fase 0.

---

## File

```
engine/config.js               costanti, moduli, pesi slot, compatibilita ruoli
engine/random.js               RNG seeded, gauss, poisson, estrazione pesata
engine/engine.js               overall efficace, linee, struttura, xG, gol, stats, cambi, calendario
tools/validazione/roster.js    generazione rose sintetiche (SOLO test)
tools/validazione/simulate.js  suite di validazione, test 1-5 + sweep (SOLO test)
docs/risultati-fase0.txt       baseline del test di regressione
```

`engine/` è autosufficiente: `engine.js` dipende solo da `config.js` e `random.js`.
Nessuna dipendenza verso `tools/`. Per la produzione basta collegare i giocatori veri
tramite un adapter DB → motore.

> I numeri in questo documento sono quelli di `docs/risultati-fase0.txt`, generato con
> `SENSIBILITA_FORZA = 0.090`. In caso di dubbio **vince il .txt**, che è la baseline
> del test di regressione ed è riproducibile byte per byte grazie al seed fisso.
