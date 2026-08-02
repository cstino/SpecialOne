import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { Fixture, Match, Team } from '../types'
import { Crest } from './Crest'

type NewsItem = {
  id: string
  tipo: 'partita' | 'mercato' | 'sistema'
  occhiello: string
  titolo: string
  testo: string
  image?: string
  home?: Team
  away?: Team
  homeCrest?: string
  awayCrest?: string
  action?: () => void
}

type AstaNews = {
  id: number
  player_id: number
  vincitore_team_id: number | null
  ingaggio_finale: number | null
  players: { nome: string; foto_url: string | null } | null
}

type TradeNews = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  risolta_il: string | null
}

type Props = {
  leagueId: number
  fixtures: Fixture[]
  matches: Match[]
  teamById: Map<number, Team>
  crestUrlByTeamId: Map<number, string>
  onOpenMatch: (matchId: number) => void
  onOpenTeam: (teamId: number) => void
}

function giornoRoma(value: Date | string) {
  const parti = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(typeof value === 'string' ? new Date(value) : value)
  const leggi = (tipo: string) => parti.find((parte) => parte.type === tipo)?.value ?? ''
  return `${leggi('year')}-${leggi('month')}-${leggi('day')}`
}

function milioni(value: number | null) {
  if (!value) return 'ingaggio riservato'
  return `${(value / 1_000_000).toLocaleString('it-IT', { maximumFractionDigits: 1 })} M€/stagione`
}

async function firmaFoto(path: string | null | undefined) {
  if (!path) return undefined
  if (path.startsWith('http')) return path
  const { data } = await supabase.storage.from('player-photos').createSignedUrl(path, 3600)
  return data?.signedUrl
}

