import { stemmaPresetDaValore } from '../lib/teamCrests'

type CrestProps = {
  value: string | null
  imageUrl?: string | null
  size?: 'small' | 'large'
  // Title Playoff vinti (teams.titoli_title): una stella dorata sopra lo stemma
  // per ognuno, oltre le cinque una sola con il numero.
  stelle?: number | null
  // Campione in carica: cornice dorata che segue esattamente il contorno dello stemma.
  campione?: boolean | null
}

function Stella() {
  return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1.6l3.1 6.6 7.2.9-5.3 5 1.4 7.2L12 17.6l-6.4 3.7L7 14.1 1.7 9.1l7.2-.9z" /></svg>
}

export function Crest({ value, imageUrl, size = 'small', stelle, campione }: CrestProps) {
  const stemma = imageUrl ? null : stemmaPresetDaValore(value)
  const img = imageUrl
    ? <img className={`crest crest--${size}`} src={imageUrl} alt="" decoding="async" />
    : <img className={`crest crest--${size}`} src={stemma?.src ?? '/stemmi-squadra/thumbs/1.png'} alt="" loading="lazy" decoding="async" />

  const n = Math.max(0, Math.floor(stelle ?? 0))
  if (n === 0 && !campione) return img

  const compatto = n > 5 || size === 'small'
  return <span className={`crest-stellato crest-stellato--${size}${campione ? ' crest-stellato--campione' : ''}`}
    title={[campione ? 'Campione in carica' : '', n > 0 ? `${n} ${n === 1 ? 'titolo' : 'titoli'} Title Playoff` : ''].filter(Boolean).join(' · ')}>
    {img}
    {n > 0 && <span className="crest-stelle" aria-label={`${n} Title Playoff vinti`}>
      {compatto
        ? <><Stella />{n > 1 && <b>{n}</b>}</>
        : Array.from({ length: n }, (_, i) => <Stella key={i} />)}
    </span>}
  </span>
}
