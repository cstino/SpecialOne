import { isEventoGol, type EventoPartita } from '../types'

export type StatEventoStorico = {
  team_id: number
  player_instance_id: number
  minuti: number
  gol: number
  tiri: number
  tiri_porta: number
}

function creaRng(seme: number) {
  let stato = seme >>> 0
  return () => { stato = (stato * 1664525 + 1013904223) >>> 0; return stato / 4294967296 }
}

// Le partite precedenti alla cronaca estesa conservano solo i gol. Minuti,
// tiri e sostituzioni vengono ricostruiti sempre nello stesso modo, così
// animazione e tabellino non possono divergere.
export function ricostruisciEventiStorici(
  gol: EventoPartita[],
  stats: StatEventoStorico[],
  titolariCasa: number[],
  titolariOspite: number[],
  teamCasa: number,
  teamOspite: number,
  seed: number,
) {
  const rnd = creaRng(seed)
  const intervalloGioco = (teamId: number, giocatoreId: number) => {
    const stat = stats.find((riga) => riga.team_id === teamId && riga.player_instance_id === giocatoreId)
    const titolari = teamId === teamCasa ? titolariCasa : titolariOspite
    if (!stat || !titolari.length || stat.minuti <= 0) return null
    return titolari.includes(giocatoreId)
      ? { da: 1, a: stat.minuti }
      : { da: Math.max(1, 90 - stat.minuti), a: 90 }
  }
  const eventi: EventoPartita[] = gol.map((evento) => {
    if (!isEventoGol(evento)) return evento
    const intervallo = intervalloGioco(evento.team_id, evento.marcatore)
    if (!intervallo || (evento.minuto >= intervallo.da && evento.minuto <= intervallo.a)) return evento
    const minuto = evento.minuto < intervallo.da ? intervallo.da : intervallo.a
    return { ...evento, minuto, blocco: Math.ceil(minuto / 15) }
  })
  for (const [lato, teamId, titolari] of [['casa', teamCasa, titolariCasa], ['ospite', teamOspite, titolariOspite]] as const) {
    const righe = stats.filter((stat) => stat.team_id === teamId)
    if (!righe.length) continue
    const azioni: Array<{ tipo: 'tiro_parato' | 'tiro_fuori'; giocatore: number; minuti: number }> = []
    for (const stat of righe) {
      for (let i = 0; i < Math.max(0, stat.tiri_porta - stat.gol); i++) azioni.push({ tipo: 'tiro_parato', giocatore: stat.player_instance_id, minuti: stat.minuti })
      for (let i = 0; i < Math.max(0, stat.tiri - stat.tiri_porta); i++) azioni.push({ tipo: 'tiro_fuori', giocatore: stat.player_instance_id, minuti: stat.minuti })
    }
    for (const azione of azioni.sort(() => rnd() - .5).slice(0, 4)) {
      const eTitolare = titolari.includes(azione.giocatore)
      const minimo = eTitolare ? 1 : Math.max(1, 90 - azione.minuti)
      const massimo = eTitolare ? Math.max(minimo, azione.minuti) : 90
      const minuto = minimo + Math.floor(rnd() * (massimo - minimo + 1))
      eventi.push({ tipo: azione.tipo, minuto, blocco: Math.ceil(minuto / 15), lato, team_id: teamId, giocatore: azione.giocatore })
    }
    const subentratiGiaUsati = new Set<number>()
    for (const titolare of righe.filter((stat) => titolari.includes(stat.player_instance_id) && stat.minuti > 0 && stat.minuti < 90)) {
      const entra = righe.find((stat) => !titolari.includes(stat.player_instance_id)
        && !subentratiGiaUsati.has(stat.player_instance_id)
        && stat.minuti === 90 - titolare.minuti)
      if (entra) {
        subentratiGiaUsati.add(entra.player_instance_id)
        eventi.push({ tipo: 'sostituzione', minuto: titolare.minuti, blocco: Math.ceil(titolare.minuti / 15), lato, team_id: teamId, esce: titolare.player_instance_id, entra: entra.player_instance_id })
      }
    }
  }
  return eventi.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
}
