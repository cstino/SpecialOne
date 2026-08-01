import type { ReactNode } from 'react'

type CrestProps = {
  value: string | null
  imageUrl?: string | null
  size?: 'small' | 'large'
}

// Stemmi disegnati, non caratteri di testo dentro una forma unica: prima ogni
// squadra che non sceglieva finiva con lo stesso scudetto viola e nei risultati
// non si capiva chi avesse giocato contro chi.
const STEMMI: Record<string, { lettera: string; inchiostro: string; disegno: ReactNode }> = {
  scudo: {
    lettera: 'S', inchiostro: '#1A0F2C',
    disegno: <>
      <path d="M32 2 60 12v28c0 16-12 26-28 30C16 66 4 56 4 40V12z" fill="#7A2FE0" />
      <path d="M32 2 4 12v28c0 16 12 26 28 30z" fill="#B978FF" />
    </>,
  },
  diagonale: {
    lettera: 'X', inchiostro: '#062E28',
    disegno: <>
      <circle cx="32" cy="34" r="30" fill="#0E5F52" />
      <path d="M2 34h60M32 4v60" stroke="#3BD9B0" strokeWidth="6" />
      <circle cx="32" cy="34" r="14" fill="#062E28" />
    </>,
  },
  torre: {
    lettera: 'T', inchiostro: '#2A0C04',
    disegno: <>
      <path d="M4 4h56v40L32 68 4 44z" fill="#C4462A" />
      <path d="M4 4h56L32 34z" fill="#F08A5D" />
    </>,
  },
  stella: {
    lettera: 'A', inchiostro: '#1B1A05',
    disegno: <>
      <path d="M32 2 58 16v28L32 68 6 44V16z" fill="#D9A521" />
      <path d="M32 2 58 16 32 34 6 16z" fill="#F5D571" />
    </>,
  },
  quartieri: {
    lettera: 'Q', inchiostro: '#04182E',
    disegno: <>
      <rect x="4" y="4" width="56" height="60" rx="8" fill="#1F6FD0" />
      <path d="M32 4h28v30H32zM4 34h28v30H4z" fill="#7CB8F5" />
    </>,
  },
  corona: {
    lettera: 'R', inchiostro: '#2B0716',
    disegno: <>
      <path d="M32 2 60 12v28c0 16-12 26-28 30C16 66 4 56 4 40V12z" fill="#B01E5A" />
      <path d="M32 2 60 12v18H4V12z" fill="#F26FA1" />
    </>,
  },
}

export function Crest({ value, imageUrl, size = 'small' }: CrestProps) {
  if (imageUrl) {
    return <img className={`crest crest--${size}`} src={imageUrl} alt="" />
  }

  const chiave = value?.startsWith('preset:') ? value.slice(7) : 'scudo'
  const stemma = STEMMI[chiave] ?? STEMMI.scudo
  return (
    <span className={`crest crest--${size} crest--disegnato`} aria-hidden="true">
      <svg viewBox="0 0 64 72" focusable="false">
        {stemma.disegno}
        <text x="32" y="44" textAnchor="middle" fill={stemma.inchiostro} fontSize="26" fontWeight="900" fontFamily="system-ui, sans-serif">{stemma.lettera}</text>
      </svg>
    </span>
  )
}
