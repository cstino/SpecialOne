// ============================================================
//  RUOLI — quello che in Football Manager sono i player roles
//
//  Un COMPITO dice quanto un giocatore si sbilancia in avanti. Un RUOLO dice
//  DOVE va: dentro o largo. Sono due assi indipendenti, e il secondo esisteva
//  solo da quando il campo ha le corsie (engine/corsie.js).
//
//  E' la distinzione che mancava. Il terzino che si sovrappone e quello che
//  rientra a centrocampo avanzano uguale, ma lasciano scoperte due cose
//  diverse: il primo la sua fascia in profondita', il secondo la fascia e
//  basta. L'avversario puo' leggerli in modo diverso, ed e' per questo che i
//  ruoli aggiungono profondita' dove i soli compiti non ne aggiungevano
//  (registro, punti 13 e 14).
//
//  DUE NUMERI, NON UN ELENCO DI CASI. Ogni ruolo e' una coppia:
//    dentro      -1 = si allarga, +1 = rientra verso il centro
//    avanti      -1 = arretra,    +1 = si spinge in avanti
//  Cosi' un ruolo nuovo e' due numeri e una riga di commento, non un blocco di
//  codice — e si compone con i compiti invece di sovrapporsi a loro.
//
//  Gli ATTRIBUTI CHIAVE dicono chi sa interpretarlo. Come per i compiti, il
//  peso che se ne va se ne va comunque: chi non ha il profilo lascia il suo
//  posto senza portare niente dove arriva.
// ============================================================

export const RUOLI = {
  // --- difensori centrali ---
  centrale:            { per: ['CB'], dentro:  0.0, avanti:  0.0, chiave: ['tackle'] },
  centrale_marcatore:  { per: ['CB'], dentro:  0.2, avanti: -0.5, chiave: ['tackle'] },
  centrale_impostatore:{ per: ['CB'], dentro:  0.0, avanti:  0.5, chiave: ['short_passing'] },

  // --- terzini ---
  terzino:             { per: ['LB','RB','LWB','RWB'], dentro:  0.0, avanti:  0.0, chiave: ['tackle'] },
  terzino_offensivo:   { per: ['LB','RB','LWB','RWB'], dentro: -0.3, avanti:  0.8, chiave: ['dribbling'] },
  terzino_interno:     { per: ['LB','RB','LWB','RWB'], dentro:  0.8, avanti:  0.4, chiave: ['short_passing'] },
  terzino_bloccato:    { per: ['LB','RB','LWB','RWB'], dentro:  0.1, avanti: -0.6, chiave: ['tackle'] },

  // --- centrocampisti centrali ---
  mediano:             { per: ['CDM','CM','CAM'], dentro:  0.0, avanti:  0.0, chiave: ['short_passing'] },
  regista:             { per: ['CDM','CM','CAM'], dentro:  0.4, avanti: -0.2, chiave: ['short_passing'] },
  mezzala:             { per: ['CDM','CM','CAM'], dentro: -0.5, avanti:  0.4, chiave: ['dribbling'] },
  incursore:           { per: ['CDM','CM','CAM'], dentro:  0.1, avanti:  0.8, chiave: ['finishing'] },
  schermo:             { per: ['CDM','CM','CAM'], dentro:  0.3, avanti: -0.7, chiave: ['tackle'] },

  // --- esterni ---
  esterno:             { per: ['LM','RM','LW','RW'], dentro:  0.0, avanti:  0.0, chiave: ['dribbling'] },
  ala_pura:            { per: ['LM','RM','LW','RW'], dentro: -0.5, avanti:  0.4, chiave: ['dribbling'] },
  esterno_a_rientrare: { per: ['LM','RM','LW','RW'], dentro:  0.8, avanti:  0.3, chiave: ['finishing'] },
  esterno_di_rientro:  { per: ['LM','RM','LW','RW'], dentro:  0.2, avanti: -0.5, chiave: ['tackle'] },

  // --- punte ---
  punta:               { per: ['ST','CF'], dentro:  0.0, avanti:  0.0, chiave: ['finishing'] },
  finalizzatore:       { per: ['ST','CF'], dentro:  0.3, avanti:  0.4, chiave: ['finishing'] },
  punta_di_manovra:    { per: ['ST','CF'], dentro:  0.0, avanti: -0.6, chiave: ['short_passing'] },
};

/** I ruoli che uno slot puo' assumere. */
export function ruoliPerSlot(slot) {
  return Object.entries(RUOLI).filter(([, r]) => r.per.includes(slot)).map(([k]) => k);
}

/** Il ruolo di partenza di uno slot: il primo della sua famiglia. */
export function ruoloNaturale(slot) {
  const l = ruoliPerSlot(slot);
  return l.length ? l[0] : null;
}

// Quanto pesa uno spostamento pieno. Tarati per restare nello stesso ordine di
// grandezza dei compiti: un ruolo sposta quanto un compito, non di piu'.
export const SCALA_DENTRO = 0.13;
export const SCALA_AVANTI = 0.09;

