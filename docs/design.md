# Manageriale Multiplayer — Documento di Design v1.1

> **v1.1** — Le sezioni 6.4, 6.5, 6.6, 7.2 e 12 sono state riscritte dopo la validazione
> di Fase 0. Le formule della v1.0 (rapporto ATT/DEF elevato a potenza, matrice counter
> moltiplicativa) **non convergevano** e sono state sostituite. Vedi `motore-fase0/README.md`
> per i risultati e il perche'. Il codice in `motore-fase0/engine.js` e' la fonte di verita':
> in caso di discrepanza con questo documento, vince il codice.

Documento consolidato. Tutte le decisioni aperte sono state chiuse. Le costanti numeriche sono valori di partenza da tarare, non verità rivelate: la sezione 12 le raccoglie tutte in un posto solo perché siano modificabili senza toccare la logica.

---

## 1. Scope

Manageriale calcistico a turni per gruppo chiuso di amici. Draft casuale iniziale, campionato simulato automaticamente, mercato quotidiano tra giocatori umani, carriera pluristagionale con crescita/declino dei calciatori.

**Fuori scope V1**: coppe, promozione/retrocessione, staff tecnico, stadi/infrastrutture, allenamenti, nazionali.

---

## 2. Pool giocatori

### 2.1 Fonte dati

Snapshot singolo **2025/26** (FC 26), 10 campionati:

Premier League, La Liga, Serie A, Bundesliga, Ligue 1, Eredivisie, Liga Portugal, Süper Lig, Saudi Pro League, EFL Championship.

**Volume dello snapshot importato**: 5.416 giocatori, 192 club. Fonte e conteggi sono
documentati in `docs/dataset-fc26.md`.

**Motivo dello snapshot singolo**: in una carriera pluristagionale gli snapshot storici sono temporalmente incoerenti (un Del Piero 2003 che invecchia accanto a un Haaland 2025 non ha senso). Con un anno zero unico, tutti invecchiano insieme e il problema duplicati/età sparisce per costruzione.

### 2.2 Campi necessari per giocatore

| Campo | Uso |
|---|---|
| `id`, `nome`, `nazionalità`, `club`, `foto_url` | Identità |
| `overall`, `potential` | Forza attuale e cap di crescita |
| `età`, `data_nascita` | Ingaggi, progressione, ritiro |
| `posizioni[]` (ordinate) | Prima = naturale, successive = secondarie |
| `piede`, `altezza` | Cosmetico / micro-modificatori |
| `pace, shooting, passing, dribbling, defending, physic` | Distribuzione statistiche partita |
| `stamina`, `finishing`, `short_passing`, `standing_tackle`, `gk_diving`, `gk_reflexes` | Sottoattributi usati dal motore |

### 2.3 Pool Icone (opzionale, consigliato)

80–120 leggende inserite a mano con rating decisi dall'admin. Compaiono nello spin con probabilità **3%**, sostituendo l'esito normale. Recupera il fattore nostalgia perso con lo snapshot singolo, al costo di un pomeriggio di data entry invece di un database storico.

### 2.4 Giocatori generati (regen)

**Non implementare prima della stagione 5.** Su 6.000 giocatori reali ne vengono draftati ~200: il pool residuo copre 6-8 stagioni di mercato svincolati.

Quando servirà:
- Numero generati per stagione = ritirati + 20%
- Età 16–19, overall 55–70
- Potential: 70% sotto 78, 25% tra 78 e 85, 5% sopra 85
- Attributi campionati dalla distribuzione reale dello stesso ruolo e fascia di overall
- Nomi da liste per nazionalità
- **Vincolo permanente**: mantenere sempre almeno il 30% del pool svincolati composto da giocatori reali mai draftati, altrimenti la lega diventa integralmente fittizia e perde il gancio del riconoscimento

---

## 3. Setup lega

### 3.1 Impostazioni admin

| Impostazione | Range | Default |
|---|---|---|
| Numero squadre `N` | 4–20 | 8 |
| Numero gironi `G` | 2–6 | 4 |
| Budget iniziale `B` | 50–200 M€ | 100 M€ |
| Reroll draft | 0–30 | 12 |
| Campionati attivi | subset dei 10 | tutti |
| Slot rosa | 20–30 | 25 |
| Portieri minimi | 2–4 | 3 |

**Partite per squadra** `P = (N − 1) × G`. Con N dispari il sistema genera un turno di riposo per giornata usando il **metodo del cerchio** (una squadra fittizia "riposo" aggiunta per rendere pari il numero, poi ruotata).

**Giornate totali** `D = (N − 1 + N mod 2) × G`: con N pari `D=P`, con N dispari
`D=N×G` perché ogni girone include una giornata di riposo per squadra.

