// Disegni dei simboli e degli oggetti dei minigiochi di SlotOne: stemma d'oro (scegli lo stemma) e pallone (calcio di rigore).

export function Scudo() {
  return <svg viewBox="0 0 64 76" className="sb-scudo__svg" aria-hidden="true">
    <defs>
      <linearGradient id="sbOro" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#fff2b0" /><stop offset=".45" stopColor="#ffcc33" /><stop offset="1" stopColor="#a8731a" /></linearGradient>
      <linearGradient id="sbOroScuro" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#5b3a05" /><stop offset="1" stopColor="#2a1a02" /></linearGradient>
    </defs>
    <path d="M32 3 L58 11 V36 C58 54 46 66 32 73 C18 66 6 54 6 36 V11 Z" fill="url(#sbOro)" stroke="#6b4608" strokeWidth="2.5" strokeLinejoin="round" />
    <path d="M32 11 L50 17 V36 C50 49 42 58 32 64 C22 58 14 49 14 36 V17 Z" fill="url(#sbOroScuro)" />
    <polygon points={stellaPunti(32, 36, 12, 5)} fill="url(#sbOro)" stroke="#fff2b0" strokeWidth="1" strokeLinejoin="round" />
    <path d="M12 14 L32 8 L24 20 Z" fill="#fff" opacity=".35" />
  </svg>
}
function stellaPunti(cx: number, cy: number, r: number, _n: number) {
  const pts: string[] = []
  for (let k = 0; k < 10; k++) { const rr = k % 2 === 0 ? r : r * 0.42, a = -Math.PI / 2 + (k * Math.PI) / 5; pts.push(`${(cx + rr * Math.cos(a)).toFixed(2)},${(cy + rr * Math.sin(a)).toFixed(2)}`) }
  return pts.join(' ')
}

export function Pallone({ className }: { className?: string }) {
  // pentagono centrale e cinque spicchi sul bordo, calcolati: niente coordinate a mano
  const poli = (cx: number, cy: number, r: number, rot: number) => Array.from({ length: 5 }, (_, k) => { const a = rot + (k * 2 * Math.PI) / 5; return [cx + r * Math.cos(a), cy + r * Math.sin(a)] as const })
  const centro = poli(24, 24, 6.4, -Math.PI / 2)
  const str = (p: ReadonlyArray<readonly [number, number]>) => p.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ')
  return <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
    <defs>
      <radialGradient id="sbPall" cx=".35" cy=".3" r=".9"><stop offset="0" stopColor="#ffffff" /><stop offset=".65" stopColor="#e9eaf0" /><stop offset="1" stopColor="#a9acbd" /></radialGradient>
      <clipPath id="sbPallClip"><circle cx="24" cy="24" r="19" /></clipPath>
    </defs>
    <circle cx="24" cy="24" r="19" fill="url(#sbPall)" />
    <g clipPath="url(#sbPallClip)" fill="#1b1b26" stroke="#1b1b26" strokeWidth=".9" strokeLinejoin="round">
      <polygon points={str(centro)} />
      {centro.map(([x, y], k) => {
        const a = -Math.PI / 2 + (k * 2 * Math.PI) / 5
        const fuori = poli(24 + 17.2 * Math.cos(a), 24 + 17.2 * Math.sin(a), 6.2, a + Math.PI)
        return <g key={k}><line x1={x} y1={y} x2={24 + 11.6 * Math.cos(a)} y2={24 + 11.6 * Math.sin(a)} fill="none" /><polygon points={str(fuori)} /></g>
      })}
    </g>
    <circle cx="24" cy="24" r="19" fill="none" stroke="#1b1b26" strokeWidth="1.6" />
    <ellipse cx="17" cy="14" rx="6" ry="3.2" fill="#fff" opacity=".55" transform="rotate(-30 17 14)" />
  </svg>
}

export function SimboloPallone() {
  return <span className="slot-sim slot-sim--pallone" aria-label="Pallone"><Pallone className="slot-sim__svg" /></span>
}
export function SimboloStemmaOro() {
  return <span className="slot-sim slot-sim--stemmaoro" aria-label="Stemma d'oro"><span className="slot-sim__scudo"><Scudo /></span></span>
}
