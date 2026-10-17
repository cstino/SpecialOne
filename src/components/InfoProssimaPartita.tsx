import type { Fixture, Team } from '../types'
import { fascia, bonus, fmtBonus } from './Pubblico'
import { SOGLIA_DERBY } from '../lib/useRivalita'

// Nella card della prossima partita (leghe con le novita'): che stadio si trova e se e' un derby.
type Props = { fixture: Fixture; miaSquadraId: number; teamById: Map<number, Team>; rivalita: Map<number, number> }

export function InfoProssimaPartita({ fixture, miaSquadraId, teamById, rivalita }: Props) {
  const casa = teamById.get(fixture.home_team_id)
  const inCasa = fixture.home_team_id === miaSquadraId
  const avversariaId = inCasa ? fixture.away_team_id : fixture.home_team_id
  const grado = rivalita.get(avversariaId) ?? 0
  const derby = grado > SOGLIA_DERBY
  const p = Number(casa?.pubblico ?? 100)
  const f = fascia(p)
  return <div className="info-partita">
    {derby && <span className="info-partita__derby">DERBY</span>}
    {fixture.campo_neutro
      ? <span className="info-partita__stadio">Campo neutro: nessun bonus casa</span>
      : <span className={`info-partita__stadio info-partita__stadio--${f.classe}`}>
        <i aria-hidden="true" />
        {inCasa ? <>Il tuo stadio: <b>{f.testo.toLowerCase()}</b> · bonus casa {fmtBonus(bonus(p))}</> : <>Stadio di {casa?.nome ?? 'casa'}: <b>{f.testo.toLowerCase()}</b> · loro bonus {fmtBonus(bonus(p))}</>}
      </span>}
  </div>
}
