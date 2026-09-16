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

/** Dove una posizione puo' andare: sale o scende di una linea, stessa corsia. */
export const SPOSTAMENTI_SLOT: Record<string, string[]> = {
  "GK": [
    "GK"
  ],
  "CB": [
    "CB",
    "CDM"
  ],
  "LB": [
    "LB",
    "LWB"
  ],
  "RB": [
    "RB",
    "RWB"
  ],
  "LWB": [
    "LWB",
    "LB",
    "LM"
  ],
  "RWB": [
    "RWB",
    "RB",
    "RM"
  ],
  "CDM": [
    "CDM",
    "CB",
    "CM"
  ],
  "CM": [
    "CM",
    "CDM",
    "CAM"
  ],
  "CAM": [
    "CAM",
    "CM",
    "ST"
  ],
  "LM": [
    "LM",
    "LWB",
    "LW"
  ],
  "RM": [
    "RM",
    "RWB",
    "RW"
  ],
  "LW": [
    "LW",
    "LM"
  ],
  "RW": [
    "RW",
    "RM"
  ],
  "ST": [
    "ST",
    "CAM"
  ]
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
    "esterno_di_rientro"
  ],
  "RM": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_di_rientro"
  ],
  "LW": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_di_rientro"
  ],
  "RW": [
    "esterno",
    "ala_pura",
    "esterno_a_rientrare",
    "esterno_di_rientro"
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
    "LWB",
    "CM",
    "CM",
    "CM",
    "RWB",
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
