type FtsgGaugeProps = {
  moduloPct: number
  stilePct: number
}

// Indice FTSG (familiarita' tattiche e stile di gioco): media tra la
// familiarita' col modulo e quella con lo stile di gioco correnti, la
// stessa combinazione che il motore usa per il malus di familiarita'
// (engine/engine.js, familiarita()). Il cerchio ha due semicirconferenze
// indipendenti — sopra il modulo, sotto lo stile — cosi' si vede subito
// QUALE delle due sta abbassando l'indice, non solo il numero finale.
export function FtsgGauge({ moduloPct, stilePct }: FtsgGaugeProps) {
  const indice = Math.round((moduloPct + stilePct) / 2)
  const cx = 50
  const cy = 50
  const r = 40
  // pathLength normalizza la lunghezza del tracciato a 100 unita' a
  // prescindere dal raggio: dasharray/dashoffset diventano percentuali
  // dirette, senza calcolare la circonferenza a mano.
  const topArc = `M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`
  const bottomArc = `M ${cx - r} ${cy} A ${r} ${r} 0 0 0 ${cx + r} ${cy}`
  return (
    <div className="ftsg-gauge__ring" role="img" aria-label={`Indice FTSG ${indice}%: modulo ${Math.round(moduloPct)}%, stile di gioco ${Math.round(stilePct)}%`}>
      <svg viewBox="0 0 100 100">
        <path d={topArc} className="ftsg-gauge__traccia" pathLength={100} />
        <path d={bottomArc} className="ftsg-gauge__traccia" pathLength={100} />
        <path
          d={topArc}
          className="ftsg-gauge__arco ftsg-gauge__arco--modulo"
          pathLength={100}
          strokeDasharray={100}
          strokeDashoffset={100 - moduloPct}
        />
        <path
          d={bottomArc}
          className="ftsg-gauge__arco ftsg-gauge__arco--stile"
          pathLength={100}
          strokeDasharray={100}
          strokeDashoffset={100 - stilePct}
        />
      </svg>
      <strong>{indice}%</strong>
    </div>
  )
}
