import { useId } from 'react'

// Facciata della bustina "promo" (Season 3, rifatta il 7/11/2026 sulle confezioni Topps 75): un'unica illustrazione SVG,
// cosi' posizioni e sovrapposizioni sono esatte su ogni schermo.
//   - in alto, sul blu notte: i tre premiati della stagione prima in fila, attaccati, tagliati alla vita
//     (capocannoniere al centro, piu' grande e davanti; assistman a sinistra, portiere a destra);
//   - una V di righe bianca/ciano/blu separa il blu dalla parte bassa argento a trama di tessuto;
//   - sulla punta della V il logo ufficiale: lo stemma e, sotto, la scritta SPECIALONE su una fascia blu notte;
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
      <linearGradient id={`${id}-ciano`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#d9fbff" />
        <stop offset=".5" stopColor="#3fdcf5" />
        <stop offset="1" stopColor="#0f8fd0" />
      </linearGradient>
      <filter id={`${id}-ombra`} x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="6" stdDeviation="8" floodColor="#020a1c" floodOpacity=".7" />
      </filter>
      <filter id={`${id}-stemma`} x="-30%" y="-20%" width="160%" height="140%">
        <feDropShadow dx="0" dy="0" stdDeviation="3" floodColor="#020a1c" floodOpacity=".85" />
        <feDropShadow dx="0" dy="6" stdDeviation="9" floodColor="#020a1c" floodOpacity=".6" />
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

    {/* Il logo ufficiale: lo stemma sulla punta della V (ombra scura per staccarlo da maglie e argento), sotto la scritta
        SPECIALONE ufficiale su una fascia blu notte con i bordi ciano (bianca e oro, sull'argento non si leggerebbe) */}
    <image href="/specialone-mark.svg" x={W / 2 - 62} y="278" width="124" height="175" filter={`url(#${id}-stemma)`} />
    <polygon points="14,474 486,466 486,526 14,534" fill="#071a45" filter={`url(#${id}-ombra)`} />
    <line x1="14" y1="474" x2="486" y2="466" stroke="#27d3f0" strokeWidth="4" />
    <line x1="14" y1="534" x2="486" y2="526" stroke="#27d3f0" strokeWidth="4" />
    <image href="/loghi/specialone_text.svg" x={W / 2 - 205} y="477" width="410" height="47" />

    {/* SEASON n e la riga sotto, nella parte argento */}
    <g fontFamily="Anton, Impact, sans-serif" textAnchor="middle">
      <text x={W / 2} y="598" fontSize="66" letterSpacing="2" fill="none" stroke="#ffffff" strokeWidth="10" strokeLinejoin="round">SEASON {stagione}</text>
      <text x={W / 2} y="598" fontSize="66" letterSpacing="2" fill="#0a1f4d">SEASON <tspan fill={`url(#${id}-ciano)`} stroke="#071a45" strokeWidth="2">{stagione}</tspan></text>
    </g>
    <text x={W / 2} y="632" textAnchor="middle" fontFamily="'Bai Jamjuree', sans-serif" fontWeight="700" fontSize="16" letterSpacing="5" fill="#2b4268">FIGURINE UFFICIALI</text>
  </svg>
}
