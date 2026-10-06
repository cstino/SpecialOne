import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { cognome } from '../lib/nomi'
import { fasciaVoto, formatoVoto } from '../lib/voti'
import { useFaseSquadra } from '../lib/faseSquadra'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership, Team } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type Riga = {
  id: number; da_team_id: number; a_team_id: number
  stato: 'in_attesa' | 'accettata' | 'rifiutata' | 'giocata'
  creata_il: string; giocata_il: string | null; gol_da: number | null; gol_a: number | null
}

// Il referto salvato (supabase/functions/simula-giornata, simulaAmichevoleCore). Nessun dato di questa partita
// e' mai finito sui giocatori: sta tutto qui.
type Referto = {
  modulo_casa: string; modulo_ospite: string; stile_casa: string; stile_ospite: string
  titolari_casa: number[]; titolari_ospite: number[]
  eventi: Array<{ tipo: 'gol'; minuto: number; lato: 'casa' | 'ospite'; team_id: number; marcatore: number; assist: number | null; piazzato?: string }>
  cambi: Array<{ minuto: number; lato: 'casa' | 'ospite'; esce: number; entra: number; motivo: 'stanchezza' | 'infortunio' }>
  cartellini: Array<{ minuto: number; lato: 'casa' | 'ospite'; giocatore: number; tipo: 'giallo' | 'rosso_diretto' | 'doppio_giallo' }>
  stats_squadra: { casa: Record<string, number>; ospite: Record<string, number> }
  player_stats: Array<{ player_instance_id: number; team_id: number; minuti: number; gol: number; assist: number }>
  voti: Array<{ id: number; lato: 'casa' | 'ospite'; voto: number | null; migliore: boolean }>
  giocatori: Array<{ id: number; nome: string; team_id: number; posizioni: string[] }>
}

const STAT_RIGHE: Array<[string, string, (v: number) => string]> = [
  ['Possesso', 'possesso', (v) => `${Math.round(v * 100)}%`],
  ['Tiri', 'tiri', String],
  ['Tiri in porta', 'inPorta', String],
  ['Precisione passaggi', 'passaggiPct', (v) => `${Math.round(v * 100)}%`],
  ['Contrasti', 'contrasti', String],
  ['Dribbling', 'dribbling', String],
]
const NOME_STILE: Record<string, string> = {
  equilibrato: 'Equilibrato', contropiede: 'Contropiede', possesso_palla: 'Possesso palla', fasce: 'Gioco sulle fasce',
  recupero_veloce: 'Recupero veloce', diretto: 'Gioco diretto', blocco_basso: 'Difesa a oltranza', personalizzato: 'Personalizzato',
}
const dataBreve = (iso: string) => new Intl.DateTimeFormat('it-IT', { timeZone: 'Europe/Rome', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }).format(new Date(iso))

