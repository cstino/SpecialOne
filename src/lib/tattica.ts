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

/** I compiti, che significano cose diverse a seconda del reparto. */
export const COMPITI_REPARTO: Record<string, Record<string, { nome: string; energia: number; spostamento: number; versoDifesa?: number; idoneita?: string }>> =
  {
  "DEF": {
    "difesa": {
      "nome": "Bloccato",
      "spostamento": -0.24,
      "energia": 0.92,
      "versoDifesa": 0.15
    },
    "attacco": {
      "nome": "Si sgancia",
      "spostamento": 0.26,
      "energia": 1.18
    }
  },
  "MID": {
    "difesa": {
      "nome": "In copertura",
      "spostamento": -0.22,
      "energia": 1.05,
      "versoDifesa": 0.3
    },
    "attacco": {
      "nome": "Si inserisce",
      "spostamento": 0.24,
      "energia": 1.2
    }
  },
  "ATT": {
    "difesa": {
      "nome": "Pressa e rientra",
      "spostamento": -0.13,
      "energia": 1.35,
      "versoDifesa": 0.6,
      "idoneita": "fiato"
    },
    "attacco": {
      "nome": "Sul filo",
      "spostamento": 0.18,
      "energia": 0.9
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
