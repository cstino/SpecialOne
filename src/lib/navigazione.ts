import { createContext, useContext } from 'react'

// Ritorno alla schermata iniziale (elenco leghe) da dentro una lega.
// Passa da un contesto invece che da una prop, altrimenti andrebbe infilata
// in tutte e otto le schermate solo per arrivare a GameNav.
export const ContestoHome = createContext<(() => void) | null>(null)

export function useTornaAllaHome() {
  return useContext(ContestoHome)
}
