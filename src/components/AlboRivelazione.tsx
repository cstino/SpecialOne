import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { LOGO_FASE } from '../lib/faseSquadra'
import { PREMI, caricaPremi, firmaStemmi, type Premio } from '../lib/premiAlbo'
import type { Membership, Standing, Team } from '../types'
import { Crest } from './Crest'
import { CoriandoliOri } from './CoriandoliOri'

type Props = {
  membership: Membership
  stagioneId: number
  onFine: (vaiAllAlbo: boolean) => void
}

type Campione = { squadra: Team | null; stemma?: string; daPlayoff: boolean; posizione: number | null }
type Battuta = { tipo: 'campione' } | { tipo: 'premio'; premio: Premio }

const SFONDO = {
  regular: '/sfondi-fase-verticali/regular_season_vert.png',
  title: '/sfondi-fase-verticali/title_playoffs_vert.png',
} as const

const ORDINE_FASI: Array<Premio['fase']> = ['regular', 'title']
const NOME_FASE = { regular: 'Regular Season', title: 'Title Playoffs' } as const
const FRASE_PREMIO = {
  marcatore: 'Il miglior marcatore',
  assistman: 'Il miglior assistman',
  portiere: 'Il miglior portiere',
} as const

// Rivelazione a scoperta della stagione conclusa: prima il campione del Title
// Playoff, poi i premi individuali uno alla volta (regular season, poi title
// playoff), ognuno con la carta coperta da scoprire.
export function AlboRivelazione({ membership, stagioneId, onFine }: Props) {
  const lega = membership.league!
  const [numero, setNumero] = useState<number | null>(null)
  const [campione, setCampione] = useState<Campione | null>(null)
  const [premi, setPremi] = useState<Premio[]>([])
  const [pronto, setPronto] = useState(false)
  const [indice, setIndice] = useState(0)
  const [svelata, setSvelata] = useState(false)
  const [scatto, setScatto] = useState(0)

  useEffect(() => {
    let vivo = true
    async function carica() {
      const [stagioneRes, playoffRes, classificaRes, tuttiPremi] = await Promise.all([
        supabase.from('seasons').select('numero').eq('id', stagioneId).single(),
        supabase.from('brackets').select('vincitore_team_id').eq('season_id', stagioneId).eq('tipo', 'title').eq('stato', 'concluso').maybeSingle(),
        supabase.from('standings').select('*').eq('season_id', stagioneId),
        caricaPremi(lega.id),
      ])
      if (!vivo) return
      const classifica = (classificaRes.data ?? []) as Standing[]
      const idPlayoff = (playoffRes.data as { vincitore_team_id: number | null } | null)?.vincitore_team_id ?? null
      const riga = idPlayoff != null ? classifica.find((voce) => voce.team_id === idPlayoff) : classifica.find((voce) => voce.posizione === 1)
      const idCampione = idPlayoff ?? riga?.team_id ?? null
      let squadra: Team | null = null
      let stemma: string | undefined
      if (idCampione != null) {
        const { data } = await supabase.from('teams').select('*').eq('id', idCampione).single()
        squadra = (data as Team | null) ?? null
        if (squadra) stemma = (await firmaStemmi([squadra])).get(squadra.id)
      }
      if (!vivo) return
      setNumero((stagioneRes.data as { numero: number } | null)?.numero ?? null)
      setCampione({ squadra, stemma, daPlayoff: idPlayoff != null, posizione: riga?.posizione ?? null })
      setPremi(tuttiPremi.filter((premio) => premio.stagioneId === stagioneId))
      setPronto(true)
    }
    void carica()
    return () => { vivo = false }
  }, [stagioneId, lega.id])

  const battute = useMemo<Battuta[]>(() => {
    const lista: Battuta[] = [{ tipo: 'campione' }]
    for (const fase of ORDINE_FASI) for (const { chiave } of PREMI) {
      const premio = premi.find((voce) => voce.fase === fase && voce.premio === chiave)
      if (premio) lista.push({ tipo: 'premio', premio })
    }
    return lista
  }, [premi])

  const battuta = battute[indice]
  const ultima = indice === battute.length - 1
  const fase: Premio['fase'] = battuta?.tipo === 'premio' ? battuta.premio.fase : 'title'

  // Il campione parte subito con i coriandoli; i premi quando si scopre la carta.
  useEffect(() => {
    if (pronto && battuta?.tipo === 'campione') setScatto((n) => n + 1)
  }, [pronto, battuta?.tipo])

  function scopri() {
    setSvelata(true)
    window.setTimeout(() => setScatto((n) => n + 1), 650)
  }

  function avanti() {
    if (ultima) { onFine(true); return }
    setSvelata(false)
    setIndice((attuale) => attuale + 1)
  }

  if (!pronto || !battuta) {
    return <div className={`albo-riv albo-riv--title`} style={{ backgroundImage: `linear-gradient(rgba(10,9,16,.55), rgba(10,9,16,.82)), url(${SFONDO.title})` }} role="status"><p className="albo-riv__attesa">Preparo l'albo d'oro…</p></div>
  }

  const premio = battuta.tipo === 'premio' ? battuta.premio : null
  const info = premio ? PREMI.find((voce) => voce.chiave === premio.premio)! : null

  return <div className={`albo-riv albo-riv--${fase}`} style={{ backgroundImage: `linear-gradient(rgba(10,9,16,.5), rgba(10,9,16,.84)), url(${SFONDO[fase]})` }} role="dialog" aria-label="Albo d'oro della stagione">
    <CoriandoliOri scatto={scatto} />
    <header className="albo-riv__testa">
      <div className="albo-riv__punti" aria-hidden="true">{battute.map((_, i) => <i className={i === indice ? 'is-attivo' : i < indice ? 'is-fatto' : ''} key={i} />)}</div>
      <button type="button" className="albo-riv__salta" onClick={() => onFine(false)}>Salta ›</button>
    </header>

    <main className="albo-riv__scena" key={indice}>
      <img className="albo-riv__logo" src={LOGO_FASE[fase]} alt="" />

      {!premio && campione && <>
        <p className="albo-riv__occhiello">Stagione {numero ?? ''} · Albo d'oro</p>
        <h1 className="albo-riv__titolo">Congratulazioni!</h1>
        <div className="albo-riv__campione">
          <div className="albo-riv__stemma"><Crest value={campione.squadra?.stemma_url ?? null} imageUrl={campione.stemma} size="large" /></div>
          <strong>{campione.squadra?.nome ?? 'Squadra non disponibile'}</strong>
          <span>{campione.daPlayoff ? 'Campioni del Title Playoff' : 'Campioni della stagione'}</span>
          {campione.daPlayoff && campione.posizione != null && <small>{campione.posizione}ª in stagione regolare</small>}
        </div>
        <button type="button" className="albo-riv__bottone" onClick={avanti}>Scopri i premi</button>
      </>}

      {premio && info && <>
        <p className="albo-riv__occhiello">{NOME_FASE[premio.fase]}</p>
        <h1 className="albo-riv__titolo albo-riv__titolo--frase">{FRASE_PREMIO[premio.premio]} è…</h1>
        <div className={`albo-riv__carta ${svelata ? 'is-svelata' : ''}`}>
          <div className="albo-riv__carta-giro">
            <div className="albo-riv__faccia albo-riv__faccia--dietro" aria-hidden={svelata}>
              <span>?</span>
              <small>{info.titolo}</small>
            </div>
            <div className="albo-riv__faccia albo-riv__faccia--fronte" aria-hidden={!svelata}>
              <div className="albo-riv__valore"><b>{premio.valore}</b><small>{premio.valore === 1 ? info.unita[0] : info.unita[1]}</small></div>
              <div className="albo-riv__foto">{premio.foto ? <img src={premio.foto} alt="" /> : <b aria-hidden="true">{premio.nome.charAt(0)}</b>}</div>
              <strong className="albo-riv__nome">{premio.nome}</strong>
              <span className="albo-riv__squadra"><Crest value={premio.squadra?.stemma_url ?? null} imageUrl={premio.stemmaFirmato} size="small" />{premio.squadra?.nome ?? '—'}</span>
              <em className="albo-riv__etichetta">{info.titolo} · {NOME_FASE[premio.fase]}</em>
            </div>
          </div>
        </div>
        {svelata
          ? <button type="button" className="albo-riv__bottone" onClick={avanti}>{ultima ? 'Vai all\'albo d\'oro' : 'Avanti'}</button>
          : <button type="button" className="albo-riv__bottone" onClick={scopri}>Scopri</button>}
      </>}
    </main>
  </div>
}
