import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { LOGO_FASE } from '../lib/faseSquadra'
import { PREMI, caricaPremi, firmaStemmi, type Premio } from '../lib/premiAlbo'
import type { Membership, Standing, Team } from '../types'
import { Crest } from './Crest'
import { ConferenceBadge } from './ConferenceBadge'
import { NOME_CONFERENZA, type Conferenza } from '../lib/conferenze'
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

const ORDINE_FASI: Array<Premio['fase']> = ['regular', 'title']
const ambitiDellaFase = (fase: Premio['fase']): Array<Premio['ambito']> => (fase === 'regular' ? ['est', 'ovest', 'totale'] : ['totale'])
const NOME_FASE = { regular: 'Regular Season', title: 'Title Playoffs' } as const
// Con le conferenze i playoff sono i tre tornei (Champions, Europa, Draft): un solo premio per tutti.
const nomeFase = (fase: Premio['fase'], conferenze: boolean) => (fase === 'title' && conferenze ? 'Playoffs' : NOME_FASE[fase])
const FRASE_PREMIO = {
  marcatore: 'Il miglior marcatore',
  assistman: 'Il miglior assistman',
  portiere: 'Il miglior portiere',
} as const
// Dopo la frase: dove vale il premio. «assoluto» solo nelle leghe con le conferenze.
function suffissoAmbito(ambito: Premio['ambito'], conferenze: boolean, fase: Premio['fase']) {
  if (ambito === 'est') return ' dell’Eastern Conference'
  if (ambito === 'ovest') return ' della Western Conference'
  return conferenze && fase === 'regular' ? ' in assoluto' : ''
}
const ETICHETTA_AMBITO = { est: 'Eastern', ovest: 'Western', totale: 'Assoluto' } as const

function IconaPremio({ tipo }: { tipo: Premio['premio'] }) {
  if (tipo === 'marcatore') return <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M12 7.2l3.4 2.5-1.3 4h-4.2l-1.3-4z" fill="currentColor" /><path d="M12 2v5.2M15.4 9.7l5.3-1.6M14.1 13.7l3.2 4.6M9.9 13.7l-3.2 4.6M8.6 9.7L3.3 8.1" stroke="currentColor" strokeWidth="1.3" /></svg>
  if (tipo === 'assistman') return <svg viewBox="0 0 24 24"><path d="M3 17c4-9 10-11 16-9" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /><path d="M15.5 4.8L19.6 8l-4.4 2.8" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" /><circle cx="5" cy="19" r="2.4" fill="currentColor" /></svg>
  return <svg viewBox="0 0 24 24"><path d="M7 21v-4.5L4.6 11a1.5 1.5 0 012.7-1.3L9 12.5V5a1.5 1.5 0 013 0v5.5V3.8a1.5 1.5 0 013 0v6.7V5.6a1.5 1.5 0 013 0V15c0 3-1.7 4.5-3.5 6z" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" /><path d="M7 18h10" stroke="currentColor" strokeWidth="1.5" /></svg>
}