> **`D` è la durata reale della stagione in giorni**, perché si simula una giornata
> per turno (vedi `docs/decisioni-fase1.md` §7). Le combinazioni ammesse vanno da 6 giorni
> (N=4, G=2) a 114 giorni (N=20, G=6): l'admin sceglie la durata senza accorgersene, quindi
> la schermata di creazione lega **deve** mostrare giornate e data di fine in `Europe/Rome`
> mentre muove i selettori.

### 3.2 Ingresso

Codice invito a 6 caratteri. `N − 1` posti disponibili oltre l'admin. Ogni partecipante registra nome squadra + stemma (galleria prefatta o upload PNG/JPEG, ridimensionato server-side a 512×512, max 2 MB).

---

## 4. Draft

### 4.1 Meccanica

1. Il giocatore preme SPIN → il sistema estrae casualmente un club tra quelli dei campionati attivi
2. Vengono mostrati tutti i giocatori di quel club
3. Il giocatore ne sceglie **uno** e lo ingaggia, oppure usa un **reroll** per rifare lo spin
4. Si ripete fino a riempire tutti gli slot

Ordine di draft: **serpentina** (1→N, poi N→1, poi 1→N…) per non svantaggiare sistematicamente chi pesca per ultimo.

### 4.2 Unicità

Un giocatore ingaggiato da una squadra è **globalmente non selezionabile** per tutte le altre. Resta visibile nella lista del club, in grigio, con lo stemma della squadra che lo possiede.

### 4.3 Budget e tetto ingaggi

L'ingaggio annuale viene **scalato dal budget al momento del pick**.

**Tetto draft**: massimo **80% di `B`** in monte ingaggi. Il restante 20% garantisce liquidità per il mercato della stagione 1, che altrimenti sarebbe morto per tutti.

> Dalla stagione 2 in poi il tetto sparisce: la pressione economica strutturale lo rende superfluo.

### 4.4 Vincolo di solvibilità

Prima di ogni pick il sistema verifica che la rosa resti completabile:

```
budget_residuo_dopo_pick  >=  (slot_liberi_dopo_pick × 0.5)
                            + (portieri_ancora_mancanti × 0.5)
```

Se il vincolo non regge, quel giocatore è **visibile ma non selezionabile**, con etichetta "non sostenibile".

**Caso limite**: se *nessun* giocatore del club estratto è ingaggiabile, lo spin viene ripetuto automaticamente **senza consumare reroll**. Senza questa regola la sfortuna può bloccare irreversibilmente un draft.

### 4.5 Vincoli di rosa

- 25 slot totali
- Minimo 3 portieri
- Nessun vincolo su difensori/centrocampisti/attaccanti (chi si costruisce una rosa sbilanciata ne paga le conseguenze in campo)

---

## 5. Economia

### 5.1 Scala ingaggi

`ingaggio = base(overall) × mod_età`, arrotondato a 0,1 M€, con floor a **0,5 M€**.

**base(overall)** — in M€/anno:

| Overall | ≤65 | 66-70 | 71-74 | 75-77 | 78-80 | 81-83 | 84-85 | 86-87 | 88-89 | 90+ |
|---|---|---|---|---|---|---|---|---|---|---|
| Base | 0,5 | 0,8 | 1,2 | 2,0 | 3,2 | 5,0 | 7,5 | 10,0 | 13,0 | 17,0 |

**mod_età**:

| Età | 16-20 | 21-23 | 24-26 | 27-30 | 31-32 | 33-34 | 35+ |
|---|---|---|---|---|---|---|---|
| Mod | 0,35 | 0,65 | 0,90 | 1,00 | 0,90 | 0,70 | 0,50 |

Verifica: 28enne da 86 → 10,0 M€. 18enne da 72 → 0,5 M€ (floor). 19enne da 84 → 2,6 M€ (i giovani forti sono affari — voluto). 30enne da 91 → 17,0 M€.

Monte ingaggi tipico di una rosa da 25 costruita col tetto: **75–80 M€**.

### 5.2 Entrate

**Dotazione iniziale `B` = 100 M€: una tantum, solo stagione 1.** Non ricorrente.

**Sponsor**: `0,20 × B` = 20 M€/stagione, fisso, a inizio stagione.

**Premi partita** — normalizzati sul numero di partite, così l'economia regge con qualsiasi configurazione di squadre e gironi:

```
vittoria  = 0.54  × B / P
pareggio  = 0.27  × B / P
sconfitta = 0.135 × B / P
```

Con N=8, G=4 (P=28), B=100M: **1,93 M€ / 0,96 M€ / 0,48 M€**.

**Premi posizione** — monte totale `0.12 × B × N`, distribuito con pesi `w_i = (N − i + 1)^1.8`:

```
premio(pos_i) = monte × w_i / Σw
```

Con N=8, B=100M (monte 96 M€):

| Pos | 1° | 2° | 3° | 4° | 5° | 6° | 7° | 8° |
|---|---|---|---|---|---|---|---|---|
| M€ | 28,4 | 22,1 | 16,6 | 12,0 | 8,4 | 5,3 | 2,4 | 0,7 |

