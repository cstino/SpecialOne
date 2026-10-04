// ============================================================
//  TAVOLE TATTICHE — copia per il frontend
//
//  Il motore e' JavaScript senza tipi e il build del frontend non lo importa:
//  la convenzione gia' in uso in questo progetto e' tenerne una copia a mano
//  (vedi MODULI in Formazione.tsx). Questo file e' GENERATO da
//  engine/config.js e engine/ruoli.js — se cambiano la', va rigenerato.
//
//  Le stesse tavole esistono anche in SQL (private.spostamenti_slot,
//  private.ruoli_slot), generate dalla stessa fonte.
// ============================================================

/** Dentro la propria linea: una posizione non cambia reparto, o cambierebbe il modulo. */
export const SPOSTAMENTI_SLOT: Record<string, string[]> = {
  "CB": [
    "CB",
    "LB",
    "RB"
  ],
  "LB": [
    "LB",
    "LWB",
    "CB"
  ],
  "RB": [
    "RB",
    "RWB",
    "CB"
  ],
  "LWB": [
    "LWB",
    "LB"
  ],
  "RWB": [
    "RWB",
    "RB"
  ],
  "CDM": [
    "CDM",
    "CM"
  ],
  "CM": [
    "CM",
    "CDM",
    "CAM",
    "LM",
    "RM"
  ],
  "CAM": [
    "CAM",
    "CM"
  ],
  "LM": [
    "LM",
    "CM"
  ],
  "RM": [
    "RM",
    "CM"
  ],
  "LW": [
    "LW",
    "ST"
  ],
  "RW": [
    "RW",
    "ST"
  ],
  "ST": [
    "ST",
    "LW",
    "RW"
  ],
  "GK": [
    "GK"
  ]
}

/** In quale linea sta ogni posizione. */
export const REPARTO: Record<string, string> = {
  "GK": "GK",
  "CB": "DEF",
  "LB": "DEF",
  "RB": "DEF",
  "LWB": "DEF",
  "RWB": "DEF",
  "CDM": "MID",
  "CM": "MID",
  "CAM": "MID",
  "LM": "MID",
  "RM": "MID",
  "LW": "ATT",
  "RW": "ATT",
  "ST": "ATT",
  "CF": "ATT"
}

/** Quanto una posizione sta a destra (+1) o a sinistra (-1). Da PESI_CORSIA. */
export const CORSIA_X: Record<string, number> = {
  "GK": 0,
  "CB": 0,
  "LB": -0.85,
  "RB": 0.85,
  "LWB": -0.9,
  "RWB": 0.9,
  "CDM": 0,
  "CM": 0,
  "CAM": 0,
  "LM": -0.8,
  "RM": 0.8,
  "LW": -0.8,
  "RW": 0.8,
  "ST": 0,
  "CF": 0
}

/** I ruoli che ogni posizione puo' interpretare. Da engine/ruoli.js. */
export const RUOLI_SLOT: Record<string, string[]> = {
  "GK": [],
  "CB": [
    "centrale",
    "centrale_marcatore",
    "centrale_impostatore"
  ],
  "LB": [
    "terzino",
    "terzino_offensivo",
    "terzino_interno",
    "terzino_bloccato"
  ],
  "RB": [
    "terzino",
    "terzino_offensivo",
    "terzino_interno",
    "terzino_bloccato"
  ],
  "LWB": [
    "terzino",
    "terzino_offensivo",
    "terzino_interno",
    "terzino_bloccato"
  ],
  "RWB": [
    "terzino",
    "terzino_offensivo",
    "terzino_interno",
    "terzino_bloccato"
  ],
  "CDM": [
    "mediano",
    "regista",
    "mezzala",
    "incursore",
    "schermo"
  ],
  "CM": [
    "mediano",
    "regista",
    "mezzala",
    "incursore",
    "schermo"
  ],
  "CAM": [
    "mediano",
    "regista",
    "mezzala",
    "incursore",
    "schermo"
  ],
  "LM": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_difensivo"
  ],
  "RM": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_difensivo"
  ],
  "LW": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_difensivo"
  ],
  "RW": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_difensivo"
  ],
  "ST": [
    "punta",
    "finalizzatore",
    "punta_di_manovra"
  ],
  "CF": [
    "punta",
    "finalizzatore",
    "punta_di_manovra"
  ]
}

