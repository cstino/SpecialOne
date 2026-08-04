import { useState } from 'react'
import { supabase } from '../lib/supabase'
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
  const [simulando, setSimulando] = useState(false)
  const [aprendo, setAprendo] = useState(false)
  const [chiudendo, setChiudendo] = useState(false)
  const [esitoSimula, setEsitoSimula] = useState<EsitoAzione | null>(null)
  const [esitoApri, setEsitoApri] = useState<EsitoAzione | null>(null)
  const [esitoChiudi, setEsitoChiudi] = useState<EsitoAzione | null>(null)

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
    const risultato = data as { riaperte?: number; estratti?: number; totale_aperto?: number }
    const riaperte = risultato?.riaperte ?? 0
    const estratti = risultato?.estratti ?? 0
    const totale = risultato?.totale_aperto ?? riaperte + estratti
    setEsitoApri({
      tono: 'ok',
      testo: totale > 0
        ? `Mercato riaperto: ${riaperte} ${riaperte === 1 ? 'asta riaperta' : 'aste riaperte'}, ${estratti} ${estratti === 1 ? 'nuovo estratto' : 'nuovi estratti'}.`
        : 'Non ci sono nuovi giocatori disponibili da estrarre o riaprire.',
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

  return (
    <main className="app-shell season-shell">
      <GameNav league={league} active="admin" onNavigate={onNavigate} />
      <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div></header>
      <div className="season-page season-page--narrow">
        <section className="season-title-row">
          <div>
            <p className="kicker">Solo amministratore · {league.nome}</p>
            <h1>Pannello admin.</h1>
            <p>Tre azioni di riserva, per quando pg_cron non parte da solo. L'apertura manuale abilita
              anche le offerte fuori dalla finestra automatica, finché il mercato non viene richiuso.</p>
          </div>
        </section>

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
      </div>
    </main>
  )
}