Rapporto 40:1 tra primo e ultimo. È aggressivo di proposito: rende la lotta per ogni posizione economicamente rilevante fino all'ultima giornata.

### 5.3 Bilancio strutturale

| Voce | Squadra media, stagione 2+ |
|---|---|
| Sponsor | 20,0 M€ |
| Partite (10V-8P-10S) | 31,8 M€ |
| Premio posizione (media) | 12,0 M€ |
| **Entrate totali** | **63,8 M€** |
| Monte ingaggi | ~76 M€ |
| **Saldo** | **−12 M€** |

Deficit strutturale di circa il **15% del monte ingaggi**. È il motore economico del gioco: ogni stagione sei costretto a vendere o svincolare. Senza deficit, il denaro smette di essere una risorsa entro la stagione 3.

I trasferimenti tra squadre sono a somma zero: non alterano la massa monetaria della lega.

### 5.4 Pagamento ingaggi

- **Inizio stagione**: addebito del monte ingaggi completo della rosa
- **Acquisto a stagione in corso**: costo trasferimento + ingaggio **pro-rata** sulle giornate rimanenti
- **Svincolo**: nessun rimborso. Libera lo slot e rimuove il giocatore dal monte ingaggi **della stagione successiva**

### 5.5 Insolvenza

Il budget non può andare negativo. Se a inizio stagione il monte ingaggi non è copribile, il sistema **svincola automaticamente** partendo dall'ingaggio più alto, finché il conto non torna.

L'operazione è pubblica e notificata. Vendere in tempo prima che intervenga il sistema è una delle decisioni centrali dell'off-season.

### 5.6 Anti-spirale del vincitore

Tassa progressiva sul monte ingaggi, addebitata a inizio stagione:

```
se monte_ingaggi > 0.85 × B:
    tassa = (monte_ingaggi − 0.85 × B) × 0.6
```

Chi accumula superstar paga un sovrapprezzo che cresce più che linearmente. Contiene la spirale ricchi-più-ricchi senza vietare nulla.

---

## 6. Formazione e tattiche

### 6.1 Moduli disponibili

4-4-2 · 4-3-3 · 4-2-3-1 · 3-5-2 · 3-4-3 · 5-3-2 · 4-2-4

### 6.2 Overall efficace del giocatore

```
OVR_eff = OVR_base × pen_ruolo × fatt_condizione × fatt_infortunio
```

**pen_ruolo**:

| Situazione | Moltiplicatore |
|---|---|
| Posizione naturale (prima in `posizioni[]`) | 1,00 |
| Posizione secondaria (elencata) | 0,96 |
| Non elencata, stesso reparto | 0,86 |
| Reparto adiacente | 0,72 |
| Reparto opposto | 0,58 |
| Giocatore di movimento in porta | `min(45, OVR × 0.45)` |
| Portiere in movimento | `min(48, OVR × 0.50)` |

Reparti: Difesa (CB, LB, RB, LWB, RWB) · Centrocampo (CDM, CM, CAM, LM, RM) · Attacco (LW, RW, ST, CF).

### 6.3 Aggregazione in linee

Ogni slot del modulo contribuisce ad ATT / MID / DEF con pesi fissi:

| Slot | DEF | MID | ATT |
|---|---|---|---|
| CB | 1,00 | 0,10 | — |
| LB / RB | 0,75 | 0,25 | 0,10 |
| LWB / RWB | 0,60 | 0,40 | 0,20 |
| CDM | 0,55 | 0,75 | 0,05 |
| CM | 0,30 | 1,00 | 0,25 |
| CAM | 0,10 | 0,65 | 0,60 |
| LM / RM | 0,25 | 0,75 | 0,35 |
| LW / RW | 0,05 | 0,30 | 0,85 |
| ST / CF | — | 0,05 | 1,00 |

```
LINEA_squadra = Σ(OVR_eff_i × peso_i) / Σ(peso_i)
```

Il portiere è tenuto fuori dalle linee e usato separatamente (sezione 7.4).

### 6.4 Profilo strutturale del modulo

> Sostituisce la matrice counter della v1.0. **Motivo**: le linee sono medie pesate,
> quindi schierare cinque difensori invece di quattro non aumentava la solidita di un punto.
> Un 5-3-2 perdeva attacco senza guadagnare difesa: era una scelta strettamente inferiore,
> e infatti perdeva contro tutti i moduli nel test empirico.

Il profilo di un modulo emerge dal **monte-pesi** dei suoi slot, confrontato col 4-3-3:

```
ATT_eff = media_ATT + K_STRUTTURA × clamp(Σ pesi_ATT − 3.65, ±3.5)
MID_eff = media_MID + K_STRUTTURA × clamp(Σ pesi_MID − 4.35, ±3.5)
DEF_eff = media_DEF + K_STRUTTURA × clamp(Σ pesi_DEF − 4.50, ±3.5)
```

