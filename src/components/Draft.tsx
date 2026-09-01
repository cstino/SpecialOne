import { useCallback, useEffect, useRef, useState } from 'react'
import { motion } from 'motion/react'
import type { User } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { ORDINE_MACRO_RUOLO, macroRuolo, type MacroRuolo } from '../lib/ruoli'
import type { League, Membership } from '../types'
import { GameNav } from './GameNav'
import type { GameView } from './GameNav'
import { firmaFoto, RosaElenco, type RosterPlayer } from './RosaElenco'
import { LoadingLogo } from './LoadingLogo'
import { PopupSpiegazione } from './PopupSpiegazione'

type DraftTeamState = {
  pick_numero: number
  stato: 'in_corso' | 'concluso'
  carta_gk: number | null
  carta_def1: number | null
  carta_def2: number | null
  carta_mid1: number | null
  carta_mid2: number | null
  carta_att1: number | null
  carta_att2: number | null
  carta_ruolo: number | null
  ruolo_scelto: MacroRuolo | null
}
type DraftCard = {
  ruolo: MacroRuolo
  id: number
  nome: string
  club: string
  campionato: string
  overall: number
  eta: number
  posizioni: string[]
  foto_url: string | null
  ingaggio: number
  ingaggiabile: boolean
}
type DraftPacchetto = {
  league_id: number
  team_id: number
  pick_numero: number
  stato: 'in_corso' | 'concluso'
  reroll_rimasti: number
  speso: number
  slot_occupati: number
  carte: DraftCard[]
}
type DraftByRolePayload = Omit<DraftPacchetto, 'carte'> & {
  ruolo_scelto: MacroRuolo | null
  carta: DraftCard | null
}
type AvanzamentoDraft = {
  team_id: number
  nome: string
  stemma_url: string | null
  controllata_da_pc: boolean
  stato: 'in_corso' | 'concluso'
  giocatori: number
  obiettivo: number
  nome_allenatore: string | null
}
type DraftProps = {
  user: User
  membership: Membership
  onNavigate: (view: GameView) => void
  onRefresh: () => void | Promise<void>
}

const NOME_RUOLO: Record<DraftCard['ruolo'], string> = {
  ALL: '',
  GK: 'Portiere',
  DEF: 'Difensore',
  MID: 'Centrocampista',
  ATT: 'Attaccante',
}

// Usato solo dal draft BY ROLE (un pulsante di spin per reparto): 4 ruoli
// distinti, uno a scelta.
const ORDINE_RUOLI_PACCHETTO: DraftCard['ruolo'][] = ['GK', 'DEF', 'MID', 'ATT']

// Un pacchetto "2 of 4" (in realta' 7 carte, non piu' 4: 1 portiere, 2
// difensori, 2 centrocampisti, 2 attaccanti) ha sempre questi 7 slot, in
// quest'ordine: e' la struttura fissa usata anche per i segnaposto prima
// che il pacchetto sia aperto/rivelato. Il backend (private.pacchetto_
// payload) restituisce le carte gia' in questo stesso ordine.
const ORDINE_CARTE_PACCHETTO: DraftCard['ruolo'][] = ['GK', 'DEF', 'DEF', 'MID', 'MID', 'ATT', 'ATT']

// Nomi decorativi per la fase di rotazione del pacchetto: mai reali, servono
// solo alla suspense visiva. Cambiano troppo in fretta per essere letti.
const NOMI_SPIN = [
  'Álvarez', 'Petrov', 'Nakamura', 'Diallo', 'Larsson', 'Okafor', 'Silva', 'Kowalski',
  'Hansen', 'Bianchi', 'Novák', 'Andersen', 'Ferreira', 'Yılmaz', 'Costa', 'Mendes',
  'Schulz', 'Kovač', 'Rossi', 'Aguilar', 'Dubois', 'Ibrahim', 'Santos', 'Wagner',
]

function milioni(euro: number) {
  return `${(euro / 1_000_000).toFixed(1).replace('.', ',')} M€`
}

