import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useTornaAllaHome } from '../lib/navigazione'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'

type AdminProps = { membership: Membership; onNavigate: (view: GameView) => void }

type EsitoAzione = { tono: 'ok' | 'errore'; testo: string }

// Fallback manuale per le tre azioni che normalmente fa pg_cron da solo:
// simulazione notturna (00:00), estrazione svincolati (07:00), chiusura
// mercato (21:00). Pensato per quando un cron non parte, non per sostituire
// l'automatismo: l'admin lo usa solo se qualcosa e' rimasto fermo.
export function Admin({ membership, onNavigate }: AdminProps) {
  const league = membership.league as League
  const tornaAllaHome = useTornaAllaHome()
  const [simulando, setSimulando] = useState(false)
  const [aprendo, setAprendo] = useState(false)
  const [chiudendo, setChiudendo] = useState(false)
  const [esitoSimula, setEsitoSimula] = useState<EsitoAzione | null>(null)
  const [esitoApri, setEsitoApri] = useState<EsitoAzione | null>(null)
  const [esitoChiudi, setEsitoChiudi] = useState<EsitoAzione | null>(null)
  const [confermaEliminazione, setConfermaEliminazione] = useState(false)
  const [nomeDigitato, setNomeDigitato] = useState('')
  const [eliminando, setEliminando] = useState(false)
  const [erroreEliminazione, setErroreEliminazione] = useState<string | null>(null)
  const [annuncioTesto, setAnnuncioTesto] = useState('')
  const [inviandoAnnuncio, setInviandoAnnuncio] = useState(false)
  const [esitoAnnuncio, setEsitoAnnuncio] = useState<EsitoAzione | null>(null)

  // Difesa in profondità: la voce di menu è già nascosta a chi non è admin, e
  // ogni RPC lo ricontrolla comunque lato server. Questo evita solo che chi
  // arriva qui manipolando lo stato del client trovi due bottoni che non
  // faranno mai nulla per lui, senza dirgli perché.
  if (membership.user_id !== league.admin_id) {
    return (
      <main className="app-shell season-shell">
        <GameNav league={league} active="admin" onNavigate={onNavigate} />
        <div className="season-page season-page--narrow">
          <p className="notice notice--error">Questo pannello è visibile solo all'amministratore della lega.</p>
        </div>
      </main>
    )
  }

  async function simulaGiornata() {
    setSimulando(true); setEsitoSimula(null)
    const { data, error } = await supabase.functions.invoke('simula-giornata', {
      body: { league_id: league.id },
    })
    setSimulando(false)
    if (error) { setEsitoSimula({ tono: 'errore', testo: error.message }); return }
    if (data?.error) { setEsitoSimula({ tono: 'errore', testo: data.error }); return }
    if (data?.completata) { setEsitoSimula({ tono: 'ok', testo: 'Non ci sono più giornate da simulare: la stagione è già completa.' }); return }
    const partite = data?.partite?.length ?? 0
    setEsitoSimula({ tono: 'ok', testo: `Giornata ${data?.giornata ?? ''} simulata: ${partite} ${partite === 1 ? 'partita' : 'partite'}.` })
  }

  async function apriMercato() {
    setAprendo(true); setEsitoApri(null)
    const { data, error } = await supabase.rpc('admin_apri_mercato', { p_league_id: league.id })
    setAprendo(false)
    if (error) { setEsitoApri({ tono: 'errore', testo: error.message }); return }
    const risultato = data as { estratti?: number; tornata?: number }
    const estratti = risultato?.estratti ?? 0
    setEsitoApri({
      tono: 'ok',
      testo: estratti > 0
        ? `Mercato live aperto: ${estratti} ${estratti === 1 ? 'nuovo svincolato' : 'nuovi svincolati'} nella tornata ${risultato?.tornata ?? ''}.`
        : 'Non ci sono altri giocatori disponibili da estrarre.',
    })
  }

  async function chiudiMercato() {
    setChiudendo(true); setEsitoChiudi(null)
    const { data, error } = await supabase.rpc('admin_chiudi_mercato', { p_league_id: league.id })
    setChiudendo(false)
    if (error) { setEsitoChiudi({ tono: 'errore', testo: error.message }); return }
    const aste = data?.aste_risolte ?? 0
    const proposte = data?.proposte_scadute ?? 0
    setEsitoChiudi({ tono: 'ok', testo: `${aste} ${aste === 1 ? 'asta risolta' : 'aste risolte'}, ${proposte} ${proposte === 1 ? 'proposta scaduta' : 'proposte scadute'}.` })
  }

  async function inviaAnnuncio() {
    setInviandoAnnuncio(true); setEsitoAnnuncio(null)
    const { data, error } = await supabase.rpc('invia_annuncio_lega', { p_league_id: league.id, p_messaggio: annuncioTesto })
    setInviandoAnnuncio(false)
    if (error) { setEsitoAnnuncio({ tono: 'errore', testo: error.message }); return }
    const inviate = (data as number | null) ?? 0
    setEsitoAnnuncio({ tono: 'ok', testo: `Inviato a ${inviate} ${inviate === 1 ? 'partecipante' : 'partecipanti'}.` })
    setAnnuncioTesto('')
  }

  async function eliminaLega() {
    setEliminando(true); setErroreEliminazione(null)
    const { error } = await supabase.rpc('elimina_lega', { p_league_id: league.id, p_conferma_nome: nomeDigitato })
    setEliminando(false)
    if (error) { setErroreEliminazione(error.message); return }
    // La lega non esiste più: non c'è una pagina a cui tornare dentro di essa.
    tornaAllaHome?.()
  }

  // Le tre azioni di riserva sostituiscono il cron notturno: hanno senso
  // solo a stagione avviata. "Elimina lega" invece serve in ogni fase —
  // anche in draft, dove una lega puo' restare bloccata e vada rifatta.
  const stagioneAvviata = league.stato === 'stagione'

  return (
    <main className="app-shell season-shell">
      <GameNav league={league} active="admin" onNavigate={onNavigate} />
      <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div></header>
      <div className="season-page season-page--narrow">
        <section className="season-title-row">
          <div>
            <p className="kicker">Solo amministratore · {league.nome}</p>
            <h1>Pannello admin.</h1>
            <p>{stagioneAvviata
              ? "Tre azioni di riserva, per quando pg_cron non parte da solo. L'apertura manuale abilita anche le offerte fuori dalla finestra automatica, finché il mercato non viene richiuso."
              : 'La lega non è ancora avviata: le azioni di riserva sul cron compariranno quando la stagione parte. Da qui puoi comunque eliminare la lega.'}</p>
          </div>
        </section>

        {stagioneAvviata && <>
        <section className="mercato-blocco">
          <div className="sezione-testa"><div><p className="kicker">00:00</p><h2>Simula la giornata</h2></div></div>
          <p className="mercato-nota">Simula la prossima giornata programmata, la stessa cosa che fa il cron ogni notte. Non fa nulla se non ci sono partite da giocare.</p>
          {esitoSimula && <p className={esitoSimula.tono === 'errore' ? 'notice notice--error' : 'notice'}>{esitoSimula.testo}</p>}
          <button className="button button--primary" type="button" disabled={simulando} onClick={() => void simulaGiornata()}>
            {simulando ? 'Simulo…' : 'Simula giornata'}
          </button>
        </section>

        <section className="mercato-blocco">
          <div className="sezione-testa"><div><p className="kicker">07:00 e 21:00</p><h2>Mercato</h2></div></div>
          <p className="mercato-nota">Aprire estrae gli svincolati del giorno, come il cron delle 07:00. Chiudere risolve le aste
            aperte e fa scadere le proposte in attesa, come il cron delle 21:00. Farlo due volte lo stesso giorno non duplica nulla.</p>
          <div className="admin-azioni-riga">
            <button className="button button--secondary" type="button" disabled={aprendo} onClick={() => void apriMercato()}>
              {aprendo ? 'Apro…' : 'Apri mercato'}
            </button>
            <button className="button button--secondary" type="button" disabled={chiudendo} onClick={() => void chiudiMercato()}>
              {chiudendo ? 'Chiudo…' : 'Chiudi mercato'}
            </button>
          </div>
          {esitoApri && <p className={esitoApri.tono === 'errore' ? 'notice notice--error' : 'notice'}>{esitoApri.testo}</p>}
          {esitoChiudi && <p className={esitoChiudi.tono === 'errore' ? 'notice notice--error' : 'notice'}>{esitoChiudi.testo}</p>}
        </section>
        </>}

        <section className="mercato-blocco">
          <div className="sezione-testa"><div><p className="kicker">In-app + push</p><h2>Annuncio alla lega</h2></div></div>
          <p className="mercato-nota">Manda un messaggio a tutti i partecipanti della lega, come notifica in-app e push (chi l'ha attivata). Toccando la notifica si apre l'app.</p>
          <textarea
            value={annuncioTesto}
            onChange={(evento) => setAnnuncioTesto(evento.target.value)}
            placeholder="Scrivi un messaggio per tutti i partecipanti…"
            maxLength={240}
            rows={3}
            disabled={inviandoAnnuncio}
            aria-label="Messaggio da inviare a tutta la lega"
          />
          {esitoAnnuncio && <p className={esitoAnnuncio.tono === 'errore' ? 'notice notice--error' : 'notice'}>{esitoAnnuncio.testo}</p>}
          <button className="button button--primary" type="button" disabled={inviandoAnnuncio || !annuncioTesto.trim()} onClick={() => void inviaAnnuncio()}>
            {inviandoAnnuncio ? 'Invio…' : 'Invia a tutti'}
          </button>
        </section>

        <section className="mercato-blocco admin-zona-pericolo">
          <div className="sezione-testa"><div><p className="kicker">Irreversibile</p><h2>Elimina lega</h2></div></div>
          <p className="mercato-nota">
            Cancella per sempre <strong>{league.nome}</strong>: squadre, rose, calendario, stagioni, mercato e
            notifiche di tutti i partecipanti, non solo le tue. Non si può annullare.
          </p>
          {!confermaEliminazione
            ? <button className="button button--danger-ghost" type="button" onClick={() => setConfermaEliminazione(true)}>Elimina lega</button>
            : <div className="player-modal__confirm">
                <div>
                  <strong>Confermi l'eliminazione?</strong>
                  <p>Per confermare, scrivi esattamente il nome della lega: <strong>{league.nome}</strong></p>
                </div>
                <input
                  type="text"
                  value={nomeDigitato}
                  onChange={(evento) => setNomeDigitato(evento.target.value)}
                  placeholder={league.nome}
                  aria-label="Digita il nome della lega per confermare"
                  disabled={eliminando}
                />
                {erroreEliminazione && <p className="notice notice--error">{erroreEliminazione}</p>}
                <div>
                  <button className="button button--danger" type="button" disabled={eliminando || nomeDigitato !== league.nome} onClick={() => void eliminaLega()}>
                    {eliminando ? 'Elimino…' : 'Elimina definitivamente'}
                  </button>
                  <button className="button button--secondary" type="button" disabled={eliminando} onClick={() => { setConfermaEliminazione(false); setNomeDigitato(''); setErroreEliminazione(null) }}>
                    Annulla
                  </button>
                </div>
              </div>}
        </section>
      </div>
    </main>
  )
}
