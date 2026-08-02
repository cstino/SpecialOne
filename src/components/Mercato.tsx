import { useCallback, useEffect, useMemo, useState } from 'react'
import { cognome } from '../lib/nomi'
import { supabase } from '../lib/supabase'
import { useSeasonData } from '../lib/useSeasonData'
import type { League, Membership } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type StatoProposta = 'in_attesa' | 'accettata' | 'rifiutata' | 'ritirata' | 'scaduta'

type Proposta = {
  id: number
  da_team_id: number
  a_team_id: number
  giocatori_offerti: number[]
  giocatori_richiesti: number[]
  conguaglio: number
  messaggio: string | null
  stato: StatoProposta
  creata_il: string
  scade_il: string
}

type Giocatore = {
  id: number
  team_id: number
  overall: number
  eta: number
  ingaggio: number
  nome: string
  ruolo: string
}

type Asta = {
  id: number
  giorno: string
  player_id: number
  ingaggio_teorico: number
  stato: 'aperta' | 'assegnata' | 'deserta'
  vincitore_team_id: number | null
  ingaggio_finale: number | null
}

type Anagrafica = { nome: string; ruolo: string; overall: number; eta: number }

// Il mercato apre alle 07:00 e chiude alle 21:00 (design §9.1, orario deciso
// il 2 agosto 2026). Qui serve solo a non far comporre una proposta che il
// database rifiuterebbe: la regola vera sta nella RPC, dove non e' aggirabile
// cambiando l'orologio del telefono.
function oraDiRoma() {
  return Number(new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', hour: '2-digit', hour12: false,
  }).format(new Date()))
}

function mercatoAperto() {
  const ora = oraDiRoma()
  return ora >= 7 && ora < 21
}

