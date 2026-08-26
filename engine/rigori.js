// ============================================================
//  CALCI DI RIGORE  (design §10.7)
//
//  NON fa parte del nucleo validato in Fase 0: la suite di
//  tools/validazione non lo importa e nessuna formula di engine.js viene
//  toccata. E' logica nuova, usata soltanto dalle eliminatorie di
//  playoff e playout quando la parita' resiste ai supplementari.
//
//  Sta in engine/ per un motivo pratico: la Edge Function importa gia' da
//  qui, e i rigori hanno bisogno dello stesso RNG seeded per essere
//  riproducibili da un seed di fixture come il resto della partita.
// ============================================================

import { rnd } from './random.js';

export const CFG_RIGORI = {
  // 0,76 e' la percentuale di realizzazione reale nei tie-break dei tornei
  // europei. Il termine lineare sposta di ~4 punti percentuali ogni 10 punti
  // di overall di scarto fra tiratore e portiere.
  BASE: 0.76,
  K_SCARTO: 0.004,
  MIN: 0.55,
  MAX: 0.95,
  SERIE: 5,
  // Limite di sicurezza: a oltranza due squadre identiche possono teoricamente
  // non chiudere mai. Oltre questa soglia decide il sorteggio, come l'antica
  // monetina. Non e' mai stato raggiunto nei test (max osservato: 15 serie).
  MAX_SERIE: 50,
};

export function probabilitaRigore(ovrTiratore, ovrPortiere) {
  // Senza questo controllo un overall mancante produce NaN, e `rnd() < NaN` e'
  // sempre falso: la sequenza diventa uno 0-0 infinito invece di segnalare il
  // problema. Meglio rompere subito e forte.
  if (!Number.isFinite(ovrTiratore) || !Number.isFinite(ovrPortiere)) {
    throw new TypeError(`Overall non valido ai rigori: tiratore=${ovrTiratore}, portiere=${ovrPortiere}`);
  }
  const p = CFG_RIGORI.BASE + CFG_RIGORI.K_SCARTO * (ovrTiratore - ovrPortiere);
  return Math.min(CFG_RIGORI.MAX, Math.max(CFG_RIGORI.MIN, p));
}

// Chi tira: i giocatori di MOVIMENTO ancora in campo alla fine della partita,
// dal miglior overall al peggiore. Il portiere e' escluso dalla lista tiratori
// (para, non tira) e chi e' uscito per infortunio o sostituzione non c'e' piu'.
export function tiratoriDaLineup(lineup) {
  const fuori = [];
  for (let i = 0; i < lineup.titolari.length; i++) {
    const g = lineup.titolari[i];
    if (!g || lineup.slots[i] === 'GK') continue;
    fuori.push({ id: g.id, nome: g.nome, ovr: g.ovr });
  }
  return fuori.sort((a, b) => b.ovr - a.ovr || a.id - b.id);
}

export function portiereDaLineup(lineup) {
  const i = lineup.slots.indexOf('GK');
  const g = i >= 0 ? lineup.titolari[i] : null;
  return g ? { id: g.id, nome: g.nome, ovr: g.ovr } : { id: null, nome: '—', ovr: 70 };
}

// Decisione matematica: una squadra ha gia' vinto se il suo punteggio supera il
// massimo che l'altra puo' ancora raggiungere con i tiri che le restano.
function giaDecisa(golA, golB, restantiA, restantiB) {
  return golA > golB + restantiB || golB > golA + restantiA;
}

/**
 * Sequenza completa dai dischetti.
 *
 * @param squadraA  { tiratori: [{id,nome,overall}], portiere: {overall}, lato: 'casa'|'ospite' }
 * @param squadraB  idem
 * @param opt.primaSquadra  'A' | 'B' — chi apre. Se assente si sorteggia, come la monetina.
 * @returns { golA, golB, vincitore: 'A'|'B', serie: [...], sorteggio: bool }
 */
export function calciaRigori(squadraA, squadraB, opt = {}) {
  const prima = opt.primaSquadra ?? (rnd() < 0.5 ? 'A' : 'B');
  const primo = prima === 'A' ? squadraA : squadraB;
  const secondo = prima === 'A' ? squadraB : squadraA;

  let golPrimo = 0, golSecondo = 0;
  const serie = [];
  let indice = 0;

  const tira = (squadra, avversaria, numero) => {
    const lista = squadra.tiratori;
    // Esaurita la lista si riparte dal primo: nel calcio vero, a oltranza,
    // ricomincia il giro degli undici rimasti in campo.
    const tiratore = lista.length ? lista[indice % lista.length] : { id: null, nome: '—', ovr: 70 };
    const p = probabilitaRigore(tiratore.ovr, avversaria.portiere.ovr);
    const segnato = rnd() < p;
    serie.push({
      numero,
      lato: squadra.lato,
      tiratoreId: tiratore.id,
      tiratore: tiratore.nome,
      segnato,
    });
    return segnato;
  };

  for (let n = 1; n <= CFG_RIGORI.MAX_SERIE; n++) {
    const oltranza = n > CFG_RIGORI.SERIE;
    // Nelle prime cinque serie i tiri restanti calano a ogni turno; a oltranza
    // ogni serie e' a se stante, quindi entrambe hanno sempre un tiro a testa.
    const restantiPrimo = oltranza ? 1 : CFG_RIGORI.SERIE - n + 1;
    const restantiSecondo = restantiPrimo;
    indice = n - 1;

    if (tira(primo, secondo, n)) golPrimo++;
    // La squadra che tira per seconda calcia solo se il risultato non e' gia'
    // deciso: e' il rigore "inutile" che nel calcio vero non si batte.
    if (giaDecisa(golPrimo, golSecondo, restantiPrimo - 1, restantiSecondo)) break;

    if (tira(secondo, primo, n)) golSecondo++;
    if (giaDecisa(golPrimo, golSecondo, restantiPrimo - 1, restantiSecondo - 1)) break;
  }

  let sorteggio = false;
  if (golPrimo === golSecondo) {
    // Sicurezza teorica, vedi MAX_SERIE.
    sorteggio = true;
    if (rnd() < 0.5) golPrimo++; else golSecondo++;
  }

  const primoHaVinto = golPrimo > golSecondo;
  return {
    golA: prima === 'A' ? golPrimo : golSecondo,
    golB: prima === 'A' ? golSecondo : golPrimo,
    vincitore: primoHaVinto === (prima === 'A') ? 'A' : 'B',
    primaSquadra: prima,
    serie,
    sorteggio,
  };
}