// Rivelazione a scoperta della stagione conclusa: prima i premi individuali uno alla volta
// (regular season e poi playoff; per ognuno East, West e totale), ognuno con la carta coperta da
// scoprire, poi i vincitori dei tornei: Draft Playoffs, Europa League e Champions League.
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
      // SOLO PROVA (mai nella versione pubblicata): ?provaConferenze finge conferenze, Europa League e premi East/West.
      const finto = import.meta.env.DEV && new URLSearchParams(window.location.search).has('provaConferenze')
      const conConferenze = finto || classifica.some((voce) => voce.conferenza)
      const tabelloni = (tabelloniRes.data ?? []) as Array<{ tipo: string; vincitore_team_id: number | null }>
      const vincitore = (tipi: string[]) => tabelloni.find((t) => tipi.includes(t.tipo) && t.vincitore_team_id != null)?.vincitore_team_id ?? null
      const idDraft = vincitore(['draft'])
      const idEuropa = vincitore(['europa']) ?? (finto ? vincitore(['draft']) : null)
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
        fase: 'draft', sfondo: conConferenze ? SFONDO.draftNuovo : SFONDO.draft, logo: LOGO_FASE.draft,
        squadra: perId.get(idDraft) ?? null, stemma: stemmi.get(idDraft), posizione: pos(idDraft),
      })
      if (idEuropa != null) lista.push({
        chiave: 'europa', titolo: 'Europa League', sottotitolo: 'Vincitori dell’Europa League',
        fase: 'draft', sfondo: SFONDO.draft, logo: LOGO_UEFA.europa,
        squadra: perId.get(idEuropa) ?? null, stemma: stemmi.get(idEuropa), posizione: pos(idEuropa),
      })
      if (idChampions != null) lista.push({
        chiave: 'champions', titolo: conConferenze ? 'Champions League' : 'Title Playoff',
        sottotitolo: conConferenze ? 'Vincitori della Champions League' : daPlayoff ? 'Campioni del Title Playoff' : 'Campioni della stagione',
        fase: 'title', sfondo: SFONDO.title, logo: conConferenze ? LOGO_UEFA.champions : LOGO_FASE.title,
        squadra: perId.get(idChampions) ?? null, stemma: stemmi.get(idChampions), posizione: pos(idChampions),
      })

      setNumero((stagioneRes.data as { numero: number } | null)?.numero ?? null)
      setConferenze(conConferenze)
      setTornei(lista)
      const premiStagione = tuttiPremi.filter((premio) => premio.stagioneId === stagioneId)
      setPremi(finto
        ? [...premiStagione.filter((p) => p.ambito === 'totale').flatMap((p) => p.fase === 'regular' ? [
            { ...p, ambito: 'est' as const, nome: `${p.nome} (finto Est)` },
            { ...p, ambito: 'ovest' as const, nome: `${p.nome} (finto Ovest)` },
            p,
          ] : [p])]
        : premiStagione)
      setPronto(true)
    }
    void carica()
    return () => { vivo = false }
  }, [stagioneId, lega.id])

  // Prima i premi dei giocatori (per ogni fase e premio: East, West, poi il totale), poi i tornei:
  // Draft Playoffs, Europa League e, per ultima, la Champions League (il gran finale con i coriandoli).
  const battute = useMemo<Battuta[]>(() => {
    const lista: Battuta[] = []
    for (const fase of ORDINE_FASI) for (const { chiave } of PREMI) for (const ambito of ambitiDellaFase(fase)) {
      const premio = premi.find((voce) => voce.fase === fase && voce.premio === chiave && voce.ambito === ambito)
      if (premio) lista.push({ tipo: 'premio', premio })
    }
    for (const torneo of tornei) lista.push({ tipo: 'torneo', torneo })
    return lista
  }, [premi, tornei])

  const battuta = battute[indice]
  const ultima = indice === battute.length - 1
  const fase: Premio['fase'] | 'draft' = battuta?.tipo === 'premio' ? battuta.premio.fase : battuta?.torneo.fase ?? 'title'
  const sfondoBattuta = battuta?.tipo === 'torneo' ? battuta.torneo.sfondo : SFONDO[battuta?.tipo === 'premio' ? battuta.premio.fase : 'title']
  const logoBattuta = battuta?.tipo === 'torneo' ? battuta.torneo.logo : LOGO_FASE[battuta?.tipo === 'premio' ? battuta.premio.fase : 'title']

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
      {battuta.tipo === 'premio' && battuta.premio.fase === 'title' && conferenze
        // Premio dei playoff con i tre tornei: i loghi dei tre tornei, non quello di uno solo.
        ? <div className="albo-riv__logo-tornei" aria-hidden="true">
            <img src={LOGO_UEFA.champions} alt="" /><img src={LOGO_UEFA.europa} alt="" /><img src={LOGO_FASE.draft} alt="" />
          </div>
        : <img className="albo-riv__logo" src={logoBattuta} alt="" />}

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
        {premio.ambito !== 'totale' && <div className="albo-riv__conferenza"><ConferenceBadge conferenza={premio.ambito as Conferenza} /><span>{NOME_CONFERENZA[premio.ambito as Conferenza]}</span></div>}
        <h1 className="albo-riv__titolo albo-riv__titolo--frase">{FRASE_PREMIO[premio.premio]}{suffissoAmbito(premio.ambito, conferenze, premio.fase)} è…</h1>
        <div className={`albo-riv__carta ${svelata ? 'is-svelata' : ''}`}>
          <div className="albo-riv__carta-giro">
            <div className="albo-riv__faccia albo-riv__faccia--dietro" aria-hidden={svelata}>
              <div className="albo-retro">
                <i className="albo-carta__raggi" aria-hidden="true" />
                <span className="albo-retro__icona"><IconaPremio tipo={premio.premio} /></span>
                <span className="albo-retro__medaglia"><b>?</b></span>
                <strong className="albo-retro__titolo">{info.titolo}</strong>
                <small className="albo-retro__fase">{nomeFase(premio.fase, conferenze)}{conferenze && premio.fase === 'regular' ? ` · ${ETICHETTA_AMBITO[premio.ambito]}` : ''} · Stagione {numero ?? ''}</small>
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
                  <em className="albo-carta__premio">{info.titolo}<i aria-hidden="true">·</i>{nomeFase(premio.fase, conferenze)}{conferenze && premio.fase === 'regular' && <><i aria-hidden="true">·</i>{ETICHETTA_AMBITO[premio.ambito]}</>}</em>
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
