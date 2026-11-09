import { useId } from 'react'

type Props = { compatto?: boolean }

// Il caricamento e' il marchio SpecialOne animato, come nei giochi moderni (9/11/2026): i pezzi entrano e si
// compongono (corona dall'alto, S da sinistra, 1 da destra, oro dal basso), poi un riflesso di luce passa sul metallo
// e il diamante della corona pulsa. Niente scritte: il testo dei caricamenti resta solo per i lettori di schermo.
// I tracciati sono quelli di public/specialone-mark.svg.
export function LoadingLogo({ compatto = false }: Props) {
  // id unici: piu' caricamenti possono stare nella stessa pagina
  const id = useId().replace(/[^a-zA-Z0-9]/g, '')
  return <span className={`loading-logo${compatto ? ' loading-logo--compatto' : ''}`} role="status" aria-label="Caricamento in corso">
    <svg className="loading-logo__marchio" viewBox="0 0 449.17 632.53" aria-hidden="true" focusable="false">
      <defs>
        <clipPath id={`metallo-${id}`}>
          <path d={CORONA} />
          <polygon points={S} />
          <polygon points={UNO} />
        </clipPath>
        <linearGradient id={`riflesso-${id}`} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stopColor="#fff" stopOpacity="0" />
          <stop offset=".5" stopColor="#d9c4ff" stopOpacity=".95" />
          <stop offset="1" stopColor="#fff" stopOpacity="0" />
        </linearGradient>
      </defs>
      <g className="loading-logo__corona">
        <path className="loading-logo__bianco" d={CORONA} />
        <polygon className="loading-logo__diamante" points={DIAMANTE} />
      </g>
      <g className="loading-logo__barrette">
        <polygon className="loading-logo__oro" points={BARRA_SX} />
        <polygon className="loading-logo__oro" points={BARRA_DX} />
      </g>
      <polygon className="loading-logo__bianco loading-logo__s" points={S} />
      <polygon className="loading-logo__bianco loading-logo__uno" points={UNO} />
      <path className="loading-logo__oro loading-logo__freccia" d={FRECCIA} />
      <g clipPath={`url(#metallo-${id})`}>
        <rect className="loading-logo__riflesso" x="-260" y="-80" width="200" height="800" fill={`url(#riflesso-${id})`} />
      </g>
    </svg>
  </span>
}

const CORONA = 'M401,183.52l-352.15.02L0,26.23s130.87,99.44,135.28,102.95l34.92,27.73,21.47-.03-22.46-39.76L225.18,0l43.22,89.82,12.63,27.31-22.56,39.81,21.28.11L449.17,26.66l-18.43,61.36-29.73,95.5ZM225.41,172.41l33.2-56.11-33.41-69.68-33.25,69.78,33.47,56ZM124.5,156.71l-55-44.09c3.84,15.86,9,29.83,13.52,44.54l41.48-.45ZM367.37,157.02l11.86-38.59c.44-1.44.12-2.82-.93-3.39-.46-.25-1.42.16-2.2.79l-50.42,40.97,41.69.22Z'
const DIAMANTE = '225.32 151.34 203.93 115.88 225.32 70.43 246.38 116.02 225.32 151.34'
const BARRA_SX = '123.99 207.27 55.56 207.47 51.43 195.6 144.7 195.62 123.99 207.27'
const BARRA_DX = '325.75 207.27 394.18 207.47 398.31 195.6 305.04 195.62 325.75 207.27'
const S = '280.61 538.17 227.67 569.4 56.3 471.68 56.33 393.19 214.1 482.19 214.4 429.99 55.56 341.63 55.58 222.97 304.32 223.13 236.97 287.27 123.44 287.53 123.25 304.26 280.67 393.05 280.61 538.17'
const UNO = '326.6 514.93 326.56 316.47 254.94 316.08 353.8 223.03 394.48 223.06 394.47 475.2 326.6 514.93'
const FRECCIA = 'M89.55,538.95c2.82-.68,4.99.86,7.57,2.31l129.46,72.68,137.03-77.23c-44.75,34.15-90.91,64.04-136.89,95.82l-137.18-93.58Z'
