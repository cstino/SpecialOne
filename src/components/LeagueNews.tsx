import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import type { Fixture, Match, Standing, Team } from '../types'
import { Crest } from './Crest'
import { formaPerSquadra, type Esito } from './SeasonUI'

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

type Stella = { nome: string; overall: number }
type RosaInfo = { forza: number; stella: Stella | null }

type Props = {
  leagueId: number
  fixtures: Fixture[]
  matches: Match[]
  standings: Standing[]
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

// Scelta deterministica: la stessa partita mostra sempre la stessa variante
// (niente sfarfallio a ogni render), ma partite diverse pescano frasi diverse
// invece del solito unico template ripetuto identico per tutta la lega.
function scegli<T>(seme: number, opzioni: T[]) {
  return opzioni[Math.abs(seme) % opzioni.length]
}

function riassumiForma(nome: string, esiti: Esito[] | undefined) {
  if (!esiti || esiti.length === 0) return `${nome} deve ancora scendere in campo in questa stagione`
  const vittorie = esiti.filter((esito) => esito === 'V').length
  const sconfitte = esiti.filter((esito) => esito === 'P').length
  const ultimo = esiti[esiti.length - 1]
  if (vittorie >= 4) return `${nome} arriva lanciata, ${vittorie} vittorie nelle ultime ${esiti.length}`
  if (sconfitte >= 4) return `${nome} arriva in un momento difficile, quasi solo sconfitte di recente`
  if (ultimo === 'V') return `${nome} arriva dalla vittoria`
  if (ultimo === 'P') return `${nome} cerca il riscatto dopo l'ultimo ko`
  return `${nome} arriva da un pareggio`
}

// Racconto della partita: qualche riga in più di quanto serva a leggere il
// solo risultato, così due 2-1 diversi non producono lo stesso identico testo.
function raccontaPartita(match: Match, homeNome: string, awayNome: string, marcatori: Map<number, string>) {
  const pari = match.gol_home === match.gol_away
  const homeVince = match.gol_home > match.gol_away
  const vincente = homeVince ? homeNome : awayNome
  const perdente = homeVince ? awayNome : homeNome
  const scarto = Math.abs(match.gol_home - match.gol_away)
  const seme = match.id

  const nomeMarcatore = (id: number) => cognome(marcatori.get(id) ?? 'un giocatore')

  const conteggio = new Map<number, number>()
  for (const evento of match.blocchi) conteggio.set(evento.marcatore, (conteggio.get(evento.marcatore) ?? 0) + 1)
  const tripletta = [...conteggio.entries()].find(([, volte]) => volte >= 3)

  const eventiLatoVincente = match.blocchi
    .filter((evento) => evento.lato === (homeVince ? 'casa' : 'ospite'))
    .sort((a, b) => a.minuto - b.minuto)
  const primoTempo = match.blocchi.filter((evento) => evento.minuto <= 45)
  const casaAlloIntervallo = primoTempo.filter((evento) => evento.lato === 'casa').length
  const ospiteAlloIntervallo = primoTempo.filter((evento) => evento.lato === 'ospite').length
  const vincenteSottoAlloIntervallo = homeVince
    ? ospiteAlloIntervallo > casaAlloIntervallo
    : casaAlloIntervallo > ospiteAlloIntervallo
  const cleanSheet = !pari && (homeVince ? match.gol_away === 0 : match.gol_home === 0)

  if (!pari && tripletta) {
    const nome = nomeMarcatore(tripletta[0])
    return {
      titolo: scegli(seme, [
        `Tripletta di ${nome}, ${vincente} vola`,
        `${nome} ne fa tre: ${vincente} travolge ${perdente}`,
        `Show di ${nome}: tre gol per ${vincente}`,
      ]),
      testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. ${nome} entra tre volte nel tabellino e decide da solo la serata di ${vincente} contro ${perdente}.`,
    }
  }

  if (!pari && vincenteSottoAlloIntervallo) {
    const nome = eventiLatoVincente.length ? nomeMarcatore(eventiLatoVincente[eventiLatoVincente.length - 1].marcatore) : null
    return {
      titolo: scegli(seme, [
        `Rimonta ${vincente}: ribaltato ${perdente}`,
        `${vincente} sotto e poi ribalta tutto`,
        `Secondo tempo super: ${vincente} rimonta ${perdente}`,
      ]),
      testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. Sotto nel punteggio all'intervallo, ${vincente} cambia marcia nella ripresa${nome ? ` e trova il sorpasso con ${nome}` : ''}.`,
    }
  }

  if (pari) {
    return {
      titolo: scegli(seme, [
        `${homeNome} e ${awayNome} non si fanno male`,
        `Punto a testa fra ${homeNome} e ${awayNome}`,
        `${homeNome}-${awayNome} si chiude in parità`,
      ]),
      testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. ${scegli(seme + 1, [
        'Un punto a testa al termine di una gara equilibrata.',
        'Nessuna delle due riesce a fare lo strappo decisivo.',
        'Si dividono la posta in una sfida senza grandi scossoni.',
      ])}`,
    }
  }

  if (cleanSheet && scarto >= 2) {
    return {
      titolo: scegli(seme, [
        `${vincente} blinda la porta e travolge ${perdente}`,
        `Difesa granitica: ${vincente} passa senza subire`,
        `${vincente} controlla su tutta la linea contro ${perdente}`,
      ]),
      testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. ${vincente} porta a casa i tre punti senza nemmeno concedere un gol a ${perdente}.`,
    }
  }

  if (scarto >= 3) {
    return {
      titolo: scegli(seme, [
        `${vincente} senza freni: travolto ${perdente}`,
        `Manita, quasi: ${vincente} dilaga contro ${perdente}`,
        `Nessuna pietà: ${vincente} schianta ${perdente}`,
      ]),
      testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. Tre punti pesanti che muovono gli equilibri del campionato.`,
    }
  }

  return {
    titolo: scegli(seme, [
      `${vincente} trova il guizzo e porta a casa la sfida`,
      `${vincente} soffre ma passa contro ${perdente}`,
      `${vincente} regola di misura ${perdente}`,
    ]),
    testo: `${homeNome} ${match.gol_home}-${match.gol_away} ${awayNome}. ${scegli(seme + 1, [
      'Una vittoria stretta, ma tre punti che pesano allo stesso modo.',
      'Basta un episodio a spostare l\'equilibrio di una gara combattuta.',
      'Partita in bilico fino alla fine, decisa nel finale.',
    ])}`,
  }
}

export function LeagueNews({ leagueId, fixtures, matches, standings, teamById, crestUrlByTeamId, onOpenMatch, onOpenTeam }: Props) {
  const [mercato, setMercato] = useState<NewsItem[]>([])
  const [marcatori, setMarcatori] = useState<Map<number, string>>(new Map())
  const [rose, setRose] = useState<Map<number, RosaInfo>>(new Map())
  const [indice, setIndice] = useState(0)
  const oggi = giornoRoma(new Date())

  const matchByFixture = useMemo(() => new Map(matches.map((match) => [match.fixture_id, match])), [matches])
  const forma = useMemo(() => formaPerSquadra(fixtures, matchByFixture), [fixtures, matchByFixture])
  const partiteOggi = useMemo(() => matches.filter((match) => giornoRoma(match.simulata_il) === oggi), [matches, oggi])

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

  // Nomi dei marcatori di oggi: servono a raccontare la partita, non solo il
  // punteggio secco (vedi raccontaPartita).
  useEffect(() => {
    let annullato = false
    async function caricaMarcatori() {
      const ids = [...new Set(partiteOggi.flatMap((match) => match.blocchi.map((evento) => evento.marcatore)))]
      if (ids.length === 0) { setMarcatori(new Map()); return }
      const { data } = await supabase.from('player_instances').select('id,players(nome)').in('id', ids)
      if (annullato) return
      setMarcatori(new Map((data ?? []).map((row) => [row.id as number, (row.players as unknown as { nome: string } | null)?.nome ?? 'un giocatore'])))
    }
    void caricaMarcatori()
    return () => { annullato = true }
  }, [partiteOggi])

  // Forza di rosa (media dei migliori 11 per overall) e giocatore di punta per
  // squadra: servono all'anteprima della prossima giornata (favorita, stelle).
  useEffect(() => {
    let annullato = false
    async function caricaRose() {
      const { data } = await supabase
        .from('player_instances')
        .select('team_id,overall_corrente,players(nome)')
        .eq('league_id', leagueId)
        .eq('ritirato', false)
        .not('team_id', 'is', null)
      if (annullato) return
      const perSquadra = new Map<number, Stella[]>()
      for (const riga of (data ?? []) as unknown as { team_id: number; overall_corrente: number; players: { nome: string } | null }[]) {
        const lista = perSquadra.get(riga.team_id) ?? []
        lista.push({ overall: riga.overall_corrente, nome: riga.players?.nome ?? 'Giocatore' })
        perSquadra.set(riga.team_id, lista)
      }
      const risultato = new Map<number, RosaInfo>()
      for (const [teamId, lista] of perSquadra) {
        const ordinata = [...lista].sort((a, b) => b.overall - a.overall)
        const top11 = ordinata.slice(0, 11)
        const forza = top11.reduce((somma, giocatore) => somma + giocatore.overall, 0) / Math.max(1, top11.length)
        risultato.set(teamId, { forza, stella: ordinata[0] ?? null })
      }
      if (!annullato) setRose(risultato)
    }
    void caricaRose()
    return () => { annullato = true }
  }, [leagueId])

  const risultati = useMemo(() => {
    const fixtureById = new Map(fixtures.map((fixture) => [fixture.id, fixture]))
    return partiteOggi.map((match): NewsItem | null => {
      const fixture = fixtureById.get(match.fixture_id)
      if (!fixture) return null
      const home = teamById.get(fixture.home_team_id)
      const away = teamById.get(fixture.away_team_id)
      const racconto = raccontaPartita(match, home?.nome ?? 'Squadra di casa', away?.nome ?? 'Squadra ospite', marcatori)
      return {
        id: `match-${match.id}`,
        tipo: 'partita',
        occhiello: `MATCH REPORT · GIORNATA ${fixture.giornata}`,
        titolo: racconto.titolo,
        testo: racconto.testo,
        home, away,
        homeCrest: crestUrlByTeamId.get(fixture.home_team_id),
        awayCrest: crestUrlByTeamId.get(fixture.away_team_id),
        action: () => onOpenMatch(match.id),
      }
    }).filter((item): item is NewsItem => Boolean(item))
  }, [fixtures, partiteOggi, marcatori, teamById, crestUrlByTeamId, onOpenMatch])

  // Anteprima della prossima giornata: come arrivano le due squadre, chi
  // parte favorita (forza di rosa) e chi sono le stelle da tenere d'occhio.
  const anteprime = useMemo<NewsItem[]>(() => {
    const prossimaGiornata = fixtures.find((fixture) => fixture.stato === 'programmata' || fixture.stato === 'in_corso')?.giornata
    if (prossimaGiornata == null || rose.size === 0) return []
    return fixtures.filter((fixture) => fixture.giornata === prossimaGiornata).map((fixture): NewsItem | null => {
      const home = teamById.get(fixture.home_team_id)
      const away = teamById.get(fixture.away_team_id)
      if (!home || !away) return null
      const rosaHome = rose.get(home.id)
      const rosaAway = rose.get(away.id)
      const seme = fixture.id

      const scartoForza = (rosaHome?.forza ?? 0) - (rosaAway?.forza ?? 0)
      const rigaFavorita = Math.abs(scartoForza) < 2.5
        ? scegli(seme + 1, ['Equilibrio totale sulla carta.', 'Match apertissimo, nessuna delle due parte favorita.', 'Difficile dare un pronostico netto.'])
        : scartoForza > 0
          ? scegli(seme + 1, [`${home.nome} parte favorita.`, `Pronostico dalla parte di ${home.nome}.`, `${home.nome} è la squadra da battere.`])
          : scegli(seme + 1, [`${away.nome} parte favorita.`, `Pronostico dalla parte di ${away.nome}.`, `${away.nome} è la squadra da battere.`])

      const stelle = [
        rosaHome?.stella ? `${cognome(rosaHome.stella.nome)} (${home.nome}, ${rosaHome.stella.overall} OVR)` : null,
        rosaAway?.stella ? `${cognome(rosaAway.stella.nome)} (${away.nome}, ${rosaAway.stella.overall} OVR)` : null,
      ].filter(Boolean).join(' e ')

      const posHome = standings.find((riga) => riga.team_id === home.id)?.posizione
      const posAway = standings.find((riga) => riga.team_id === away.id)?.posizione
      const rigaClassifica = posHome && posAway
        ? `In classifica è ${posHome}ª contro ${posAway}ª.`
        : null

      const testo = [
        `${riassumiForma(home.nome, forma.get(home.id))}. ${riassumiForma(away.nome, forma.get(away.id))}.`,
        rigaClassifica,
        rigaFavorita,
        stelle ? `Da tenere d'occhio ${stelle}.` : null,
      ].filter(Boolean).join(' ')

      return {
        id: `preview-${fixture.id}`,
        tipo: 'partita',
        occhiello: `ANTEPRIMA · GIORNATA ${fixture.giornata}`,
        titolo: scegli(seme, [
          `${home.nome} - ${away.nome}, chi la spunta?`,
          `${home.nome} contro ${away.nome}: tutto pronto`,
          `Si avvicina ${home.nome}-${away.nome}`,
        ]),
        testo,
        home, away,
        homeCrest: crestUrlByTeamId.get(home.id),
        awayCrest: crestUrlByTeamId.get(away.id),
        action: () => onOpenTeam(home.id),
      }
    }).filter((item): item is NewsItem => Boolean(item))
  }, [fixtures, rose, forma, standings, teamById, crestUrlByTeamId, onOpenTeam])

  const notizie = useMemo<NewsItem[]>(() => {
    const raccolta = [...risultati, ...mercato]
    if (raccolta.length) return raccolta
    if (anteprime.length) return anteprime
    return [{
      id: 'quiet-day', tipo: 'sistema', occhiello: 'SPECIALONE DAILY',
      titolo: 'La quiete prima del prossimo fischio d’inizio',
      testo: 'Nessun risultato o movimento ufficiale registrato oggi. Le dirigenze lavorano, il mercato osserva.',
    }]
  }, [risultati, mercato, anteprime])

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