function milioni(euro: number) {
  return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

const ETICHETTE_STATO: Record<StatoProposta, string> = {
  in_attesa: 'In attesa',
  accettata: 'Accettata',
  rifiutata: 'Rifiutata',
  ritirata: 'Ritirata',
  scaduta: 'Scaduta',
}

export function Mercato({ membership, onNavigate }: Props) {
  const league = membership.league as League
  // Squadre e stemmi arrivano da qui: firmare le URL degli stemmi e' gia'
  // risolto, e rifarlo a mano avrebbe prodotto una seconda verita'.
  const dati = useSeasonData(membership)
  const [rose, setRose] = useState<Giocatore[]>([])
  const [proposte, setProposte] = useState<Proposta[]>([])
  const [aste, setAste] = useState<Asta[]>([])
  const [svincolati, setSvincolati] = useState<Map<number, Anagrafica>>(new Map())
  // Solo le proprie: la RLS non consegna quelle altrui, ed e' il punto.
  const [mieOfferte, setMieOfferte] = useState<Map<number, number>>(new Map())
  const [bozzaOfferta, setBozzaOfferta] = useState<Record<number, string>>({})
  // Offrire impegna il denaro: quello che conta non e' il budget ma cio' che
  // resta dopo aver messo da parte le offerte ancora in gioco.
  const [conti, setConti] = useState<{ disponibile: number; impegnato: number; slot_liberi: number } | null>(null)
  const [caricamento, setCaricamento] = useState(true)
  const [errore, setErrore] = useState<string | null>(null)

  const [avversaria, setAvversaria] = useState<number | null>(null)
  const [chiesti, setChiesti] = useState<number[]>([])
  const [offerti, setOfferti] = useState<number[]>([])
  const [conguaglio, setConguaglio] = useState('0')
  const [messaggio, setMessaggio] = useState('')
  const [inCorso, setInCorso] = useState(false)
  const [esito, setEsito] = useState<string | null>(null)

  const aperto = mercatoAperto()

  const carica = useCallback(async () => {
    setCaricamento(true)
    setErrore(null)
    const [istanzeRes, proposteRes, asteRes, offerteRes, contiRes] = await Promise.all([
      supabase.from('player_instances')
        .select('id, team_id, player_id, overall_corrente, eta_corrente, ingaggio')
        .eq('league_id', league.id).not('team_id', 'is', null),
      supabase.from('trade_proposals').select('*')
        .eq('league_id', league.id).order('creata_il', { ascending: false }),
      supabase.from('free_agent_auctions')
        .select('id, giorno, player_id, ingaggio_teorico, stato, vincitore_team_id, ingaggio_finale')
        .eq('league_id', league.id).order('giorno', { ascending: false }).order('id').limit(60),
      supabase.from('free_agent_bids').select('auction_id, ingaggio_offerto'),
      supabase.rpc('budget_disponibile', { p_league_id: league.id }),
    ])
    const primoErrore = istanzeRes.error ?? proposteRes.error ?? asteRes.error ?? offerteRes.error
    if (primoErrore) { setErrore(primoErrore.message); setCaricamento(false); return }

    const istanze = istanzeRes.data ?? []
    const asteRighe = (asteRes.data ?? []) as Asta[]
    // Una sola interrogazione per l'anagrafica: i giocatori delle rose e
    // quelli all'asta vengono dalla stessa tabella.
    const daCercare = [...new Set([
      ...istanze.map((i) => i.player_id),
      ...asteRighe.map((a) => a.player_id),
    ])]
    const { data: anagrafica, error: erroreAnagrafica } = daCercare.length
      ? await supabase.from('players').select('id, nome, posizioni, overall, eta').in('id', daCercare)
      : { data: [], error: null }
    if (erroreAnagrafica) { setErrore(erroreAnagrafica.message); setCaricamento(false); return }

    const perId = new Map((anagrafica ?? []).map((p) => [p.id, p as
      { id: number; nome: string; posizioni: string[]; overall: number; eta: number }]))
    setProposte((proposteRes.data ?? []) as Proposta[])
    setAste(asteRighe)
    setMieOfferte(new Map((offerteRes.data ?? []).map((o) => [o.auction_id, o.ingaggio_offerto])))
    // Un errore qui non deve impedire di usare il mercato: e' un indicatore.
    setConti(contiRes.error ? null : contiRes.data as typeof conti)
    setSvincolati(new Map(asteRighe.map((a) => [a.player_id, {
      nome: cognome(perId.get(a.player_id)?.nome ?? '—'),
      ruolo: perId.get(a.player_id)?.posizioni?.[0] ?? '—',
      overall: perId.get(a.player_id)?.overall ?? 0,
      eta: perId.get(a.player_id)?.eta ?? 0,
    }])))
    setRose(istanze.map((i) => ({
      id: i.id,
      team_id: i.team_id as number,
      overall: i.overall_corrente,
      eta: i.eta_corrente,
      ingaggio: i.ingaggio,
      nome: cognome(perId.get(i.player_id)?.nome ?? '—'),
      ruolo: perId.get(i.player_id)?.posizioni?.[0] ?? '—',
    })))
    setCaricamento(false)
  }, [league.id])

  useEffect(() => { void carica() }, [carica])

  const nomeSquadra = useCallback(
    (id: number) => dati.teamById.get(id)?.nome ?? 'Squadra',
    [dati.teamById],
  )
  const stemma = useCallback((id: number) => <Crest
    value={dati.teamById.get(id)?.stemma_url ?? null}
    imageUrl={dati.crestUrlByTeamId.get(id) ?? null}
  />, [dati.teamById, dati.crestUrlByTeamId])
  const giocatore = useCallback((id: number) => rose.find((g) => g.id === id), [rose])

  const miaRosa = useMemo(
    () => rose.filter((g) => g.team_id === membership.id).sort((a, b) => b.overall - a.overall),
    [rose, membership.id],
  )
  const rosaAvversaria = useMemo(
    () => rose.filter((g) => g.team_id === avversaria).sort((a, b) => b.overall - a.overall),
    [rose, avversaria],
  )

  const ricevute = proposte.filter((p) => p.a_team_id === membership.id && p.stato === 'in_attesa')
  const inviate = proposte.filter((p) => p.da_team_id === membership.id && p.stato === 'in_attesa')
  const concluse = proposte.filter((p) => p.stato === 'accettata')

  // Le aste arrivano ordinate per giorno decrescente: la prima riga dice qual
  // e' l'estrazione piu' recente, e sono quelle le uniche su cui si offre.
  const giornoAste = aste[0]?.giorno ?? null
  const asteDelGiorno = aste.filter((a) => a.giorno === giornoAste)

  async function offri(asta: Asta) {
    const grezzo = bozzaOfferta[asta.id] ?? ''
    const valore = Math.round(Number(grezzo.replace(',', '.')) * 1_000_000)
    if (!grezzo || Number.isNaN(valore)) { setEsito('Ingaggio non valido.'); return }
    await chiama(
      () => supabase.rpc('offri_per_svincolato', { p_auction_id: asta.id, p_ingaggio: valore }),
      'Offerta registrata. Si apre alle 21:00.',
    )
  }

  function alterna(elenco: number[], id: number, imposta: (v: number[]) => void) {
    imposta(elenco.includes(id) ? elenco.filter((x) => x !== id) : [...elenco, id])
  }

  // PromiseLike e non Promise: `supabase.rpc(...)` restituisce un builder
  // che si puo' attendere ma non e' una Promise vera.
  async function chiama(azione: () => PromiseLike<{ error: { message: string } | null }>, successo: string) {
    setInCorso(true)
    setEsito(null)
    const { error } = await azione()
    setInCorso(false)
    setEsito(error ? error.message : successo)
    if (!error) await carica()
  }

  async function invia() {
    const valore = Math.round(Number(conguaglio.replace(',', '.')) * 1_000_000)
    if (!avversaria || Number.isNaN(valore)) { setEsito('Conguaglio non valido.'); return }
    await chiama(
      () => supabase.rpc('proponi_scambio', {
        p_a_team_id: avversaria,
        p_giocatori_offerti: offerti,
        p_giocatori_richiesti: chiesti,
        p_conguaglio: valore,
        p_messaggio: messaggio.trim() || null,
      }),
      'Proposta inviata.',
    )
    setChiesti([]); setOfferti([]); setConguaglio('0'); setMessaggio('')
  }

  const listaGiocatori = (
    elenco: Giocatore[], selezionati: number[], imposta: (v: number[]) => void, vuoto: string,
  ) => elenco.length === 0
    ? <p className="season-empty">{vuoto}</p>
    : <ul className="mercato-rosa">
        {elenco.map((g) => <li key={g.id}>
          <button
            type="button"
            className={selezionati.includes(g.id) ? 'is-scelto' : ''}
            onClick={() => alterna(selezionati, g.id, imposta)}
            aria-pressed={selezionati.includes(g.id)}
          >
            <b>{g.overall}</b>
            <span><strong>{g.nome}</strong><small>{g.ruolo} · {g.eta} anni</small></span>
            <em>{milioni(g.ingaggio)}</em>
          </button>
        </li>)}
      </ul>

  const riepilogo = (p: Proposta) => <>
    <div className="mercato-scambio">
      <div>
        <small>{p.da_team_id === membership.id ? 'Offri' : 'Ti offre'}</small>
        {p.giocatori_offerti.length === 0
          ? <span className="mercato-nessuno">nessun giocatore</span>
          : p.giocatori_offerti.map((id) => <span key={id}>{giocatore(id)?.nome ?? `#${id}`}</span>)}
      </div>
      <i aria-hidden="true">⇄</i>
      <div>
        <small>{p.da_team_id === membership.id ? 'Chiedi' : 'Ti chiede'}</small>
        {p.giocatori_richiesti.length === 0
          ? <span className="mercato-nessuno">nessun giocatore</span>
          : p.giocatori_richiesti.map((id) => <span key={id}>{giocatore(id)?.nome ?? `#${id}`}</span>)}
      </div>
    </div>
    {p.conguaglio !== 0 && <p className="mercato-conguaglio">
      Conguaglio: <strong>{milioni(Math.abs(p.conguaglio))}</strong>{' '}
      {p.conguaglio > 0 ? `da ${nomeSquadra(p.da_team_id)}` : `da ${nomeSquadra(p.a_team_id)}`}
    </p>}
    {p.messaggio && <p className="mercato-messaggio">«{p.messaggio}»</p>}
  </>

  return <main className="app-shell season-shell">
    <GameNav league={league} active="mercato" onNavigate={onNavigate} />
    <header className="topbar season-topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <span className={`mercato-finestra ${aperto ? 'e-aperto' : ''}`}>
        {aperto ? 'Mercato aperto · chiude alle 21:00' : 'Mercato chiuso · apre alle 07:00'}
      </span>
    </header>

    {caricamento && <div className="season-page"><p className="season-empty">Carico il mercato…</p></div>}
    {errore && <div className="season-page"><p className="season-empty">{errore}</p></div>}

    {!caricamento && !errore && <div className="season-page season-page--narrow">
      <section className="season-title-row">
        <div>
          <p className="kicker">Stagione {league.stagione_corrente} · {league.nome}</p>
          <h1>Mercato.</h1>
          <p>Si tratta dalle 07:00 alle 21:00. Le proposte non accettate entro la chiusura scadono.</p>
        </div>
        <div className="season-total">
          <strong>{milioni(conti ? conti.disponibile : membership.budget)}</strong>
          <span>{conti && conti.impegnato > 0 ? 'disponibile' : 'budget'}</span>
        </div>
      </section>

      {conti && conti.impegnato > 0 && <p className="mercato-impegno">
        <strong>{milioni(conti.impegnato)}</strong> sono impegnati in offerte ancora aperte e tornano
        disponibili se le perdi o le ritiri. Posti liberi in rosa: <strong>{conti.slot_liberi}</strong>.
      </p>}

      {esito && <p className="notice">{esito}</p>}

      {/* ---- Ricevute: la cosa piu' urgente, quindi per prima ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">In arrivo</p><h2>Proposte ricevute</h2></div></div>
        {ricevute.length === 0
          ? <p className="season-empty">Nessuna proposta da valutare.</p>
          : ricevute.map((p) => <article className="mercato-card" key={p.id}>
              <header>{stemma(p.da_team_id)}<strong>{nomeSquadra(p.da_team_id)}</strong></header>
              {riepilogo(p)}
              <footer>
                <button className="button button--primary" type="button" disabled={inCorso || !aperto}
                  onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: true }), 'Scambio concluso.')}>
                  Accetta
                </button>
                <button className="button button--secondary" type="button" disabled={inCorso}
                  onClick={() => chiama(() => supabase.rpc('rispondi_a_proposta', { p_proposta_id: p.id, p_accetta: false }), 'Proposta rifiutata.')}>
                  Rifiuta
                </button>
              </footer>
            </article>)}
      </section>

      {/* ---- Svincolati del giorno: a busta chiusa ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Asta a busta chiusa</p><h2>Svincolati del giorno</h2></div></div>
        <p className="mercato-nota">
          Offri l’ingaggio annuale che sei disposto a pagare. <strong>Nessuno vede le offerte altrui</strong>,
          e nemmeno tu vedi quanto chiede davvero il giocatore: se lo sapessi offriresti sempre un euro sopra.
          Alle 21:00 vince l’offerta più alta che supera la sua richiesta, e <strong>a parità vince chi ha
          offerto prima</strong> — modificare l’offerta fa ripartire il tuo turno. Nessun limite al numero di
          aste vinte: contano solo il budget e gli slot liberi in rosa. <strong>Offrire impegna il
          denaro</strong> finché l’asta non si chiude, così non puoi promettere più di quanto hai.
        </p>

        {asteDelGiorno.length === 0
          ? <p className="season-empty">Nessuna estrazione ancora. I nuovi svincolati escono ogni giorno alle 07:00.</p>
          : <ul className="mercato-aste">
              {asteDelGiorno.map((a) => {
                const g = svincolati.get(a.player_id)
                const mia = mieOfferte.get(a.id)
                return <li key={a.id} className={a.stato !== 'aperta' ? 'e-chiusa' : ''}>
                  <b>{g?.overall ?? '—'}</b>
                  <span>
                    <strong>{g?.nome ?? `#${a.player_id}`}</strong>
                    <small>{g?.ruolo} · {g?.eta} anni · valore {milioni(a.ingaggio_teorico)}</small>
                  </span>
                  {a.stato === 'aperta'
                    ? <div className="mercato-asta-offerta">
                        <input
                          type="text" inputMode="decimal"
                          placeholder={mia ? (mia / 1_000_000).toFixed(1).replace('.', ',') : 'M€'}
                          value={bozzaOfferta[a.id] ?? ''}
                          onChange={(e) => setBozzaOfferta({ ...bozzaOfferta, [a.id]: e.target.value })}
                        />
                        <button className="button button--secondary" type="button"
                          disabled={inCorso || !aperto} onClick={() => void offri(a)}>
                          {mia ? 'Modifica' : 'Offri'}
                        </button>
                      </div>
                    : <em className={a.stato === 'assegnata' ? 'e-presa' : ''}>
                        {a.stato === 'assegnata'
                          ? `${nomeSquadra(a.vincitore_team_id ?? 0)} · ${milioni(a.ingaggio_finale ?? 0)}`
                          : 'Nessuno l’ha preso'}
                      </em>}
                  {a.stato === 'aperta' && mia && <i className="mercato-asta-mia">Hai offerto {milioni(mia)}</i>}
                </li>
              })}
            </ul>}
      </section>

      {/* ---- Compositore ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Tratta</p><h2>Nuova proposta</h2></div></div>
        {!aperto && <p className="notice">Il mercato è chiuso: puoi preparare la proposta ma potrai inviarla dalle 07:00.</p>}

        <div className="mercato-scelta-squadra">
          {dati.teams.filter((s) => s.id !== membership.id).map((s) => <button
            key={s.id} type="button"
            className={avversaria === s.id ? 'is-scelto' : ''}
            onClick={() => { setAvversaria(s.id); setChiesti([]) }}
          >
            {stemma(s.id)}
            <span>{s.nome}</span>
          </button>)}
        </div>

        {avversaria && <>
          <div className="mercato-colonne">
            <div>
              <h3>Cosa chiedi a {nomeSquadra(avversaria)}</h3>
              {listaGiocatori(rosaAvversaria, chiesti, setChiesti, 'Rosa non disponibile.')}
            </div>
            <div>
              <h3>Cosa offri</h3>
              {listaGiocatori(miaRosa, offerti, setOfferti, 'La tua rosa è vuota.')}
            </div>
          </div>

          <div className="mercato-conguaglio-riga">
            <label>
              <span>Conguaglio in M€</span>
              <input type="text" inputMode="decimal" value={conguaglio}
                onChange={(e) => setConguaglio(e.target.value)} placeholder="0" />
              <small>Positivo: paghi tu. Negativo: paga lui.</small>
            </label>
            <label>
              <span>Messaggio (facoltativo)</span>
              <input type="text" value={messaggio} maxLength={240}
                onChange={(e) => setMessaggio(e.target.value)} placeholder="Due righe per convincerlo" />
            </label>
          </div>

          <button className="button button--primary" type="button"
            disabled={inCorso || !aperto || (chiesti.length === 0 && offerti.length === 0)}
            onClick={() => void invia()}>
            {inCorso ? 'Invio…' : 'Invia la proposta'}
          </button>
        </>}
      </section>

      {/* ---- Inviate ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">In uscita</p><h2>Proposte inviate</h2></div></div>
        {inviate.length === 0
          ? <p className="season-empty">Nessuna proposta in attesa di risposta.</p>
          : inviate.map((p) => <article className="mercato-card" key={p.id}>
              <header>{stemma(p.a_team_id)}<strong>A {nomeSquadra(p.a_team_id)}</strong></header>
              {riepilogo(p)}
              <footer>
                <button className="button button--secondary" type="button" disabled={inCorso}
                  onClick={() => chiama(() => supabase.rpc('ritira_proposta', { p_proposta_id: p.id }), 'Proposta ritirata.')}>
                  Ritira
                </button>
              </footer>
            </article>)}
      </section>

      {/* ---- Log pubblico: design §9.3, tutti vedono tutto ---- */}
      <section className="mercato-blocco">
        <div className="sezione-testa"><div><p className="kicker">Trasparenza</p><h2>Trattative concluse</h2></div></div>
        <p className="mercato-nota">Ogni scambio concluso è visibile a tutta la lega, con giocatori e cifre.</p>
        {concluse.length === 0
          ? <p className="season-empty">Nessuno scambio finora.</p>
          : <ul className="mercato-log">
              {concluse.map((p) => <li key={p.id}>
                <strong>{nomeSquadra(p.da_team_id)}</strong>
                <i aria-hidden="true">⇄</i>
                <strong>{nomeSquadra(p.a_team_id)}</strong>
                <span>
                  {p.giocatori_offerti.map((id) => giocatore(id)?.nome ?? `#${id}`).join(', ') || '—'}
                  {' per '}
                  {p.giocatori_richiesti.map((id) => giocatore(id)?.nome ?? `#${id}`).join(', ') || '—'}
                  {p.conguaglio !== 0 && ` · ${milioni(Math.abs(p.conguaglio))}`}
                </span>
                <em>{ETICHETTE_STATO[p.stato]}</em>
              </li>)}
            </ul>}
      </section>
    </div>}
  </main>
}
