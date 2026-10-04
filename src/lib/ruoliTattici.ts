// I nomi che l'utente legge. Le chiavi sono quelle del motore (engine/ruoli.js):
// tenerle separate dalle etichette permette di cambiare parole senza toccare
// una taratura.
export const RUOLO_LABEL: Record<string, { nome: string; detto: string }> = {
  centrale: { nome: 'Centrale', detto: 'Tiene la posizione e non si scopre.' },
  centrale_marcatore: { nome: 'Marcatore', detto: 'Più basso e aggressivo sull’uomo.' },
  centrale_impostatore: { nome: 'Impostatore', detto: 'Fa partire l’azione da dietro.' },
  terzino: { nome: 'Terzino', detto: 'Copre la fascia senza esporsi.' },
  terzino_offensivo: { nome: 'Fluidificante', detto: 'Si allarga e si sovrappone.' },
  terzino_interno: { nome: 'Terzino interno', detto: 'Rientra dentro: rinforza il centro, lascia la fascia.' },
  terzino_bloccato: { nome: 'Terzino bloccato', detto: 'Resta dietro, non accompagna mai.' },
  mediano: { nome: 'Mediano', detto: 'Fa legna e smista, senza sbilanciarsi.' },
  regista: { nome: 'Regista', detto: 'Gioca stretto e detta i tempi.' },
  mezzala: { nome: 'Mezzala', detto: 'Si allarga verso la fascia e accompagna.' },
  incursore: { nome: 'Incursore', detto: 'Attacca l’area senza palla.' },
  schermo: { nome: 'Schermo', detto: 'Davanti alla difesa e basta.' },
  esterno: { nome: 'Esterno', detto: 'Tiene la fascia in entrambe le fasi.' },
  ala_pura: { nome: 'Ala pura', detto: 'Larghissima, salta l’uomo e crossa.' },
  esterno_a_rientrare: { nome: 'A rientrare', detto: 'Converge dentro per calciare.' },
  esterno_difensivo: { nome: 'Esterno difensivo', detto: 'Raddoppia sul terzino avversario e copre la fascia.' },
  punta: { nome: 'Punta', detto: 'Gioca sul filo e attacca la porta.' },
  finalizzatore: { nome: 'Finalizzatore', detto: 'Vive in area, tocca poco e segna.' },
  punta_di_manovra: { nome: 'Punta di manovra', detto: 'Scende a legare il gioco.' },
}