con `K_STRUTTURA = 2.2`. Le baseline sono i monte-pesi del 4-3-3, calcolate a runtime dalla
tabella 6.3 — non vanno inserite a mano.

Profili risultanti (punti di overall rispetto al 4-3-3):

| Modulo | ATT | MID | DEF |
|---|---|---|---|
| 4-3-3 | 0,00 | 0,00 | 0,00 |
| 4-4-2 | −0,55 | −0,11 | +0,22 |
| 4-2-3-1 | −0,11 | −1,87 | +0,66 |
| 3-5-2 | −1,10 | −0,33 | +1,32 |
| 3-4-3 | +0,55 | +0,22 | −0,66 |
| 5-3-2 | −1,54 | −0,99 | +1,98 |
| 4-2-4 | +1,65 | −2,09 | −0,66 |

**Il counter non esiste come formula separata**: emerge dal confronto `ATT_A` contro `DEF_B`
dentro l'esponenziale dell'xG. Un 4-2-4 (ATT alto) contro un 5-3-2 (DEF alto) si scontra
esattamente dove deve.

Vantaggio del modello: funziona automaticamente con qualsiasi modulo aggiunto in futuro,
basta definirne gli slot. Nessuna cella da tarare a mano.

**Verifica empirica** (torneo all-play-all, rose costruite su misura per ogni modulo,
1500 partite per accoppiamento): scarto tra il modulo migliore e il peggiore = **0,113
punti/partita**, cioe 3,2 punti su una stagione da 28 giornate. Nessun modulo domina.

> Attenzione: 3-5-2 e 5-3-2 devono avere slot **diversi**. Il 3-5-2 usa wing-back alti
> (LWB/RWB), il 5-3-2 terzini bassi (LB/RB) in una linea a cinque. Nella v1.0 avevano
> gli stessi slot ed erano lo stesso modulo.

### 6.5 Familiarità col modulo

Malus **in punti di overall**, non in percentuale:

```
malus_fam = −FAM_MALUS_MAX × (1 − min(1, partite_col_modulo / 15))
```

Con `FAM_MALUS_MAX = 3.5`: al primo utilizzo la squadra perde **3,5 punti di overall** su
attacco e centrocampo. Dopo 15 partite il malus e nullo.

Contatore per squadra e per modulo, decade del 10% a stagione se il modulo non viene usato.

> Perche in punti e non in percentuale: e direttamente confrontabile con tutto il resto.
> "Cambiare modulo ti costa 3,5 punti di overall finche non lo impari" e una frase che i
> partecipanti capiscono al volo. "Ti costa il 6%" no.

### 6.6 Fattore campo

Squadra di casa: **+2,0 punti di overall** su ATT e MID (additivo, non percentuale).
Produce un tasso di vittorie interne del 45,9%, in linea coi campionati reali.

### 6.7 Formazione automatica di fallback

Se alle **23:00 (Europe/Rome)** non è stata salvata una formazione valida, il sistema genera automaticamente:
- Modulo: l'ultimo usato, o 4-3-3 al primo utilizzo
- Undici: massimizza la somma di `OVR_eff` con assegnazione ottimale ruolo/giocatore (algoritmo ungherese o greedy con backtracking)
- Panchina: 9 migliori residui garantendo almeno 1 portiere

---

## 7. Motore di simulazione

### 7.1 Architettura: modello a blocchi

La partita è divisa in **6 blocchi da 15 minuti**. Per ogni blocco si ricalcolano le forze in base agli 11 effettivamente in campo, si stima un xG, si estraggono i gol.

**Perché a blocchi e non a eventi minuto per minuto**: i cambi e il calo di stamina diventano naturali (la squadra con riserve stanche crolla nell'ultimo quarto d'ora, come nella realtà), le distribuzioni sono realistiche per costruzione, e il costo di sviluppo è circa un quinto. Il prezzo pagato è l'assenza di una cronaca causale ("Tizio serve Caio che segna"); gli assist restano comunque simulabili in modo plausibile.

### 7.2 Sequenza per blocco

**Passo 1 — Forze di linea** (tutto additivo, in punti di overall)

```
ATT_C = media_ATT_C + strutt_ATT_C + malus_fam_C + BONUS_CASA_ATT
MID_C = media_MID_C + strutt_MID_C + malus_fam_C + BONUS_CASA_MID
DEF_C = media_DEF_C + strutt_DEF_C
```

(la squadra ospite senza i bonus casa)

**Passo 2 — Controllo del gioco**

```
ctrl_C = clamp(0.5 + AMPLIFICA_CONTROLLO × (MID_C − MID_O) / 100, 0.22, 0.78)
```

Differenza, non rapporto. Con `AMPLIFICA_CONTROLLO = 1.4` un vantaggio di 5 punti a
centrocampo produce il 57% di controllo.

**Passo 3 — xG del blocco**

```
xG_C = XG_BASE_BLOCCO × (ctrl_C / 0.5) × exp(SENSIBILITA_FORZA × clamp(ATT_C − DEF_O, ±10))
```

