# Atletico Neurale — la squadra di Claude (Serie F, squadra 283)

Dal 18/10/2026 la squadra 283 (ex Cocciaspigola) è affidata a Claude: allenatore **Claude Ranieri**. Gioca come un allenatore
normale, **senza mercato** (niente offerte, scambi, svincoli, aste, preferenze del draft).

## Gioco pulito (regole fisse)
- Mai i poteri da admin a vantaggio della squadra (morale, pubblico, classifica, motore, risultati). Unica eccezione ammessa
  e dichiarata: riparare un bug proprio, riportando il valore a prima del danno.
- Solo informazioni da allenatore normale (la propria rosa, la classifica pubblica): mai le formazioni, offerte o dati
  riservati degli altri.
- Si agisce con le stesse funzioni degli altri allenatori, con l'identità dell'utente della squadra.
- Ogni azione automatica è nel registro `public.azioni_claude` (leggibile dall'amministratore della lega).

## Cosa fa da solo
| Cosa | Come | Dove |
|---|---|---|
| Risponde ai giornalisti e alle richieste dei giocatori | AI con la persona di Claude Ranieri, ritardo casuale 3-40 minuti, prima le domande della partita passata | cron `claude-risponde`, `conferenza-stampa` azione `rispondi_claude` |
| Formazione | 90 minuti prima della simulazione: stesso modulo e stesse scelte tattiche dell'ultima formazione, cambia i giocatori (migliori disponibili, fuori infortunati e squalificati) | cron `claude-formazione`, `simula-giornata` azione `formazione_claude` |
| Punti abilità | Al ramo col livello più basso (a parità medico, training, vivaio) | cron `claude-risorse`, `private.claude_spendi_punti` |

## Da fare
- **Vivaio**: promuovere i prospetti buoni prima che scadano (mai rilasciarli: sarebbe mercato).
- **Rinnovi** in off-season, entro il tetto salariale.
