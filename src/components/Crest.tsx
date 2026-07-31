type CrestProps = {
  value: string | null
  imageUrl?: string | null
  size?: 'small' | 'large'
}

const simboli: Record<string, string> = {
  scudo: 'S1',
  diagonale: 'XI',
  torre: '♜',
  stella: '★',
  quartieri: '4',
  corona: '♛',
}

export function Crest({ value, imageUrl, size = 'small' }: CrestProps) {
  if (imageUrl) {
    return <img className={`crest crest--${size}`} src={imageUrl} alt="" />
  }

  const preset = value?.startsWith('preset:') ? value.slice(7) : 'scudo'
  return (
    <span className={`crest crest--${size} crest--${preset}`} aria-hidden="true">
      <span>{simboli[preset] ?? 'S1'}</span>
    </span>
  )
}