/** I compiti, che significano cose diverse a seconda del reparto. */
export const COMPITI_REPARTO: Record<string, Record<string, { nome: string; energia: number }>> =
  {
  "DEF": {
    "difesa": {
      "nome": "Bloccato",
      "energia": 0.96
    },
    "attacco": {
      "nome": "Si sgancia",
      "energia": 1.07
    }
  },
  "MID": {
    "difesa": {
      "nome": "In copertura",
      "energia": 1.02
    },
    "attacco": {
      "nome": "Si inserisce",
      "energia": 1.08
    }
  },
  "ATT": {
    "difesa": {
      "nome": "Pressing alto",
      "energia": 1.06
    },
    "attacco": {
      "nome": "Sul filo",
      "energia": 0.95
    }
  }
}

export const COMPITI: string[] = ["difesa","equilibrio","attacco"]

/** Partite con lo stesso schieramento per riempire una barra. CFG.FAM_PARTITE_PIENA. */
export const FAM_PARTITE_PIENA = 5

export const MODULI: Record<string, string[]> = {
  "4-3-3": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "CM",
    "CM",
    "CM",
    "LW",
    "ST",
    "RW"
  ],
  "4-3-3 offensivo": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "CM",
    "CM",
    "CAM",
    "LW",
    "ST",
    "RW"
  ],
  "4-3-3 difensivo": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "CM",
    "CM",
    "CDM",
    "LW",
    "ST",
    "RW"
  ],
  "4-4-2": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "LM",
    "CM",
    "CM",
    "RM",
    "ST",
    "ST"
  ],
  "4-2-3-1": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "CDM",
    "CDM",
    "CAM",
    "LW",
    "RW",
    "ST"
  ],
  "3-5-2": [
    "GK",
    "CB",
    "CB",
    "CB",
    "LM",
    "CM",
    "CDM",
    "CM",
    "RM",
    "ST",
    "ST"
  ],
  "3-4-3": [
    "GK",
    "CB",
    "CB",
    "CB",
    "LM",
    "CM",
    "CM",
    "RM",
    "LW",
    "ST",
    "RW"
  ],
  "5-3-2": [
    "GK",
    "LB",
    "CB",
    "CB",
    "CB",
    "RB",
    "CM",
    "CM",
    "CM",
    "ST",
    "ST"
  ],
  "4-2-4": [
    "GK",
    "LB",
    "CB",
    "CB",
    "RB",
    "CM",
    "CM",
    "LW",
    "ST",
    "ST",
    "RW"
  ]
}

// Come FC: "++" e "+" per chi rende di piu', "−" per chi rende di meno. Le
// soglie tagliano il 18% circa dei colleghi per fascia agli estremi
// (tools/validazione/taratura-ruoli.mjs). Li mostra la formazione, sulle magliette.
export function segnoIdoneita(v: number): { segno: string; tono: 'piu' | 'meno' } | null {
  if (v >= 0.6) return { segno: '++', tono: 'piu' }
  if (v >= 0.25) return { segno: '+', tono: 'piu' }
  if (v <= -0.6) return { segno: '−−', tono: 'meno' }
  if (v <= -0.25) return { segno: '−', tono: 'meno' }
  return null
}

