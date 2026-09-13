// ============================================================
//  ON-SEASON DRAFT IN DIRETTA
//
//  Una chiamata al minuto, in ordine di posizione, come al draft NBA. La card
//  compare in home solo mentre il draft e' in corso (e per un po' dopo la
//  fine, per chi arriva tardi), e mostra l'ultima chiamata in grande piu' lo
//  storico sotto.
//
//  NIENTE SPOILER, ED E' LO SCHEMA A GARANTIRLO
//  Questo componente non ha nessuna logica di occultamento, e non deve averne:
//  una scelta non ancora chiamata ha player_instance_id nullo nel database,
//  perche' private.avanza_draft_live la risolve solo quando tocca a quella
//  squadra. Non c'e' niente da nascondere perche' il dato non esiste ancora.
//  Vedi supabase/migrations/20260913103000_draft_live_a_passi.sql.
//
//  L'ORA E' QUELLA DEL SERVER, non del telefono: useOraCorrente sincronizza
//  con il database compensando il tempo di andata e ritorno. Un orologio
//  locale sballato falserebbe il conto alla rovescia della prossima chiamata.
// ============================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { oraServerAdesso, useOraCorrente } from '../lib/countdown'
import { firmaFoto } from './RosaElenco'
import { macroRuolo } from '../lib/ruoli'
import { Crest } from './Crest'
import type { Team } from '../types'

// Ogni quanto si richiede lo stato al database mentre il draft e' in corso.
// Cinque secondi: la chiamata cade una volta al minuto, quindi appare con meno
// di cinque secondi di ritardo e la query resta leggera.
const RINFRESCO_MS = 5000

// Quante chiamate gia' avvenute stanno in una pagina dello storico. Le pagine
// si contano dalla PRIMA scelta in avanti, non dall'ultima all'indietro: cosi'
// la pagina 1 contiene sempre le chiamate 1-2-3 e non cambia contenuto mano a
// mano che il draft prosegue.
const PER_PAGINA = 3

// Per quanto la card resta in home dopo l'ultima chiamata, cosi' chi apre
// l'app a draft finito vede comunque com'e' andata.
const CODA_DOPO_FINE_MS = 6 * 60 * 60 * 1000

type Finestra = {
  stagione: number
  avviata_il: string | null
  estrazione_il: string | null
  risolta_il: string | null
  passo_secondi: number
}

type Chiamata = {
  sceltaId: number
  posizione: number
  teamId: number
  stato: 'usata' | 'vuota'
  nome: string | null
  ruolo: string | null
  macro: string
  overall: number | null
  foto: string | null
}

type Props = {
  leagueId: number
  teamById: Map<number, Team>
  crestUrlByTeamId: Map<number, string>
  mioTeamId: number
}