> **Questa e la correzione piu importante della v1.1.** La v1.0 usava `(ATT/DEF)^2.0`.
> Non funziona: un divario di 5 punti di overall vale il 6% come rapporto, il 12% al
> quadrato. Nel campionato produceva 50 punti al vincitore e uno spread di 23 (target 35-50),
> con la squadra piu debole che vinceva il titolo nel 3,6% dei casi. Lo sweep dell'esponente
> da 1,2 a 3,5 non risolveva: anche a 3,5 lo spread arrivava solo a 28. Il problema era la
> forma della funzione, non la taratura.

Con `SENSIBILITA_FORZA = 0.090`, un punto di overall di vantaggio vale circa +9% di
occasioni, **indipendentemente dal livello assoluto** — che e la proprieta che il rapporto
non aveva.

Il `clamp` a ±10 e obbligatorio: l'esponenziale e illimitato e senza tetto un mismatch
estremo produce oltre 4 gol a partita.

**Passo 4 — Portiere**

```
xG_C_finale = xG_C × (1 − (GK_ovr_O − 75) / 180)
```

**Passo 5 — Gol**

`gol_C_blocco ~ Poisson(xG_C_finale)`

**Passo 6 — xG accumulato**

Sommare `xG_C_finale` in un totale di partita: serve al passo 7.3 per derivare i tiri.

### 7.3 Statistiche individuali

Volumi di squadra per partita, poi ripartiti tra i giocatori:

| Statistica | Formula squadra |
|---|---|
| Tiri | `xG_totale / conv`, con `conv ~ N(0.105, 0.03)` clampato [0,07; 0,17] |
| Tiri in porta | `tiri × N(0.36, 0.07)`, mai meno dei gol |
| Passaggi tentati | `480 × ctrl_adj × 2` |
| % riuscita | `0.78 + 0.0025 × (MID_squadra − 75)` |
| Contrasti | `18 × (1 − ctrl_adj) × 2` |
| Dribbling tentati | `12 × ctrl_adj × 2` |

> I tiri si derivano dall'**xG accumulato**, non dai gol realizzati. Nella v1.0 erano
> `gol / conv`: la disuguaglianza di Jensen faceva esplodere la media (conversione estratta
> a 0,05 con 2 gol = 40 tiri in una partita), portando la media a 15,6 contro un target di
> 11-14. E anche piu corretto concettualmente: una squadra puo tirare 20 volte e non segnare.

**Ripartizione per giocatore**: peso = `peso_ruolo_statistica × (attributo_rilevante / 100)`, normalizzato sulla squadra.

| Statistica | Attributo | Ruoli favoriti |
|---|---|---|
| Tiri | `finishing` | ATT ×3,0 · CAM ×1,8 · CM ×0,8 · DIF ×0,25 |
| Passaggi | `short_passing` | CM ×1,6 · CDM ×1,5 · CB ×1,3 · ATT ×0,6 |
| Contrasti | `standing_tackle` | CB ×1,7 · CDM ×1,6 · TER ×1,4 · ATT ×0,4 |
| Dribbling | `dribbling` | ALA ×2,0 · CAM ×1,6 · ATT ×1,2 · CB ×0,15 |

**Marcatori**: estrazione pesata su `peso_ATT_slot × (finishing / 100)^1.5`. Dopo ogni gol
il peso del marcatore viene moltiplicato per `DAMPING_MARCATORE = 0.45`, altrimenti lo stesso
attaccante segna quattro gol su cinque troppo spesso.
**Assist**: estrazione pesata su `peso_MID/ATT × (short_passing / 100)`, escluso il marcatore, con probabilità 0,72 che il gol abbia un assist.

### 7.4 Sostituzioni automatiche

