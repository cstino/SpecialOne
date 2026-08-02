import { stemmaPresetDaValore } from '../lib/teamCrests'

type CrestProps = {
  value: string | null
  imageUrl?: string | null
  size?: 'small' | 'large'
}

export function Crest({ value, imageUrl, size = 'small' }: CrestProps) {
  if (imageUrl) {
    return <img className={`crest crest--${size}`} src={imageUrl} alt="" decoding="async" />
  }

  const stemma = stemmaPresetDaValore(value)
  return <img className={`crest crest--${size}`} src={stemma?.src ?? '/stemmi-squadra/thumbs/1.png'} alt="" loading="lazy" decoding="async" />
}
