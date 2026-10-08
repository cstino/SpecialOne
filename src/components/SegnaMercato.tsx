// Il segnalino verde col dollaro: il giocatore e' sul mercato (la sua squadra lo ha messo in lista).
export function SegnaMercato({ className = '' }: { className?: string }) {
  return <i className={`segna-mercato ${className}`} title="Sul mercato" aria-label="Sul mercato">$</i>
}
