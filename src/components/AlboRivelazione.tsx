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

type Torneo = {
  chiave: 'draft' | 'europa' | 'champions'
  titolo: string
  sottotitolo: string
  fase: 'regular' | 'title' | 'draft'
  sfondo: string
  logo: string
  squadra: Team | null
  stemma?: string
  posizione: number | null
}
type Battuta = { tipo: 'torneo'; torneo: Torneo } | { tipo: 'premio'; premio: Premio }

const SFONDO = {
  regular: '/sfondi-fase-verticali/regular_season_vert.png',
  title: '/sfondi-fase-verticali/title_playoffs_vert.png',
  draft: '/sfondi-fase-verticali/draft_playoffs_vert.png',
  draftNuovo: '/sfondi-fase-verticali/draft_playoffs_nuovo_vert.webp',
} as const
const LOGO_UEFA = {
  champions: '/loghi-fase/uefa/champions-league.png',
  europa: '/loghi-fase/uefa/europa-league.png',
} as const

// «Regular Season» o il nome del torneo del premio.
const etichettaFase = (premio: Premio, conferenze: boolean) => premio.fase === 'regular' ? 'Regular Season' : NOME_TORNEO(premio.ambito as Torneo['chiave'], conferenze)
const ORDINE_TORNEI: Array<Torneo['chiave']> = ['draft', 'europa', 'champions']
const FRASE_PREMIO = {
  marcatore: 'Il miglior marcatore',
  assistman: 'Il miglior assistman',
  portiere: 'Il miglior portiere',
} as const
// Nome del torneo: con le conferenze la Champions League, senza il Title Playoff.
const NOME_TORNEO = (chiave: Torneo['chiave'], conferenze: boolean) =>
  chiave === 'draft' ? 'Draft Playoffs' : chiave === 'europa' ? 'Europa League' : conferenze ? 'Champions League' : 'Title Playoff'
const DEL_TORNEO = (chiave: Torneo['chiave'], conferenze: boolean) =>
  chiave === 'draft' ? ' dei Draft Playoffs' : chiave === 'europa' ? ' dell’Europa League' : conferenze ? ' della Champions League' : ' del Title Playoff'
// Sfondo e logo di un torneo (e dei suoi premi).
function aspettoTorneo(chiave: Torneo['chiave'], conferenze: boolean) {
  if (chiave === 'draft') return { fase: 'draft' as const, sfondo: conferenze ? SFONDO.draftNuovo : SFONDO.draft, logo: LOGO_FASE.draft }
  if (chiave === 'europa') return { fase: 'draft' as const, sfondo: SFONDO.draft, logo: LOGO_UEFA.europa }
  return { fase: 'title' as const, sfondo: SFONDO.title, logo: conferenze ? LOGO_UEFA.champions : LOGO_FASE.title }
}

function IconaPremio({ tipo }: { tipo: Premio['premio'] }) {
  if (tipo === 'marcatore') return <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M12 7.2l3.4 2.5-1.3 4h-4.2l-1.3-4z" fill="currentColor" /><path d="M12 2v5.2M15.4 9.7l5.3-1.6M14.1 13.7l3.2 4.6M9.9 13.7l-3.2 4.6M8.6 9.7L3.3 8.1" stroke="currentColor" strokeWidth="1.3" /></svg>
  if (tipo === 'assistman') return <svg viewBox="0 0 24 24"><path d="M3 17c4-9 10-11 16-9" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /><path d="M15.5 4.8L19.6 8l-4.4 2.8" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /><circle cx="5" cy="19" r="2.4" fill="currentColor" /></svg>
  return <svg viewBox="0 0 24 24"><path d="M7 21v-4.5L4.6 11a1.5 1.5 0 012.7-1.3L9 12.5V5a1.5 1.5 0 013 0v5.5V3.8a1.5 1.5 0 013 0v6.7V5.6a1.5 1.5 0 013 0V15c0 3-1.7 4.5-3.5 6z" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" /><path d="M7 18h10" stroke="currentColor" strokeWidth="1.5" /></svg>
}

