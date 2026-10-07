import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { firmaStemmi } from '../lib/premiAlbo'
import { urlFotoGiocatore } from '../lib/fotoGiocatore'
import { faseLive, mmss, type ScelteLiveGiocatore, type ScelteLiveStato } from '../lib/useScelteLive'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'
import { ReazioniLive } from './ReazioniLive'
import { ruoliIt } from '../lib/ruoli'

type Props = {
  membership: Membership
  stato: ScelteLiveStato
  adesso: number
  onMenu: () => void
  onVaiSorteggio: (() => void) | null
  // Anteprima con dati fittizi: le squadre arrivano da fuori, niente database.
  squadreDemo?: Team[]
}

const FINESTRA_NOME: Record<string, string> = { on: 'ON-Season', off: 'OFF-Season' }
const euro = (v: number) => `${(v / 1_000_000).toFixed(1).replace('.', ',')} M€`

function FotoGiocatore({ g, grande = false }: { g: ScelteLiveGiocatore; grande?: boolean }) {
  const url = urlFotoGiocatore(g.foto_url)
  return <span className={`dlive__foto${grande ? ' dlive__foto--grande' : ''}`}>
    {url ? <img src={url} alt="" decoding="async" /> : <b>{g.nome.split(' ').map((x) => x[0]).slice(0, 2).join('')}</b>}
  </span>
}

