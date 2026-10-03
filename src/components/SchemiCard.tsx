import { useEffect, useRef, useState } from 'react'
import { Icona } from './Icona'
import { TestoAdattato } from './TestoAdattato'

// La card "Schemi" sopra moduli e stile (season 2, stile EA FC): due schemi
// tattici con un nome. Lo schema ATTIVO e' quello che gioca; lo schema RISERVA
// si prepara: il suo modulo impara una partita alla volta anche se non lo si
// schiera. Si tocca uno schema per vederlo e modificarlo, la matita lo
// rinomina, "Usa in partita" li scambia, "Elimina" libera la riserva.
// Registro tattico, punto 41.

type Quale = 'attivo' | 'riserva'

export function SchemiCard({
  nomeAttivo, nomeRiserva, selezionato, descrizioneAttivo, descrizioneRiserva, partite, partitePiene,
  onSeleziona, onRinomina, onUsaRiserva, onEliminaRiserva,
}: {
  nomeAttivo: string
  /** null = nessuna riserva: lo slot e' vuoto. */
  nomeRiserva: string | null
  selezionato: Quale
  descrizioneAttivo: string
  descrizioneRiserva: string
  /** Partite imparate dal modulo della riserva (0 se non c'e' ancora una riga). */
  partite: number
  partitePiene: number
  onSeleziona: (quale: Quale) => void
  onRinomina: (quale: Quale, nome: string) => void
  onUsaRiserva: () => void
  onEliminaRiserva: () => void
}) {
  const [modifica, setModifica] = useState<Quale | null>(null)
  const [bozza, setBozza] = useState('')
  const campo = useRef<HTMLInputElement>(null)
  useEffect(() => { if (modifica) campo.current?.select() }, [modifica])

  function inizia(quale: Quale) {
    setBozza(quale === 'attivo' ? nomeAttivo : nomeRiserva ?? '')
    setModifica(quale)
  }
  function conferma() {
    const nome = bozza.trim().slice(0, 24)
    if (modifica && nome) onRinomina(modifica, nome)
    setModifica(null)
  }

  const imparato = partite >= partitePiene
  const segmento = (quale: Quale, nome: string, descrizione: string) => {
    const attivo = selezionato === quale
    return <div className={`schemi-card__slot${attivo ? ' is-selezionato' : ''}${quale === 'attivo' ? ' is-giocante' : ''}`}>
      <button className="schemi-card__corpo" type="button" aria-pressed={attivo} onClick={() => onSeleziona(quale)}>
        <small>{quale === 'attivo' ? 'Schema attivo' : 'Schema riserva'}</small>
        {modifica === quale
          ? <input ref={campo} className="schemi-card__nome-campo" value={bozza} maxLength={24} aria-label="Nome dello schema"
            onClick={(e) => e.stopPropagation()} onChange={(e) => setBozza(e.target.value)} onBlur={conferma}
            onKeyDown={(e) => { if (e.key === 'Enter') conferma(); if (e.key === 'Escape') setModifica(null) }} />
          : <strong><TestoAdattato minimo={0.6}>{nome}</TestoAdattato></strong>}
        <em>{descrizione}</em>
      </button>
      <button className="schemi-card__matita" type="button" aria-label={`Rinomina ${nome}`}
        onMouseDown={(e) => e.preventDefault()} onClick={() => inizia(quale)}><Icona nome="modifica" /></button>
    </div>
  }

  return <section className="schemi-card" aria-label="Schemi tattici">
    <div className="schemi-card__slot-riga">
      {segmento('attivo', nomeAttivo, descrizioneAttivo)}
      {nomeRiserva !== null
        ? segmento('riserva', nomeRiserva, descrizioneRiserva)
        : <button className="schemi-card__vuoto" type="button" onClick={() => onSeleziona('riserva')}>
          <small>Schema riserva</small>
          <strong>+ Prepara uno schema</strong>
          <em>Lo impari anche senza schierarlo</em>
        </button>}
    </div>
    {nomeRiserva !== null && <div className="schemi-card__riserva">
      <span className="schemi-card__apprendimento">
        <small>{imparato ? 'Conosciuta come lo schema attivo' : `Riserva: la stai imparando, ${partite}/${partitePiene} partite`}</small>
        <i aria-hidden="true"><b style={{ width: `${Math.min(100, partite / partitePiene * 100)}%` }} /></i>
      </span>
      <button type="button" onClick={onUsaRiserva} title="La riserva diventa lo schema che gioca e quello attivo prende il suo posto: nessuno perde familiarità">Usa in partita</button>
      <button type="button" className="is-elimina" onClick={onEliminaRiserva}>Elimina</button>
    </div>}
  </section>
}

// Si chiede il nome la prima volta che si salva uno schema riserva.
export function DialogoNomeRiserva({ nomeIniziale, classe = '', onConferma, onAnnulla }: {
  nomeIniziale: string
  /** Le classi di fase (formazione-broadcast formazione-broadcast--regular...) per i colori. */
  classe?: string
  onConferma: (nome: string) => void
  onAnnulla: () => void
}) {
  const [nome, setNome] = useState(nomeIniziale)
  const campo = useRef<HTMLInputElement>(null)
  useEffect(() => { campo.current?.select() }, [])
  const valido = nome.trim().length > 0
  return <div className={`schemi-dialogo-layer ${classe}`} role="presentation" onPointerDown={(e) => { if (e.target === e.currentTarget) onAnnulla() }}>
    <section className="schemi-dialogo" role="dialog" aria-modal="true" aria-label="Nome dello schema riserva">
      <small>Nuovo schema riserva</small>
      <strong>Come lo chiami?</strong>
      <input ref={campo} value={nome} maxLength={24} onChange={(e) => setNome(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter' && valido) onConferma(nome.trim()) }} aria-label="Nome" />
      <div>
        <button type="button" onClick={onAnnulla}>Annulla</button>
        <button type="button" className="is-primario" disabled={!valido} onClick={() => onConferma(nome.trim())}>Salva</button>
      </div>
    </section>
  </div>
}
