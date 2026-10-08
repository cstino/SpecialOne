// Il morale in una faccina, da «in rotta con la squadra» (arrabbiata) a «entusiasta» (contentissima). Disegnata a
// tratti, senza emoji, e colorata come la dicitura della stessa fascia (stessi colori di .morale--* in styles.css).
export type FasciaMorale = 'ottimo' | 'buono' | 'medio' | 'basso' | 'critico'

export function etichettaMorale(morale: number): { testo: string; classe: FasciaMorale } {
  if (morale >= 80) return { testo: 'Entusiasta', classe: 'ottimo' }
  if (morale >= 60) return { testo: 'Sereno', classe: 'buono' }
  if (morale >= 40) return { testo: 'Insoddisfatto', classe: 'medio' }
  if (morale >= 20) return { testo: 'Scontento', classe: 'basso' }
  return { testo: 'In rotta con la squadra', classe: 'critico' }
}

export function FaccinaMorale({ morale, className = '' }: { morale: number; className?: string }) {
  const { testo, classe } = etichettaMorale(morale)
  return (
    <svg className={`faccina-morale faccina-morale--${classe} ${className}`} viewBox="0 0 24 24" role="img" aria-label={`Morale: ${testo}`} fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <title>{testo}</title>
      <circle cx="12" cy="12" r="9.6" />
      {classe === 'ottimo' && <>
        <path d="M7.6 10.4q1.4-2 2.8 0M13.6 10.4q1.4-2 2.8 0" />
        <path d="M7.4 13.6h9.2q-.4 4.4-4.6 4.4t-4.6-4.4z" fill="currentColor" fillOpacity=".28" />
      </>}
      {classe === 'buono' && <>
        <circle cx="9" cy="10" r=".9" fill="currentColor" stroke="none" /><circle cx="15" cy="10" r=".9" fill="currentColor" stroke="none" />
        <path d="M8 14.2q4 3.6 8 0" />
      </>}
      {classe === 'medio' && <>
        <circle cx="9" cy="10" r=".9" fill="currentColor" stroke="none" /><circle cx="15" cy="10" r=".9" fill="currentColor" stroke="none" />
        <path d="M8.6 15.2h6.8" />
      </>}
      {classe === 'basso' && <>
        <circle cx="9" cy="10.2" r=".9" fill="currentColor" stroke="none" /><circle cx="15" cy="10.2" r=".9" fill="currentColor" stroke="none" />
        <path d="M8.4 16.2q3.6-3 7.2 0" />
      </>}
      {classe === 'critico' && <>
        <path d="M6.8 7.4l4 1.6M17.2 7.4l-4 1.6" />
        <circle cx="9" cy="11" r=".9" fill="currentColor" stroke="none" /><circle cx="15" cy="11" r=".9" fill="currentColor" stroke="none" />
        <path d="M8.2 16.6q3.8-3.6 7.6 0" />
      </>}
    </svg>
  )
}
