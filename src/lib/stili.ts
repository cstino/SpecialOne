// ============================================================
//  STILI DI GIOCO — nomi e descrizioni per l'interfaccia
// ============================================================

// Le stesse 8 chiavi di engine/config.js STILI e private.stili_validi() lato DB
// (sync a mano, stesso pattern gia' in uso per MODULI/moduli_validi()).
export const STILI: string[] = ['equilibrato', 'contropiede', 'possesso_palla', 'fasce', 'recupero_veloce', 'diretto', 'blocco_basso', 'personalizzato']

export const STILE_LABEL: Record<string, string> = {
  equilibrato: 'EQUILIBRATO',
  contropiede: 'CONTROPIEDE',
  possesso_palla: 'POSSESSO PALLA',
  fasce: 'GIOCO SULLE FASCE',
  recupero_veloce: 'RECUPERO VELOCE',
  diretto: 'GIOCO DIRETTO',
  blocco_basso: 'DIFESA A OLTRANZA',
  personalizzato: 'PERSONALIZZATO',
}

export const STILE_DESCRIZIONI: Record<string, string> = {
  equilibrato: 'Nessun aggiustamento tattico.',
  contropiede: 'Difensivo e attendista, sfrutta le occasioni in ripartenza.',
  possesso_palla: 'Dominio del centrocampo e del possesso.',
  fasce: 'Veloce sulle corsie, cross e ampiezza.',
  recupero_veloce: 'Difesa alta e pressing per riconquistare la palla.',
  diretto: 'Verticale, salta il centrocampo, punta sulla profondità.',
  blocco_basso: 'Massima solidità difensiva, rischia il minimo indispensabile.',
  personalizzato: 'Scegli tu linea, ampiezza, velocità di manovra e dove attaccare.',
}

// Cosa implica ogni stile preimpostato sulle altre indicazioni. Sotto uno stile
// preimpostato quelle sezioni sono bloccate e mostrano questi valori (solo
// informativi: nel motore vale l'effetto dello stile). Passando a Personalizzato
// si parte da qui. null = l'opzione predefinita.
export type AssiStile = { linea: string | null; ampiezza: string | null; velocita: string | null; focus: string | null }
export const ASSI_STILE: Record<string, AssiStile> = {
  equilibrato:     { linea: null,    ampiezza: null,      velocita: null,        focus: null },
  contropiede:     { linea: 'bassa', ampiezza: 'stretta', velocita: 'veloce',    focus: null },
  possesso_palla:  { linea: 'alta',  ampiezza: 'stretta', velocita: 'ragionata', focus: null },
  fasce:           { linea: null,    ampiezza: 'larga',   velocita: null,        focus: 'FASCE' },
  recupero_veloce: { linea: 'alta',  ampiezza: null,      velocita: 'veloce',    focus: null },
  diretto:         { linea: null,    ampiezza: null,      velocita: 'veloce',    focus: null },
  blocco_basso:    { linea: 'bassa', ampiezza: 'stretta', velocita: 'ragionata', focus: null },
  personalizzato:  { linea: null,    ampiezza: null,      velocita: null,        focus: null },
}
export const assiDelloStile = (stile: string): AssiStile => ASSI_STILE[stile] ?? ASSI_STILE.equilibrato