export function DraftLive({ leagueId, teamById, crestUrlByTeamId, mioTeamId }: Props) {
  const [finestra, setFinestra] = useState<Finestra | null>(null)
  const [chiamate, setChiamate] = useState<Chiamata[]>([])
  const [totale, setTotale] = useState(0)
  const [pronto, setPronto] = useState(false)
  const adesso = useOraCorrente()

  const carica = useCallback(async () => {
    // La finestra ON non ancora risolta, oppure l'ultima risolta di recente.
    const { data: finestre } = await supabase
      .from('finestre_scelte')
      .select('stagione, avviata_il, estrazione_il, risolta_il, passo_secondi')
      .eq('league_id', leagueId)
      .eq('finestra', 'on')
      .order('stagione', { ascending: false })
      .limit(1)
    const f = (finestre ?? [])[0] as Finestra | undefined
    if (!f) { setFinestra(null); setPronto(true); return }
    setFinestra(f)

    const { data: scelte } = await supabase
      .from('scelte_draft')
      .select('id, posizione, stato, team_proprietario_id, player_instance_id')
      .eq('league_id', leagueId)
      .eq('stagione', f.stagione)
      .eq('finestra', 'on')
      .in('stato', ['determinata', 'usata', 'vuota'])
      .order('posizione', { ascending: true })

    const righe = scelte ?? []
    setTotale(righe.length)
    const fatte = righe.filter((s) => s.stato === 'usata' || s.stato === 'vuota')

    // Anagrafica solo delle chiamate GIA' avvenute: le altre non hanno
    // player_instance_id, quindi non c'e' nulla da chiedere.
    const idIstanze = [...new Set(fatte.map((s) => s.player_instance_id).filter((v): v is number => v != null))]
    const { data: istanze } = idIstanze.length
      ? await supabase.from('player_instances').select('id, player_id, overall_corrente').in('id', idIstanze)
      : { data: [] }
    const idGiocatori = [...new Set((istanze ?? []).map((i) => i.player_id))]
    const { data: anagrafica } = idGiocatori.length
      ? await supabase.from('players').select('id, nome, posizioni, overall, foto_url').in('id', idGiocatori)
      : { data: [] }
    const fotoFirmate = await Promise.all((anagrafica ?? []).filter((p) => p.foto_url)
      .map(async (p) => [p.id, await firmaFoto(p.foto_url)] as const))
    const fotoPerGiocatore = new Map(fotoFirmate.filter((v): v is [number, string] => Boolean(v[1])))
    const anagraficaPerId = new Map((anagrafica ?? []).map((p) => [p.id, p]))
    const istanzaPerId = new Map((istanze ?? []).map((i) => [i.id, i]))

    setChiamate(fatte.map((s) => {
      const istanza = s.player_instance_id != null ? istanzaPerId.get(s.player_instance_id) : undefined
      const p = istanza ? anagraficaPerId.get(istanza.player_id) : undefined
      return {
        sceltaId: s.id,
        posizione: s.posizione ?? 0,
        teamId: s.team_proprietario_id,
        stato: s.stato === 'usata' ? 'usata' : 'vuota',
        nome: p?.nome ?? null,
        ruolo: p?.posizioni?.[0] ?? null,
        macro: macroRuolo(p?.posizioni ?? []).toLowerCase(),
        overall: istanza?.overall_corrente ?? p?.overall ?? null,
        foto: p ? fotoPerGiocatore.get(p.id) ?? null : null,
      }
    }))
    setPronto(true)
  }, [leagueId])

  useEffect(() => { void carica() }, [carica])

  // In corso = partito e non ancora concluso. Solo allora vale la pena
  // interrogare il database ogni cinque secondi.
  const inCorso = Boolean(finestra?.avviata_il && !finestra.risolta_il)

  useEffect(() => {
    if (!inCorso) return
    const t = setInterval(() => { void carica() }, RINFRESCO_MS)
    return () => clearInterval(t)
  }, [inCorso, carica])

  const ultima = chiamate.length ? chiamate[chiamate.length - 1] : null
  // In ordine di chiamata, dalla prima: l'ultima sta gia' in evidenza sopra.
  const precedenti = chiamate.slice(0, -1)
  const pagine = Math.max(1, Math.ceil(precedenti.length / PER_PAGINA))

  // "segui" tiene lo storico agganciato all'ultima pagina mentre il draft
  // corre. Appena si sfoglia indietro si stacca, altrimenti il rinfresco ogni
  // cinque secondi riporterebbe in fondo mentre si sta guardando l'inizio.
  // Tornando sull'ultima pagina si riaggancia da solo.
  const [pagina, setPagina] = useState(0)
  const [segui, setSegui] = useState(true)
  useEffect(() => { if (segui) setPagina(pagine - 1) }, [segui, pagine])

  const paginaValida = Math.min(pagina, pagine - 1)
  const vaiA = (p: number) => {
    const n = Math.min(Math.max(0, p), pagine - 1)
    setPagina(n)
    setSegui(n === pagine - 1)
  }
  const visibili = precedenti.slice(paginaValida * PER_PAGINA, paginaValida * PER_PAGINA + PER_PAGINA)

  const prossimaFra = useMemo(() => {
    if (!finestra?.avviata_il || finestra.risolta_il) return null
    const passo = (finestra.passo_secondi || 60) * 1000
    const scadenza = new Date(finestra.avviata_il).getTime() + chiamate.length * passo
    return Math.max(0, scadenza - adesso)
  }, [finestra, chiamate.length, adesso])

  if (!pronto || !finestra) return null

  // Non ancora partito: la card non serve, il conto alla rovescia della
  // finestra vive gia' nella pagina Scelte.
  if (!finestra.avviata_il) return null
  if (finestra.risolta_il && adesso - new Date(finestra.risolta_il).getTime() > CODA_DOPO_FINE_MS) return null

  const concluso = Boolean(finestra.risolta_il)

  return (
    <article className="flex flex-col gap-5 border-b border-white/10 pb-10">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[.62rem] font-extrabold uppercase tracking-[.14em] text-orange-300/85">
            {concluso ? 'On-Season Draft · concluso' : 'On-Season Draft · in diretta'}
          </p>
          <h2 className="font-display mt-1 text-2xl font-extrabold text-white">
            {concluso ? 'Tutte le chiamate' : `Chiamata ${chiamate.length} di ${totale}`}
          </h2>
        </div>
        {!concluso && (
          <span className="flex shrink-0 items-center gap-2 rounded-full border border-orange-400/30 bg-orange-500/10 px-3 py-1.5">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-orange-400 opacity-70" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-orange-400" />
            </span>
            <span className="text-[.62rem] font-extrabold uppercase tracking-[.12em] text-orange-200">Live</span>
          </span>
        )}
      </div>

      {/* LA NOTIZIA: l'ultima chiamata, nel formato che l'utente ha chiesto. */}
      {ultima && (
        <div className="overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-br from-orange-500/12 via-white/[.04] to-transparent">
          <div className="flex items-start gap-4 p-4 md:p-5">
            <div className="min-w-0 flex-1">
              <p className="text-[.82rem] leading-snug text-white/75">
                Con la scelta numero <b className="font-display text-white">{ultima.posizione}</b>,
                {' '}<b className="text-white">{teamById.get(ultima.teamId)?.nome ?? 'la squadra'}</b>
                {ultima.stato === 'usata' ? ' seleziona…' : ' non esercita la scelta.'}
              </p>
              {ultima.stato === 'usata' ? (
                <div className="mt-3 flex items-center gap-3">
                  {ultima.foto
                    ? <img src={ultima.foto} alt="" className="h-16 w-16 shrink-0 rounded-xl object-cover object-top ring-1 ring-white/15" />
                    : <div className="grid h-16 w-16 shrink-0 place-items-center rounded-xl bg-white/5 text-lg font-bold text-white/30 ring-1 ring-white/10">?</div>}
                  <div className="min-w-0">
                    <p className="font-display truncate text-xl font-extrabold leading-tight text-white">{ultima.nome ?? 'Giocatore'}</p>
                    <p className="mt-1 flex items-center gap-2 text-[.7rem] font-bold uppercase tracking-wide text-white/50">
                      {ultima.ruolo && <span className={`role-pill role-pill--${ultima.macro}`}>{ultima.ruolo}</span>}
                      {ultima.overall != null && <span className="tabular-nums">OVR {ultima.overall}</span>}
                    </p>
                  </div>
                </div>
              ) : (
                <p className="mt-2 text-[.76rem] text-white/45">
                  Nessuna preferenza disponibile rientrava sotto il tetto ingaggi.
                </p>
              )}
            </div>
            <Crest value={teamById.get(ultima.teamId)?.stemma_url ?? null} imageUrl={crestUrlByTeamId.get(ultima.teamId)} />
          </div>
        </div>
      )}

      {!concluso && prossimaFra != null && (
        <p className="text-center text-[.76rem] text-white/55">
          {chiamate.length >= totale
            ? 'Ultima chiamata effettuata.'
            : <>Prossima chiamata tra <strong className="font-display tabular-nums text-white">{Math.ceil(prossimaFra / 1000)}s</strong></>}
        </p>
      )}

      {precedenti.length > 0 && (
        <div className="flex flex-col">
          {/* Senza questa intestazione le chiamate precedenti sembravano la
              lista di preferenze della squadra appena chiamata: e' successo
              davvero, alla prima prova del 13 settembre 2026. */}
          <div className="mb-1 flex items-center justify-between gap-3">
            <p className="text-[.62rem] font-extrabold uppercase tracking-[.14em] text-white/35">
              Già chiamati
            </p>
            {pagine > 1 && (
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => vaiA(paginaValida - 1)}
                  disabled={paginaValida === 0}
                  aria-label="Chiamate precedenti"
                  className="grid h-7 w-7 place-items-center rounded-lg bg-white/8 text-white/70 transition enabled:hover:bg-white/15 enabled:hover:text-white disabled:opacity-25"
                >‹</button>
                <span className="min-w-[3.2rem] text-center text-[.62rem] font-extrabold uppercase tracking-[.1em] text-white/35 tabular-nums">
                  {paginaValida + 1} / {pagine}
                </span>
                <button
                  type="button"
                  onClick={() => vaiA(paginaValida + 1)}
                  disabled={paginaValida >= pagine - 1}
                  aria-label="Chiamate successive"
                  className="grid h-7 w-7 place-items-center rounded-lg bg-white/8 text-white/70 transition enabled:hover:bg-white/15 enabled:hover:text-white disabled:opacity-25"
                >›</button>
              </div>
            )}
          </div>
          <div className="flex flex-col divide-y divide-white/10">
          {visibili.map((c) => (
            <div key={c.sceltaId} className={`flex items-center gap-3 py-2.5 ${c.teamId === mioTeamId ? 'text-orange-200' : ''}`}>
              <b className="font-display w-6 shrink-0 text-center text-[.82rem] font-extrabold text-white/40 tabular-nums">{c.posizione}</b>
              {c.foto
                ? <img src={c.foto} alt="" className="h-8 w-8 shrink-0 rounded-lg object-cover object-top ring-1 ring-white/10" />
                : <div className="h-8 w-8 shrink-0 rounded-lg bg-white/5 ring-1 ring-white/10" />}
              <div className="min-w-0 flex-1">
                <p className="truncate text-[.82rem] font-bold text-white">{c.nome ?? 'Scelta non esercitata'}</p>
                <p className="truncate text-[.66rem] text-white/45">{teamById.get(c.teamId)?.nome ?? '—'}</p>
              </div>
              {c.ruolo && <span className={`role-pill role-pill--${c.macro} shrink-0`}>{c.ruolo}</span>}
              {c.overall != null && <strong className="font-display shrink-0 text-[.9rem] font-extrabold tabular-nums text-white/80">{c.overall}</strong>}
            </div>
          ))}
          </div>
        </div>
      )}
    </article>
  )
}
