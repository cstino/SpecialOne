import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { PREMI, caricaPremi, type Premio } from '../lib/premiAlbo'
import type { League, Membership, Season, Standing, Team } from '../types'
import { Crest } from './Crest'
import { GameNav, type GameView } from './GameNav'
import { SeasonState } from './SeasonUI'

type Campione = {
  stagione: Season
  classifica: Standing
  squadra: Team | null
  stemmaFirmato?: string
  // Dalla stagione 2 il titolo lo vince il playoff, non la stagione regolare
  // (design §10.7). Resta falso per le stagioni giocate prima dei tabelloni e
  // per le leghe sotto le 8 squadre, dove i playoff non si giocano.
  daPlayoff: boolean
}

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

function dataItaliana(data: string | null) {
  if (!data) return null
  return new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${data}T12:00:00`))
}

export function AlboDOro({ membership, onNavigate }: Props) {
  const league = membership.league as League
  const [campioni, setCampioni] = useState<Campione[]>([])
  const [premi, setPremi] = useState<Premio[]>([])
  const [stagionePremi, setStagionePremi] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const carica = useCallback(async () => {
    setLoading(true)
    setError(null)

    const { data: stagioni, error: erroreStagioni } = await supabase
      .from('seasons')
      .select('*')
      .eq('league_id', league.id)
      .eq('stato', 'conclusa')
      .order('numero', { ascending: false })
    if (erroreStagioni) {
      setError(erroreStagioni.message)
      setLoading(false)
      return
    }

    const stagioniConcluse = (stagioni ?? []) as Season[]
    if (stagioniConcluse.length === 0) {
      setCampioni([])
      setLoading(false)
      return
    }

    const idsStagioni = stagioniConcluse.map((stagione) => stagione.id)
    // Serve tutta la classifica, non solo la prima: il campione puo' essere
    // arrivato quarto in stagione regolare e aver vinto il playoff, e di lui
    // vogliamo comunque mostrare punti e record.
    const [classificheRes, playoffRes] = await Promise.all([
      supabase.from('standings').select('*').eq('league_id', league.id).in('season_id', idsStagioni),
      supabase.from('brackets').select('season_id, vincitore_team_id')
        .eq('league_id', league.id).in('season_id', idsStagioni)
        .eq('tipo', 'title').eq('stato', 'concluso'),
    ])
    if (classificheRes.error || playoffRes.error) {
      setError(classificheRes.error?.message ?? playoffRes.error?.message ?? 'Dati non disponibili.')
      setLoading(false)
      return
    }

    const classifiche = (classificheRes.data ?? []) as Standing[]
    const campionePlayoffPerStagione = new Map(
      ((playoffRes.data ?? []) as Array<{ season_id: number; vincitore_team_id: number | null }>)
        .filter((b) => b.vincitore_team_id != null)
        .map((b) => [b.season_id, b.vincitore_team_id!]),
    )
    // Il titolo e' del vincitore del playoff; dove il playoff non c'e' stato
    // (stagione 1, o lega sotto le 8 squadre) vale la prima in classifica.
    const vincitori = stagioniConcluse.flatMap((stagione) => {
      const diStagione = classifiche.filter((riga) => riga.season_id === stagione.id)
      const idPlayoff = campionePlayoffPerStagione.get(stagione.id)
      const riga = idPlayoff != null
        ? diStagione.find((r) => r.team_id === idPlayoff)
        : diStagione.find((r) => r.posizione === 1)
      return riga ? [{ riga, daPlayoff: idPlayoff != null }] : []
    })
    const idsSquadre = [...new Set(vincitori.map((v) => v.riga.team_id))]
    const { data: squadre, error: erroreSquadre } = idsSquadre.length
      ? await supabase.from('teams').select('*').in('id', idsSquadre)
      : { data: [], error: null }
    if (erroreSquadre) {
      setError(erroreSquadre.message)
      setLoading(false)
      return
    }

    const squadrePerId = new Map(((squadre ?? []) as Team[]).map((squadra) => [squadra.id, squadra]))
    const stemmiFirmati = await Promise.all(((squadre ?? []) as Team[])
      .filter((squadra) => squadra.stemma_url && !squadra.stemma_url.startsWith('preset:'))
      .map(async (squadra) => {
        const { data } = await supabase.storage.from('team-crests').createSignedUrl(squadra.stemma_url!, 3600)
        return [squadra.id, data?.signedUrl] as const
      }))
    const stemmiPerSquadra = new Map(stemmiFirmati.filter((voce): voce is readonly [number, string] => Boolean(voce[1])))
    const vincitorePerStagione = new Map(vincitori.map((v) => [v.riga.season_id, v]))

    setCampioni(stagioniConcluse.flatMap((stagione) => {
      const vincitore = vincitorePerStagione.get(stagione.id)
      if (!vincitore) return []
      const { riga, daPlayoff } = vincitore
      return [{
        stagione, classifica: riga, daPlayoff,
        squadra: squadrePerId.get(riga.team_id) ?? null,
        stemmaFirmato: stemmiPerSquadra.get(riga.team_id),
      }]
    }))

    // Un errore sui premi non deve nascondere l'albo dei campioni.
    setPremi(await caricaPremi(league.id))
    setLoading(false)
  }, [league.id])

  useEffect(() => { void carica() }, [carica])

  const ultimoCampione = campioni[0]
  const stagioneInVista = campioni.find((campione) => campione.stagione.id === stagionePremi) ?? campioni[0]
  const premiInVista = stagioneInVista ? premi.filter((premio) => premio.stagioneId === stagioneInVista.stagione.id) : []
  const fasiInVista = (['regular', 'title'] as const).filter((fase) => fase === 'regular' || premiInVista.some((premio) => premio.fase === fase))
  return <main className="app-shell season-shell honors-shell">
    <GameNav league={league} active="honors" onNavigate={onNavigate} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Storia della lega</span></header>
    <SeasonState loading={loading} error={error} onRetry={carica} />
    {!loading && !error && <div className="season-page season-page--narrow honors-page">
      <section className="honors-heading">
        <div>
          <p className="kicker">{league.nome}</p>
          <h1>Albo d'oro.</h1>
          <p>Le squadre che hanno scritto la storia della lega, stagione dopo stagione.</p>
        </div>
        <div className="honors-cup" aria-hidden="true"><span>★</span><small>{campioni.length}</small><b>titoli assegnati</b></div>
      </section>

      {ultimoCampione ? <section className="honors-champion">
        <div className="honors-champion__glow" aria-hidden="true" />
        <p>Campione in carica</p>
        <div className="honors-champion__team">
          <Crest value={ultimoCampione.squadra?.stemma_url ?? null} stelle={ultimoCampione.squadra?.titoli_title} imageUrl={ultimoCampione.stemmaFirmato} size="large" />
          <div>
            <small>STAGIONE {ultimoCampione.stagione.numero}</small>
            <h2>{ultimoCampione.squadra?.nome ?? 'Squadra non disponibile'}</h2>
            <span>
              {ultimoCampione.daPlayoff
                ? <>Vincitore del Title Playoff · {ultimoCampione.classifica.posizione}ª in stagione regolare</>
                : <>{ultimoCampione.classifica.punti} punti · {ultimoCampione.classifica.vittorie} vittorie</>}
            </span>
          </div>
        </div>
        {dataItaliana(ultimoCampione.stagione.data_fine) && <em>Trionfo del {dataItaliana(ultimoCampione.stagione.data_fine)}</em>}
      </section> : <section className="honors-empty"><span aria-hidden="true">★</span><h2>Il primo trofeo è ancora in palio.</h2><p>Quando una stagione si concluderà, qui comparirà la squadra campione.</p></section>}

      {campioni.length > 0 && <section className="honors-list" aria-label="Campioni delle stagioni passate">
        <div className="honors-list__heading"><p className="kicker">Archivio campioni</p><span>{campioni.length} {campioni.length === 1 ? 'stagione' : 'stagioni'}</span></div>
        <ol>
          {campioni.map((campione, indice) => <li className={indice === 0 ? 'is-current' : ''} key={campione.stagione.id}>
            <span className="honors-list__season">S{campione.stagione.numero}</span>
            <Crest value={campione.squadra?.stemma_url ?? null} imageUrl={campione.stemmaFirmato} />
            <strong>{campione.squadra?.nome ?? 'Squadra non disponibile'}</strong>
            <span className="honors-list__record">
              {campione.daPlayoff && <b className="honors-badge">TITLE PLAYOFF</b>}
              {campione.classifica.punti} PT <i>·</i> {campione.classifica.vittorie}V {campione.classifica.pareggi}N {campione.classifica.sconfitte}P
            </span>
            {indice === 0 && <em>IN CARICA</em>}
          </li>)}
        </ol>
      </section>}

      {campioni.length > 0 && premi.length > 0 && <section className="honors-premi" aria-label="Premi individuali">
        <div className="honors-list__heading"><p className="kicker">Premi individuali</p><span>Stagione {stagioneInVista?.stagione.numero}</span></div>
        {campioni.length > 1 && <div className="honors-premi__stagioni" role="tablist" aria-label="Stagione">
          {campioni.map((campione) => <button type="button" role="tab" aria-selected={campione.stagione.id === stagioneInVista?.stagione.id}
            className={campione.stagione.id === stagioneInVista?.stagione.id ? 'is-attiva' : ''} key={campione.stagione.id}
            onClick={() => setStagionePremi(campione.stagione.id)}>S{campione.stagione.numero}</button>)}
        </div>}
        <div className="honors-premi__fasi">
          {fasiInVista.map((fase) => <div className={`honors-premi__fase honors-premi__fase--${fase}`} key={fase}>
            <h3>{fase === 'regular' ? 'Regular Season' : 'Title Playoffs'}</h3>
            {PREMI.map(({ chiave, titolo, unita }) => {
              const premio = premiInVista.find((voce) => voce.fase === fase && voce.premio === chiave)
              return <article className="honors-premio" key={chiave}>
                <span className="honors-premio__titolo">{titolo}</span>
                {premio ? <>
                  <div className="honors-premio__foto">{premio.foto ? <img src={premio.foto} alt="" loading="lazy" /> : <b aria-hidden="true">{premio.nome.charAt(0)}</b>}</div>
                  <div className="honors-premio__chi">
                    <strong>{premio.nome}</strong>
                    <span><Crest value={premio.squadra?.stemma_url ?? null} stelle={premio.squadra?.titoli_title} imageUrl={premio.stemmaFirmato} size="small" />{premio.squadra?.nome ?? '—'}</span>
                  </div>
                  <div className="honors-premio__valore"><b>{premio.valore}</b><small>{premio.valore === 1 ? unita[0] : unita[1]}</small></div>
                </> : <p className="honors-premio__vuoto">Non assegnato</p>}
              </article>
            })}
          </div>)}
        </div>
      </section>}
    </div>}
  </main>
}
