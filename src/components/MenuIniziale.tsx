import { useEffect, useMemo, useState, type FormEvent } from 'react'
import type { User } from '@supabase/supabase-js'
import type { Notifica } from '../lib/notifiche'
import { supabase } from '../lib/supabase'
import type { Membership, Season, Standing } from '../types'
import { Crest } from './Crest'
import { GuidaArgomenti, ARGOMENTI_AIUTO } from './Help'
import { Notifiche } from './Notifiche'

type Props = {
  user: User
  memberships: Membership[]
  onEntraNellaLega: (leagueId: number) => void
  onCreaLega: () => void
  onEntraConCodice: () => void
  onRefresh: () => void
  onApriNotifica: (notifica: Notifica) => void
}

const ETICHETTE_STATO: Record<string, string> = {
  setup: 'In preparazione',
  draft: 'Draft in corso',
  stagione: 'Stagione in corso',
  conclusa: 'Conclusa',
}

export function MenuIniziale({ user, memberships, onEntraNellaLega, onCreaLega, onEntraConCodice, onRefresh, onApriNotifica }: Props) {
  const [vista, setVista] = useState<'leghe' | 'profilo' | 'aiuto'>('leghe')
  const [menuAperto, setMenuAperto] = useState(false)
  const [classifiche, setClassifiche] = useState<Map<number, Standing>>(new Map())
  const [righeClassifica, setRigheClassifica] = useState<Standing[]>([])
  const [stagioni, setStagioni] = useState<Map<number, Season>>(new Map())
  const [stemmi, setStemmi] = useState<Record<number, string>>({})
  const [nomeAllenatore, setNomeAllenatore] = useState<string | null>(null)
  const [inModifica, setInModifica] = useState(false)
  const [bozzaNome, setBozzaNome] = useState('')
  const [salvataggio, setSalvataggio] = useState(false)
  const [erroreNome, setErroreNome] = useState<string | null>(null)

  useEffect(() => {
    if (!menuAperto) return
    const chiudiConEsc = (evento: KeyboardEvent) => { if (evento.key === 'Escape') setMenuAperto(false) }
    document.addEventListener('keydown', chiudiConEsc)
    return () => { document.removeEventListener('keydown', chiudiConEsc) }
  }, [menuAperto])

  useEffect(() => {
    let attivo = true
    async function caricaProfilo() {
      const { data } = await supabase.from('profiles').select('nome_allenatore').eq('user_id', user.id).maybeSingle()
      if (!attivo) return
      const nome = (data as { nome_allenatore: string } | null)?.nome_allenatore ?? null
      setNomeAllenatore(nome)
      setBozzaNome(nome ?? '')
    }
    void caricaProfilo()
    return () => { attivo = false }
  }, [user.id])

  useEffect(() => {
    let attivo = true
    async function carica() {
      const idSquadre = memberships.map((item) => item.id)
      if (idSquadre.length === 0) return

      // Una sola interrogazione per tutte le squadre dell'utente: la posizione
      // serve alla card della lega e alle statistiche di carriera.
      const { data } = await supabase.from('standings').select('*').in('team_id', idSquadre)
      if (attivo && data) {
        const righe = data as Standing[]
        const mappa = new Map<number, Standing>()
        for (const riga of righe) mappa.set(riga.team_id, riga)
        setClassifiche(mappa)
        setRigheClassifica(righe)

        // I titoli si contano solo sulle stagioni concluse.
        const idStagioni = [...new Set(righe.map((riga) => riga.season_id))]
        if (idStagioni.length) {
          const { data: dati } = await supabase.from('seasons').select('*').in('id', idStagioni)
          if (attivo && dati) setStagioni(new Map((dati as Season[]).map((stagione) => [stagione.id, stagione])))
        }
      }

      const firmati = await Promise.all(memberships
        .filter((item) => item.stemma_url && !item.stemma_url.startsWith('preset:'))
        .map(async (item) => {
          const { data: url } = await supabase.storage.from('team-crests').createSignedUrl(item.stemma_url!, 3600)
          return [item.id, url?.signedUrl] as const
        }))
      if (attivo) setStemmi(Object.fromEntries(firmati.filter((voce): voce is readonly [number, string] => Boolean(voce[1]))))
    }
    void carica()
    return () => { attivo = false }
  }, [memberships])

  async function salvaNome(evento: FormEvent) {
    evento.preventDefault()
    setSalvataggio(true)
    setErroreNome(null)
    const { data, error } = await supabase.rpc('aggiorna_nome_allenatore', { p_nome: bozzaNome })
    if (error) setErroreNome(error.message)
    else {
      setNomeAllenatore((data as { nome_allenatore: string }).nome_allenatore)
      setInModifica(false)
    }
    setSalvataggio(false)
  }

  const carriera = useMemo(() => {
    const concluse = righeClassifica.filter((riga) => stagioni.get(riga.season_id)?.stato === 'conclusa')
    const piazzamenti = righeClassifica.map((riga) => riga.posizione).filter((posizione): posizione is number => typeof posizione === 'number')
    return {
      leghe: memberships.length,
      stagioni: new Set(righeClassifica.map((riga) => riga.season_id)).size,
      titoli: concluse.filter((riga) => riga.posizione === 1).length,
      recordPunti: righeClassifica.reduce((massimo, riga) => Math.max(massimo, riga.punti), 0),
      migliorPiazzamento: piazzamenti.length ? Math.min(...piazzamenti) : null,
      partite: righeClassifica.reduce((somma, riga) => somma + riga.giocate, 0),
      concluse,
    }
  }, [righeClassifica, stagioni, memberships.length])

  const iniziale = (nomeAllenatore ?? user.email ?? '?').trim().charAt(0).toUpperCase()

  return <main className="app-shell menu-shell">
    <header className="topbar">
      <div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div>
      <div className="topbar__azioni">
        <Notifiche userId={user.id} onApriNotifica={onApriNotifica} />
        <button className="apri-menu" type="button" onClick={() => setMenuAperto(true)} aria-label="Apri il menu" aria-expanded={menuAperto}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" /></svg>
        </button>
      </div>
    </header>

    <div className="menu-page">
      {vista === 'aiuto' ? <>
        <div className="sezione-testa">
          <div><p className="kicker">Guida</p><h2>Aiuto</h2></div>
          <button className="button-fantasma" type="button" onClick={() => setVista('leghe')}>← Le tue leghe</button>
        </div>
        <p className="menu-hero__sotto">Tutte le regole del gioco, spiegate senza gergo tecnico.
          Tocca un argomento per aprirlo. Puoi leggerle anche prima di entrare in una lega, dato
          che sono le stesse per tutte.</p>
        <GuidaArgomenti argomenti={ARGOMENTI_AIUTO} />
      </> : vista === 'profilo' ? <>
        <div className="sezione-testa">
          <div><p className="kicker">Il tuo account</p><h2>Profilo allenatore</h2></div>
          <button className="button-fantasma" type="button" onClick={() => setVista('leghe')}>← Le tue leghe</button>
        </div>

        <section className="profilo-card">
          <div className="profilo-testa">
            <span className="profilo-avatar" aria-hidden="true">{iniziale}</span>
            <div className="profilo-identita">
              {inModifica ? (
                <form className="profilo-form" onSubmit={salvaNome}>
                  <label>
                    Nome allenatore
                    <input type="text" value={bozzaNome} minLength={2} maxLength={30} required autoFocus disabled={salvataggio} onChange={(evento) => setBozzaNome(evento.target.value)} />
                  </label>
                  <div className="profilo-form__azioni">
                    <button className="button button--primary" type="submit" disabled={salvataggio}>{salvataggio ? 'Salvo…' : 'Salva'}</button>
                    <button className="text-button" type="button" disabled={salvataggio} onClick={() => { setInModifica(false); setBozzaNome(nomeAllenatore ?? ''); setErroreNome(null) }}>Annulla</button>
                  </div>
                </form>
              ) : (
                <>
                  <p className="kicker">Allenatore</p>
                  <h2>{nomeAllenatore ?? 'Senza nome'}</h2>
                  <small>{user.email}</small>
                </>
              )}
            </div>
            {!inModifica && <button className="button-fantasma" type="button" onClick={() => setInModifica(true)}>{nomeAllenatore ? 'Modifica' : 'Scegli il nome'}</button>}
          </div>
          {erroreNome && <p className="notice notice--error">{erroreNome}</p>}

          <div className="profilo-numeri">
            <div><b>{carriera.leghe}</b><span>Leghe</span></div>
            <div><b>{carriera.stagioni}</b><span>Stagioni</span></div>
            <div><b>{carriera.titoli}</b><span>Titoli</span></div>
            <div><b>{carriera.partite}</b><span>Partite</span></div>
            <div><b>{carriera.recordPunti}</b><span>Record punti</span></div>
            <div><b>{carriera.migliorPiazzamento ? `${carriera.migliorPiazzamento}ª` : '—'}</b><span>Miglior posto</span></div>
          </div>

          <div className="profilo-albo">
            <h3>Albo d&#39;oro</h3>
            {carriera.concluse.length === 0
              ? <p className="season-empty">Nessuna stagione conclusa: l&#39;albo si riempie quando finisce il primo campionato.</p>
              : <ul>
                {carriera.concluse.map((riga) => {
                  const squadra = memberships.find((item) => item.id === riga.team_id)
                  return <li key={`${riga.season_id}-${riga.team_id}`}>
                    <span className={`albo-posto ${riga.posizione === 1 ? 'albo-posto--oro' : ''}`}>{riga.posizione ?? '—'}ª</span>
                    <span><b>{squadra?.nome ?? 'Squadra'}</b><small>{squadra?.league?.nome ?? '—'} · {riga.punti} punti</small></span>
                  </li>
                })}
              </ul>}
          </div>
        </section>
      </> : <>
        <section className="menu-hero">
          <p className="kicker">Il tuo spogliatoio</p>
          <h1>Bentornato{nomeAllenatore ? `, ${nomeAllenatore}` : ''}.</h1>
          <p className="menu-hero__sotto">{memberships.length === 0
            ? 'Non partecipi ancora a nessuna lega. Creane una o entra con un codice invito.'
            : `Partecipi a ${memberships.length} ${memberships.length === 1 ? 'lega' : 'leghe'}.`}</p>
        </section>

        <section className="menu-azioni">
          <button className="menu-azione menu-azione--primaria" type="button" onClick={onCreaLega}>
            <span className="menu-azione__icona" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M12 5v14M5 12h14" /></svg>
            </span>
            <span><b>Crea una lega</b><small>Scegli formato, budget e regole del draft</small></span>
          </button>
          <button className="menu-azione" type="button" onClick={onEntraConCodice}>
            <span className="menu-azione__icona" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 7h3a4 4 0 0 1 0 8h-3M9 17H6a4 4 0 0 1 0-8h3M8 12h8" /></svg>
            </span>
            <span><b>Entra con un codice</b><small>Hai ricevuto un invito da un amico</small></span>
          </button>
        </section>

        <div className="sezione-testa">
          <div><p className="kicker">Dove giochi</p><h2>Le tue leghe</h2></div>
          <button className="button-fantasma" type="button" onClick={onRefresh}>Aggiorna</button>
        </div>

        {memberships.length === 0
          ? <p className="season-empty">Nessuna lega. Il primo passo è crearne una.</p>
          : <div className="menu-leghe">
            {memberships.map((squadra) => {
              const lega = squadra.league!
              const classifica = classifiche.get(squadra.id)
              const inStagione = lega.stato === 'stagione' || lega.stato === 'conclusa'
              return <button className="menu-lega" type="button" key={squadra.id} onClick={() => onEntraNellaLega(lega.id)}>
                <Crest value={squadra.stemma_url} imageUrl={stemmi[squadra.id]} size="small" />
                <span className="menu-lega__testo">
                  <b>{squadra.nome}</b>
                  <small>{lega.nome} · {lega.n_squadre} squadre</small>
                </span>
                <span className="menu-lega__coda">
                  <span className={`pillola-stato ${lega.stato === 'stagione' ? 'pillola-stato--attesa' : lega.stato === 'conclusa' ? 'pillola-stato--fatta' : ''}`}>
                    {ETICHETTE_STATO[lega.stato] ?? lega.stato}
                  </span>
                  {inStagione && classifica && <em>{classifica.posizione ?? '—'}ª · {classifica.punti} pt</em>}
                </span>
              </button>
            })}
          </div>}
      </>}
    </div>

    {menuAperto && <div className="pannello-fondale" role="presentation" onPointerDown={(evento) => { if (evento.target === evento.currentTarget) setMenuAperto(false) }}>
      <aside className="pannello-laterale" role="dialog" aria-modal="true" aria-label="Menu account">
        <div className="pannello-testa">
          <span className="profilo-avatar" aria-hidden="true">{iniziale}</span>
          <div>
            <b>{nomeAllenatore ?? 'Senza nome'}</b>
            <small>{user.email}</small>
          </div>
          <button className="pannello-chiudi" type="button" onClick={() => setMenuAperto(false)} aria-label="Chiudi il menu">×</button>
        </div>
        <nav className="pannello-voci">
          <button type="button" onClick={() => { setVista('profilo'); setMenuAperto(false) }}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="8" r="3.6" /><path d="M5 20c0-3.6 3.1-5.6 7-5.6s7 2 7 5.6" /></svg>
            Profilo
          </button>
          <button type="button" onClick={() => { setVista('aiuto'); setMenuAperto(false) }}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M9.3 9.3a2.7 2.7 0 1 1 3.6 2.5c-.8.4-1.4 1-1.4 2v.4" /><path d="M12 16.8v.1" /></svg>
            Aiuto
          </button>
          <button className="pannello-voci__uscita" type="button" onClick={() => supabase.auth.signOut()}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 17l5-5-5-5M20 12H9M12 20H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h6" /></svg>
            Esci
          </button>
        </nav>
      </aside>
    </div>}
  </main>
}