export function Draft({ user, membership, onNavigate, onRefresh }: DraftProps) {
  const league = membership.league as League
  const isByRole = league.modalita_draft === 'by_role'
  const [state, setState] = useState<DraftTeamState | null>(null)
  const [payload, setPayload] = useState<DraftPacchetto | null>(null)
  const [byRolePayload, setByRolePayload] = useState<DraftByRolePayload | null>(null)
  const [fotoCarte, setFotoCarte] = useState<Map<number, string>>(new Map())
  const [selezionati, setSelezionati] = useState<number[]>([])
  const [fase, setFase] = useState<'vuoto' | 'girando' | 'rivelato'>('vuoto')
  const [spesoDraft, setSpesoDraft] = useState<number>(0)
  const [rosaAperta, setRosaAperta] = useState(false)
  const [squadraVista, setSquadraVista] = useState<{ id: number; nome: string } | null>(null)
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [refresh, setRefresh] = useState(0)
  const spinRef = useRef<number | null>(null)
  const [nomiSpin, setNomiSpin] = useState<string[]>(['', '', '', '', '', '', ''])
  // Con il draft che parte squadra per squadra, chi entra per primo non vede
  // piu' la Lobby: senza questo pezzo perderebbe l'unico posto dove il
  // codice invito era mostrato dopo la creazione della lega.
  const [squadreIscritte, setSquadreIscritte] = useState<number | null>(null)
  const [copiato, setCopiato] = useState(false)
  const [avanzamento, setAvanzamento] = useState<AvanzamentoDraft[]>([])
  const [preparazionePc, setPreparazionePc] = useState(false)
  const automazionePcRef = useRef(false)

  const caricaAvanzamento = useCallback(async () => {
    const { data, error: avanzamentoError } = await supabase.rpc('stato_avanzamento_draft', { p_league_id: league.id })
    if (avanzamentoError) {
      setError(avanzamentoError.message)
      return [] as AvanzamentoDraft[]
    }
    const righe = (data ?? []) as AvanzamentoDraft[]
    setAvanzamento(righe)
    return righe
  }, [league.id])

  // Mostra sempre dati reali, anche se un altro browser o il cron completa
  // una rosa mentre questa pagina è aperta.
  useEffect(() => {
    if (league.stato !== 'draft') return
    let active = true
    async function aggiorna() {
      const righe = await caricaAvanzamento()
      if (!active) return
      if (righe.length > 0 && righe.every((riga) => riga.stato === 'concluso')) await onRefresh()
    }
    void aggiorna()
    const timer = window.setInterval(() => void aggiorna(), 1800)
    return () => { active = false; window.clearInterval(timer) }
  }, [caricaAvanzamento, league.stato, onRefresh])

  // Appena l'utente finisce, prepara una squadra PC per chiamata. In questo
  // modo non rischiamo timeout e la lista può aggiornarsi fra una squadra e
  // la successiva; il cron al minuto resta soltanto il paracadute.
  useEffect(() => {
    if (league.stato !== 'draft' || state?.stato !== 'concluso' || automazionePcRef.current) return
    let active = true
    automazionePcRef.current = true
    async function completaPc() {
      setPreparazionePc(true)
      while (active) {
        const { data, error: completamentoError } = await supabase.rpc('completa_prossima_squadra_pc', { p_league_id: league.id })
        if (completamentoError) {
          if (active) setError(completamentoError.message)
          break
        }
        await caricaAvanzamento()
        if (data !== true) break
      }
      if (active) {
        setPreparazionePc(false)
        await onRefresh()
      }
      automazionePcRef.current = false
    }
    void completaPc()
    return () => { active = false; automazionePcRef.current = false }
  }, [caricaAvanzamento, league.id, league.stato, onRefresh, state?.stato])

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true); setError(null); setSelezionati([])
      const [{ data: teamState, error: stateError }, { data: istanze }, { count: iscritte }] = await Promise.all([
        supabase.from('draft_team_state').select('*').eq('team_id', membership.id).maybeSingle(),
        supabase.from('player_instances').select('ingaggio').eq('league_id', league.id).eq('team_id', membership.id),
        supabase.from('teams').select('id', { count: 'exact', head: true }).eq('league_id', league.id),
      ])
      if (!active) return
      setSpesoDraft((istanze ?? []).reduce((somma, i) => somma + i.ingaggio, 0))
      setSquadreIscritte(iscritte ?? null)
      if (stateError || !teamState) { setError(stateError?.message ?? 'Stato del tuo draft non disponibile.'); setLoading(false); return }
      const nextState = teamState as DraftTeamState
      setState(nextState)
      const haCartaAperta = isByRole ? nextState.carta_ruolo !== null : nextState.carta_gk !== null
      if (haCartaAperta && nextState.stato === 'in_corso') {
        const result = isByRole
          ? await supabase.rpc('draft_by_role_spin', { p_league_id: league.id, p_ruolo: nextState.ruolo_scelto ?? 'GK' })
          : await supabase.rpc('draft_apri_pacchetto', { p_league_id: league.id })
        if (!active) return
        if (result.error) setError(result.error.message)
        else if (isByRole) {
          const dati = result.data as DraftByRolePayload
          setByRolePayload(dati)
          setFase('rivelato')
          setFotoCarte(await firmaTutte(dati.carta ? [dati.carta] : []))
        } else {
          const dati = result.data as DraftPacchetto
          setPayload(dati)
          setFase('rivelato')
          setFotoCarte(await firmaTutte(dati.carte))
        }
      } else { setPayload(null); setByRolePayload(null); setFase('vuoto') }
      setLoading(false)
    }
    void load()
    return () => { active = false; if (spinRef.current) window.clearInterval(spinRef.current) }
  }, [isByRole, league.id, membership.id, refresh])

  async function firmaTutte(carte: DraftCard[]) {
    const voci = await Promise.all(carte.map(async (c) => [c.id, await firmaFoto(c.foto_url)] as const))
    return new Map(voci.filter((v): v is [number, string] => Boolean(v[1])))
  }

  function avviaRotazione(dati: DraftPacchetto) {
    setPayload(dati)
    setFase('girando')
    setSelezionati([])
    if (spinRef.current) window.clearInterval(spinRef.current)
    spinRef.current = window.setInterval(() => {
      setNomiSpin([0, 1, 2, 3, 4, 5, 6].map(() => NOMI_SPIN[Math.floor(Math.random() * NOMI_SPIN.length)]))
    }, 65)
    window.setTimeout(async () => {
      if (spinRef.current) { window.clearInterval(spinRef.current); spinRef.current = null }
      setFase('rivelato')
      setFotoCarte(await firmaTutte(dati.carte))
    }, 1000)
  }

  function avviaRotazioneByRole(dati: DraftByRolePayload) {
    setByRolePayload(dati)
    setFase('girando')
    if (spinRef.current) window.clearInterval(spinRef.current)
    spinRef.current = window.setInterval(() => {
      setNomiSpin([NOMI_SPIN[Math.floor(Math.random() * NOMI_SPIN.length)], '', '', '', '', '', ''])
    }, 65)
    window.setTimeout(async () => {
      if (spinRef.current) { window.clearInterval(spinRef.current); spinRef.current = null }
      setFase('rivelato')
      setFotoCarte(await firmaTutte(dati.carta ? [dati.carta] : []))
    }, 1000)
  }

  async function apriPacchetto() {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_apri_pacchetto', { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else avviaRotazione(result.data as DraftPacchetto)
    setPending(false)
  }

  async function reroll() {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_pacchetto_reroll', { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else avviaRotazione(result.data as DraftPacchetto)
    setPending(false)
  }

  async function spinByRole(ruolo: MacroRuolo) {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_by_role_spin', { p_league_id: league.id, p_ruolo: ruolo })
    if (result.error) setError(result.error.message)
    else avviaRotazioneByRole(result.data as DraftByRolePayload)
    setPending(false)
  }

  async function rerollByRole() {
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_by_role_reroll', { p_league_id: league.id })
    if (result.error) setError(result.error.message)
    else avviaRotazioneByRole(result.data as DraftByRolePayload)
    setPending(false)
  }

  async function ingaggiaByRole() {
    const carta = byRolePayload?.carta
    if (!carta?.ingaggiabile) return
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_by_role_ingaggia', {
      p_league_id: league.id,
      p_player_id: carta.id,
    })
    if (result.error) setError(result.error.message)
    else { setByRolePayload(null); setFase('vuoto'); setRefresh((value) => value + 1) }
    setPending(false)
  }

  function toggleCarta(carta: DraftCard) {
    if (!carta.ingaggiabile || fase !== 'rivelato') return
    setSelezionati((attuali) => {
      if (attuali.includes(carta.id)) return attuali.filter((id) => id !== carta.id)
      if (attuali.length >= 2) return attuali
      return [...attuali, carta.id]
    })
  }

  async function confermaScelta() {
    if (selezionati.length !== 2) return
    setPending(true); setError(null)
    const result = await supabase.rpc('draft_scegli_pacchetto', {
      p_league_id: league.id,
      p_player_id_1: selezionati[0],
      p_player_id_2: selezionati[1],
    })
    if (result.error) setError(result.error.message)
    else { setPayload(null); setFase('vuoto'); setSelezionati([]); setRefresh((value) => value + 1) }
    setPending(false)
  }

  if (loading) return <main className="loading-screen"><LoadingLogo /><p>Apro il pacchetto…</p></main>
  if (error && !state) return <main className="fatal-state"><h1>Draft non disponibile</h1><p>{error}</p></main>

  const picks = state?.pick_numero ?? 0
  const total = league.slot_rosa
  const tetto = league.budget_draft
  const speso = spesoDraft
  const disponibile = Math.max(0, tetto - speso)
  const progressoSpesa = tetto > 0 ? Math.min(100, (speso / tetto) * 100) : 0
  // Stessa formula del vincolo di solvibilita' server-side (private.pick_sostenibile,
  // design §4.4), applicata ai DUE pick del turno insieme: quanto si puo' spendere in
  // totale sulle due carte scelte ora, una volta accantonato il minimo di 0,5M per
  // ognuno degli slot che restano da riempire DOPO questo turno.
  const pickDelTurno = isByRole ? 1 : 2
  const slotLiberiDopoTurno = Math.max(0, total - picks - pickDelTurno)
  const massimoSpesaTurno = Math.max(0, disponibile - slotLiberiDopoTurno * 500_000)
  const squadreCompletate = avanzamento.filter((riga) => riga.stato === 'concluso').length
  const percentualeLega = avanzamento.length > 0 ? (squadreCompletate / avanzamento.length) * 100 : 0

  return (
    <main className="app-shell draft-shell">
      <GameNav league={league} active="draft" onNavigate={onNavigate} />
      <header className="topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span className="user-email">{user.email}</span></header>
      <PopupSpiegazione userId={membership.user_id} hintKey={`draft-${isByRole ? 'by-role' : '2-of-4'}`} titolo="Come funziona il Draft">
        {isByRole ? <>
          <p>A ogni turno scegli un ruolo e fai uno spin: pesca un giocatore disponibile per quel ruolo.
            Puoi ingaggiarlo subito o rifare lo spin (i reroll sono limitati). Ogni giocatore è unico in
            tutta la lega: appena qualcuno lo ingaggia, sparisce per tutti gli altri.</p>
        </> : <>
          <p>Apri un pacchetto per reparto: 4 carte, ne scegli 2. Se meno di 2 carte sono ingaggiabili,
            quelle ingaggiabili restano ferme e solo le altre si ripescano automaticamente, senza consumarti
            un reroll. Ogni giocatore è unico in tutta la lega: appena qualcuno lo prende, sparisce per gli
            altri.</p>
        </>}
        <p>Nessun ordine di turno: tutte le squadre draftano in contemporanea, a modo e velocità loro. Il
          budget del draft è una parte del budget iniziale della lega, e ogni ingaggio deve restare
          sostenibile per completare l'intera rosa — il sistema blocca una scelta che ti lascerebbe senza
          margine per finirla.</p>
      </PopupSpiegazione>
      <section className="draft-hero">
        <div><p className="kicker">Draft {isByRole ? 'BY ROLE' : '2 of 4'} · {league.nome}</p><h1>{state?.stato === 'concluso' ? 'Rosa completa.' : 'Scegli bene.'}</h1><p>{isByRole ? `Hai completato ${picks} spin su ${total}. Scegli liberamente il reparto del prossimo.` : `La tua squadra è al pacchetto ${Math.min(Math.floor(picks / 2) + 1, total / 2)} su ${total / 2}.`} Le altre squadre possono draftare contemporaneamente.</p></div>
        <button className="draft-turn-board draft-turn-board--clickable" type="button" onClick={() => setRosaAperta(true)}>
          <span>La tua squadra</span>
          <strong>{membership.nome}</strong>
          <small>{state?.stato === 'concluso' ? 'Draft completato' : `${picks} / ${total} giocatori`}</small>
          <div className="draft-budget">
            <div className="draft-budget__bar"><div className="draft-budget__fill" style={{ width: `${progressoSpesa}%` }} /></div>
            <div className="draft-budget__cifre"><span>{milioni(speso)} speso</span><span>{milioni(disponibile)} disponibile</span></div>
            <small>Tetto draft: {milioni(tetto)} su {milioni(league.budget_iniziale)} di budget iniziale</small>
          </div>
          <span className="draft-turn-board__hint">Tocca per vedere la rosa →</span>
        </button>
      </section>
      {state?.stato !== 'concluso' && (
        <section className="draft-max-spesa">
          <span className="draft-max-spesa__etichetta">Max spesa turno</span>
          <strong className="draft-max-spesa__cifra">{milioni(massimoSpesaTurno)}</strong>
        </section>
      )}
      {squadreIscritte !== null && squadreIscritte < league.n_squadre && (
        <section className="draft-invito-banner">
          <div><p className="kicker">Posti liberi</p><h2>{squadreIscritte} / {league.n_squadre} squadre iscritte</h2><p>Chi entra ora comincia subito il proprio draft, senza aspettare gli altri.</p></div>
          <button
            type="button"
            onClick={() => { void navigator.clipboard.writeText(league.codice_invito); setCopiato(true); window.setTimeout(() => setCopiato(false), 1800) }}
          >
            <small>CODICE INVITO</small>
            <strong>{league.codice_invito}</strong>
            <span>{copiato ? 'Copiato' : 'Tocca per copiare'}</span>
          </button>
        </section>
      )}
      {error && <p className="notice notice--error" role="alert">{error}</p>}
      {state?.stato === 'concluso' ? (
        <section className="draft-action-panel draft-waiting-panel">
          <div className="draft-waiting-panel__testa">
            <div>
              <p className="kicker">Draft concluso</p>
              <h2>{squadreCompletate === avanzamento.length && avanzamento.length > 0 ? 'Tutte le rose sono pronte.' : 'Preparazione delle altre rose…'}</h2>
              <p>{preparazionePc ? 'Le squadre PC stanno completando automaticamente il draft.' : 'Controllo lo stato delle altre squadre.'}</p>
            </div>
            <strong>{squadreCompletate}/{avanzamento.length || league.n_squadre}</strong>
          </div>
          <div className="draft-waiting-total" aria-label={`${squadreCompletate} squadre complete su ${avanzamento.length}`}>
            <i style={{ width: `${percentualeLega}%` }} />
          </div>
          <ul className="draft-waiting-list">
            {avanzamento.map((riga) => {
              const completa = riga.stato === 'concluso'
              const quota = Math.min(100, (riga.giocatori / Math.max(riga.obiettivo, 1)) * 100)
              return <li key={riga.team_id} className={completa ? 'is-complete' : 'is-loading'}>
                <button
                  type="button"
                  className="draft-waiting-list__row"
                  onClick={() => setSquadraVista({ id: riga.team_id, nome: riga.nome })}
                >
                  <span className="draft-waiting-list__stato" aria-hidden="true">{completa ? '✓' : ''}</span>
                  <div>
                    <strong>{riga.nome}{riga.controllata_da_pc ? <small>PC</small> : null}</strong>
                    <span>{riga.nome_allenatore ? `${riga.nome_allenatore} · ` : ''}{completa ? 'Rosa completata' : riga.controllata_da_pc ? 'Estrazione in corso' : 'In attesa del giocatore'}</span>
                    <div className="draft-waiting-list__bar"><i style={{ width: `${quota}%` }} /></div>
                  </div>
                  <b>{riga.giocatori}/{riga.obiettivo}</b>
                </button>
              </li>
            })}
          </ul>
        </section>
      ) : (
        <section className="draft-club-panel">
          {isByRole ? (
            <>
              <div className="section-heading-row">
                <div>
                  <p className="kicker">{fase === 'vuoto' ? 'Scegli il prossimo reparto' : fase === 'girando' ? 'Spin in corso…' : NOME_RUOLO[byRolePayload?.ruolo_scelto ?? 'ALL']}</p>
                  <h2>{fase === 'vuoto' ? 'Chi vuoi cercare?' : fase === 'girando' ? 'Scouting il pool attivo.' : 'Firma o prova un reroll.'}</h2>
                </div>
                {fase !== 'vuoto' && (
                  <button className="draft-reroll-oro" type="button" disabled={pending || fase === 'girando' || (byRolePayload?.reroll_rimasti ?? 0) < 1} onClick={rerollByRole}>
                    <span className="draft-azione-testo">Reroll · {byRolePayload?.reroll_rimasti ?? 0}</span>
                  </button>
                )}
              </div>
              {fase === 'vuoto' && (
                <>
                  <p>Ogni spin mostra un solo giocatore del reparto scelto. La composizione finale della rosa dipende interamente da te.</p>
                  <div className="draft-role-grid">
                    {ORDINE_RUOLI_PACCHETTO.map((ruolo) => (
                      <button key={ruolo} className={`draft-role-choice draft-role-choice--${ruolo.toLowerCase()}`} type="button" disabled={pending} onClick={() => spinByRole(ruolo)}>
                        <span>{ruolo}</span>
                        <strong>{NOME_RUOLO[ruolo]}</strong>
                        <small>Spin</small>
                      </button>
                    ))}
                  </div>
                </>
              )}
              {fase !== 'vuoto' && (
                <div className="draft-by-role-card">
                  <span className={`draft-ruolo-badge draft-ruolo-badge--${(byRolePayload?.ruolo_scelto ?? 'GK').toLowerCase()}`}>{NOME_RUOLO[byRolePayload?.ruolo_scelto ?? 'GK']}</span>
                  {fase === 'girando' && (
                    <div className="draft-carta draft-carta--spin">
                      <div className="draft-carta__foto draft-carta__foto--spin" aria-hidden="true" />
                      <strong className="draft-carta__nome-spin">{nomiSpin[0]}</strong>
                      <span className="draft-carta__ovr-spin">{40 + Math.floor(Math.random() * 55)}</span>
                    </div>
                  )}
                  {fase === 'rivelato' && byRolePayload?.carta && (
                    <motion.div
                      className="draft-carta draft-carta--by-role"
                      initial={{ opacity: 0, scale: 0.88, y: 8 }}
                      animate={{ opacity: 1, scale: 1, y: 0 }}
                      transition={{ type: 'spring', stiffness: 340, damping: 22 }}
                    >
                      <div className="draft-carta__foto">
                        {fotoCarte.get(byRolePayload.carta.id) ? <img src={fotoCarte.get(byRolePayload.carta.id)} alt="" /> : <span aria-hidden="true">{byRolePayload.carta.nome.charAt(0)}</span>}
                      </div>
                      <div className="draft-carta__info">
                        <strong>{byRolePayload.carta.nome}</strong>
                        <small>{byRolePayload.carta.club} · {byRolePayload.carta.eta} anni</small>
                        <small className="draft-carta__posizioni">{byRolePayload.carta.posizioni.join(' · ')}</small>
                      </div>
                      <b className="draft-carta__ovr">{byRolePayload.carta.overall}</b>
                      <div className="draft-carta__wage">
                        {(byRolePayload.carta.ingaggio / 1_000_000).toFixed(1)} M€
                        <small>{byRolePayload.carta.ingaggiabile ? 'Sostenibile' : 'Non sostenibile'}</small>
                      </div>
                    </motion.div>
                  )}
                </div>
              )}
              {fase === 'rivelato' && (
                <button className="button button--primary draft-conferma" type="button" disabled={pending || !byRolePayload?.carta?.ingaggiabile} onClick={ingaggiaByRole}>
                  Ingaggia {byRolePayload?.carta?.nome ?? 'giocatore'}
                </button>
              )}
            </>
          ) : (
            <>
          <div className="section-heading-row">
            <div>
              <p className="kicker">{fase === 'vuoto' ? 'Pronto per il prossimo spin' : fase === 'girando' ? 'Apertura in corso…' : 'Pacchetto aperto'}</p>
              <h2>{fase === 'vuoto' ? '7 giocatori: 1 portiere, 2 difensori, 2 centrocampisti, 2 attaccanti.' : fase === 'girando' ? 'Scouting il pool attivo.' : 'Scegli 2 carte su 7.'}</h2>
            </div>
            {fase === 'vuoto' ? (
              <button className="draft-spin-viola" type="button" disabled={pending} onClick={apriPacchetto}><span className="draft-azione-testo">Spin</span></button>
            ) : (
              <button className="draft-reroll-oro" type="button" disabled={pending || fase === 'girando' || (payload?.reroll_rimasti ?? 0) < 1} onClick={reroll}><span className="draft-azione-testo">Reroll · {payload?.reroll_rimasti ?? 0}</span></button>
            )}
          </div>
          {fase === 'vuoto' && <p>Selezionane 2, gli altri sono scartati.</p>}
          <div className="draft-pacchetto-grid">
            {ORDINE_CARTE_PACCHETTO.map((ruoloSegnaposto, indice) => {
              const carta = payload?.carte[indice]
              const ruolo = carta?.ruolo ?? ruoloSegnaposto
              return (
                <div key={indice} className={`draft-carta-slot draft-carta-slot--${ruolo.toLowerCase()}`}>
                  <span className={`draft-ruolo-badge draft-ruolo-badge--${ruolo.toLowerCase()}`}>{NOME_RUOLO[ruolo]}</span>
                  {fase === 'vuoto' && (
                    <div className="draft-carta draft-carta--vuota" aria-hidden="true">
                      <span className="draft-carta__punto-vuoto">?</span>
                    </div>
                  )}
                  {fase === 'girando' && (
                    <div className="draft-carta draft-carta--spin">
                      <div className="draft-carta__foto draft-carta__foto--spin" aria-hidden="true" />
                      <strong className="draft-carta__nome-spin">{nomiSpin[indice]}</strong>
                      <span className="draft-carta__ovr-spin">{40 + Math.floor(Math.random() * 55)}</span>
                    </div>
                  )}
                  {fase === 'rivelato' && carta && (
                    <motion.button
                      type="button"
                      className={`draft-carta${selezionati.includes(carta.id) ? ' draft-carta--selezionata' : ''}`}
                      disabled={pending || !carta.ingaggiabile}
                      onClick={() => toggleCarta(carta)}
                      initial={{ opacity: 0, scale: 0.88, y: 8 }}
                      animate={{ opacity: 1, scale: 1, y: 0 }}
                      transition={{ type: 'spring', stiffness: 340, damping: 22, delay: indice * 0.08 }}
                    >
                      <div className="draft-carta__foto">
                        {fotoCarte.get(carta.id) ? <img src={fotoCarte.get(carta.id)} alt="" loading="lazy" /> : <span aria-hidden="true">{carta.nome.charAt(0)}</span>}
                      </div>
                      <div className="draft-carta__info">
                        <strong>{carta.nome}</strong>
                        <small>{carta.club} · {carta.eta} anni</small>
                        <small className="draft-carta__posizioni">{carta.posizioni.join(' · ')}</small>
                      </div>
                      <b className="draft-carta__ovr">{carta.overall}</b>
                      <div className="draft-carta__wage">
                        {(carta.ingaggio / 1_000_000).toFixed(1)} M€
                        <small>{!carta.ingaggiabile ? 'Non sostenibile' : selezionati.includes(carta.id) ? 'Selezionata ✓' : 'Tocca per scegliere'}</small>
                      </div>
                    </motion.button>
                  )}
                </div>
              )
            })}
          </div>
          {fase === 'rivelato' && (
            <button className="button button--primary draft-conferma" type="button" disabled={pending || selezionati.length !== 2} onClick={confermaScelta}>
              Conferma scelta ({selezionati.length}/2)
            </button>
          )}
            </>
          )}
        </section>
      )}
      {state?.stato !== 'concluso' && fase === 'vuoto' && <button className="text-button draft-refresh" type="button" onClick={() => setRefresh((value) => value + 1)}>Aggiorna stato</button>}
      {rosaAperta && <RosaModale league={league} teamId={membership.id} nome={membership.nome} onClose={() => setRosaAperta(false)} />}
      {squadraVista && <RosaModale league={league} teamId={squadraVista.id} nome={squadraVista.nome} onClose={() => setSquadraVista(null)} />}
    </main>
  )
}

