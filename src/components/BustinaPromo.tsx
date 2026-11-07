import { useId } from 'react'

// Facciata della bustina "promo" (Season 3, rifatta il 7/11/2026 sulle confezioni Topps 75): un'unica illustrazione SVG,
// cosi' posizioni e sovrapposizioni sono esatte su ogni schermo.
//   - in alto, sul blu notte: i tre premiati della stagione prima in fila, attaccati, tagliati alla vita
//     (capocannoniere al centro, piu' grande e davanti; assistman a sinistra, portiere a destra);
//   - una V di righe bianca/ciano/blu separa il blu dalla parte bassa argento a trama di tessuto;
//   - sulla punta della V il marchio: rombo cromato con l'emblema, SPECIAL cromato e ONE ciano, davanti a tutto;
//   - in basso SEASON n (Anton) e la riga "Figurine ufficiali".
// Coordinate in un riquadro 500x654 (le proporzioni del corpo della bustina). I ritagli dei giocatori sono quadrati con
// la persona tagliata alla vita sul bordo basso: i fondi delle foto finiscono sotto la V o dietro il marchio.
export type PremiatoFacciata = { premio: 'marcatore' | 'assistman' | 'portiere'; nome: string; foto?: string }

const W = 500
const H = 654
// Bordo alto della parte argento: dai lati (y = BORDO) alla punta al centro (y = BORDO + PUNTA).
const BORDO = 360
const PUNTA = 92
const v = (y: number) => `0,${y} ${W / 2},${y + PUNTA} ${W},${y}`