export function Amichevoli({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const dati = useSeasonData(membership)
  const fase = useFaseSquadra(league.id, membership.id, dati.season?.id)
  const offseason = league.fase_carriera === 'offseason'
  const [squadre, setSquadre] = useState<Team[]>([])
  const [righe, setRighe] = useState<Riga[]>([])
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)
  const [occupato, setOccupato] = useState<number | 'invito' | null>(null)
  const [aperta, setAperta] = useState<number | null>(null)

  const carica = useCallback(async () => {
    const [t, a] = await Promise.all([
      supabase.from('teams').select('*').eq('league_id', league.id).eq('attiva', true),
      supabase.from('amichevoli').select('id, da_team_id, a_team_id, stato, creata_il, giocata_il, gol_da, gol_a').eq('league_id', league.id).order('id', { ascending: false }),
    ])
    if (t.error || a.error) { setErrore((t.error ?? a.error)!.message); setCaricamento(false); return }
    setSquadre((t.data ?? []) as Team[])
    setRighe((a.data ?? []) as Riga[])
    setCaricamento(false)
  }, [league.id])

  useEffect(() => { void carica() }, [carica])
  // Inviti e risposte arrivano da altre persone: si rilegge ogni qualche secondo mentre la pagina e' aperta.
  useEffect(() => {
    const timer = window.setInterval(() => { void carica() }, 6000)
    return () => window.clearInterval(timer)
  }, [carica])

  const perId = useMemo(() => new Map(squadre.map((t) => [t.id, t])), [squadre])
  const nome = (id: number) => perId.get(id)?.nome ?? 'Squadra'
  const mie = membership.id
  const inCorsoCon = (altra: number) => righe.some((r) => (r.stato === 'in_attesa' || r.stato === 'accettata')
    && ((r.da_team_id === mie && r.a_team_id === altra) || (r.da_team_id === altra && r.a_team_id === mie)))
  const ricevuti = righe.filter((r) => r.stato === 'in_attesa' && r.a_team_id === mie)
  const inviati = righe.filter((r) => r.stato === 'in_attesa' && r.da_team_id === mie)
  const daGiocare = righe.filter((r) => r.stato === 'accettata' && (r.da_team_id === mie || r.a_team_id === mie))
  const giocate = righe.filter((r) => r.stato === 'giocata')
  const avversarie = squadre.filter((t) => t.id !== mie && !t.controllata_da_pc && t.user_id)

  // La partita si simula sul server, con le formazioni salvate di ciascuno. Non salva niente sui giocatori.
  async function gioca(id: number) {
    setOccupato(id); setErrore(null)
    const { error } = await supabase.functions.invoke('simula-giornata', { body: { league_id: league.id, amichevole_id: id } })
    if (error) setErrore('La partita non è partita: riprova fra un attimo.')
    await carica()
    setOccupato(null)
  }
  async function invita(altra: number) {
    setOccupato('invito'); setErrore(null)
    const { error } = await supabase.rpc('invia_amichevole', { p_league_id: league.id, p_a_team_id: altra })
    if (error) setErrore(error.message)
    await carica()
    setOccupato(null)
  }
  async function rispondi(id: number, accetta: boolean) {
    setOccupato(id); setErrore(null)
    const { error } = await supabase.rpc('rispondi_amichevole', { p_id: id, p_accetta: accetta })
    if (error) { setErrore(error.message); setOccupato(null); await carica(); return }
    if (accetta) await gioca(id)
    else { await carica(); setOccupato(null) }
  }

  const squadraRiga = (id: number) => <span className="amichevoli__squadra"><Crest value={perId.get(id)?.stemma_url ?? null} stelle={perId.get(id)?.titoli_title} /><strong>{nome(id)}</strong></span>

  return <main className="app-shell season-shell scambi-shell">
    <GameNav league={league} active="amichevoli" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${offseason ? 'e-aperto' : ''}`}>{offseason ? 'Amichevoli aperte' : 'Solo in off-season'}</span>
    </header>

    {caricamento && <div className="season-page"><section className="season-state is-caricamento mercato-caricamento"><LoadingLogo compatto /><h2>Preparo le amichevoli…</h2><span className="caricamento-barra" aria-hidden="true" /></section></div>}

    {!caricamento && aperta === null && <div className={`season-page season-page--narrow scambi-page scambi-broadcast formazione-broadcast formazione-broadcast--${fase}`}>
      <section className="amichevoli__intro">
        <p className="kicker">Prova le tattiche</p>
        <h1>Amichevoli</h1>
        <p>Sfida un'altra squadra per provare formazione e tattiche. È una partita vera, ma <strong>non succede mai</strong>: niente statistiche, infortuni, cartellini, stanchezza o familiarità. Si gioca con le formazioni che hai salvato in Formazione. Le amichevoli giocate le vede tutta la lega.</p>
      </section>
      {errore && <p className="notice notice--error" role="alert">{errore}</p>}

      {ricevuti.length > 0 && <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">In arrivo</p><h2>Inviti ricevuti</h2></div></div>
        <ul className="amichevoli__lista">{ricevuti.map((r) => <li key={r.id}>
          {squadraRiga(r.da_team_id)}
          <span className="amichevoli__azioni">
            <button type="button" className="button button--primary" disabled={occupato !== null} onClick={() => void rispondi(r.id, true)}>{occupato === r.id ? 'Gioco…' : 'Accetta'}</button>
            <button type="button" className="button button--ghost" disabled={occupato !== null} onClick={() => void rispondi(r.id, false)}>Rifiuta</button>
          </span>
        </li>)}</ul>
      </section>}

      {daGiocare.length > 0 && <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">Accettate</p><h2>Da giocare</h2></div></div>
        <ul className="amichevoli__lista">{daGiocare.map((r) => <li key={r.id}>
          <span className="amichevoli__coppia">{squadraRiga(r.da_team_id)}<i>vs</i>{squadraRiga(r.a_team_id)}</span>
          <span className="amichevoli__azioni"><button type="button" className="button button--primary" disabled={occupato !== null} onClick={() => void gioca(r.id)}>{occupato === r.id ? 'Gioco…' : 'Gioca ora'}</button></span>
        </li>)}</ul>
      </section>}

      {offseason && <section className="scambi-blocco">
        <div className="sezione-testa"><div><p className="kicker">Sfida</p><h2>Invita una squadra</h2></div></div>
        {avversarie.length === 0 ? <p className="season-empty">Non ci sono altre squadre da sfidare.</p>
          : <ul className="amichevoli__lista">{avversarie.map((t) => <li key={t.id}>
            {squadraRiga(t.id)}
            <span className="amichevoli__azioni">
              {inCorsoCon(t.id)
                ? <small className="amichevoli__nota">{inviati.some((r) => r.a_team_id === t.id) ? 'Invito inviato' : 'In corso'}</small>
                : <button type="button" className="button button--ghost" disabled={occupato !== null} onClick={() => void invita(t.id)}>Invita</button>}
            </span>
          </li>)}</ul>}
      </section>}

      <section className="scambi-blocco" id="amichevoli-giocate">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p><h2>Amichevoli giocate{giocate.length > 0 && <span className="scambi-conteggio"> {giocate.length}</span>}</h2></div></div>
        {giocate.length === 0 ? <p className="season-empty">Nessuna amichevole giocata, per ora.</p>
          : <ul className="amichevoli__lista amichevoli__lista--giocate">{giocate.map((r) => <li key={r.id}>
            <button type="button" className="amichevoli__partita" onClick={() => setAperta(r.id)}>
              {squadraRiga(r.da_team_id)}
              <span className="amichevoli__punteggio"><b>{r.gol_da}</b><i>-</i><b>{r.gol_a}</b></span>
              {squadraRiga(r.a_team_id)}
              {r.giocata_il && <small>{dataBreve(r.giocata_il)}</small>}
            </button>
          </li>)}</ul>}
      </section>
    </div>}

    {!caricamento && aperta !== null && <div className={`season-page season-page--narrow scambi-page scambi-broadcast formazione-broadcast formazione-broadcast--${fase}`}>
      <ReffertoAmichevole id={aperta} squadre={perId} onIndietro={() => setAperta(null)} />
    </div>}
  </main>
}

// Il referto di un'amichevole: punteggio, marcatori, cronaca, statistiche e formazioni con i voti.
function ReffertoAmichevole({ id, squadre, onIndietro }: { id: number; squadre: Map<number, Team>; onIndietro: () => void }) {
  const [riga, setRiga] = useState<(Riga & { risultato: Referto | null }) | null>(null)
  const [errore, setErrore] = useState<string | null>(null)
  useEffect(() => {
    let vivo = true
    void supabase.from('amichevoli').select('id, da_team_id, a_team_id, stato, creata_il, giocata_il, gol_da, gol_a, risultato').eq('id', id).maybeSingle()
      .then(({ data, error }) => { if (!vivo) return; if (error || !data) setErrore(error?.message ?? 'Amichevole non trovata.'); else setRiga(data as Riga & { risultato: Referto | null }) })
    return () => { vivo = false }
  }, [id])

  if (errore) return <><button type="button" className="button button--ghost" onClick={onIndietro}>‹ Amichevoli</button><p className="season-empty">{errore}</p></>
  if (!riga || !riga.risultato) return <><button type="button" className="button button--ghost" onClick={onIndietro}>‹ Amichevoli</button><p className="season-empty">Carico il referto…</p></>
  const r = riga.risultato
  const casa = squadre.get(riga.da_team_id), ospite = squadre.get(riga.a_team_id)
  const nomi = new Map(r.giocatori.map((g) => [g.id, g]))
  const nomeG = (gid: number | null) => (gid === null ? '' : cognome(nomi.get(gid)?.nome ?? 'Giocatore'))
  const voti = new Map(r.voti.map((v) => [v.id, v]))
  const statG = new Map(r.player_stats.map((s) => [s.player_instance_id, s]))

  type Riga2 = { minuto: number; chiave: string; icona: string; testo: string; lato: 'casa' | 'ospite' }
  const cronaca: Riga2[] = [
    ...r.eventi.map((e, i): Riga2 => ({ minuto: e.minuto, chiave: `g${i}`, icona: '⚽', lato: e.lato, testo: `Gol di ${nomeG(e.marcatore)}${e.assist ? ` (assist ${nomeG(e.assist)})` : ''}${e.piazzato ? ' · da calcio piazzato' : ''}` })),
    ...r.cambi.map((c, i): Riga2 => ({ minuto: c.minuto, chiave: `c${i}`, icona: c.motivo === 'infortunio' ? '✚' : '🔄', lato: c.lato, testo: `${c.motivo === 'infortunio' ? 'Infortunio: ' : 'Cambio: '}esce ${nomeG(c.esce)}, entra ${nomeG(c.entra)}` })),
    ...r.cartellini.map((c, i): Riga2 => ({ minuto: c.minuto, chiave: `k${i}`, icona: c.tipo === 'giallo' ? '🟨' : '🟥', lato: c.lato, testo: `${c.tipo === 'giallo' ? 'Ammonito' : c.tipo === 'doppio_giallo' ? 'Espulso (doppio giallo)' : 'Espulso'}: ${nomeG(c.giocatore)}` })),
  ].sort((a, b) => a.minuto - b.minuto)

  const squadraTit = (lato: 'casa' | 'ospite') => {
    const teamId = lato === 'casa' ? riga.da_team_id : riga.a_team_id
    const tit = new Set(lato === 'casa' ? r.titolari_casa : r.titolari_ospite)
    const giocatori = r.player_stats.filter((s) => s.team_id === teamId && s.minuti > 0)
      .sort((a, b) => Number(tit.has(b.player_instance_id)) - Number(tit.has(a.player_instance_id)) || b.minuti - a.minuti)
    return giocatori.map((s) => {
      const v = voti.get(s.player_instance_id)
      return <li key={s.player_instance_id} className={tit.has(s.player_instance_id) ? 'is-titolare' : ''}>
        <span className="amichevoli__g-nome">{nomi.get(s.player_instance_id)?.nome ?? 'Giocatore'}{v?.migliore && <em title="Migliore in campo"> ★</em>}</span>
        <small>{nomi.get(s.player_instance_id)?.posizioni?.[0] ?? ''} · {s.minuti}'</small>
        <span className="amichevoli__g-azioni">{s.gol > 0 && `⚽${s.gol > 1 ? s.gol : ''}`}{s.assist > 0 && ` 🅰️${s.assist > 1 ? s.assist : ''}`}</span>
        {v && typeof v.voto === 'number' ? <b className={`amichevoli__voto amichevoli__voto--${fasciaVoto(v.voto)}`}>{formatoVoto(v.voto)}</b> : <b className="amichevoli__voto amichevoli__voto--nessuno">–</b>}
      </li>
    })
  }

  return <article className="amichevoli__referto">
    <button type="button" className="button button--ghost" onClick={onIndietro}>‹ Amichevoli</button>
    <p className="amichevoli__etichetta">Amichevole · non conta per classifica e statistiche{riga.giocata_il ? ` · ${dataBreve(riga.giocata_il)}` : ''}</p>
    <div className="amichevoli__testata">
      <div><Crest value={casa?.stemma_url ?? null} stelle={casa?.titoli_title} size="large" /><strong>{casa?.nome ?? 'Squadra'}</strong><small>{r.modulo_casa} · {NOME_STILE[r.stile_casa] ?? r.stile_casa}</small></div>
      <span className="amichevoli__risultato"><b>{riga.gol_da}</b><i>-</i><b>{riga.gol_a}</b></span>
      <div><Crest value={ospite?.stemma_url ?? null} stelle={ospite?.titoli_title} size="large" /><strong>{ospite?.nome ?? 'Squadra'}</strong><small>{r.modulo_ospite} · {NOME_STILE[r.stile_ospite] ?? r.stile_ospite}</small></div>
    </div>

    <section className="scambi-blocco">
      <div className="sezione-testa"><div><p className="kicker">Partita</p><h2>Cronaca</h2></div></div>
      {cronaca.length === 0 ? <p className="season-empty">Nessun evento da raccontare.</p>
        : <ol className="amichevoli__cronaca">{cronaca.map((c) => <li key={c.chiave} className={`amichevoli__evento amichevoli__evento--${c.lato}`}><b>{c.minuto}'</b><span aria-hidden="true">{c.icona}</span><p>{c.testo}</p></li>)}</ol>}
    </section>

    <section className="scambi-blocco">
      <div className="sezione-testa"><div><p className="kicker">Numeri</p><h2>Statistiche</h2></div></div>
      <table className="amichevoli__stats"><tbody>
        {STAT_RIGHE.map(([etichetta, chiave, formato]) => {
          const a = r.stats_squadra.casa[chiave], b = r.stats_squadra.ospite[chiave]
          if (typeof a !== 'number' || typeof b !== 'number') return null
          return <tr key={chiave}><td>{formato(a)}</td><th>{etichetta}</th><td>{formato(b)}</td></tr>
        })}
      </tbody></table>
    </section>

    <section className="scambi-blocco">
      <div className="sezione-testa"><div><p className="kicker">In campo</p><h2>Formazioni e voti</h2></div></div>
      <div className="amichevoli__formazioni">
        <div><h3>{casa?.nome}</h3><ul className="amichevoli__giocatori">{squadraTit('casa')}</ul></div>
        <div><h3>{ospite?.nome}</h3><ul className="amichevoli__giocatori">{squadraTit('ospite')}</ul></div>
      </div>
    </section>
  </article>
}
