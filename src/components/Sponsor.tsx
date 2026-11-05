import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { LoadingLogo } from './LoadingLogo'
import { PopupSpiegazione } from './PopupSpiegazione'

// Sponsor (Season 3, docs/DIARIO-SEASON3.md §10): offerte di aziende reali a breve e lungo termine, un contratto attivo
// per colonna. Offerte, verifica e premi li fa il database (sponsor_stato, sponsor_scegli, sponsor_rinuncia): qui si
// legge e basta. Loghi in public/loghi-sponsor (Simple Icons).

type Categoria = 'breve' | 'lungo'
type Stato = 'offerta' | 'attiva' | 'completata' | 'fallita' | 'rinunciata'
type Contratto = {
  id: number; categoria: Categoria; tipo: string; titolo: string; descrizione: string; premio: number; effetto_tifo: number
  partite: number; stato: Stato; progresso: { fatto?: number; di?: number }; scelta_il: string | null; chiusa_il: string | null
  azienda: { nome: string; slug: string; colore: string }
}
type StatoSponsor = { attivi: boolean; contratti: Contratto[]; pausa: Partial<Record<Categoria, string>> | null; crediti: number | null }

const fmt = (n: number) => new Intl.NumberFormat('it-IT').format(n)
const ora = (iso: string) => new Intl.DateTimeFormat('it-IT', { weekday: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Rome' }).format(new Date(iso))
const COLONNE: Array<{ id: Categoria; titolo: string; sotto: string }> = [
  { id: 'breve', titolo: 'Breve termine', sotto: 'La prossima partita o le prossime due' },
  { id: 'lungo', titolo: 'Lungo termine', sotto: 'Da 5 a 8 partite' },
]

function Logo({ azienda }: { azienda: Contratto['azienda'] }) {
  return <span className="sp-logo" style={{ ['--sp-colore' as string]: azienda.colore }}><img src={`/loghi-sponsor/${azienda.slug}.svg`} alt="" /></span>
}

function Premio({ c }: { c: Contratto }) {
  return <span className="sp-premio">
    <b>+{fmt(c.premio)}</b><small>crediti</small>
    {c.effetto_tifo !== 0 && <em className={c.effetto_tifo > 0 ? 'is-su' : 'is-giu'}>tifo {c.effetto_tifo > 0 ? '+' : ''}{c.effetto_tifo}</em>}
  </span>
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

export function PaginaSponsor({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const [dati, setDati] = useState<StatoSponsor | null>(null)
  const [errore, setErrore] = useState<string | null>(null)
  const [lavoro, setLavoro] = useState<number | null>(null)
  const [conferma, setConferma] = useState<number | null>(null)

  const carica = useCallback(async () => {
    const { data, error } = await supabase.rpc('sponsor_stato', { p_league_id: league.id })
    if (error) { setErrore(error.message); return }
    setDati(data as StatoSponsor)
  }, [league.id])
  useEffect(() => { void carica() }, [carica])

  async function azione(id: number, rpc: 'sponsor_scegli' | 'sponsor_rinuncia') {
    setLavoro(id); setErrore(null)
    const { error } = await supabase.rpc(rpc, { p_contratto_id: id })
    setLavoro(null); setConferma(null)
    if (error) { setErrore(error.message); return }
    await carica()
  }

  const contratti = dati?.contratti ?? []
  const storico = contratti.filter((c) => c.stato === 'completata' || c.stato === 'fallita' || c.stato === 'rinunciata')

  return <main className="app-shell season-shell sp-shell">
    <GameNav league={league} active="sponsor" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Sponsor</span></header>
    <div className="season-page season-page--narrow sp-page">
      <PopupSpiegazione userId={membership.user_id} hintKey="sponsor-v1" titolo="Come funzionano gli sponsor">
        <p>Le aziende ti propongono dei contratti: se raggiungi l'obiettivo ti pagano in <strong>crediti</strong>. Ci sono due colonne, <strong>breve</strong> e <strong>lungo termine</strong>, con tre offerte ciascuna.</p>
        <p>Puoi firmare <strong>un contratto per colonna</strong>. Quando lo completi o lo fallisci arrivano offerte nuove. Le offerte che non firmi cambiano a ogni giornata, perché dipendono da come sta la tua squadra: avversari, classifica, tifo, gol.</p>
        <p>I contratti si verificano sulle partite che hai già visto, quindi i crediti non svelano i risultati. Se rinunci a un contratto, le nuove offerte di quella colonna arrivano dopo 24 ore. Alcuni sponsor piacciono poco ai tifosi, altri li fanno contenti: è scritto sull'offerta.</p>
      </PopupSpiegazione>
      <section className="alerts-heading sp-testa">
        <div><p className="kicker">{league.nome} · Extra campo</p><h1>Sponsor.</h1>
          <p>Firma un contratto per colonna, raggiungi l'obiettivo, incassa i crediti.</p></div>
        {dati?.crediti != null && <div className="sp-crediti"><small>I tuoi crediti</small><b>{fmt(dati.crediti)}</b></div>}
      </section>
      {errore && <p className="notice notice--error" role="alert">{errore}</p>}

      {!dati ? <section className="season-state is-caricamento"><LoadingLogo compatto /><h2>Carico gli sponsor…</h2><span className="caricamento-barra" aria-hidden="true" /></section>
        : !dati.attivi ? <p className="season-empty">Gli sponsor si fanno vivi a stagione in corso.</p>
        : <div className="sp-colonne">
          {COLONNE.map((col) => {
            const attivo = contratti.find((c) => c.categoria === col.id && c.stato === 'attiva')
            const offerte = contratti.filter((c) => c.categoria === col.id && c.stato === 'offerta')
            const pausa = dati.pausa?.[col.id]
            return <section className="sp-colonna" key={col.id}>
              <header><h2>{col.titolo}</h2><small>{col.sotto}</small></header>
              {attivo ? <article className="sp-contratto is-attivo">
                <div className="sp-contratto__testa"><Logo azienda={attivo.azienda} /><div><small>{attivo.azienda.nome} · contratto firmato</small><strong>{attivo.titolo}</strong></div><Premio c={attivo} /></div>
                <p>{attivo.descrizione}</p>
                {attivo.progresso?.di != null && <div className="sp-progresso" aria-label={`Avanzamento ${attivo.progresso.fatto ?? 0} su ${attivo.progresso.di}`}>
                  <i style={{ width: `${Math.min(100, ((attivo.progresso.fatto ?? 0) * 100) / Math.max(1, attivo.progresso.di))}%` }} />
                  <span>{attivo.progresso.fatto ?? 0} / {attivo.progresso.di}</span>
                </div>}
                {conferma === attivo.id
                  ? <div className="sp-conferma"><span>Rinunci al contratto? Le nuove offerte arrivano fra 24 ore.</span>
                      <button type="button" className="button button--secondary" disabled={lavoro !== null} onClick={() => void azione(attivo.id, 'sponsor_rinuncia')}>Rinuncia</button>
                      <button type="button" className="button button--secondary" onClick={() => setConferma(null)}>Annulla</button></div>
                  : <button type="button" className="sp-rinuncia" onClick={() => setConferma(attivo.id)}>Rinuncia al contratto</button>}
              </article>
                : pausa ? <p className="sp-vuoto">Nuove offerte da {ora(pausa)}.</p>
                : offerte.length === 0 ? <p className="sp-vuoto">Nessuna offerta adesso: tornano quando ci sono abbastanza partite davanti.</p>
                : offerte.map((c) => <article className="sp-contratto" key={c.id}>
                  <div className="sp-contratto__testa"><Logo azienda={c.azienda} /><div><small>{c.azienda.nome}</small><strong>{c.titolo}</strong></div><Premio c={c} /></div>
                  <p>{c.descrizione}</p>
                  <button type="button" className="button button--primary sp-firma" disabled={lavoro !== null} onClick={() => void azione(c.id, 'sponsor_scegli')}>{lavoro === c.id ? 'Firmo…' : 'Firma il contratto'}</button>
                </article>)}
            </section>
          })}
        </div>}

      {storico.length > 0 && <section className="sp-storico">
        <h2>Ultimi contratti</h2>
        <ul>{storico.map((c) => <li key={c.id} className={`is-${c.stato}`}>
          <Logo azienda={c.azienda} />
          <span><strong>{c.titolo}</strong><small>{c.azienda.nome} · {c.stato === 'completata' ? 'completato' : c.stato === 'fallita' ? 'non riuscito' : 'rinunciato'}{c.chiusa_il ? ` · ${ora(c.chiusa_il)}` : ''}</small></span>
          <b>{c.stato === 'completata' ? `+${fmt(c.premio)}` : '—'}</b>
        </li>)}</ul>
      </section>}
    </div>
  </main>
}
