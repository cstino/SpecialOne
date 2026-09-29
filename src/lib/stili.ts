// ============================================================
//  STILI DI GIOCO — nomi e descrizioni per l'interfaccia
// ============================================================

// Le stesse 7 chiavi di engine/config.js STILI e private.stili_validi() lato DB
// (sync a mano, stesso pattern gia' in uso per MODULI/moduli_validi()).
export const STILI: string[] = ['equilibrato', 'contropiede', 'possesso_palla', 'fasce', 'recupero_veloce', 'diretto', 'blocco_basso']

export const STILE_LABEL: Record<string, string> = {
  equilibrato: 'EQUILIBRATO',
  contropiede: 'CONTROPIEDE',
  possesso_palla: 'POSSESSO PALLA',
  fasce: 'GIOCO SULLE FASCE',
  recupero_veloce: 'RECUPERO VELOCE',
  diretto: 'GIOCO DIRETTO',
  blocco_basso: 'DIFESA A OLTRANZA',
}

export const STILE_DESCRIZIONI: Record<string, string> = {
  equilibrato: 'Nessun aggiustamento tattico.',
  contropiede: 'Difensivo e attendista, sfrutta le occasioni in ripartenza.',
  possesso_palla: 'Dominio del centrocampo e del possesso.',
  fasce: 'Veloce sulle corsie, cross e ampiezza.',
  recupero_veloce: 'Difesa alta e pressing per riconquistare la palla.',
  diretto: 'Verticale, salta il centrocampo, punta sulla profondità.',
  blocco_basso: 'Massima solidità difensiva, rischia il minimo indispensabile.',
}