// Rivelazione a scoperta della stagione conclusa: prima i tre premi individuali della stagione regolare,
// poi un blocco per ogni torneo (Draft Playoffs, Europa League, Champions League per ultima): i suoi tre
// premi individuali, ognuno con la carta coperta da scoprire, e infine la squadra vincitrice.
export function AlboRivelazione({ membership, stagioneId, onFine }: Props) {
  const lega = membership.league!
  const [numero, setNumero] = useState<number | null>(null)
  const [tornei, setTornei] = useState<Torneo[]>([])
  const [conferenze, setConferenze] = useState(false)
  const [premi, setPremi] = useState<Premio[]>([])
  const [pronto, setPronto] = useState(false)
  const [indice, setIndice] = useState(0)
  const [svelata, setSvelata] = useState(false)
  const [scatto, setScatto] = useState(0)

  useEffect(() => {
    let vivo = true
    async function carica() {
      const [stagioneRes, tabelloniRes, classificaRes, tuttiPremi] = await Promise.all([
        supabase.from('seasons').select('numero').eq('id', stagioneId).single(),
        supabase.from('brackets').select('tipo, vincitore_team_id').eq('season_id', stagioneId).eq('stato', 'concluso'),
        supabase.from('standings').select('*').eq('season_id', stagioneId),
        caricaPremi(lega.id),
      ])
      if (!vivo) return
      const classifica = (classificaRes.data ?? []) as Standing[]
      const conConferenze = classifica.some((voce) => voce.conferenza)
      const tabelloni = (tabelloniRes.data ?? []) as Array<{ tipo: string; vincitore_team_id: number | null }>
      const vincitore = (tipi: string[]) => tabelloni.find((t) => tipi.includes(t.tipo) && t.vincitore_team_id != null)?.vincitore_team_id ?? null
      const idDraft = vincitore(['draft'])
      const idEuropa = vincitore(['europa'])
      let idChampions = vincitore(['champions', 'title'])
      // Senza il tabellone del titolo (leghe piccole) il campione e' il primo della stagione regolare.
      const daPlayoff = idChampions != null
      if (idChampions == null && !conConferenze) idChampions = classifica.find((voce) => voce.posizione === 1)?.team_id ?? null

      const ids = [idDraft, idEuropa, idChampions].filter((id): id is number => id != null)
      const { data: squadreDati } = ids.length ? await supabase.from('teams').select('*').in('id', ids) : { data: [] }
      const squadre = (squadreDati ?? []) as Team[]
      const perId = new Map(squadre.map((squadra) => [squadra.id, squadra]))
      const stemmi = await firmaStemmi(squadre)
      if (!vivo) return
      const pos = (id: number | null) => (id != null ? classifica.find((voce) => voce.team_id === id)?.posizione ?? null : null)

      const lista: Torneo[] = []
      if (idDraft != null) lista.push({
        chiave: 'draft', titolo: 'Draft Playoffs', sottotitolo: 'Vincitori dei Draft Playoffs',
        ...aspettoTorneo('draft', conConferenze),
        squadra: perId.get(idDraft) ?? null, stemma: stemmi.get(idDraft), posizione: pos(idDraft),
      })
      if (idEuropa != null) lista.push({
        chiave: 'europa', titolo: 'Europa League', sottotitolo: 'Vincitori dell’Europa League',
        ...aspettoTorneo('europa', conConferenze),
        squadra: perId.get(idEuropa) ?? null, stemma: stemmi.get(idEuropa), posizione: pos(idEuropa),
      })
      if (idChampions != null) lista.push({
        chiave: 'champions', titolo: NOME_TORNEO('champions', conConferenze),
        sottotitolo: conConferenze ? 'Vincitori della Champions League' : daPlayoff ? 'Campioni del Title Playoff' : 'Campioni della stagione',
        ...aspettoTorneo('champions', conConferenze),
        squadra: perId.get(idChampions) ?? null, stemma: stemmi.get(idChampions), posizione: pos(idChampions),
      })

      setNumero((stagioneRes.data as { numero: number } | null)?.numero ?? null)
      setConferenze(conConferenze)
      setTornei(lista)
      const premiStagione = tuttiPremi.filter((premio) => premio.stagioneId === stagioneId)
      setPremi(premiStagione)
      setPronto(true)
    }
    void carica()
    return () => { vivo = false }
  }, [stagioneId, lega.id])

  // Stagione regolare (3 premi), poi per ogni torneo i suoi 3 premi e la squadra vincitrice:
  // Draft Playoffs, Europa League e, per ultima, la Champions League (il gran finale con i coriandoli).
  const battute = useMemo<Battuta[]>(() => {
    const lista: Battuta[] = []
    for (const { chiave } of PREMI) {
      const premio = premi.find((voce) => voce.fase === 'regular' && voce.premio === chiave)
      if (premio) lista.push({ tipo: 'premio', premio })
    }
    for (const chiaveTorneo of ORDINE_TORNEI) {
      for (const { chiave } of PREMI) {
        const premio = premi.find((voce) => voce.fase === 'title' && voce.ambito === chiaveTorneo && voce.premio === chiave)
        if (premio) lista.push({ tipo: 'premio', premio })
      }
      const torneo = tornei.find((voce) => voce.chiave === chiaveTorneo)
      if (torneo) lista.push({ tipo: 'torneo', torneo })
    }
    return lista
  }, [premi, tornei])

  const battuta = battute[indice]
  const ultima = indice === battute.length - 1
  // Aspetto della scena: stagione regolare per i premi della regular, altrimenti quello del torneo.
  const chiaveBattuta: Torneo['chiave'] | null = battuta?.tipo === 'torneo' ? battuta.torneo.chiave
    : battuta?.tipo === 'premio' && battuta.premio.fase === 'title' ? (battuta.premio.ambito as Torneo['chiave']) : null
  const aspetto = chiaveBattuta ? aspettoTorneo(chiaveBattuta, conferenze) : { fase: 'regular' as const, sfondo: SFONDO.regular, logo: LOGO_FASE.regular }
  const fase = aspetto.fase
  const sfondoBattuta = aspetto.sfondo
  const logoBattuta = aspetto.logo

  // I tornei partono subito con i coriandoli (la Champions e' l'ultima); i premi quando si scopre la carta.
  useEffect(() => {
    if (pronto && battuta?.tipo === 'torneo') setScatto((n) => n + 1)
  }, [pronto, battuta?.tipo, indice])

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

  return <div className={`albo-riv albo-riv--${fase}`} style={{ backgroundImage: `linear-gradient(rgba(10,9,16,.5), rgba(10,9,16,.84)), url(${sfondoBattuta})` }} role="dialog" aria-label="Albo d'oro della stagione">
    <CoriandoliOri scatto={scatto} />
    <header className="albo-riv__testa">
      <div className="albo-riv__punti" aria-hidden="true">{battute.map((_, i) => <i className={i === indice ? 'is-attivo' : i < indice ? 'is-fatto' : ''} key={i} />)}</div>
      <button type="button" className="albo-riv__salta" onClick={() => onFine(false)}>Salta ›</button>
    </header>

    <main className="albo-riv__scena" key={indice}>
      <img className="albo-riv__logo" src={logoBattuta} alt="" />

      {battuta.tipo === 'torneo' && <>
        <p className="albo-riv__occhiello">Stagione {numero ?? ''} · {battuta.torneo.titolo}</p>
        <h1 className="albo-riv__titolo">Congratulazioni!</h1>
        <div className="albo-riv__campione">
          <div className="albo-riv__stemma"><Crest value={battuta.torneo.squadra?.stemma_url ?? null} stelle={battuta.torneo.squadra?.titoli_title} imageUrl={battuta.torneo.stemma} size="large" /></div>
          <strong>{battuta.torneo.squadra?.nome ?? 'Squadra non disponibile'}</strong>
          <span>{battuta.torneo.sottotitolo}</span>
          {battuta.torneo.posizione != null && <small>{battuta.torneo.posizione}ª in stagione regolare</small>}
        </div>
        <button type="button" className="albo-riv__bottone" onClick={avanti}>{ultima ? 'Vai all\'albo d\'oro' : 'Avanti'}</button>
      </>}

      {premio && info && <>
        <p className="albo-riv__occhiello">Stagione {numero ?? ''} · Premi</p>
        <h1 className="albo-riv__titolo albo-riv__titolo--frase">{FRASE_PREMIO[premio.premio]}{premio.fase === 'title' ? DEL_TORNEO(premio.ambito as Torneo['chiave'], conferenze) : ''} è…</h1>
        <div className={`albo-riv__carta ${svelata ? 'is-svelata' : ''}`}>
          <div className="albo-riv__carta-giro">
            <div className="albo-riv__faccia albo-riv__faccia--dietro" aria-hidden={svelata}>
              <div className="albo-retro">
                <i className="albo-carta__raggi" aria-hidden="true" />
                <span className="albo-retro__icona"><IconaPremio tipo={premio.premio} /></span>
                <span className="albo-retro__medaglia"><b>?</b></span>
                <strong className="albo-retro__titolo">{info.titolo}</strong>
                <small className="albo-retro__fase">{etichettaFase(premio, conferenze)} · Stagione {numero ?? ''}</small>
              </div>
            </div>
            <div className="albo-riv__faccia albo-riv__faccia--fronte" aria-hidden={!svelata}>
              <div className="albo-carta">
                <i className="albo-carta__raggi" aria-hidden="true" />
                <div className="albo-carta__lato">
                  <b className="albo-carta__valore">{premio.valore}</b>
                  <small className="albo-carta__unita">{premio.valore === 1 ? info.unita[0] : info.unita[1]}</small>
                  <i className="albo-carta__filo" aria-hidden="true" />
                  <span className="albo-carta__icona" aria-hidden="true"><IconaPremio tipo={premio.premio} /></span>
                  <span className="albo-carta__stemma"><Crest value={premio.squadra?.stemma_url ?? null} stelle={premio.squadra?.titoli_title} imageUrl={premio.stemmaFirmato} size="small" /></span>
                </div>
                <div className="albo-carta__foto">{premio.foto ? <img src={premio.foto} alt="" /> : <b aria-hidden="true">{premio.nome.charAt(0)}</b>}</div>
                <div className="albo-carta__fondo">
                  <strong className="albo-carta__nome">{premio.nome}</strong>
                  <span className="albo-carta__squadra">
                    <Crest value={premio.squadra?.stemma_url ?? null} stelle={premio.squadra?.titoli_title} imageUrl={premio.stemmaFirmato} size="small" />
                    <span>{premio.squadra?.nome ?? '—'}</span>
                  </span>
                  <em className="albo-carta__premio">{info.titolo}<i aria-hidden="true">·</i>{etichettaFase(premio, conferenze)}</em>
                </div>
              </div>
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