export function FacciataPromo({ premiati, stagione }: { premiati: PremiatoFacciata[]; stagione: number }) {
  const id = useId().replace(/:/g, '')
  const foto = (p: PremiatoFacciata['premio']) => premiati.find((x) => x.premio === p)?.foto
  return <svg className="pk__facciata" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    <defs>
      <linearGradient id={`${id}-notte`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#0d3a8f" />
        <stop offset=".55" stopColor="#082459" />
        <stop offset="1" stopColor="#051638" />
      </linearGradient>
      <radialGradient id={`${id}-alone`} cx="250" cy="230" r="230" gradientUnits="userSpaceOnUse">
        <stop offset="0" stopColor="#5fe3ff" stopOpacity=".55" />
        <stop offset=".5" stopColor="#1f8fe0" stopOpacity=".18" />
        <stop offset="1" stopColor="#1f8fe0" stopOpacity="0" />
      </radialGradient>
      <pattern id={`${id}-righe`} width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(-28)">
        <rect width="2" height="9" fill="#fff" opacity=".045" />
      </pattern>
      <linearGradient id={`${id}-argento`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ffffff" />
        <stop offset=".45" stopColor="#e6ecf4" />
        <stop offset="1" stopColor="#c3cedb" />
      </linearGradient>
      <pattern id={`${id}-trama`} width="6" height="6" patternUnits="userSpaceOnUse">
        <path d="M0 6 L6 0 M-1 1 L1 -1 M5 7 L7 5" stroke="#5d7391" strokeWidth=".7" opacity=".16" />
        <path d="M0 0 L6 6" stroke="#ffffff" strokeWidth=".7" opacity=".5" />
      </pattern>
      <linearGradient id={`${id}-cromo`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ffffff" />
        <stop offset=".38" stopColor="#dce6f1" />
        <stop offset=".5" stopColor="#7f93ab" />
        <stop offset=".53" stopColor="#f4f8fc" />
        <stop offset=".8" stopColor="#b4c3d4" />
        <stop offset="1" stopColor="#ffffff" />
      </linearGradient>
      <linearGradient id={`${id}-olo`} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#7ff6ff" stopOpacity=".55" />
        <stop offset=".35" stopColor="#ffffff" stopOpacity="0" />
        <stop offset=".6" stopColor="#ff9cf0" stopOpacity=".45" />
        <stop offset=".85" stopColor="#ffe98a" stopOpacity=".4" />
        <stop offset="1" stopColor="#7ff6ff" stopOpacity=".5" />
      </linearGradient>
      <linearGradient id={`${id}-ciano`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#d9fbff" />
        <stop offset=".5" stopColor="#3fdcf5" />
        <stop offset="1" stopColor="#0f8fd0" />
      </linearGradient>
      <filter id={`${id}-ombra`} x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="6" stdDeviation="8" floodColor="#020a1c" floodOpacity=".7" />
      </filter>
      <filter id={`${id}-bordo`} x="-10%" y="-10%" width="120%" height="120%">
        <feDropShadow dx="0" dy="0" stdDeviation="1.4" floodColor="#9ff3ff" floodOpacity=".9" />
        <feDropShadow dx="0" dy="8" stdDeviation="10" floodColor="#020a1c" floodOpacity=".75" />
      </filter>
    </defs>

    {/* Fondo blu notte con alone e righine */}
    <rect width={W} height={H} fill={`url(#${id}-notte)`} />
    <rect width={W} height={H} fill={`url(#${id}-righe)`} />
    <rect width={W} height={H} fill={`url(#${id}-alone)`} />
    {/* Il numero della stagione, enorme e appena accennato dietro i giocatori */}
    <text x={W / 2} y="330" textAnchor="middle" fontFamily="Anton, Impact, sans-serif" fontSize="420" fill="none" stroke="#5fe3ff" strokeWidth="3" opacity=".16">{stagione}</text>

    {/* I premiati: i laterali dietro, il capocannoniere davanti */}
    {foto('assistman') && <image href={foto('assistman')} x="-34" y="135" width="320" height="320" filter={`url(#${id}-ombra)`} />}
    {foto('portiere') && <image href={foto('portiere')} x="214" y="135" width="320" height="320" filter={`url(#${id}-ombra)`} />}
    {foto('marcatore') && <image href={foto('marcatore')} x="70" y="108" width="360" height="360" filter={`url(#${id}-bordo)`} />}

    {/* Parte bassa argento a trama di tessuto, sopra i fondi delle foto */}
    <polygon points={`${v(BORDO)} ${W},${H} 0,${H}`} fill={`url(#${id}-argento)`} />
    <polygon points={`${v(BORDO)} ${W},${H} 0,${H}`} fill={`url(#${id}-trama)`} />
    {/* La V: righe bianca, ciano e blu */}
    <polyline points={v(BORDO - 34)} fill="none" stroke="#ffffff" strokeWidth="9" strokeLinejoin="miter" />
    <polyline points={v(BORDO - 20)} fill="none" stroke="#27d3f0" strokeWidth="13" strokeLinejoin="miter" />
    <polyline points={v(BORDO - 6)} fill="none" stroke="#071a45" strokeWidth="8" strokeLinejoin="miter" />

    {/* Marchio sulla punta della V: rombo cromato con l'emblema in alto (sopra la scritta), poi SPECIAL / ONE davanti */}
    <g filter={`url(#${id}-ombra)`}>
      <polygon points="250,292 340,382 250,472 160,382" fill={`url(#${id}-cromo)`} stroke="#071a45" strokeWidth="5" strokeLinejoin="round" />
      <polygon points="250,308 324,382 250,456 176,382" fill="#0a2a6b" />
      <polygon points="250,308 324,382 250,456 176,382" fill={`url(#${id}-olo)`} />
      <image href="/specialone-mark.svg" x="218" y="314" width="64" height="64" />
    </g>
    <g transform="translate(250 0) skewX(-9) translate(-250 0)" fontFamily="'Saira Condensed', 'Arial Narrow', sans-serif" fontWeight="800" textAnchor="middle">
      <text x="250" y="455" fontSize="112" letterSpacing="-1" fill="none" stroke="#071a45" strokeWidth="16" strokeLinejoin="round">SPECIAL</text>
      <text x="250" y="455" fontSize="112" letterSpacing="-1" fill={`url(#${id}-cromo)`} stroke="#ffffff" strokeWidth="2">SPECIAL</text>
      <text x="250" y="455" fontSize="112" letterSpacing="-1" fill={`url(#${id}-olo)`}>SPECIAL</text>
      <text x="250" y="512" fontSize="62" letterSpacing="10" fill="none" stroke="#071a45" strokeWidth="12" strokeLinejoin="round">ONE</text>
      <text x="250" y="512" fontSize="62" letterSpacing="10" fill={`url(#${id}-ciano)`} stroke="#ffffff" strokeWidth="1.5">ONE</text>
    </g>

    {/* SEASON n e la riga sotto, nella parte argento */}
    <g fontFamily="Anton, Impact, sans-serif" textAnchor="middle">
      <text x={W / 2} y="598" fontSize="66" letterSpacing="2" fill="none" stroke="#ffffff" strokeWidth="10" strokeLinejoin="round">SEASON {stagione}</text>
      <text x={W / 2} y="598" fontSize="66" letterSpacing="2" fill="#0a1f4d">SEASON <tspan fill={`url(#${id}-ciano)`} stroke="#071a45" strokeWidth="2">{stagione}</tspan></text>
    </g>
    <text x={W / 2} y="632" textAnchor="middle" fontFamily="'Bai Jamjuree', sans-serif" fontWeight="700" fontSize="16" letterSpacing="5" fill="#2b4268">FIGURINE UFFICIALI</text>
  </svg>
}