function RosaModale({ league, teamId, nome, onClose }: { league: League; teamId: number; nome: string; onClose: () => void }) {
  const [giocatori, setGiocatori] = useState<RosterPlayer[]>([])
  const [foto, setFoto] = useState<Map<number, string>>(new Map())
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    async function load() {
      const { data: instances } = await supabase.from('player_instances')
        .select('id, player_id, ingaggio, overall_corrente, eta_corrente')
        .eq('league_id', league.id).eq('team_id', teamId)
      const ids = (instances ?? []).map((i) => i.player_id)
      const { data: catalogo } = ids.length
        ? await supabase.from('players').select('id, nome, club, posizioni, foto_url').in('id', ids)
        : { data: [] }
      if (!active) return
      const byId = new Map((catalogo ?? []).map((p) => [p.id, p]))
      const elenco: RosterPlayer[] = (instances ?? []).map((i) => {
        const p = byId.get(i.player_id)
        return {
          id: i.id, ingaggio: i.ingaggio, overall: i.overall_corrente, eta: i.eta_corrente,
          nome: p?.nome ?? '—', club: p?.club ?? '—', posizioni: p?.posizioni ?? [], foto_url: p?.foto_url ?? null,
        }
      }).sort((a, b) => {
        const ra = ORDINE_MACRO_RUOLO.indexOf(macroRuolo(a.posizioni))
        const rb = ORDINE_MACRO_RUOLO.indexOf(macroRuolo(b.posizioni))
        return ra !== rb ? ra - rb : b.overall - a.overall
      })
      setGiocatori(elenco)
      const voci = await Promise.all(elenco.map(async (g) => [g.id, await firmaFoto(g.foto_url)] as const))
      if (!active) return
      setFoto(new Map(voci.filter((v): v is [number, string] => Boolean(v[1]))))
      setLoading(false)
    }
    void load()
    return () => { active = false }
  }, [league.id, teamId])

  const speso = giocatori.reduce((somma, g) => somma + g.ingaggio, 0)

  return (
    <div className="modale-sfondo" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="modale-rosa" onClick={(e) => e.stopPropagation()}>
        <div className="modale-rosa__testa">
          <div><p className="kicker">{nome}</p><h2>{giocatori.length} / {league.slot_rosa} giocatori</h2><small>{milioni(speso)} di ingaggi complessivi</small></div>
          <button className="button-icona" type="button" onClick={onClose} aria-label="Chiudi">✕</button>
        </div>
        <RosaElenco giocatori={giocatori} foto={foto} loading={loading} />
      </div>
    </div>
  )
}