// Draft OFF-Season in diretta. Il server ha gia' deciso tutto, ma il giocatore di
// ogni scelta si legge solo dal momento del reveal: 15 secondi di annuncio
// («con la scelta n la squadra X seleziona…»), 15 di reveal, poi la scelta va nel recap.
export function DraftScelteLive({ membership, stato, adesso, onMenu, onVaiSorteggio, squadreDemo }: Props) {
  const league = membership.league as League
  const [squadreReali, setSquadre] = useState<Team[]>([])
  const squadre = squadreDemo ?? squadreReali
  const [stemmi, setStemmi] = useState<Map<number, string>>(new Map())

  useEffect(() => {
    if (squadreDemo) return
    let vivo = true
    void (async () => {
      const { data } = await supabase.from('teams').select('*').eq('league_id', league.id).eq('attiva', true)
      const elenco = (data ?? []) as Team[]
      const firmati = await firmaStemmi(elenco)
      if (!vivo) return
      setSquadre(elenco)
      setStemmi(firmati)
    })()
    return () => { vivo = false }
  }, [league.id, squadreDemo])

  const squadraDi = useMemo(() => new Map(squadre.map((t) => [t.id, t])), [squadre])
  const fase = faseLive(stato, adesso)
  const pick = fase.n > 0 ? stato.picks[fase.n - 1] : undefined
  const squadraPick = pick ? squadraDi.get(pick.team_id) : undefined
  const origine = pick && pick.team_origine_id !== pick.team_id ? squadraDi.get(pick.team_origine_id) : undefined
  const rivelate = stato.picks.filter((p) => p.esito !== null)
  const recap = [...rivelate].reverse()
  const secondiSorteggio = stato.sorteggio_il ? (Date.parse(stato.sorteggio_il) - adesso) / 1000 : null
  const nomeFinestra = `${FINESTRA_NOME[stato.finestra] ?? stato.finestra} ${stato.stagione}`
  const mia = (id: number | undefined) => id !== undefined && id === membership.id

  return <main className="sorteggio dlive">
    <header className="sorteggio__testa">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <button type="button" className="dlive__menu" onClick={onMenu}>‹ Menu</button>
    </header>

    <section className="sorteggio__scena dlive__scena">
      <p className="sorteggio__occhiello">Draft {nomeFinestra}</p>
      <p className="dlive__progresso">
        {fase.stadio === 'prima' ? `${stato.totale} scelte · 30 secondi ciascuna`
          : fase.stadio === 'fine' ? `${stato.totale} scelte su ${stato.totale}`
          : `Scelta ${fase.n} di ${stato.totale}`}
      </p>

      {fase.stadio === 'prima' && <div className="dlive__attesa">
        <h1>Il draft parte tra</h1>
        <div className="dlive__conto-grande">{mmss(fase.rimasti)}</div>
        <p>Si scelgono i giocatori nell'ordine dei playoff: ogni squadra prende il primo giocatore della sua lista ancora libero.</p>
      </div>}

      {fase.stadio === 'intro' && pick && <div className="dlive__intro" key={`i${pick.n}`}>
        <small>Con la scelta numero {pick.n}</small>
        <div className="dlive__stemma"><Crest value={squadraPick?.stemma_url ?? null} imageUrl={squadraPick ? stemmi.get(squadraPick.id) : undefined} size="large" stelle={squadraPick?.titoli_title} /></div>
        <strong>{squadraPick?.nome ?? 'La squadra'}</strong>
        <span className="dlive__seleziona">{mia(pick.team_id) ? 'La tua squadra ' : ''}seleziona<i>.</i><i>.</i><i>.</i></span>
        {origine && <em>scelta ceduta da {origine.nome}</em>}
        <div className="dlive__barra" style={{ ['--p' as string]: `${Math.min(100, (fase.trascorsi / Math.max(1, fase.durataFase)) * 100)}%` }}><b>{Math.ceil(fase.rimasti)}</b></div>
      </div>}

      {fase.stadio === 'reveal' && pick && <div className="dlive__reveal" key={`r${pick.n}`}>
        {pick.esito === null && <p className="dlive__attesa-reveal">Rivelo la scelta<i>.</i><i>.</i><i>.</i></p>}
        {pick.esito === 'usata' && pick.giocatore && <div className={`dlive__carta${mia(pick.team_id) ? ' is-mia' : ''}`}>
          <small>{squadraPick?.nome ?? 'La squadra'} ha scelto</small>
          <FotoGiocatore g={pick.giocatore} grande />
          <strong>{pick.giocatore.nome}</strong>
          <div className="dlive__dati">
            <b className="dlive__ovr">{pick.giocatore.overall}</b>
            <span>{ruoliIt(pick.giocatore.posizioni.slice(0, 3))}</span>
            <span>{pick.giocatore.eta} anni</span>
          </div>
          <div className="dlive__contratto">{euro(pick.giocatore.ingaggio)} · 1 stagione</div>
          <div className="dlive__chi"><Crest value={squadraPick?.stemma_url ?? null} imageUrl={squadraPick ? stemmi.get(squadraPick.id) : undefined} size="small" stelle={squadraPick?.titoli_title} /><span>#{pick.n}</span></div>
        </div>}
        {pick.esito === 'vuota' && <div className="dlive__carta dlive__carta--vuota">
          <small>{squadraPick?.nome ?? 'La squadra'}</small>
          <strong>Nessuna scelta</strong>
          <p>Nella lista non c'era nessun giocatore ancora libero che entrasse nel tetto ingaggi.</p>
        </div>}
        <div className="dlive__barra dlive__barra--reveal" style={{ ['--p' as string]: `${Math.min(100, (fase.trascorsi / Math.max(1, fase.durataFase)) * 100)}%` }}><b>{Math.ceil(fase.rimasti)}</b></div>
      </div>}

      {fase.stadio === 'fine' && <div className="dlive__fine">
        <h1>Draft concluso.</h1>
        {onVaiSorteggio && secondiSorteggio !== null
          ? <>
            <p>{secondiSorteggio > 0 ? `Il sorteggio delle conference parte tra ${mmss(secondiSorteggio)}.` : 'Il sorteggio delle conference è in corso.'}</p>
            <button type="button" className="dlive__vai" onClick={onVaiSorteggio}>Vai al sorteggio delle conference</button>
          </>
          : <p>Le scelte sono nelle rose. Qui sotto il riepilogo.</p>}
      </div>}
    </section>

    <ReazioniLive leagueId={league.id} contesto="draft" mioTeamId={membership.id} sigla={(id) => squadraDi.get(id)?.sigla ?? '—'} demo={squadreDemo ? { teamIds: squadreDemo.map((t) => t.id) } : undefined} />

    <section className="dlive__recap" aria-label="Scelte già rivelate">
      <h2>Scelte rivelate <span>{rivelate.length}<i>/{stato.totale}</i></span></h2>
      {recap.length === 0 && <p className="dlive__vuoto">Le scelte compariranno qui man mano che vengono rivelate.</p>}
      <ol>
        {recap.map((p) => {
          const t = squadraDi.get(p.team_id)
          const nuova = p.n === fase.n && fase.stadio === 'reveal' && fase.trascorsi < 6
          return <li key={p.n} className={`${mia(p.team_id) ? 'is-mia' : ''}${nuova ? ' is-nuova' : ''}${p.esito === 'vuota' ? ' is-vuota' : ''}`}>
            <span className="dlive__n">{p.n}</span>
            <Crest value={t?.stemma_url ?? null} imageUrl={t ? stemmi.get(t.id) : undefined} stelle={t?.titoli_title} />
            <span className="dlive__squadra">{t?.nome ?? '—'}</span>
            {p.giocatore
              ? <><FotoGiocatore g={p.giocatore} /><span className="dlive__nome">{p.giocatore.nome}</span><b className="dlive__ovr">{p.giocatore.overall}</b></>
              : <span className="dlive__nome dlive__nome--vuoto">nessuna scelta</span>}
          </li>
        })}
      </ol>
    </section>
  </main>
}