5 cambi, 3 finestre — collocate alla fine dei blocchi **3, 4 e 5** (≈45', 60', 75').

Logica: per ogni slot, se il titolare ha `condizione < 55` **e** esiste in panchina un giocatore con `OVR_eff` superiore per quello slot, sostituisci. Massimo 2 cambi per finestra, massimo 5 totali.

L'utente può opzionalmente predefinire cambi programmati (giocatore X esce al blocco Y), che hanno priorità sulla logica automatica.

---

## 8. Stamina e infortuni

### 8.1 Condizione

Ogni giocatore ha una `condizione` persistente 0–100, distinta dall'attributo `stamina` del dataset (che ne governa la velocità di consumo).

**Consumo per blocco giocato**:
```
consumo = 3.4 − 1.6 × (stamina / 100)
```
Un giocatore da 90 di stamina perde ~11,8 punti in una partita intera; uno da 60 ne perde ~14,6.

**Recupero tra giornate**:

| Situazione | Recupero |
|---|---|
| Fuori dai convocati / tribuna | +38 |
| In panchina senza entrare | +30 |
| Ha giocato (anche parzialmente) | +8 |

Cap a 100.

> ⚠️ **Modifica rispetto alla specifica originale.** Era previsto il recupero completo con una sola giornata di riposo. Con 25 giocatori in rosa e 2 giornate al giorno, quella regola rende la rotazione gratuita e la stamina una meccanica puramente decorativa: basta alternare due undici e nessuno cala mai. Col recupero parziale, un titolare fisso perde ~4 punti netti a giornata e dopo 10 giornate è a 60, costringendo a scelte reali sulla profondità della rosa.

> 🔁 **Da rivedere in Fase 2.** Il ragionamento qui sopra assume 2 giornate al giorno, che
> non è più il ritmo scelto (`docs/decisioni-fase1.md` §7). Il calo *per giornata* non cambia,
> ma il calo *per giorno reale* si dimezza: con una giornata per turno un titolare fisso
> impiega ~10 giorni invece di ~5 per scendere a 60. La meccanica regge, la taratura di
> `REC_GIOCATO` va rimisurata quando si accende la condizione. Non toccare adesso: in Fase 1
> il motore gira con `usaCondizione: false`.

**Effetto sull'overall**:

| Condizione | Fattore |
|---|---|
| ≥ 85 | 1,000 |
| 70–84 | 0,975 |
| 55–69 | 0,940 |
| 40–54 | 0,890 |
| < 40 | 0,820 |

### 8.2 Infortuni

Probabilità per partita giocata:
```
p = 0.025 × (1 + (100 − condizione) / 50) × mod_età
```

| Età | <24 | 24-30 | 31-33 | 34+ |
|---|---|---|---|---|
| mod | 0,85 | 1,00 | 1,25 | 1,50 |

A piena condizione: 2,5%. A condizione 40: 5,5%. Risultato atteso: ~0,7 infortuni per partita su 22 titolari.

**Durata**: distribuzione pesata verso il basso — 60% da 1 a 2 giornate, 30% da 3 a 6, 10% da 8 a 15.

**Rientro**: al ritorno il giocatore ha condizione 65 e un malus temporaneo di `−0.03` sull'overall per 2 giornate.

---

## 9. Mercato

### 9.1 Finestra quotidiana

| Orario (Europe/Rome) | Evento |
|---|---|
| 00:00 | Simulazione di **una** giornata |
| 07:00 | Apertura mercato + estrazione 10 svincolati |
| 21:00 | Chiusura mercato + rivelazione buste chiuse + scadenza proposte |
| 23:00 | Deadline formazioni (poi fallback automatico) |

> **Chiusura spostata dalle 17:00 alle 21:00** — decisione dell'utente, 2 agosto 2026.
> Vince sulla versione precedente di questa tabella.
>
> Le 17:00 cadevano in orario di lavoro: chi apriva l'app solo la sera trovava le proposte
> già scadute e le aste già assegnate, cioè non giocava il mercato. Con le 21:00 la finestra
> copre la serata, e resta comunque il margine giusto prima della deadline formazioni: alle
> 21:00 si scopre chi si è preso all'asta, e ci sono **due ore** per rifare la formazione
> tenendone conto prima che alle 23:00 scatti il fallback.

### 9.2 Trattative tra squadre

Tre tipi di proposta:
- **Acquisto secco**: cifra in M€ per un giocatore
- **Scambio**: giocatore A per giocatore B
- **Scambio con conguaglio**: giocatore A + M€ per giocatore B

**Verifica di solvibilità dell'acquirente**:
```
budget >= costo_trasferimento + ingaggio_pro_rata_giornate_rimanenti
```
E la rosa deve restare valida (≤ slot massimi, ≥ 3 portieri) per **entrambe** le squadre.

Le proposte scadono alla chiusura del mercato del giorno.

### 9.3 Log pubblico

**Tutte le trattative concluse** sono visibili a tutti, con giocatori scambiati, cifre e differenziale di valore. Non è un vincolo tecnico ma sociale: in un gruppo di amici la collusione è inevitabile, e l'unico deterrente efficace è la visibilità.

### 9.4 Svincolati — asta a busta chiusa

Ogni giorno alle 07:00 il sistema estrae **10 giocatori** dal pool disponibile, con vincolo di **almeno 3 giocatori sotto i 20 anni**.

Ogni squadra può fare **una offerta per giocatore**, in ingaggio annuale offerto.

**Soglia di accettazione del giocatore**:
```
soglia = ingaggio_teorico × uniform(0.90, 1.10)
```
Non visibile alle squadre. Offerte sotto soglia vengono scartate.

**Assegnazione**: alle 17:00 vince l'offerta più alta sopra soglia. A parità, sorteggio. Il giocatore entra in rosa con contratto di 1 anno all'ingaggio offerto. Se nessuna offerta supera la soglia, il giocatore torna nel pool.

**Vincolo**: una squadra non può vincere più di 3 aste nello stesso giorno.

### 9.5 Svincolo

Libera lo slot immediatamente. Nessun rimborso. Il giocatore esce dal monte ingaggi della **stagione successiva** ed entra nel pool svincolati.

---

## 10. Fine stagione

### 10.1 Classifica

Criteri, in ordine: **punti → scontri diretti → differenza reti → gol fatti → sorteggio**.

Vittoria 3 punti, pareggio 1.

### 10.2 Progressione giocatori

| Età | Variazione overall |
|---|---|
| ≤ 22 | `+(potential − OVR) × uniform(0.15, 0.45)` |
| 23–26 | `+(potential − OVR) × uniform(0.05, 0.25)` |
| 27–31 | `uniform(−1, +1)` |
| 32–35 | `−uniform(0.5, 2.5)` |
| ≥ 36 | `−uniform(1.5, 4.0)` |

L'overall non supera mai `potential`. Il `potential` stesso può variare di ±1 con probabilità 15% per gli under 21 (i "breakout").

### 10.3 Ritiro

```
p_ritiro = max(0, (età − 33) × 0.12)
```
36 anni → 36%. 38 anni → 60%. 40 anni → 84%. Ritiro forzato a 42.

### 10.4 Rinnovi contrattuali

Off-season, prima della nuova stagione. Ogni contratto in scadenza va rinnovato o il giocatore diventa svincolato.

**Richiesta del giocatore**:
```
richiesta = ingaggio_teorico(OVR_nuovo, età_nuova)
          × mod_rendimento    (0.85 – 1.35, da percentile di rendimento nel ruolo)
          × mod_ambizione     (0.90 top-3 · 1.00 metà · 1.15 ultimo terzo)
          × uniform(0.95, 1.05)
```

Mostrata al giocatore come **range con ±12% di incertezza** ("chiede circa 4,2–5,3 M€"). Il numero esatto non è visibile: se lo fosse, offriresti sempre quello e la meccanica sparirebbe.

**Offerta della squadra**: ingaggio + durata 1–4 anni.
```
costo_annuo = offerta × (1 + 0.08 × (durata − 1))
```
Contratto lungo costa di più ma **blocca l'ingaggio**: legare un 19enne con potential 88 per 4 anni a 2,5 M€ è la mossa più redditizia del gioco. Contratto corto è economico ma ti espone al rinnovo a prezzo di mercato l'anno dopo.

**Accettazione**:
- offerta ≥ richiesta → accetta
- 0,90 ≤ offerta/richiesta < 1,00 → probabilità lineare da 0 a 1
- offerta < 0,90 × richiesta → rifiuta, diventa svincolato

### 10.5 Nuova stagione

L'admin può rimuovere squadre e aggiungerne di nuove. Una squadra entrante riceve la dotazione `B` completa e fa un draft di ingresso dal pool svincolati (non dal pool club, che è già stato distribuito).

---

## 11. Modello dati (bozza Supabase)

```
leagues            id, nome, admin_id, codice_invito, settings jsonb, stato, stagione_corrente
teams              id, league_id, user_id, nome, stemma_url, budget, eliminata
players            id, nome, nazionalita, foto_url, overall, potential, eta,
                   posizioni text[], attributi jsonb, is_regen, is_icon
player_instances   id, league_id, player_id, team_id, overall_corrente, eta_corrente,
                   condizione, ingaggio, contratto_scadenza, infortunato_fino_a
seasons            id, league_id, numero, stato
fixtures           id, season_id, giornata, home_team_id, away_team_id, data_sim, stato
matches            id, fixture_id, gol_home, gol_away, modulo_home, modulo_away,
                   blocchi jsonb, stats_squadra jsonb
match_stats        id, match_id, player_instance_id, minuti, gol, assist, tiri,
                   tiri_porta, passaggi_t, passaggi_r, contrasti_v, contrasti_p, dribbling
lineups            id, team_id, giornata, modulo, titolari jsonb, panchina jsonb, tribuna jsonb
formation_xp       team_id, modulo, partite_giocate
transfers          id, league_id, from_team, to_team, players_out[], players_in[],
                   conguaglio, stato, creata_il, risolta_il
fa_auctions        id, league_id, giorno, player_instance_id, stato
fa_bids            id, auction_id, team_id, offerta, vinta
standings          season_id, team_id, punti, v, n, p, gf, gs, posizione
transactions       id, team_id, tipo, importo, descrizione, saldo_dopo, creata_il
```

`transactions` è un registro append-only di tutti i movimenti economici. Non è opzionale: senza, il primo bug di budget è impossibile da diagnosticare.

---

## 12. Costanti di bilanciamento

Tutte in un unico file di configurazione, modificabili senza toccare la logica.

```js
// Economia
BUDGET_INIZIALE        = 100_000_000
SPONSOR_PCT            = 0.20
PREMIO_VITTORIA_PCT    = 0.54   // / n_partite
PREMIO_PAREGGIO_PCT    = 0.27
PREMIO_SCONFITTA_PCT   = 0.135
PREMI_POSIZIONE_PCT    = 0.12   // × n_squadre
TETTO_DRAFT_PCT        = 0.80
SOGLIA_LUXURY_TAX      = 0.85
ALIQUOTA_LUXURY_TAX    = 0.60
INGAGGIO_MINIMO        = 500_000

// Motore — VALIDATI IN FASE 0, non modificare senza rilanciare la suite
BLOCCHI_PARTITA        = 6
XG_BASE_BLOCCO         = 0.252
SENSIBILITA_FORZA      = 0.090  // <- parametro piu sensibile del sistema
DIFF_CLAMP             = 10     // tetto su (ATT - DEF): l'esponenziale e illimitato
AMPLIFICA_CONTROLLO    = 1.4
BONUS_CASA_ATT         = 2.0    // PUNTI di overall
BONUS_CASA_MID         = 2.0
DIVISORE_PORTIERE      = 180
CONVERSIONE_MEDIA      = 0.105
CONVERSIONE_SIGMA      = 0.03
DAMPING_MARCATORE      = 0.45

// Tattica
K_STRUTTURA            = 2.2
STRUTT_CLAMP           = 3.5
FAM_MALUS_MAX          = 3.5    // PUNTI di overall al primo utilizzo
FAM_PARTITE_PIENA      = 15

// Condizione
CONSUMO_BASE           = 3.4
CONSUMO_MOD_STAMINA    = 1.6
REC_TRIBUNA            = 38
REC_PANCHINA           = 30
REC_GIOCATO            = 8

// Infortuni
INFORTUNIO_BASE        = 0.025
INFORTUNIO_DIV_COND    = 50
```

---

## 13. Roadmap

L'ordine è per **rischio decrescente**, non per visibilità. La tentazione sarà partire da lobby e draft perché sono le parti divertenti: sono anche quelle che sai già fare, quindi non ti dicono nulla sulla fattibilità del progetto.

### Fase 0 — Validazione del motore · ✅ **COMPLETATA — esito GO**

Script standalone Node o Python. Nessun database, nessun React, nessun login.

- Carica due rose fittizie da JSON
- Implementa le sezioni 6 e 7
- Simula 10.000 partite e 500 stagioni complete
- Verifica le distribuzioni:

| Metrica | Target |
|---|---|
| Gol/partita | 2,5 – 2,9 |
| Vittorie casa | 43 – 47% |
| Pareggi | 23 – 27% |
| Punti del vincitore (28 partite) | 58 – 68 |
| Spread punti primo/ultimo | 35 – 50 |
| Tiri/partita per squadra | 11 – 14 |
| % passaggi riusciti | 76 – 88% |

**Esito**: 13 target su 13 rientrati, dopo aver riscritto la formula xG e il modello dei
moduli (vedi note nelle sezioni 6.4 e 7.2). Codice e report in `motore-fase0/`.

### Fase 1 — Lega giocabile (3–5 settimane)

Lobby · codici invito · registrazione squadra · draft completo · schieramento formazione · calendario · cron di simulazione · classifica · statistiche.

**Niente mercato, niente contratti, niente stamina, niente progressione.**

Obiettivo: giocare una stagione intera con il gruppo. Se dopo 28 giornate hanno ancora voglia di continuare, il gioco funziona e vale la pena costruire il resto.

### Fase 2 — Profondità (2–4 settimane)

Condizione · infortuni · sostituzioni automatiche · familiarità moduli · mercato completo (trattative, aste svincolati, svincoli) · log pubblico.

### Fase 3 — Carriera (2–3 settimane)

Progressione e declino · ritiri · rinnovi contrattuali · premi posizione · gestione multi-stagione · rimozione e aggiunta squadre.

### Fase 4 — Longevità (solo dopo la stagione 4)

Giocatori generati · pool Icone · statistiche storiche e albo d'oro.

---

## 14. Rischi residui

**Bilanciamento del motore.** Non è un problema di codice ma di game design, e non si risolve delegandolo a un agent. Richiede iterazione manuale sui parametri guardando istogrammi. È la parte meno gratificante del progetto perché non produce nulla di visibile, ed è dove i progetti di questo tipo si arenano. La Fase 0 esiste esattamente per affrontarla quando l'entusiasmo è ancora al massimo.

**Ampiezza dello scope.** Questo progetto è circa 3–4 volte BeyX. La roadmap a fasi è l'unico modo per avere qualcosa di giocabile prima di esaurire la spinta.

**Collusione tra partecipanti.** Nessun sistema tecnico la impedisce in un gruppo di amici. Il log pubblico è un deterrente, non una soluzione. Se diventa un problema, l'opzione successiva è un veto: una trattativa può essere bloccata se la maggioranza delle squadre la ritiene truccata.

**Fuso orario.** Tutti i cron e le deadline vanno ancorati esplicitamente a `Europe/Rome`, non a UTC né al fuso del server. È il tipo di bug che si manifesta solo al cambio dell'ora legale, cioè nel momento peggiore.
