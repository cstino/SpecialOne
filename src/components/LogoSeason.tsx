import { useId } from 'react'

// Logo "SEASON n": targa esagonale scura con bordo d'oro, scritta in corsivo sportivo e numero grande in oro.
// SVG inline (niente file): vale per qualunque stagione e si scala con il contenitore.
export function LogoSeason({ n, className }: { n: number; className?: string }) {
  const id = useId().replace(/:/g, '')
  return <svg className={className} viewBox="0 0 150 58" role="img" aria-label={`Season ${n}`}>
    <defs>
      <linearGradient id={`${id}-oro`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#fff6cf" />
        <stop offset=".45" stopColor="#ffd84d" />
        <stop offset=".55" stopColor="#e0a82a" />
        <stop offset="1" stopColor="#fff0b0" />
      </linearGradient>
      <linearGradient id={`${id}-fondo`} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#1b0736" />
        <stop offset="1" stopColor="#3a0d63" />
      </linearGradient>
      <linearGradient id={`${id}-lucido`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#fff" stopOpacity=".28" />
        <stop offset=".5" stopColor="#fff" stopOpacity="0" />
      </linearGradient>
    </defs>
    <polygon points="12,3 138,3 148,29 138,55 12,55 2,29" fill={`url(#${id}-fondo)`} stroke={`url(#${id}-oro)`} strokeWidth="3" strokeLinejoin="round" />
    <polygon points="14,7 136,7 140,18 10,18" fill={`url(#${id}-lucido)`} />
    <line x1="101" y1="10" x2="95" y2="48" stroke={`url(#${id}-oro)`} strokeWidth="2" />
    <g transform="skewX(-10)" fontWeight="900" fontFamily="inherit">
      <text x="58" y="35" textAnchor="middle" fontSize="15.5" letterSpacing="2" fill="#fff">SEASON</text>
      <text x="128" y="43" textAnchor="middle" fontSize={n >= 10 ? 26 : 36} fill={`url(#${id}-oro)`} stroke="#2a1500" strokeWidth=".8">{n}</text>
    </g>
  </svg>
}
