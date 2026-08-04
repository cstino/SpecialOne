# Dataset FC 26

- Fonte: [FC 26 (FIFA 26) Player Data — rovnez](https://www.kaggle.com/datasets/rovnez/fc-26-fifa-26-player-data)
- Snapshot: 21 settembre 2025 (`FC26_20250921.csv`)
- Licenza dichiarata dal dataset: CC BY 4.0
- Origine dichiarata: scraping di SoFIFA
- SHA-256 archivio usato: `a58223323b824376f69e912912947754b108a20d241d5bb22fdd19c54e5c5c3b`
- SHA-256 CSV usato: `4399cb2bcc2a14a2872e76a118f8f4bf64d7954503949c75751a14f33863e3b2`

La selezione usa gli identificativi numerici dei campionati e produce 5.416 giocatori
appartenenti a 192 club:

| Campionato | Giocatori |
|---|---:|
| Premier League | 547 |
| La Liga | 554 |
| Serie A | 565 |
| Bundesliga | 525 |
| Ligue 1 | 488 |
| Eredivisie | 526 |
| Liga Portugal | 522 |
| Süper Lig | 469 |
| Saudi Pro League | 536 |
| EFL Championship | 684 |

Il file grezzo non viene distribuito nel repository. Le foto non sono usate in hotlink:
lo script separato le ridimensiona e le carica nel bucket privato Supabase.

## Pool élite globale

Il 4 agosto 2026 sono stati aggiunti **576** giocatori dai campionati non
inclusi nel pool base: **355** con overall `>= 75` e **221** under 22 con
overall `67–74`. I giovani sono limitati alle stesse leghe esterne che hanno
almeno un giocatore da 75+. Restano etichettati con il campionato reale, ma il
flag `elite_globale` li rende estraibili in ogni lega. Le 20 righe del dataset
senza campionato non sono state importate.
