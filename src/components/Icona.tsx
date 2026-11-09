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
  // rinomina: una matita
  modifica: 'M4.5 19.5 5 15.5 15.5 5a2 2 0 0 1 3 3L8 18.5Zm9.5-12.5 3 3',
  // azioni della scheda giocatore (pagina mercato)
  // rinnovo: un contratto con le righe
  contratto: 'M14 3.5H7A1.5 1.5 0 0 0 5.5 5v14A1.5 1.5 0 0 0 7 20.5h10a1.5 1.5 0 0 0 1.5-1.5V8ZM14 3.5V8h4.5M9 12.5h6M9 16h4',
  // mercato: un cartellino del prezzo
  mercato: 'M3.5 12.6V4.5a1 1 0 0 1 1-1h8.1l7.9 7.9a1.5 1.5 0 0 1 0 2.1l-7 7a1.5 1.5 0 0 1-2.1 0ZM8.2 8.2h.01',
  // prestito: esce dalla squadra
  prestito: 'M14 4.5h5.5V10M19.5 4.5 11 13M17.5 14v4a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 18V8A1.5 1.5 0 0 1 6 6.5h4',
  // richiamo dal prestito: freccia che torna
  richiama: 'M9 14.5 4.5 10 9 5.5M4.5 10h10a5 5 0 0 1 0 10H11',
  // svincolo: giocatore col segno meno
  svincola: 'M15.5 20v-1.5a4 4 0 0 0-4-4h-5a4 4 0 0 0-4 4V20M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM16 11h5.5',
} as const

export type NomeIcona = keyof typeof TRACCIATI

export function Icona({ nome }: { nome: NomeIcona }) {
  return (
    <svg className="icona" viewBox="0 0 24 24" width="1em" height="1em" aria-hidden="true" focusable="false">
      <path d={TRACCIATI[nome]} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