export function LeagueNews({ leagueId, fixtures, matches, teamById, crestUrlByTeamId, onOpenMatch, onOpenTeam }: Props) {
  const [mercato, setMercato] = useState<NewsItem[]>([])
  const [indice, setIndice] = useState(0)
  const oggi = giornoRoma(new Date())

  useEffect(() => {
    let annullato = false
    async function caricaMercato() {
      const [asteResult, tradeResult] = await Promise.all([
        supabase.from('free_agent_auctions')
          .select('id,player_id,vincitore_team_id,ingaggio_finale,players(nome,foto_url)')
          .eq('league_id', leagueId).eq('giorno', oggi).eq('stato', 'assegnata')
          .order('id', { ascending: false }).limit(12),
        supabase.from('trade_proposals')
          .select('id,da_team_id,a_team_id,giocatori_offerti,giocatori_richiesti,risolta_il')
          .eq('league_id', leagueId).eq('stato', 'accettata')
          .order('risolta_il', { ascending: false }).limit(30),
      ])
      if (annullato) return

      const aste = (asteResult.data ?? []) as unknown as AstaNews[]
      const scambi = ((tradeResult.data ?? []) as TradeNews[]).filter((trade) => trade.risolta_il && giornoRoma(trade.risolta_il) === oggi)
      const instanceIds = [...new Set(scambi.flatMap((trade) => [...trade.giocatori_offerti, ...trade.giocatori_richiesti]))]
      const { data: istanze } = instanceIds.length
        ? await supabase.from('player_instances').select('id,players(nome,foto_url)').in('id', instanceIds)
        : { data: [] }
      const anagrafica = new Map((istanze ?? []).map((row) => [row.id, row.players as unknown as { nome: string; foto_url: string | null } | null]))

      const notizieAste = await Promise.all(aste.filter((asta) => asta.vincitore_team_id).map(async (asta): Promise<NewsItem> => {
        const squadra = teamById.get(asta.vincitore_team_id!)
        const nome = asta.players?.nome ?? 'Un nuovo giocatore'
        return {
          id: `asta-${asta.id}`,
          tipo: 'mercato',
          occhiello: 'CALCIOMERCATO · UFFICIALE',
          titolo: `${squadra?.nome ?? 'Una squadra'} piazza il colpo ${nome}`,
          testo: `Operazione chiusa: il giocatore firma per ${milioni(asta.ingaggio_finale)}. Ora la parola passa al campo.`,
          image: await firmaFoto(asta.players?.foto_url),
          action: () => onOpenTeam(asta.vincitore_team_id!),
        }
      }))

      const notizieScambi = await Promise.all(scambi.map(async (trade): Promise<NewsItem> => {
        const da = teamById.get(trade.da_team_id)?.nome ?? 'Club cedente'
        const a = teamById.get(trade.a_team_id)?.nome ?? 'Club acquirente'
        const coinvolti = [...trade.giocatori_offerti, ...trade.giocatori_richiesti]
        const nomi = coinvolti.map((id) => anagrafica.get(id)?.nome).filter(Boolean) as string[]
        const protagonista = nomi[0] ?? 'un nuovo rinforzo'
        const foto = anagrafica.get(coinvolti[0])?.foto_url
        return {
          id: `trade-${trade.id}`,
          tipo: 'mercato',
          occhiello: 'BREAKING NEWS · SCAMBIO',
          titolo: `${da} e ${a}, accordo totale per ${protagonista}`,
          testo: nomi.length > 1 ? `Affare definito: nell’operazione sono coinvolti ${nomi.join(', ')}.` : 'Le due dirigenze hanno depositato l’accordo e il trasferimento è ufficiale.',
          image: await firmaFoto(foto),
          action: () => onOpenTeam(trade.a_team_id),
        }
      }))
      if (!annullato) setMercato([...notizieAste, ...notizieScambi])
    }
    void caricaMercato()
    return () => { annullato = true }
  }, [leagueId, oggi, teamById, onOpenTeam])

  const risultati = useMemo(() => {
    const fixtureById = new Map(fixtures.map((fixture) => [fixture.id, fixture]))
    return matches.filter((match) => giornoRoma(match.simulata_il) === oggi).map((match): NewsItem | null => {
      const fixture = fixtureById.get(match.fixture_id)
      if (!fixture) return null
      const home = teamById.get(fixture.home_team_id)
      const away = teamById.get(fixture.away_team_id)
      const pari = match.gol_home === match.gol_away
      const homeVince = match.gol_home > match.gol_away
      const vincente = homeVince ? home?.nome : away?.nome
      const perdente = homeVince ? away?.nome : home?.nome
      const scarto = Math.abs(match.gol_home - match.gol_away)
      const titolo = pari
        ? `${home?.nome ?? 'Casa'} e ${away?.nome ?? 'Ospiti'} non si fanno male`
        : scarto >= 3
          ? `${vincente} senza freni: travolto ${perdente}`
          : `${vincente} trova il guizzo e porta a casa la sfida`
      return {
        id: `match-${match.id}`,
        tipo: 'partita',
        occhiello: `MATCH REPORT · GIORNATA ${fixture.giornata}`,
        titolo,
        testo: `${home?.nome ?? 'Squadra di casa'} ${match.gol_home}-${match.gol_away} ${away?.nome ?? 'Squadra ospite'}. ${pari ? 'Un punto a testa al termine di una gara combattuta.' : 'Tre punti pesanti che muovono gli equilibri del campionato.'}`,
        home, away,
        homeCrest: crestUrlByTeamId.get(fixture.home_team_id),
        awayCrest: crestUrlByTeamId.get(fixture.away_team_id),
        action: () => onOpenMatch(match.id),
      }
    }).filter((item): item is NewsItem => Boolean(item))
  }, [fixtures, matches, oggi, teamById, crestUrlByTeamId, onOpenMatch])

  const notizie = useMemo<NewsItem[]>(() => {
    const raccolta = [...risultati, ...mercato]
    return raccolta.length ? raccolta : [{
      id: 'quiet-day', tipo: 'sistema', occhiello: 'SPECIALONE DAILY',
      titolo: 'La quiete prima del prossimo fischio d’inizio',
      testo: 'Nessun risultato o movimento ufficiale registrato oggi. Le dirigenze lavorano, il mercato osserva.',
    }]
  }, [risultati, mercato])

  useEffect(() => {
    setIndice((corrente) => Math.min(corrente, notizie.length - 1))
    if (notizie.length < 2) return
    const timer = window.setInterval(() => setIndice((corrente) => (corrente + 1) % notizie.length), 6500)
    return () => window.clearInterval(timer)
  }, [notizie.length])

  const attiva = notizie[indice] ?? notizie[0]
  return <article className={`league-news league-news--${attiva.tipo}`}>
    <header className="league-news__heading"><div><p className="kicker">Newsroom</p><h2>Oggi nella lega</h2></div><span>LIVE</span></header>
    <div className="league-news__viewport">
      <button className="league-news__story" type="button" onClick={attiva.action} disabled={!attiva.action}>
        <div className="league-news__copy"><small>{attiva.occhiello}</small><strong>{attiva.titolo}</strong><p>{attiva.testo}</p>{attiva.action && <em>Leggi la storia →</em>}</div>
        <div className="league-news__visual" aria-hidden="true">
          {attiva.image ? <img src={attiva.image} alt="" /> : attiva.home && attiva.away ? <div className="league-news__duel"><Crest value={attiva.home.stemma_url} imageUrl={attiva.homeCrest} size="large" /><b>VS</b><Crest value={attiva.away.stemma_url} imageUrl={attiva.awayCrest} size="large" /></div> : <img src="/specialone-mark.svg" alt="" className="league-news__mark" />}
        </div>
      </button>
    </div>
    {notizie.length > 1 && <footer className="league-news__controls"><button type="button" aria-label="Notizia precedente" onClick={() => setIndice((indice - 1 + notizie.length) % notizie.length)}>‹</button><div>{notizie.map((notizia, posizione) => <button key={notizia.id} className={posizione === indice ? 'is-active' : ''} type="button" aria-label={`Vai alla notizia ${posizione + 1}`} onClick={() => setIndice(posizione)} />)}</div><button type="button" aria-label="Notizia successiva" onClick={() => setIndice((indice + 1) % notizie.length)}>›</button></footer>}
  </article>
}
