# Reparto medico — effetti per livello

Tre effetti, tutti dalla funzione `private.effetti_ramo('medico', livello)`:

| Effetto | Formula | Max (livello 10) |
|---|---|---|
| Rischio infortuni (`riduzione_infortuni_pct`) | (livello / 2) × 6 %, sale ai livelli pari | −30% |
| Recupero post-partita (`riduzione_calo_residuo_pct`) | ((livello + 1) / 2) × 8 %, sale ai livelli dispari | +40% |
| **Guarigione** (`recupero_infortuni_pct`), dal 18/10/2026 | livello × 3 % | 30% a giornata |

**Guarigione.** A ogni giornata un infortunato ha questa probabilità di rientrare UNA giornata prima del conto alla rovescia
normale (−1 a giornata). Vale anche per gli infortuni già in corso (dalla giornata successiva al punto speso); non accorcia mai un
infortunio nuovo nel momento in cui avviene. Deciso con il committente; implementato in `aggiorna_condizione_rosa` (migrazione
`20261018280000`) senza toccare il motore di simulazione. La durata dell'infortunio resta decisa a sorte quando avviene
(60% 1-2 giornate, 30% 3-6, 10% 8-15, poi riscalata sulla lunghezza della stagione).
