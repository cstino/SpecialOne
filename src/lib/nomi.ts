// Il dataset FC 26 usa il nome puntato ("J. Bellingham"). Nell'interfaccia mostriamo
// il cognome da solo: si legge a colpo d'occhio e sta nello spazio di una casella.
//
// "J. Bellingham" -> "Bellingham"   (via l'iniziale puntata)
// "J. C. Rodríguez" -> "Rodríguez"  (via tutte le iniziali)
// "O. El Hilali" -> "El Hilali"     (cognome composto conservato)
// "David Soria" -> "Soria"          (nessuna iniziale: cade il nome proprio)
// "Rodri" -> "Rodri"                (mononimo invariato)
export function cognome(nome: string) {
  const parti = nome.trim().split(/\s+/)
  while (parti.length > 1 && /^\p{L}\.$/u.test(parti[0])) parti.shift()
  if (parti.length > 1 && !nome.includes('.')) return parti[parti.length - 1]
  return parti.join(' ')
}

const senzaAccenti = (testo: string) => testo.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim()

/**
 * Il nome per la scheda giocatore: nome di battesimo piccolo sopra, cognome grande
 * (richiesta del 4 ottobre 2026). `breve` e' il nome del dataset ("K. Nedeljkovic",
 * o gia' il solo cognome), `esteso` il long_name ("Kosta Nedeljkovic"): il cognome
 * si toglie dalla fine dell'esteso senza badare agli accenti. Se non c'e' l'esteso
 * (giocatori generati) resta il nome breve; se il cognome non si trova in fondo
 * (mononimi come "Rodri") il nome esteso intero va sopra, al posto del nome di
 * battesimo. Al massimo due nomi di battesimo, per non allungare la riga.
 */
export function nomeSuDueRighe(breve: string, esteso?: string | null): { nome: string | null; cognome: string } {
  const cogn = cognome(breve)
  if (!esteso) return { nome: null, cognome: breve }
  const parti = esteso.trim().split(/\s+/)
  const cognParti = cogn.split(/\s+/).length
  const coda = parti.slice(-cognParti).join(' ')
  let nome: string
  if (parti.length > cognParti && senzaAccenti(coda) === senzaAccenti(cogn)) {
    nome = parti.slice(0, -cognParti).slice(0, 2).join(' ')
  } else {
    nome = senzaAccenti(esteso) === senzaAccenti(cogn) ? '' : parti.slice(0, 3).join(' ')
  }
  return { nome: nome || null, cognome: cogn }
}
