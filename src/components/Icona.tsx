// Icone dei pulsanti rotondi. I caratteri "‹", "›" e "×" non stanno al centro
// del loro spazio (ognuno ha la sua linea di base e i suoi margini laterali), e
// dentro un cerchio lo scarto si vede. Un tracciato SVG in un quadrato 24×24 e'
// centrato per costruzione.
const TRACCIATI = {
  indietro: 'M14.5 5.5 8 12l6.5 6.5',
  avanti: 'M9.5 5.5 16 12l-6.5 6.5',
  chiudi: 'M6.5 6.5l11 11M17.5 6.5l-11 11',
  giu: 'M5.5 9 12 15.5 18.5 9',
  // piano di sviluppo attivo: un manubrio
  allenamento: 'M3.5 10v4M6.5 7.5v9M17.5 7.5v9M20.5 10v4M6.5 12h11',
  // cambio ruolo in corso: due frecce opposte
  cambio: 'M5 8.5h13m-3.5-3.5L18 8.5 14.5 12M19 15.5H6m3.5 3.5L6 15.5 9.5 12',
} as const

export type NomeIcona = keyof typeof TRACCIATI

export function Icona({ nome }: { nome: NomeIcona }) {
  return (
    <svg className="icona" viewBox="0 0 24 24" width="1em" height="1em" aria-hidden="true" focusable="false">
      <path d={TRACCIATI[nome]} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
