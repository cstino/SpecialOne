import { stemmaPresetDaValore } from '../lib/teamCrests'

type CrestProps = {
  value: string | null
  imageUrl?: string | null
  size?: 'small' | 'large'
  // Title Playoff vinti (teams.titoli_title): una stella dorata sopra lo stemma
  // per ognuno, oltre le cinque una sola con il numero.
  stelle?: number | null
  // Immagine subito, senza caricamento pigro: per le scene dove lo stemma cambia di continuo (roulette).
  eager?: boolean
}

function Stella() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1.6l3.1 6.6 7.2.9-5.3 5 1.4 7.2L12 17.6l-6.4 3.7L7 14.1 1.7 9.1l7.2-.9z" /></svg>
}

export function Crest({ value, imageUrl, size = 'small', stelle, eager = false }: CrestProps) {
  const stemma = imageUrl ? null : stemmaPresetDaValore(value)
  const classePreset = stemma ? ` crest--preset-${stemma.id}` : ''
  const img = imageUrl
    ? <img className={`crest crest--${size}`} src={imageUrl} alt="" decoding="async" />
    : <img className={`crest crest--${size}${classePreset}`} src={stemma?.src ?? '/stemmi-squadra/thumbs/1.png'} alt="" loading={eager ? 'eager' : 'lazy'} decoding={eager ? 'sync' : 'async'} />

  const n = Math.max(0, Math.floor(stelle ?? 0))
  if (n === 0) return img

  const compatto = n > 5 || size === 'small'
  return <span className={`crest-stellato crest-stellato--${size}`}
    title={`${n} ${n === 1 ? 'titolo' : 'titoli'} Title Playoff`}>
    {img}
    {n > 0 && <span className="crest-stelle" aria-label={`${n} Title Playoff vinti`}>
      {compatto
        ? <><Stella />{n > 1 && <b>{n}</b>}</>
        : Array.from({ length: n }, (_, i) => <Stella key={i} />)}
    </span>}
  </span>
}
