// ============================================================
//  MORALE — e il capitano, che senza morale non aveva niente da fare
//
//  QUANTO DEVE PESARE. La risposta non e' d'istinto, ed e' il motivo per cui
//  vale la pena scriverla. FM-Arena ha misurato il morale in Football Manager
//  su 2.880 partite, normalizzate su una stagione da 38:
//
//      morale  5 (Quite Poor)   47,1 punti
//      morale 10 (Okay)         47,3 punti
//      morale 15 (Very Good)    50,9 punti
//
//  Da scarso a molto buono: +3,8 punti su 38 partite. Nello stesso banco la
//  condizione fisica da "Fair" a "Excellent" ne vale +15,6, e la coesione di
//  squadra +6. Il morale e' quindi la piu' PICCOLA delle tre leve, circa un
//  quarto della condizione.
//
//  E' un risultato che va contro l'istinto — un giocatore demoralizzato sembra
//  dover rendere molto meno — ed e' esattamente per questo che si segue il dato
//  invece della sensazione. Tarato a occhio, il morale avrebbe schiacciato le
//  tattiche, che nello stesso metro valgono il doppio.
//
//  LA COESIONE NON SI DUPLICA. In FM il morale individuale e la coesione di
//  squadra sono due cose separate, e la seconda pesa di piu'. Da noi la
//  coesione esiste gia' ed e' la familiarita' col modulo (formation_xp): vale
//  gia' quasi un gol a partita. Qui si aggiunge solo il pezzo individuale.
//
//  COME ENTRA. Non toccando ovrEfficace: si usa il canale degli scarti
//  (lineup.tattica), lo stesso di ruoli e corsie. Il motore validato resta
//  intatto, e chi non passa il morale non vede nessuna differenza.
// ============================================================

// Il morale in player_instances va 0-100 e parte da 70. Settanta e' quindi il
// punto neutro: chi non ha mai fatto niente di particolare non deve ne'
// guadagnare ne' perdere.
export const MORALE_NEUTRO = 70;

// Punti di overall efficace a morale 100 (e -0,27 a morale 40). Tarato per
// riprodurre lo scarto di FM: vedi la prova in tools/validazione.
export const SCALA_MORALE = 0.27;

// Il morale non scende all'infinito. Un giocatore demoralizzato rende peggio,
// ma non diventa un altro giocatore: sotto questa soglia smette di peggiorare,
// come in FM dove fra "Quite Poor" e "Okay" non si misura differenza.
export const PAVIMENTO = -0.44;
export const SOFFITTO = 0.32;

/** Lo scarto di un singolo giocatore, prima del capitano. */
export function scartoMorale(morale) {
  if (typeof morale !== 'number' || !Number.isFinite(morale)) return 0;
  const g = ((morale - MORALE_NEUTRO) / 30) * SCALA_MORALE;
  return Math.max(PAVIMENTO, Math.min(SOFFITTO, g));
}

// ------------------------------------------------------------
//  IL CAPITANO
//
//  In FM il capitano non gioca meglio: tiene su lo spogliatoio. Qui fa
//  esattamente quello, e solo quello — attenua la parte NEGATIVA del morale dei
//  compagni, senza toccare quella positiva. Una squadra che gia' vola non ha
//  bisogno di un capitano; una che sta affondando si'.
//
//  E' la stessa forma che il gioco usa gia' per la mentalita' "bandiera" nei
//  rinnovi (private.applica_morale_checkpoint), dove chi e' bandiera assorbe
//  parte del malcontento. Riusarla qui tiene coerente il modo in cui questo
//  gioco descrive il carattere di un giocatore.
//
//  Chi e' un buon capitano: il suo morale e la sua freddezza
//  (mentality_composure). Non serve un attributo di leadership, che nei dati
//  FC 26 non esiste — era la ragione per cui la fascia era stata rimandata.
//
//  UN CAPITANO DEMORALIZZATO FA DANNO. Il fattore puo' andare sotto zero: se
//  chi porta la fascia e' il piu' scontento di tutti, il malcontento degli
//  altri pesa di piu', non di meno.
// ------------------------------------------------------------
export const ASSORBIMENTO_MAX = 0.45;

export function qualitaCapitano(g) {
  if (!g) return 0;
  const m = typeof g.morale === 'number' ? g.morale : MORALE_NEUTRO;
  const freddezza = typeof g.composure === 'number' ? g.composure : 60;
  // Meta' da come sta lui, meta' da che tipo e'. Entrambi normalizzati sul
  // proprio punto neutro, cosi' un capitano nella media vale zero.
  const quotaMorale = (m - MORALE_NEUTRO) / 30;
  const quotaFreddezza = (freddezza - 60) / 25;
  return Math.max(-1, Math.min(1, quotaMorale * 0.5 + quotaFreddezza * 0.5));
}

/**
 * Lo scarto di overall efficace dovuto al morale, nella forma che il motore si
 * aspetta: (giocatore) => punti. Da sommare agli altri canali con sommaDelta().
 *
 * `lineup.capitano` e' il giocatore con la fascia, se c'e'.
 */
export function deltaMorale(lineup) {
  const titolari = lineup?.titolari;
  if (!titolari?.length) return null;
  if (!titolari.some((g) => typeof g?.morale === 'number')) return null;

  const cap = lineup.capitano ?? null;
  const assorbe = cap ? qualitaCapitano(cap) * ASSORBIMENTO_MAX : 0;

  return (g) => {
    const s = scartoMorale(g?.morale);
    // Il capitano attenua solo il malcontento. Se lui stesso e' a terra,
    // assorbe negativo e lo peggiora.
    if (s < 0 && g !== cap) return s * (1 - assorbe);
    return s;
  };
}

/**
 * Chi porta la fascia se nessuno l'ha scelta: il migliore per qualita' da
 * capitano fra i titolari, a parita' il piu' esperto. Come per i piazzati,
 * chi non se ne occupa non deve accorgersi che la scelta esiste.
 */
export function capitanoAutomatico(titolari) {
  const c = (titolari || []).filter(Boolean);
  if (!c.length) return null;
  return c.reduce((best, g) => {
    const q = qualitaCapitano(g), qb = qualitaCapitano(best);
    if (q !== qb) return q > qb ? g : best;
    return (g.eta ?? 0) > (best.eta ?? 0) ? g : best;
  });
}
