// Icone dei pulsanti rotondi. I caratteri "‹", "›" e "×" non stanno al centro
// del loro spazio (ognuno ha la sua linea di base e i suoi margini laterali), e
// dentro un cerchio lo scarto si vede. Un tracciato SVG in un quadrato 24×24 e'
// centrato per costruzione.
const TRACCIATI = {
  indietro: 'M14.5 5.5 8 12l6.5 6.5',
  avanti: 'M9.5 5.5 16 12l-6.5 6.5',
  chiudi: 'M6.5 6.5l11 11M17.5 6.5l-11 11',
} as const

export type NomeIcona = keyof typeof TRACCIATI

export function Icona({ nome }: { nome: NomeIcona }) {
  return (
    <svg className="icona" viewBox="0 0 24 24" width="1em" height="1em" aria-hidden="true" focusable="false">
      <path d={TRACCIATI[nome]} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
