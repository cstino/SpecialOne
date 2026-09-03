type FtsgGaugeProps = {
  moduloPct: number
  stilePct: number
  onClick?: () => void
}

// Indice FTSG (familiarita' tattiche e stile di gioco): media tra la
// familiarita' col modulo e quella con lo stile di gioco correnti, la
// stessa combinazione che il motore usa per il malus di familiarita'
// (engine/engine.js, familiarita()). Il cerchio e' diviso in due meta'
// uguali e sempre colorate — sopra il modulo (viola), sotto lo stile
// (turchese) — cosi' i due colori restano una legenda fissa anche a 0%.
//
// Ogni meta' cresce dal proprio polo (ore 12 per il modulo, ore 6 per lo
// stile) verso i due lati in modo simmetrico, non da un bordo verso
// l'altro: a percentuali basse il segno resta comunque ben visibile nel
// punto piu' in vista della meta', invece di nascondersi appena sopra la
// linea d'incontro tra le due semicirconferenze. Per farlo ogni meta' e'
// in realta' due quarti di cerchio indipendenti (sinistra e destra dal
// polo), riempiti alla STESSA percentuale — due grafici a quarto di
// cerchio distinti che, uniti, si leggono come un unico semicerchio.
export function FtsgGauge({ moduloPct, stilePct, onClick }: FtsgGaugeProps) {
  const indice = Math.round((moduloPct + stilePct) / 2)
  const cx = 50
  const cy = 50
  const r = 40
  const poloAlto = `${cx} ${cy - r}`
  const poloBasso = `${cx} ${cy + r}`
  const equatoreSx = `${cx - r} ${cy}`
  const equatoreDx = `${cx + r} ${cy}`
  // Tracciati di sfondo: le due semicirconferenze intere, sempre piene.
  const topArc = `M ${equatoreSx} A ${r} ${r} 0 0 1 ${equatoreDx}`
  const bottomArc = `M ${equatoreSx} A ${r} ${r} 0 0 0 ${equatoreDx}`
  // I quattro quarti attivi, ognuno a partire dal proprio polo.
  const moduloSx = `M ${poloAlto} A ${r} ${r} 0 0 0 ${equatoreSx}`
  const moduloDx = `M ${poloAlto} A ${r} ${r} 0 0 1 ${equatoreDx}`
  const stileSx = `M ${poloBasso} A ${r} ${r} 0 0 1 ${equatoreSx}`
  const stileDx = `M ${poloBasso} A ${r} ${r} 0 0 0 ${equatoreDx}`
  const label = `Indice FTSG ${indice}%: modulo ${Math.round(moduloPct)}%, stile di gioco ${Math.round(stilePct)}%. Tocca per i dettagli.`
  return (
    <button type="button" className="ftsg-gauge__ring" onClick={onClick} aria-label={label}>
      <svg viewBox="0 0 100 100">
        <path d={topArc} className="ftsg-gauge__meta ftsg-gauge__meta--modulo" pathLength={100} />
        <path d={bottomArc} className="ftsg-gauge__meta ftsg-gauge__meta--stile" pathLength={100} />
        {[moduloSx, moduloDx].map((d) => (
          <path
            key={d}
            d={d}
            className="ftsg-gauge__arco ftsg-gauge__arco--modulo"
            pathLength={100}
            strokeDasharray={100}
            strokeDashoffset={100 - moduloPct}
          />
        ))}
        {[stileSx, stileDx].map((d) => (
          <path
            key={d}
            d={d}
            className="ftsg-gauge__arco ftsg-gauge__arco--stile"
            pathLength={100}
            strokeDasharray={100}
            strokeDashoffset={100 - stilePct}
          />
        ))}
      </svg>
      <strong>{indice}%</strong>
    </button>
  )
}
