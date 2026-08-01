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