// --- IDONEITA' AI RUOLI: generato da tools/validazione/taratura-ruoli.mjs ---
export const PROFILI_RUOLI: Record<string, string[]> = {
  "centrale_marcatore": [
    "defending_marking_awareness",
    "standing_tackle",
    "power_strength",
    "attacking_heading_accuracy"
  ],
  "centrale_impostatore": [
    "short_passing",
    "skill_long_passing",
    "mentality_vision",
    "mentality_composure"
  ],
  "terzino_offensivo": [
    "attacking_crossing",
    "movement_sprint_speed",
    "dribbling",
    "movement_acceleration"
  ],
  "terzino_interno": [
    "short_passing",
    "skill_ball_control",
    "mentality_vision",
    "mentality_interceptions"
  ],
  "terzino_bloccato": [
    "defending_marking_awareness",
    "standing_tackle",
    "mentality_interceptions",
    "power_strength"
  ],
  "regista": [
    "mentality_vision",
    "skill_long_passing",
    "short_passing",
    "mentality_composure"
  ],
  "mezzala": [
    "dribbling",
    "skill_ball_control",
    "short_passing",
    "movement_agility"
  ],
  "incursore": [
    "mentality_positioning",
    "finishing",
    "movement_acceleration",
    "power_long_shots"
  ],
  "schermo": [
    "mentality_interceptions",
    "standing_tackle",
    "defending_marking_awareness",
    "mentality_aggression"
  ],
  "ala_pura": [
    "movement_sprint_speed",
    "movement_acceleration",
    "attacking_crossing",
    "dribbling"
  ],
  "esterno_a_rientrare": [
    "finishing",
    "skill_curve",
    "dribbling",
    "movement_agility"
  ],
  "esterno_difensivo": [
    "standing_tackle",
    "mentality_interceptions",
    "movement_sprint_speed",
    "defending_marking_awareness"
  ],
  "finalizzatore": [
    "finishing",
    "mentality_positioning",
    "movement_reactions",
    "mentality_composure"
  ],
  "punta_di_manovra": [
    "short_passing",
    "mentality_vision",
    "skill_ball_control",
    "power_strength"
  ]
}

const ATTRIBUTI_GENERALI: string[] = ["defending_marking_awareness","standing_tackle","power_strength","attacking_heading_accuracy","short_passing","skill_long_passing","mentality_vision","mentality_composure","attacking_crossing","movement_sprint_speed","dribbling","movement_acceleration","skill_ball_control","mentality_interceptions","movement_agility","mentality_positioning","finishing","power_long_shots","mentality_aggression","skill_curve","movement_reactions"]

export const TARATURA_RUOLI: Record<string, { atteso: number; pendenza: number; deviazione: number }> = {
  centrale_marcatore: { atteso: 11.71, pendenza: 0.363, deviazione: 3.93 },
  centrale_impostatore: { atteso: 2.13, pendenza: 0.284, deviazione: 3.51 },
  terzino_offensivo: { atteso: 5.81, pendenza: -0.260, deviazione: 3.84 },
  terzino_interno: { atteso: 1.63, pendenza: 0.164, deviazione: 1.94 },
  terzino_bloccato: { atteso: 1.64, pendenza: -0.071, deviazione: 3.82 },
  regista: { atteso: 4.68, pendenza: 0.244, deviazione: 2.56 },
  mezzala: { atteso: 5.07, pendenza: 0.028, deviazione: 3.65 },
  incursore: { atteso: -1.89, pendenza: -0.004, deviazione: 5.19 },
  schermo: { atteso: -2.15, pendenza: -0.063, deviazione: 9.26 },
  ala_pura: { atteso: 10.65, pendenza: -0.120, deviazione: 4.33 },
  esterno_a_rientrare: { atteso: 8.15, pendenza: 0.096, deviazione: 4.00 },
  esterno_difensivo: { atteso: -14.11, pendenza: -0.305, deviazione: 7.93 },
  finalizzatore: { atteso: 9.72, pendenza: 0.409, deviazione: 2.91 },
  punta_di_manovra: { atteso: 6.79, pendenza: 0.175, deviazione: 3.07 },
}

const mediaAttributi = (a: Record<string, number | null | undefined>, chiavi: string[]): number | null => {
  let somma = 0
  for (const k of chiavi) {
    const v = a[k]
    if (typeof v !== 'number' || !Number.isFinite(v)) return null
    somma += v
  }
  return somma / chiavi.length
}

/** Stessa formula di idoneitaRuolo in engine/ruoli.js: da -1 a +1, 0 se ruolo base o dati mancanti. */
export function idoneitaRuolo(attributi: Record<string, number | null | undefined> | null | undefined, overall: number, ruolo: string): number {
  const profilo = PROFILI_RUOLI[ruolo]
  const t = TARATURA_RUOLI[ruolo]
  if (!attributi || !profilo || !t) return 0
  const suo = mediaAttributi(attributi, profilo)
  const generale = mediaAttributi(attributi, ATTRIBUTI_GENERALI)
  if (suo === null || generale === null) return 0
  const atteso = t.atteso + t.pendenza * (overall - 75)
  return Math.max(-1, Math.min(1, (suo - generale - atteso) / (t.deviazione * 1.5)))
}
// --- fine idoneita' ai ruoli ---