/** Quanto un giocatore sa interpretare il ruolo, da -1 a +1. */
export function idoneitaRuolo(g, ruolo) {
  const r = RUOLI[ruolo];
  if (!g || !r || !r.chiave?.length) return 0;
  const suoi = r.chiave.map((k) => g[k]).filter((v) => typeof v === 'number');
  if (!suoi.length) return 0;
  const mio = suoi.reduce((a, b) => a + b, 0) / suoi.length;
  // Confronto con la sua media generale: premia chi in quella cosa e' meglio
  // di quanto sia in generale, non semplicemente chi e' piu' forte.
  const media = ((g.finishing ?? 50) + (g.short_passing ?? 50) + (g.tackle ?? 50) + (g.dribbling ?? 50)) / 4;
  return Math.max(-1, Math.min(1, (mio - media) / 12));
}

/** I pesi di corsia dopo il ruolo. */
export function corsiaConRuolo(wc, ruolo, giocatore) {
  const r = RUOLI[ruolo];
  if (!wc || !r || !r.dentro) return wc;
  const resa = 0.25 + 0.75 * ((idoneitaRuolo(giocatore, ruolo) + 1) / 2);
  const k = r.dentro * SCALA_DENTRO;
  if (k > 0) {
    // rientra: lascia la fascia e porta peso al centro, ma solo se sa starci
    return { SX: wc.SX * (1 - k), CEN: wc.CEN + (wc.SX + wc.DX) * k * resa, DX: wc.DX * (1 - k) };
  }
  const a = -k;
  // si allarga: lascia il centro e va sulla sua fascia naturale
  const versoSX = wc.SX >= wc.DX;
  return {
    SX: wc.SX + (versoSX ? wc.CEN * a * resa : 0),
    CEN: wc.CEN * (1 - a),
    DX: wc.DX + (versoSX ? 0 : wc.CEN * a * resa),
  };
}

// Quanto COSTA non saper interpretare il ruolo, in punti di overall efficace a
// inadeguatezza piena. Solo costo, mai premio: vedi deltaRuoli(). E' il pezzo che mancava: prima l'idoneita' governava solo
// come il peso si smistava fra le corsie, cioe' una cosa che LEGGE L'AVVERSARIO
// e non il rendimento di chi gioca. Il risultato era un ruolo che rendeva
// uguale a chiunque lo si desse, che e' esattamente il contrario di come
// funziona in Football Manager: li' la resa di un giocatore dipende da quanto
// il ruolo gli somiglia.
export const VALORE_IDONEITA = 2.0;

/**
 * Lo scarto di overall efficace dovuto ai ruoli, nella forma che il motore si
 * aspetta: (giocatore, slot) => punti. Si somma agli altri canali tattici.
 *
 * Vale solo per i titolari, e per posizione: chi entra dal cambio eredita il
 * ruolo dello slot in cui entra, non quello di chi esce — e' la posizione in
 * campo ad avere un ruolo, non la persona.
 */
export function deltaRuoli(lineup) {
  const ruoli = lineup?.ruoli;
  if (!ruoli || !ruoli.some(Boolean)) return null;
  const perSlot = new Map();
  (lineup.titolari || []).forEach((g, i) => { if (g && ruoli[i]) perSlot.set(i, ruoli[i]); });
  if (!perSlot.size) return null;
  // Indice di slot per giocatore: il motore passa (g, slot) e lo slot e' il
  // nome della posizione, che in un modulo puo' ripetersi (due CB, due CM).
  // Si tiene quindi l'associazione per identita' del giocatore.
  const perGiocatore = new Map();
  (lineup.titolari || []).forEach((g, i) => { if (g && ruoli[i]) perGiocatore.set(g, ruoli[i]); });
  return (g) => {
    const r = perGiocatore.get(g);
    if (!r) return 0;
    // SOLO PENALITA', mai bonus. In FC un giocatore in un ruolo che non gli
    // appartiene paga il 10% sulle statistiche difensive; non esiste un premio
    // per il ruolo azzeccato. La ragione e' di disegno, non di realismo: se il
    // ruolo giusto desse un bonus, chi non entra nella schermata partirebbe in
    // svantaggio — e le tattiche devono restare una cosa che si puo' ignorare
    // senza essere puniti.
    //
    // Il valore tattico di un ruolo non sta qui: sta in DOVE mette il
    // giocatore (corsiaConRuolo, avanzamentoRuolo), che e' una scelta a due
    // facce. Questo canale dice solo se sa eseguirlo.
    return Math.min(0, idoneitaRuolo(g, r)) * VALORE_IDONEITA;
  };
}

/** Somma piu' canali tattici in un solo scarto. */
export function sommaDelta(...fn) {
  const attivi = fn.filter(Boolean);
  if (!attivi.length) return undefined;
  if (attivi.length === 1) return attivi[0];
  return (g, slot) => attivi.reduce((t, f) => t + f(g, slot), 0);
}

/** Lo spostamento di linea che il ruolo aggiunge al compito. */
export function avanzamentoRuolo(ruolo) {
  const r = RUOLI[ruolo];
  return r ? r.avanti * SCALA_AVANTI : 0;
}
