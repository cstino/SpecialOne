import '@supabase/functions-js/edge-runtime.d.ts'
import { withSupabase } from '@supabase/server'
import { ovrEfficace, schiera, simulaPartita } from '../../../engine/engine.js'
import { tiltTecnico, tiltRapido } from '../../../engine/tattiche.js'
import { CFG, MODULI, PESI_SLOT } from '../../../engine/config.js'
import { setSeed } from '../../../engine/random.js'
import { calciaRigori, portiereDaLineup, tiratoriDaLineup } from '../../../engine/rigori.js'
import { capitanoAutomatico, deltaMorale } from '../../../engine/morale.js'
import { deltaRuoli, sommaDelta } from '../../../engine/ruoli.js'
import { deltaCorsie } from '../../../engine/corsie.js'
import { deltaSquadra, deltaCoperturaLibero } from '../../../engine/squadra.js'
import { pagelle, migliorInCampo } from '../../../engine/pagelle.js'

// La chiave segreta del progetto, esposta con un nome non riservato: la
// piattaforma non inietta SUPABASE_SECRET_KEY e vieta di crearla a mano.
// Serve per due cose insieme, ed e' la stessa mappa: autenticare il cron
// (header `apikey`) e costruire il client amministrativo.
const CHIAVE_SEGRETA = Deno.env.get('CHIAVE_SEGRETA_PROGETTO') ?? ''

type JsonMap = Record<string, unknown>
type GolBlocco = { blocco: number; casa: number; ospite: number }
type Lato = 'casa' | 'ospite'
type EventoGol = { tipo: 'gol'; minuto: number; blocco: number; lato: Lato; team_id: number; marcatore: number; assist: number | null }
type EventoTiro = { tipo: 'tiro_parato' | 'tiro_fuori'; minuto: number; blocco: number; lato: Lato; team_id: number; giocatore: number }
type EventoSostituzione = { tipo: 'sostituzione'; minuto: number; blocco: number; lato: Lato; team_id: number; esce: number; entra: number }
type EventoInfortunio = { tipo: 'infortunio'; minuto: number; blocco: number; lato: Lato; team_id: number; esce: number; entra: number }
type EventoCartellino = { tipo: 'cartellino'; minuto: number; blocco: number; lato: Lato; team_id: number; giocatore: number; colore: 'giallo' | 'rosso_diretto' | 'doppio_giallo' }
type EventoPartita = EventoGol | EventoTiro | EventoSostituzione | EventoInfortunio | EventoCartellino
// Un cambio come lo restituisce il motore (blocco al cui termine avviene e
// sosta di gioco: 0 = intervallo o pausa prima dei supplementari) e come lo
// racconta la cronaca, col suo minuto.
type CambioMotore = { lato: Lato; blocco: number; esce: number; entra: number; motivo: 'stanchezza' | 'infortunio'; sosta: number; tardiva: boolean }
type CambioCronaca = CambioMotore & { minuto: number }
type CartellinoMotore = { lato: Lato; blocco: number; giocatore: number; tipo: 'giallo' | 'rosso_diretto' | 'doppio_giallo' }
type CartellinoCronaca = CartellinoMotore & { minuto: number }
// Da che minuto a che minuto ogni giocatore e' stato in campo, per lato.
type Finestre = Map<Lato, Map<number, { da: number; a: number }>>
type DbPlayer = { id: number; nome: string; posizioni: string[]; piede: string | null }
type Instance = { id: number; team_id: number; player_id: number; overall_corrente: number; eta_corrente: number; condizione: number; infortunato_fino_a: number; ammonizioni_stagione: number; squalificato_fino_a: number; posizioni_override: string[] | null; specializzazione_attiva: string | null; morale: number | null }
type EnginePlayer = { id: number; nome: string; posizioni: string[]; ovr: number; eta: number; stamina: number; finishing: number; short_passing: number; tackle: number; dribbling: number; condizione: number; infortunatoFinoA: number; squalificatoFinoA: number; tiltTecnico: number | null; tiltRapido: number | null; specialita: { rigori: number }; piede: string | null; piazzati: { battuta: number; testa: number; marcatura: number; punizione: number; presa: number }; specializzazione: string | null; morale: number; composure: number; attributi: Record<string, number> }
// moltiplicatoreInfortuni e' facoltativo: se assente l'engine usa 1 (nessun
// effetto), esattamente come nella suite di validazione.
type EngineRoster = { nome: string; giocatori: EnginePlayer[]; esperienzaModulo: Record<string, number>; esperienzaStile: Record<string, number>; moltiplicatoreInfortuni?: number; xpDisposizione?: Array<{ disposizione: string[]; partite: number }>; xpIndicazioni?: number; familiarita?: { disposizione: number; indicazioni: number } }
type DbLineup = { team_id: number; giornata?: number; modulo: string; disposizione?: string[] | null; ruoli?: (string | null)[] | null; compiti?: (string | null)[] | null; focus_corsia?: string | null; linea_difensiva?: string | null; ampiezza?: string | null; ruolo_portiere?: string | null; titolari: number[]; panchina: number[]; tribuna: number[]; stile_gioco: string; automatica: boolean; rigorista?: number | null; punizione_corta?: number | null; punizione_lunga?: number | null; angolo_dx?: number | null; angolo_sx?: number | null }
type EngineLineup = { modulo: string; slots: string[]; titolari: EnginePlayer[]; panchina: EnginePlayer[]; cambiFatti: number; incaricati: { rigorista: number | null; punizione_corta: number | null; punizione_lunga: number | null; angolo_dx: number | null; angolo_sx: number | null }; capitano: EnginePlayer | null; ruoli: (string | null)[] | null; compiti: (string | null)[] | null; tattica?: (g: EnginePlayer, slot: string) => number }
type Fixture = { id: number; season_id: number; league_id: number; giornata: number; home_team_id: number; away_team_id: number; stato: string; campo_neutro: boolean; bracket_tie_id: number | null; mano: number | null }

function requiredNumber(attributes: Record<string, number>, field: string, playerId: number) {
  const value = attributes[field]
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`Giocatore ${playerId}: attributo obbligatorio ${field} assente.`)
  }
  return value
}

// Gli attributi arrivano gia' calcolati dal database, da un'unica formula:
// catalogo + crescita insieme all'overall + piano di sviluppo (TRAINING).
// Vedi private.attributi_istanza e la migrazione 20260927010000.
//
// Prima questo file rifaceva la crescita per conto suo con le pendenze, e
// trattava attributi_override come un valore fisso da non far crescere: due
// copie della stessa regola, che con il piano di sviluppo sarebbero state tre.

// Media di piu' attributi, saltando quelli che mancano. Se non ce n'e' nemmeno
// uno torna 45: un valore basso ma non nullo, cosi' un dato incompleto non
// rende qualcuno imbattibile ne' inutile sui piazzati.
function media(attributi: Record<string, number>, campi: string[]): number {
  const presenti = campi.map((c) => attributi[c]).filter((v) => typeof v === 'number' && Number.isFinite(v))
  if (!presenti.length) return 45
  return Math.round(presenti.reduce((a, b) => a + b, 0) / presenti.length)
}

function adaptPlayer(instance: Instance, player: DbPlayer, attributi: Record<string, number> | undefined): EnginePlayer {
  if (!player || !player.nome || !Array.isArray(player.posizioni) || player.posizioni.length === 0) {
    throw new Error(`Giocatore ${instance.id}: dati anagrafici o posizioni mancanti.`)
  }
  for (const [field, value] of Object.entries({
    ovr: instance.overall_corrente,
    eta: instance.eta_corrente,
    condizione: instance.condizione,
    infortunatoFinoA: instance.infortunato_fino_a,
    squalificatoFinoA: instance.squalificato_fino_a,
  })) {
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`Giocatore ${instance.id}: campo ${field} assente.`)
  }
  if (!attributi) throw new Error(`Giocatore ${instance.id}: attributi correnti assenti.`)
  const attributo = (campo: string) => requiredNumber(attributi, campo, instance.id)
  // Il quadro completo serve ai profili tattici e ai piazzati, che devono poter
  // rispondere "non lo so" invece di far saltare la giornata: qui non si
  // pretende che un attributo ci sia.
  const quadroCompleto = attributi

  return {
    id: instance.id,
    nome: player.nome,
    // Un cambio di ruolo completato (Gestione risorse, TRAINING) sostituisce
    // integralmente il ruolo del catalogo condiviso per questa istanza:
    // vedi private.completa_cambi_ruolo() e player_instances.posizioni_override.
    posizioni: instance.posizioni_override ?? player.posizioni,
    ovr: instance.overall_corrente,
    eta: instance.eta_corrente,
    stamina: attributo('stamina'),
    finishing: attributo('finishing'),
    short_passing: attributo('short_passing'),
    tackle: attributo('standing_tackle'),
    dribbling: attributo('dribbling'),
    // Qui c'era anche 'gk', caricato come obbligatorio e mai letto da nessuno:
    // non dal motore, non dal frontend, non dal database. La forza del portiere
    // il motore la ricava da ovrEfficace come per tutti gli altri, cioe' dal
    // suo overall — un attributo separato sarebbe stato un doppio conteggio.
    // Toglierlo elimina anche un modo di far fallire la giornata di un'intera
    // lega: attributoEffettivo solleva se il campo manca, e un giocatore senza
    // 'gk' avrebbe interrotto la simulazione per un valore che nessuno usa.
    condizione: instance.condizione,
    infortunatoFinoA: instance.infortunato_fino_a,
    squalificatoFinoA: instance.squalificato_fino_a,
    // I due profili del sistema tattico (engine/tattiche.js). Sono DIFFERENZE
    // fra attributi, non attributi: e' cio' che li rende indipendenti
    // dall'overall e quindi leve tattiche vere invece di overall travestito.
    //
    // Valgono null quando gli attributi non bastano — i giocatori del vivaio
    // non ne hanno 8 su 10, i portieri hanno pace e physic a null — e in quel
    // caso il motore non applica nessun effetto tattico a quel giocatore.
    // Mai un errore: una giornata non deve saltare per un attributo assente.
    // I profili leggono il giocatore di ADESSO: catalogo piu' crescita piu'
    // specializzazione. Prima dell'allineamento con main leggevano il catalogo
    // e basta, quindi descrivevano il ragazzo appena importato.
    tiltTecnico: tiltTecnico(quadroCompleto),
    tiltRapido: tiltRapido(quadroCompleto),
    // Gli attributi da specialista. Per ora solo i rigori, perche' e' l'unico
    // gesto che il motore sa gia' simulare (engine/rigori.js, tie-break dei
    // playoff). Punizioni e angoli arriveranno insieme alla meccanica che li
    // usa: assegnarli adesso sarebbe solo un'etichetta senza effetto.
    // Il morale entra in partita da settembre 2026 (engine/morale.js). Vale
    // poco di proposito: FM-Arena misura +3,8 punti su 38 fra morale scarso e
    // molto buono, un quarto di quanto vale la condizione fisica.
    morale: instance.morale ?? 70,
    // La freddezza serve solo a scegliere e pesare il capitano: nei dati FC 26
    // non esiste un attributo di leadership, e questa e' l'approssimazione
    // piu' onesta che il catalogo offra.
    composure: quadroCompleto['mentality_composure'] ?? 60,
    specialita: { rigori: quadroCompleto['mentality_penalties'] ?? instance.overall_corrente },
    // Le valutazioni sui calci piazzati (engine/piazzati.js). Attributi
    // completamente diversi da quelli della manovra: e' il punto della cosa.
    // Una squadra modesta palla a terra puo' essere temibile sui corner.
    // Il piede decide se un angolo rientra o esce, e vale il 34% di gol da
    // corner in piu' quando la combinazione e' giusta. Vedi engine/piazzati.js.
    piede: player.piede,
    piazzati: {
      // chi batte: cross e traiettoria
      battuta: media(quadroCompleto, ['attacking_crossing', 'skill_curve']),
      // chi attacca il pallone: stacco, elevazione, fisico per liberarsi
      testa: media(quadroCompleto, ['attacking_heading_accuracy', 'power_jumping', 'power_strength']),
      // chi lo difende: marcatura e stacco
      marcatura: media(quadroCompleto, ['defending_marking_awareness', 'power_jumping']),
      // chi calcia le punizioni
      punizione: media(quadroCompleto, ['skill_fk_accuracy', 'power_long_shots']),
      // il portiere che esce sui cross
      presa: media(quadroCompleto, ['gk_positioning', 'gk_handling']),
    },
    // Serve al motore solo per i rigori: la specializzazione "para_rigori"
    // di un portiere vale punti di overall aggiuntivi dal dischetto.
    // Vedi engine/rigori.js, portiereDaLineup().
    specializzazione: instance.specializzazione_attiva ?? null,
    // L'idoneita' ai ruoli legge il profilo del giocatore (engine/ruoli.js).
    attributi: quadroCompleto,
  }
}

// ------------------------------------------------------------
//  LE DUE BARRE DI FAMILIARITA'
//
//  Specchio di private.avanza_familiarita in SQL: qui si LEGGE la barra con cui
//  la squadra scende in campo oggi, la' si fa AVANZARE dopo il fischio finale.
//  Le due formule devono restare uguali, altrimenti una squadra gioca con una
//  barra e se ne vede scrividere un'altra.
// ------------------------------------------------------------
function disposizioneDi(lineup: DbLineup): string[] {
  const d = lineup.disposizione
  if (d && d.length === 11) return d
  return [...((MODULI as Record<string, string[]>)[lineup.modulo] ?? [])]
}

const resaFamiliarita = (distanza: number) => Math.max(0, Math.min(1, 1 - 1.6 * Math.max(0, Math.min(1, distanza))))

function quoteFamiliarita(roster: EngineRoster, lineup: DbLineup): { disposizione: number; indicazioni: number } {
  const piena = CFG.FAM_PARTITE_PIENA
  const disp = disposizioneDi(lineup)
  const righe = roster.xpDisposizione ?? []
  // Lo schieramento esatto, se gia' giocato.
  const esatta = righe.find((r) => r.disposizione?.length === 11 && r.disposizione.every((s, i) => s === disp[i]))
  let quotaDisp: number
  if (esatta) {
    quotaDisp = Math.min(1, esatta.partite / piena)
  } else {
    // Mai giocato: eredita dal piu' simile, come fa la semina in SQL.
    quotaDisp = 0
    for (const r of righe) {
      if (!r.disposizione || r.disposizione.length !== 11) continue
      const uguali = r.disposizione.reduce((n, sl, i) => n + (sl === disp[i] ? 1 : 0), 0)
      const q = Math.min(1, r.partite / piena) * resaFamiliarita(1 - uguali / 11)
      if (q > quotaDisp) quotaDisp = q
    }
    // La semina in SQL arrotonda a partite intere: qui si fa lo stesso, se no
    // la partita si gioca con una barra e il database ne registra un'altra.
    quotaDisp = Math.min(1, Math.round(quotaDisp * piena) / piena)
  }
  return { disposizione: quotaDisp, indicazioni: Math.min(1, (roster.xpIndicazioni ?? 0) / piena) }
}

function buildLineup(lineup: DbLineup, roster: EngineRoster, capitanoId: number | null = null, tattiche = false): EngineLineup {
  const byId = new Map(roster.giocatori.map((player) => [player.id, player]))
  const slots = MODULI[lineup.modulo]
  if (!slots || slots.length !== 11 || lineup.titolari.length !== 11) throw new Error(`Formazione non valida per la squadra ${lineup.team_id}.`)
  // Un giocatore puo' sparire dalla rosa DOPO che la formazione e' stata
  // salvata: il mercato chiude alle 21:00 e la formazione salvata prima (o
  // ereditata dalla giornata precedente) resta li' con dentro un ceduto.
  //
  // Prima qui c'era un throw. Siccome l'errore risale fino al gestore esterno,
  // UNA sola formazione stantia avrebbe fatto fallire la giornata dell'intera
  // lega. Un ceduto va trattato come un indisponibile qualsiasi.
  const titolari = lineup.titolari.map((id) => byId.get(id))
  const riserveSalvate = lineup.panchina
    .map((id) => byId.get(id))
    .filter((giocatore): giocatore is EnginePlayer => Boolean(giocatore))

  // Stessa logica per gli infortunati e per gli squalificati: `schiera()`
  // scarta gli indisponibili, ma qui la formazione arriva dal database e il
  // motore non sa nulla di cartellini o squalifiche (e' un vincolo di
  // disponibilita', non un effetto di gioco), quindi senza questo blocco uno
  // squalificato scenderebbe in campo.
  const undici: Array<EnginePlayer | undefined> = titolari
  const rimpiazzi: Array<{ esce: string; entra: string }> = []
  for (let i = 0; i < undici.length; i++) {
    const attuale = undici[i]
    if (attuale && attuale.infortunatoFinoA <= 0 && attuale.squalificatoFinoA <= 0) continue
    const inCampo = new Set(undici.filter(Boolean).map((giocatore) => giocatore!.id))
    const candidati = [...riserveSalvate, ...roster.giocatori]
      .filter((giocatore) => giocatore.infortunatoFinoA <= 0 && giocatore.squalificatoFinoA <= 0 && !inCampo.has(giocatore.id))
    if (candidati.length === 0) continue
    let migliore = candidati[0]
    for (const candidato of candidati) {
      if (ovrEfficace(candidato, slots[i]) > ovrEfficace(migliore, slots[i])) migliore = candidato
    }
    rimpiazzi.push({ esce: attuale ? attuale.nome : 'giocatore non piu’ in rosa', entra: migliore.nome })
    undici[i] = migliore
  }
  // Restare senza undici e' l'unico caso che resta irrecuperabile: il motore
  // non sa giocare in dieci dal primo minuto.
  if (undici.some((giocatore) => !giocatore)) {
    throw new Error(`Rosa insufficiente per completare la formazione della squadra ${lineup.team_id}.`)
  }
  if (rimpiazzi.length) {
    console.log(`Squadra ${lineup.team_id}: rimpiazzati indisponibili`, rimpiazzi)
  }

  const formazione = undici as EnginePlayer[]
  const inCampo = new Set(formazione.map((giocatore) => giocatore.id))
  const panchina: EnginePlayer[] = []
  const inPanchina = new Set<number>()
  const aggiungiInPanchina = (giocatore: EnginePlayer) => {
    if (panchina.length >= 9 || giocatore.infortunatoFinoA > 0 || giocatore.squalificatoFinoA > 0 || inCampo.has(giocatore.id) || inPanchina.has(giocatore.id)) return
    panchina.push(giocatore)
    inPanchina.add(giocatore.id)
  }
  // Conserva le riserve sane scelte dall'allenatore e completa gli eventuali
  // buchi con i migliori giocatori disponibili della rosa.
  riserveSalvate.forEach(aggiungiInPanchina)
  const miglioriDisponibili = [...roster.giocatori].sort((a, b) => b.ovr - a.ovr)
  miglioriDisponibili.forEach(aggiungiInPanchina)

  // Chi batte piazzati e rigori, scelto dall'allenatore o assegnato in
  // automatico al salvataggio (private.sistema_incaricati). Il motore lo
  // rispetta finche' quel giocatore e' in campo, poi torna al migliore
  // rimasto — vedi engine/piazzati.js e engine/rigori.js.
  const incaricati = {
    rigorista: lineup.rigorista ?? null,
    punizione_corta: lineup.punizione_corta ?? null,
    punizione_lunga: lineup.punizione_lunga ?? null,
    angolo_dx: lineup.angolo_dx ?? null,
    angolo_sx: lineup.angolo_sx ?? null,
  }
  // La fascia. Se il capitano designato non e' in campo passa al migliore fra
  // chi gioca, esattamente come in Football Manager e come gia' succede per i
  // calci piazzati: un incarico non deve sparire perche' chi lo aveva e' in
  // tribuna.
  const capitanoScelto = tattiche && capitanoId ? formazione.find((g: EnginePlayer) => g.id === capitanoId) ?? null : null
  const capitano = tattiche ? (capitanoScelto ?? capitanoAutomatico(formazione)) : null
  // Ruoli e compiti per slot (engine/ruoli.js, engine/config.js). NULL finche'
  // l'interfaccia degli schemi personalizzati non li scrive: il motore in quel
  // caso non applica nessuno scarto.
  const ruoli = tattiche && lineup.ruoli && lineup.ruoli.length === 11 ? [...lineup.ruoli] : null
  const compiti = tattiche && lineup.compiti && lineup.compiti.length === 11 ? [...lineup.compiti] : null
  return { modulo: lineup.modulo, slots: [...slots], titolari: formazione, panchina, cambiFatti: 0, incaricati, capitano, ruoli, compiti }
}

function seedFor(fixture: Fixture) {
  const value = (BigInt(fixture.id) * 2654435761n + BigInt(fixture.season_id) * 1013904223n) % 4294967295n
  return Number(value || 1n)
}

function mapValue(map: Map<number, number> | undefined, id: number) {
  return map?.get(id) ?? 0
}

// ============================================================
//  DURATA DEGLI INFORTUNI
//
//  Il motore sorteggia 1-2, 3-6 oppure 8-15 giornate, tarato su una stagione
//  da 28 partite (la configurazione della validazione di Fase 0). In un
//  campionato da 14 giornate un 8-15 significa perdere il giocatore fino alla
//  fine: non e' una scelta tattica, e' una condanna.
//
//  Scaliamo la durata sulla lunghezza vera della stagione, con un tetto al 40%
//  delle giornate totali. Si tocca solo qui: le formule del motore restano
//  intatte, come impone CLAUDE.md §4.
// ============================================================

const GIORNATE_DI_TARATURA = 28

// Diffida: ogni 5 ammonizioni nella stagione scatta una squalifica automatica
// di 1 giornata (stesso regolamento del calcio vero, es. Serie A). Il conto
// si azzera qui quando scatta, e separatamente prima dei playoff/tabelloni
// di fine stagione (private.crea_tabelloni) — mai a meta' campionato.
const DIFFIDA_SOGLIA = 5

function scalaInfortunio(giornateOriginali: number, giornateTotali: number) {
  if (giornateOriginali <= 0 || giornateTotali <= 0) return giornateOriginali
  const scalato = Math.round(giornateOriginali * giornateTotali / GIORNATE_DI_TARATURA)
  const tetto = Math.max(1, Math.ceil(giornateTotali * 0.4))
  return Math.max(1, Math.min(scalato, tetto))
}

// ============================================================
//  MINUTI E ASSIST
//
//  Il motore decide i gol e i marcatori (chi segna, in totale); non modella
//  ne' il minuto esatto ne' l'ultimo passaggio. Minuto e assist sono quindi
//  un'attribuzione di presentazione, calcolata qui e non nell'engine: cosi'
//  il motore validato resta intatto e il suo stream RNG non viene consumato.
//  L'RNG e' lo stesso LCG di engine/random.js, ma con stato locale e seme
//  derivato da quello della partita: gli assist sono riproducibili quanto
//  il risultato.
//
//  Correzione del 4 agosto 2026 (segnalazione utente, lega reale): un
//  giocatore subentrato a partita in corso poteva risultare marcatore o
//  assistman di un gol caduto in un blocco precedente al suo ingresso —
//  il motore restituisce i marcatori come lista aggregata di fine partita,
//  senza legame col blocco, quindi l'abbinamento a un blocco specifico era
//  del tutto arbitrario. Ora l'engine espone anche `presenzePerBlocco` (chi
//  era davvero in campo in ciascun blocco) e l'abbinamento sceglie, fra i
//  marcatori rimasti, chi era presente in quel blocco. Il totale di gol e
//  assist per giocatore a fine partita resta identico a quello del motore:
//  cambia solo in quale blocco viene mostrato ciascuna occorrenza.
// ============================================================

const MINUTI_PER_BLOCCO = 15
// Con i supplementari (blocchi 7 e 8) la cronaca arriva a 120': prima il tetto
// era 90 e i gol dei supplementari finivano senza minuto, poi "riparati" dentro
// i tempi regolamentari.
const BLOCCO_MASSIMO = 8
const BLOCCHI_REGOLAMENTARI = 6
const MINUTO_MASSIMO = BLOCCO_MASSIMO * MINUTI_PER_BLOCCO
const QUOTA_GOL_SENZA_ASSIST = 0.28 // rigori, tiri da fuori, ribattute, azioni personali

// Propensione all'assist per slot. Non deriva da PESI_STAT.passaggi, che misura
// il volume di passaggi: userebbe i centrali difensivi come uomini assist.
const PESO_ASSIST: Record<string, number> = {
  GK: 0.02,
  CB: 0.15, LB: 0.75, RB: 0.75, LWB: 0.90, RWB: 0.90,
  CDM: 0.50, CM: 0.95, CAM: 1.60, LM: 1.20, RM: 1.20,
  LW: 1.70, RW: 1.70, ST: 1.00, CF: 1.10,
}

function creaRng(seme: number) {
  // `seed ^ costante` in JavaScript e' un intero a 32 bit CON segno: con un seme
  // negativo il generatore restituiva numeri negativi, e minuti e blocchi dei
  // tiri uscivano fuori dall'intervallo (tiri prima dell'ingresso del giocatore).
  let stato = seme >>> 0
  return () => {
    stato = (stato * 1664525 + 1013904223) % 4294967296
    return stato / 4294967296
  }
}

function scegliPesatoLocale<T>(items: T[], pesi: number[], rnd: () => number): T {
  const totale = pesi.reduce((somma, peso) => somma + peso, 0)
  if (totale <= 0) return items[Math.floor(rnd() * items.length)]
  let resto = rnd() * totale
  for (let i = 0; i < items.length; i++) {
    resto -= pesi[i]
    if (resto <= 0) return items[i]
  }
  return items[items.length - 1]
}

// Sceglie l'uomo assist fra i titolari presenti in campo in quel blocco,
// escluso il marcatore. Senza il filtro di presenza un giocatore subentrato
// solo dopo poteva risultare assistman di un gol segnato prima del suo ingresso.
function scegliAssist(lineup: EngineLineup, marcatore: number, presenti: number[], rnd: () => number): number | null {
  if (rnd() < QUOTA_GOL_SENZA_ASSIST) return null
  const candidati: number[] = []
  const pesi: number[] = []
  for (let i = 0; i < lineup.slots.length; i++) {
    const giocatore = lineup.titolari[i]
    if (!giocatore || giocatore.id === marcatore) continue
    if (!presenti.includes(giocatore.id)) continue
    candidati.push(giocatore.id)
    pesi.push((PESO_ASSIST[lineup.slots[i]] ?? 0.5) * (giocatore.short_passing / 100))
  }
  if (candidati.length === 0) return null
  return scegliPesatoLocale(candidati, pesi, rnd)
}

// Trasforma i gol per blocco in eventi cronologici con minuto, marcatore e assist.
function costruisciEventiGol(
  golPerBlocco: GolBlocco[],
  lati: Array<{ lato: 'casa' | 'ospite'; teamId: number; lineup: EngineLineup; marcatori: number[]; presenzePerBlocco: number[][] }>,
  seed: number,
): EventoGol[] {
  const rnd = creaRng(seed)
  const eventi: EventoGol[] = []

  for (const blocco of golPerBlocco) {
    for (const lato of lati) {
      const quanti = lato.lato === 'casa' ? blocco.casa : blocco.ospite
      for (let g = 0; g < quanti; g++) {
        const minutoBase = (blocco.blocco - 1) * MINUTI_PER_BLOCCO
        eventi.push({
          tipo: 'gol',
          minuto: minutoBase + 1 + Math.floor(rnd() * MINUTI_PER_BLOCCO),
          blocco: blocco.blocco,
          lato: lato.lato,
          team_id: lato.teamId,
          marcatore: 0,
          assist: null,
        })
      }
    }
  }

  eventi.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.blocco - destra.blocco)

  // I marcatori arrivano dal motore come lista per squadra, senza legame con il
  // blocco: il totale a fine partita e' gia' deciso dal motore (validato) e non
  // cambia qui. Scegliamo pero' CHI, fra i marcatori rimasti, viene assegnato a
  // QUESTO blocco preferendo chi era davvero in campo in quel momento — un
  // subentrato non puo' risultare marcatore di un gol segnato prima del suo
  // ingresso. Se per caso nessuno dei rimasti era presente in quel blocco
  // (evento raro), si ripiega sul primo rimasto pur di non perdere il gol: il
  // totale per giocatore a fine partita resta comunque quello del motore,
  // cambia solo in quale blocco viene mostrato.
  // Abbinamento marcatori-gol per tutta la partita insieme (matching
  // bipartito), non in ordine cronologico: con l'assegnazione "al primo
  // libero" i gol dei primi blocchi consumavano i marcatori che servivano
  // dopo, e un gol dei supplementari restava a chi era gia' uscito — poi
  // veniva spostato nei 90' e la cronaca contraddiceva il risultato.
  const marcatorePerEvento = new Map<EventoGol, number>()
  for (const lato of lati) {
    const golLato = eventi.filter((evento) => evento.lato === lato.lato)
    const pool = [...lato.marcatori]
    const presenteIn = (evento: EventoGol, id: number) => (lato.presenzePerBlocco[evento.blocco - 1] ?? []).includes(id)
    const golDiSlot: Array<number | null> = pool.map(() => null)
    const prova = (g: number, visti: Set<number>): boolean => {
      for (let j = 0; j < pool.length; j++) {
        if (visti.has(j) || !presenteIn(golLato[g], pool[j])) continue
        visti.add(j)
        const occupante = golDiSlot[j]
        if (occupante === null || prova(occupante, visti)) { golDiSlot[j] = g; return true }
      }
      return false
    }
    for (let g = 0; g < golLato.length; g++) prova(g, new Set())
    golDiSlot.forEach((g, j) => { if (g !== null) marcatorePerEvento.set(golLato[g], pool[j]) })
    // Gol senza nessun marcatore della lista in campo in quel blocco (il
    // motore sceglie i marcatori sull'intera partita, compresi i sostituiti):
    // lo segna un compagno presente, con gli stessi pesi del motore. Il
    // totale di squadra non cambia; il chiamante ricalcola i gol per
    // giocatore da questi eventi.
    for (const evento of golLato) {
      if (marcatorePerEvento.has(evento)) continue
      const presenti = lato.presenzePerBlocco[evento.blocco - 1] ?? []
      const candidati: number[] = []
      const pesi: number[] = []
      lato.lineup.slots.forEach((slot, i) => {
        const giocatore = lato.lineup.titolari[i]
        if (!giocatore || slot === 'GK' || !presenti.includes(giocatore.id)) return
        candidati.push(giocatore.id)
        pesi.push(((PESI_SLOT as Record<string, { ATT: number }>)[slot]?.ATT ?? 0.1) * Math.pow(giocatore.finishing / 100, 1.5) + 0.001)
      })
      const liberi = pool.filter((_, j) => golDiSlot[j] === null)
      const scelto = candidati.length ? scegliPesatoLocale(candidati, pesi, rnd) : liberi[0]
      if (scelto === undefined) continue
      marcatorePerEvento.set(evento, scelto)
      const slotLibero = pool.findIndex((_, j) => golDiSlot[j] === null)
      if (slotLibero >= 0) golDiSlot[slotLibero] = -1
    }
  }
  const minutiUsatiPerSquadra = new Map<number, Set<number>>()

  for (const evento of eventi) {
    const lato = lati.find((item) => item.lato === evento.lato)!
    const presenti = lato.presenzePerBlocco[evento.blocco - 1] ?? []
    const marcatore = marcatorePerEvento.get(evento)
    if (marcatore === undefined) continue
    evento.marcatore = marcatore
    evento.assist = scegliAssist(lato.lineup, marcatore, presenti, rnd)

    // Un gol non attraversa mai il 90': regolamentari (blocchi 1-6) e
    // supplementari (7-8) sono fasi distinte e il loro parziale e' gia'
    // deciso dal motore (gol_home_90/gol_away_90).
    const primoBloccoFase = evento.blocco <= BLOCCHI_REGOLAMENTARI ? 1 : BLOCCHI_REGOLAMENTARI + 1
    const ultimoBloccoFase = evento.blocco <= BLOCCHI_REGOLAMENTARI ? BLOCCHI_REGOLAMENTARI : BLOCCO_MASSIMO
    let inizio: number
    if (presenti.includes(marcatore)) {
      // Caso comune: il marcatore scelto era davvero presente in questo
      // blocco. `presenzePerBlocco` fotografa il cambio al confine del
      // blocco: un subentrato al 60' puo' quindi comparire gia' nel blocco
      // 46'-60'. Se pero' non c'era ancora nel blocco precedente (e' appena
      // subentrato), il gol non puo' essere raccontato dal suo primissimo
      // minuto: lo spostiamo al blocco successivo (61'-75'), corretto il 4
      // agosto 2026. Nell'ultimo blocco di una fase si resta nel blocco,
      // nella sua seconda meta'.
      // Che un subentrato non segni prima del suo ingresso lo garantisce
      // ora adattaAiMinutiInCampo, sul minuto vero del cambio (2 ottobre 2026).
      inizio = (evento.blocco - 1) * MINUTI_PER_BLOCCO + 1
    } else {
      // Nessun marcatore presente disponibile (raro dopo il matching): si
      // racconta il gol nel blocco piu' vicino in cui il marcatore era in
      // campo, ma sempre dentro la stessa fase; se nella fase non c'era mai,
      // il gol resta nel suo blocco.
      let distanzaMinima = Infinity
      let bloccoReale = evento.blocco
      for (let b = primoBloccoFase; b <= ultimoBloccoFase; b++) {
        if (!(lato.presenzePerBlocco[b - 1] ?? []).includes(marcatore)) continue
        const distanza = Math.abs(b - evento.blocco)
        if (distanza < distanzaMinima) { distanzaMinima = distanza; bloccoReale = b }
      }
      evento.blocco = bloccoReale
      inizio = (bloccoReale - 1) * MINUTI_PER_BLOCCO + 1
    }
    const fine = Math.min(evento.blocco <= BLOCCHI_REGOLAMENTARI ? BLOCCHI_REGOLAMENTARI * MINUTI_PER_BLOCCO : MINUTO_MASSIMO, Math.floor((inizio - 1) / MINUTI_PER_BLOCCO + 1) * MINUTI_PER_BLOCCO)
    let minutiUsati = minutiUsatiPerSquadra.get(evento.team_id)
    if (!minutiUsati) { minutiUsati = new Set<number>(); minutiUsatiPerSquadra.set(evento.team_id, minutiUsati) }
    let candidati = Array.from({ length: fine - inizio + 1 }, (_, indice) => inizio + indice)
      .filter((minuto) => !minutiUsati.has(minuto))
    if (!candidati.length) candidati = Array.from({ length: fine - inizio + 1 }, (_, indice) => inizio + indice)
    evento.minuto = candidati[Math.floor(rnd() * candidati.length)]
    minutiUsati.add(evento.minuto)
  }

  return eventi.filter((evento) => evento.marcatore !== 0)
    .sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.blocco - destra.blocco)
}

// Il motore restituisce statistiche individuali aggregate: qui le rendiamo
// coerenti con il totale di squadra senza cambiare alcun esito simulato. In
// particolare un marcatore ha sempre almeno un tiro e un tiro in porta per
// ogni gol: requisito necessario per poter raccontare azioni reali, non un
// evento inventato dalla UI.
function rendiTiriCoerenti(righe: Array<Record<string, number>>, teamStats: JsonMap) {
  const totaleTiri = Number(teamStats.tiri ?? 0)
  const totaleInPorta = Number(teamStats.inPorta ?? 0)
  const ordinaPerCapacita = (campo: 'tiri' | 'tiri_porta') => [...righe].sort((a, b) =>
    (b[campo] - b.gol) - (a[campo] - a.gol) || a.player_instance_id - b.player_instance_id)

  for (const riga of righe) {
    riga.tiri = Math.max(riga.tiri, riga.gol)
    riga.tiri_porta = Math.min(riga.tiri, Math.max(riga.tiri_porta, riga.gol))
  }
  let differenza = totaleTiri - righe.reduce((somma, riga) => somma + riga.tiri, 0)
  let indice = 0
  while (differenza > 0 && righe.length) { righe[indice++ % righe.length].tiri++; differenza-- }
  while (differenza < 0) {
    const candidata = ordinaPerCapacita('tiri')[0]
    if (!candidata || candidata.tiri <= candidata.gol) break
    candidata.tiri--; candidata.tiri_porta = Math.min(candidata.tiri_porta, candidata.tiri); differenza++
  }

  for (const riga of righe) riga.tiri_porta = Math.min(riga.tiri, Math.max(riga.gol, riga.tiri_porta))
  differenza = totaleInPorta - righe.reduce((somma, riga) => somma + riga.tiri_porta, 0)
  indice = 0
  while (differenza > 0) {
    const candidate = righe.filter((riga) => riga.tiri_porta < riga.tiri)
    if (!candidate.length) break
    candidate[indice++ % candidate.length].tiri_porta++; differenza--
  }
  while (differenza < 0) {
    const candidata = ordinaPerCapacita('tiri_porta')[0]
    if (!candidata || candidata.tiri_porta <= candidata.gol) break
    candidata.tiri_porta--; differenza++
  }
}

// Il minuto di ogni cambio. Il motore gioca a blocchi di 15' e cambia al
// confine di un blocco; la cronaca da' al cambio un minuto vero vicino a quel
// confine, cosi' i cambi non cadono piu' tutti al 45', 60' e 75'. Stessa sosta,
// stesso minuto. La coerenza con tiri e gol (chi esce non fa nulla dopo quel
// minuto, chi entra nulla prima) la garantisce adattaAiMinutiInCampo.
function minutiCambi(cambi: CambioMotore[], seed: number): CambioCronaca[] {
  const rnd = creaRng(seed ^ 0x5bd1e995)
  const out: CambioCronaca[] = []
  for (const lato of ['casa', 'ospite'] as Lato[]) {
    const gruppi = new Map<string, CambioMotore[]>()
    for (const cambio of cambi.filter((c) => c.lato === lato)) {
      const chiave = cambio.sosta === 0 ? `pausa-${cambio.blocco}` : `sosta-${cambio.sosta}`
      gruppi.set(chiave, [...(gruppi.get(chiave) ?? []), cambio])
    }
    // In ordine di tempo: nello stesso blocco l'infortunio avviene durante il
    // gioco, i cambi per stanchezza e l'intervallo alla sua fine.
    const momento = (c: CambioMotore) => c.motivo === 'infortunio' ? 0 : 1
    const ordinati = [...gruppi.values()].sort((a, b) => a[0].blocco - b[0].blocco || momento(a[0]) - momento(b[0]) || a[0].sosta - b[0].sosta)
    let ultimo = 0
    for (const gruppo of ordinati) {
      const { blocco, sosta, motivo, tardiva } = gruppo[0]
      const confine = blocco * MINUTI_PER_BLOCCO
      let minuto: number
      if (sosta === 0) {
        // Intervallo (46') o pausa prima dei supplementari (91').
        minuto = confine + 1
      } else {
        // Infortunio: dentro il blocco in cui succede. Cambio per stanchezza:
        // da poco prima a poco dopo il confine; l'ultimo di una finestra
        // divisa arriva verso la fine.
        let da = motivo === 'infortunio' ? confine - MINUTI_PER_BLOCCO + 2 : tardiva ? confine + 7 : confine - 4
        // L'infortunio resta ad almeno 2' dalla fine del blocco: chi entra puo'
        // ancora prendere un cartellino in quel blocco, dopo il suo ingresso.
        const a = motivo === 'infortunio' ? confine - 2 : tardiva ? confine + 14 : confine + 10
        da = Math.min(Math.max(da, ultimo + 3), a)
        minuto = da + Math.floor(rnd() * (a - da + 1))
      }
      ultimo = Math.max(ultimo, minuto)
      for (const cambio of gruppo) out.push({ ...cambio, minuto })
    }
  }
  return out
}

// Chi e' in campo e da quando: i titolari dal fischio d'inizio, i subentrati
// dal minuto del loro cambio, fino al cambio che li toglie o al fischio finale.
function finestreInCampo(lati: Array<{ lato: Lato; titolari: number[] }>, cambi: CambioCronaca[], fine: number): Finestre {
  const finestre: Finestre = new Map()
  for (const lato of lati) {
    const mappa = new Map<number, { da: number; a: number }>()
    for (const id of lato.titolari) mappa.set(id, { da: 0, a: fine })
    for (const cambio of cambi.filter((c) => c.lato === lato.lato).sort((a, b) => a.minuto - b.minuto)) {
      const esce = mappa.get(cambio.esce)
      if (esce) esce.a = Math.min(esce.a, cambio.minuto)
      mappa.set(cambio.entra, { da: cambio.minuto, a: fine })
    }
    finestre.set(lato.lato, mappa)
  }
  return finestre
}

// I cartellini cadevano tutti a fine blocco (15', 30', 45'...). Ora prendono un
// minuto nel loro blocco, dentro la finestra in campo del giocatore; un rosso
// chiude la finestra, il secondo giallo viene dopo il primo.
function minutiCartellini(cartellini: CartellinoMotore[], finestre: Finestre, seed: number): CartellinoCronaca[] {
  const rnd = creaRng(seed ^ 0x27d4eb2f)
  const ultimoPerGiocatore = new Map<number, number>()
  return cartellini.map((cartellino) => {
    const finestra = finestre.get(cartellino.lato)?.get(cartellino.giocatore)
    const inizioBlocco = (cartellino.blocco - 1) * MINUTI_PER_BLOCCO + 1
    let da = Math.max(inizioBlocco, (finestra?.da ?? 0) + 1, (ultimoPerGiocatore.get(cartellino.giocatore) ?? 0) + 1)
    const a = Math.min(cartellino.blocco * MINUTI_PER_BLOCCO, finestra?.a ?? MINUTO_MASSIMO)
    if (da > a) da = a
    const minuto = Math.max(1, da + Math.floor(rnd() * (a - da + 1)))
    ultimoPerGiocatore.set(cartellino.giocatore, minuto)
    if (finestra && cartellino.tipo !== 'giallo') finestra.a = minuto
    return { ...cartellino, minuto }
  })
}

// Rete di sicurezza sui minuti veri: ogni gol, assist, tiro e cartellino cade
// dentro il suo blocco E dentro la finestra in campo del protagonista (e
// dell'uomo assist). Se nel blocco non c'e' posto, si cerca nella stessa fase
// (regolamentari o supplementari): il parziale dei 90' non cambia mai.
function adattaAiMinutiInCampo(eventi: EventoPartita[], finestre: Finestre, rnd: () => number) {
  const intervallo = (evento: EventoPartita, bloccoDa: number, bloccoA: number) => {
    let da = (bloccoDa - 1) * MINUTI_PER_BLOCCO + 1
    let a = bloccoA * MINUTI_PER_BLOCCO
    const finestreLato = finestre.get(evento.lato)
    const protagonisti = evento.tipo === 'gol' ? [evento.marcatore, evento.assist]
      : evento.tipo === 'tiro_parato' || evento.tipo === 'tiro_fuori' ? [evento.giocatore] : []
    for (const id of protagonisti) {
      if (id === null) continue
      const finestra = finestreLato?.get(id)
      if (!finestra) continue
      // Chi entra al minuto m tira dal minuto dopo; chi esce al minuto m al
      // massimo in quel minuto.
      da = Math.max(da, finestra.da + 1)
      a = Math.min(a, finestra.a)
    }
    return { da, a }
  }
  for (const evento of eventi) {
    if (evento.tipo !== 'gol' && evento.tipo !== 'tiro_parato' && evento.tipo !== 'tiro_fuori') continue
    let { da, a } = intervallo(evento, evento.blocco, evento.blocco)
    if (evento.minuto >= da && evento.minuto <= a) continue
    if (da > a && evento.tipo === 'gol' && evento.assist !== null) {
      // Marcatore e uomo assist non sono mai stati in campo insieme in quel
      // blocco: il gol resta, senza assist.
      evento.assist = null
      ;({ da, a } = intervallo(evento, evento.blocco, evento.blocco))
    }
    if (da > a) {
      const regolamentare = evento.blocco <= BLOCCHI_REGOLAMENTARI
      ;({ da, a } = intervallo(evento, regolamentare ? 1 : BLOCCHI_REGOLAMENTARI + 1, regolamentare ? BLOCCHI_REGOLAMENTARI : BLOCCO_MASSIMO))
      if (da > a) continue
    }
    evento.minuto = da + Math.floor(rnd() * (a - da + 1))
  }
}

// Minuti giocati dai minuti veri dei cambi e dei rossi, non piu' a multipli
// di 15: servono al tabellino e alle pagelle.
function minutiGiocati(finestre: Map<number, { da: number; a: number }> | undefined, minuti: Map<number, number> | undefined) {
  if (!finestre || !minuti) return
  for (const id of minuti.keys()) {
    const finestra = finestre.get(id)
    if (finestra) minuti.set(id, Math.max(1, finestra.a - finestra.da))
  }
}

function costruisciEventiPartita(
  gol: EventoGol[],
  lati: Array<{ lato: Lato; teamId: number; presenzePerBlocco: number[][]; stats: Array<Record<string, number>> }>,
  cambi: CambioCronaca[],
  cartellini: CartellinoCronaca[],
  finestre: Finestre,
  seed: number,
): EventoPartita[] {
  const rnd = creaRng(seed ^ 0x9e3779b9)
  const eventi: EventoPartita[] = [...gol]

  for (const lato of lati) {
    const blocchiPerGiocatore = new Map<number, number[]>()
    for (let indice = 0; indice < lato.presenzePerBlocco.length; indice++) {
      for (const giocatore of lato.presenzePerBlocco[indice] ?? []) {
        blocchiPerGiocatore.set(giocatore, [...(blocchiPerGiocatore.get(giocatore) ?? []), indice + 1])
      }
    }
    for (const stat of lato.stats) {
      const id = stat.player_instance_id
      const blocchi = blocchiPerGiocatore.get(id) ?? []
      if (!blocchi.length) continue
      const parati = Math.max(0, stat.tiri_porta - stat.gol)
      const fuori = Math.max(0, stat.tiri - stat.tiri_porta)
      for (const tipo of ['tiro_parato', 'tiro_fuori'] as const) {
        const quanti = tipo === 'tiro_parato' ? parati : fuori
        for (let numero = 0; numero < quanti; numero++) {
          // `?? blocchi[0]` non e' difesa teorica: un blocco indefinito qui
          // produce un minuto NaN, e normalizzaCronaca ridistribuisce gli
          // eventi senza minuto valido in base alla loro POSIZIONE nell'array
          // — cioe' ignorando del tutto chi fosse in campo. E' cosi' che i
          // tiri finivano prima dell'ingresso di chi li aveva calciati.
          const blocco = blocchi[Math.floor(rnd() * blocchi.length)] ?? blocchi[0]
          eventi.push({
            tipo,
            minuto: (blocco - 1) * MINUTI_PER_BLOCCO + 1 + Math.floor(rnd() * MINUTI_PER_BLOCCO),
            blocco,
            lato: lato.lato,
            team_id: lato.teamId,
            giocatore: id,
          })
        }
      }
    }
  }
  // I cambi, compresi quelli per infortunio, arrivano dal motore col loro
  // minuto (minutiCambi): prima erano ricostruiti confrontando le presenze
  // di due blocchi, e cadevano tutti al confine.
  for (const cambio of cambi) {
    const lato = lati.find((item) => item.lato === cambio.lato)
    if (!lato) continue
    eventi.push({
      tipo: cambio.motivo === 'infortunio' ? 'infortunio' : 'sostituzione',
      minuto: Math.min(MINUTO_MASSIMO, cambio.minuto),
      blocco: Math.ceil(cambio.minuto / MINUTI_PER_BLOCCO),
      lato: cambio.lato,
      team_id: lato.teamId,
      esce: cambio.esce,
      entra: cambio.entra,
    })
  }
  for (const cartellino of cartellini) {
    const lato = lati.find((item) => item.lato === cartellino.lato)
    if (!lato) continue
    eventi.push({
      tipo: 'cartellino',
      minuto: Math.min(MINUTO_MASSIMO, cartellino.minuto),
      blocco: cartellino.blocco,
      lato: cartellino.lato,
      team_id: lato.teamId,
      giocatore: cartellino.giocatore,
      colore: cartellino.tipo,
    })
  }
  // Rete di sicurezza finale: nessun tiro e nessun gol puo' cadere fuori dai
  // blocchi in cui il giocatore era davvero in campo. I singoli passaggi qui
  // sopra gia' ci provano, ma bastava un blocco indefinito perche' l'evento
  // scivolasse nella ricostruzione per posizione di normalizzaCronaca e
  // ricomparisse a inizio partita. Qui l'invariante e' verificata una volta
  // sola, alla fine, su TUTTI gli eventi: se un evento e' fuori posto viene
  // spostato nel blocco valido piu' vicino, senza toccare ne' il totale dei
  // gol ne' quello dei tiri (cambia solo QUANDO vengono mostrati).
  const presenzePerLato = new Map<Lato, Map<number, number[]>>()
  for (const lato of lati) {
    const mappa = new Map<number, number[]>()
    for (let indice = 0; indice < lato.presenzePerBlocco.length; indice++) {
      for (const giocatore of lato.presenzePerBlocco[indice] ?? []) {
        mappa.set(giocatore, [...(mappa.get(giocatore) ?? []), indice + 1])
      }
    }
    presenzePerLato.set(lato.lato, mappa)
  }
  for (const evento of eventi) {
    const protagonista = evento.tipo === 'gol'
      ? evento.marcatore
      : evento.tipo === 'tiro_parato' || evento.tipo === 'tiro_fuori'
        ? evento.giocatore
        : null
    if (protagonista === null) continue
    // Solo blocchi della stessa fase: spostare un gol oltre il 90' cambierebbe
    // il parziale raccontato rispetto a quello deciso dal motore.
    const regolamentare = evento.blocco <= BLOCCHI_REGOLAMENTARI
    const blocchi = presenzePerLato.get(evento.lato)?.get(protagonista)
      ?.filter((blocco) => (blocco <= BLOCCHI_REGOLAMENTARI) === regolamentare)
    if (!blocchi?.length || blocchi.includes(evento.blocco)) continue
    let bloccoValido = blocchi[0]
    for (const blocco of blocchi) {
      if (Math.abs(blocco - evento.blocco) < Math.abs(bloccoValido - evento.blocco)) bloccoValido = blocco
    }
    evento.blocco = bloccoValido
    evento.minuto = (bloccoValido - 1) * MINUTI_PER_BLOCCO + 1 + Math.floor(rnd() * MINUTI_PER_BLOCCO)
  }
  // Poi i minuti veri: nessuno tira prima di entrare o dopo essere uscito.
  adattaAiMinutiInCampo(eventi, finestre, rnd)

  return eventi.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
}

// `blocchi` e' la fonte della cronaca animata. Un minuto nullo e' pericoloso
// anche se il tipo TypeScript dichiara il contrario: dopo la serializzazione
// JSON `null <= 2` vale true e il client mostrerebbe subito tutta la partita.
// Una cronaca incompleta non deve pero' mai bloccare risultato, classifica e
// condizione della rosa. Gli eventi anomali vengono quindi riparati qui,
// prima del salvataggio, e segnalati nei log per poter indagare la causa.
function normalizzaCronaca(eventi: EventoPartita[]) {
  const senzaMinutoPerBlocco = new Map<number, number[]>()
  const haMinutoValido = (evento: EventoPartita) => {
    const minuto = Number(evento.minuto)
    return Number.isInteger(minuto) && minuto >= 1 && minuto <= MINUTO_MASSIMO
  }

  eventi.forEach((evento, indice) => {
    if (haMinutoValido(evento)) return
    const bloccoLetto = Number(evento.blocco)
    const blocco = Number.isInteger(bloccoLetto) && bloccoLetto >= 1 && bloccoLetto <= BLOCCO_MASSIMO
      ? bloccoLetto
      : Math.min(6, Math.floor(indice * 6 / Math.max(1, eventi.length)) + 1)
    const indici = senzaMinutoPerBlocco.get(blocco) ?? []
    indici.push(indice)
    senzaMinutoPerBlocco.set(blocco, indici)
  })

  const minutiRicostruiti = new Map<number, { minuto: number; blocco: number }>()
  for (const [blocco, indici] of senzaMinutoPerBlocco) {
    indici.forEach((indice, posizione) => {
      minutiRicostruiti.set(indice, {
        blocco,
        minuto: (blocco - 1) * MINUTI_PER_BLOCCO + Math.ceil((posizione + 1) * MINUTI_PER_BLOCCO / (indici.length + 1)),
      })
    })
  }

  let corretti = 0
  const normalizzati = eventi.map((evento, indice) => {
    const ricostruito = minutiRicostruiti.get(indice)
    if (ricostruito) {
      corretti++
      return { ...evento, ...ricostruito }
    }
    const minuto = Number(evento.minuto)
    const blocco = Math.ceil(minuto / MINUTI_PER_BLOCCO)
    if (Number(evento.blocco) === blocco) return evento
    corretti++
    return { ...evento, minuto, blocco }
  })
  if (corretti) console.error(`Cronaca normalizzata: corretti ${corretti} eventi incompleti.`)
  return normalizzati.sort((sinistra, destra) => sinistra.minuto - destra.minuto || sinistra.team_id - destra.team_id)
}

function playerStats(teamId: number, stats: JsonMap, teamStats: JsonMap, assist: Map<number, number>) {
  const minuti = stats.minuti as Map<number, number>
  const tiri = stats.tiri as Map<number, number>
  const passaggi = stats.passaggi as Map<number, number>
  const contrasti = stats.contrasti as Map<number, number>
  const dribbling = stats.dribbling as Map<number, number>
  const marcatori = stats.marcatoriIds as number[]
  const goals = new Map<number, number>()
  for (const id of marcatori) goals.set(id, (goals.get(id) ?? 0) + 1)
  const shotsTotal = Number(teamStats.tiri ?? 0)
  const shotsOnTarget = Number(teamStats.inPorta ?? 0)
  const passPct = Number(teamStats.passaggiPct ?? 0)

  return [...minuti.entries()].map(([id, minutes]) => {
    const shots = mapValue(tiri, id)
    const passes = mapValue(passaggi, id)
    return {
      player_instance_id: id,
      team_id: teamId,
      minuti: Math.max(0, Math.min(90, minutes)),
      gol: goals.get(id) ?? 0,
      assist: assist.get(id) ?? 0,
      tiri: shots,
      tiri_porta: Math.min(shots, shotsTotal ? Math.round(shots * shotsOnTarget / shotsTotal) : 0),
      passaggi_tentati: passes,
      passaggi_riusciti: Math.min(passes, Math.round(passes * passPct)),
      contrasti_vinti: mapValue(contrasti, id),
      contrasti_persi: 0,
      dribbling: mapValue(dribbling, id),
    }
  })
}

export default {
  // Due chiamanti: l'amministratore dal browser (JWT utente) e il cron
  // notturno, che presenta la chiave segreta del progetto nell'header `apikey`.
  fetch: withSupabase({
    auth: ['user', 'secret'],
    env: { secretKeys: CHIAVE_SEGRETA ? { default: CHIAVE_SEGRETA } : {} },
  }, async (req, ctx) => {
    try {
      if (req.method !== 'POST') return Response.json({ error: 'Metodo non consentito.' }, { status: 405 })
      const body = await req.json().catch(() => ({})) as { league_id?: number; giornata?: number }
      const leagueId = Number(body.league_id)
      if (!Number.isInteger(leagueId) || leagueId < 1) return Response.json({ error: 'league_id non valido.' }, { status: 400 })

      // Lettura con il client amministrativo, come tutto il resto della
      // funzione: in modalita' segreta `ctx.supabase` porta la chiave del cron,
      // che PostgREST non riconosce. Il controllo sull'admin resta esplicito.
      const chiamataDiSistema = ctx.authMode === 'secret'
      const { data: league, error: leagueError } = await ctx.supabaseAdmin.from('leagues')
        .select('id, nome, admin_id, stato, giornate_totali, tattiche_attive').eq('id', leagueId).single()
      if (leagueError || !league) return Response.json({ error: 'Lega non trovata.' }, { status: 404 })
      if (!chiamataDiSistema && league.admin_id !== ctx.userClaims?.id) {
        return Response.json({ error: 'Solo l’amministratore può simulare una giornata.' }, { status: 403 })
      }
      if (league.stato !== 'stagione') return Response.json({ error: 'La stagione non è in corso.' }, { status: 409 })

      // L'interruttore del sistema tattico, per lega (20260917100000). Spento
      // di default: morale in campo, ruoli, compiti, schemi personalizzati e
      // capitano restano tutti fermi finche' l'amministratore non lo accende.
      const tatticheAttive = Boolean((league as { tattiche_attive?: boolean }).tattiche_attive)

      const { data: firstFixture, error: firstError } = await ctx.supabaseAdmin.from('fixtures')
        .select('giornata').eq('league_id', leagueId).eq('stato', 'programmata').order('giornata').limit(1).maybeSingle()
      if (firstError) throw firstError
      if (!firstFixture) return Response.json({ league_id: leagueId, completata: true, modo: ctx.authMode, partite: [] })
      if (body.giornata && body.giornata !== firstFixture.giornata) {
        return Response.json({ error: `La prossima giornata simulabile è la ${firstFixture.giornata}.` }, { status: 409 })
      }
      const giornata = firstFixture.giornata

      const { data: fixtureRows, error: fixturesError } = await ctx.supabaseAdmin.from('fixtures')
        .select('*').eq('league_id', leagueId).eq('giornata', giornata).eq('stato', 'programmata').order('id')
      if (fixturesError) throw fixturesError
      const fixtures = (fixtureRows ?? []) as Fixture[]
      const teamIds = [...new Set(fixtures.flatMap((fixture) => [fixture.home_team_id, fixture.away_team_id]))]

      // Ritorni di eliminatoria: serve il risultato dell'andata per sapere se
      // l'accoppiamento e' in parita' e quindi se giocare i supplementari
      // (design §10.7). Nell'andata i ruoli erano invertiti, quindi il
      // vantaggio di chi ORA gioca in casa e' gol_away meno gol_home.
      const scartoAndataPerFixture = new Map<number, number>()
      const tieDaControllare = fixtures.filter((f) => f.bracket_tie_id !== null && f.mano === 2)
      if (tieDaControllare.length > 0) {
        const { data: andate, error: andateError } = await ctx.supabaseAdmin.from('fixtures')
          .select('bracket_tie_id, matches(gol_home, gol_away)')
          .in('bracket_tie_id', tieDaControllare.map((f) => f.bracket_tie_id))
          .eq('mano', 1)
        if (andateError) throw andateError
        // matches.fixture_id e' UNIQUE, quindi PostgREST dovrebbe restituire un
        // oggetto; a seconda di come deduce la relazione puo' pero' tornare un
        // array. Accettiamo entrambe le forme: sbagliare qui significherebbe
        // giocare i supplementari quando non servono, o non giocarli affatto.
        type RigaAndata = { bracket_tie_id: number; matches: MatchGol | MatchGol[] | null }
        type MatchGol = { gol_home: number; gol_away: number }
        const perTie = new Map<number, MatchGol>()
        for (const riga of (andate ?? []) as RigaAndata[]) {
          const m = Array.isArray(riga.matches) ? riga.matches[0] : riga.matches
          if (m) perTie.set(riga.bracket_tie_id, m)
        }
        for (const f of tieDaControllare) {
          const andata = perTie.get(f.bracket_tie_id!)
          // Nessuna andata (finale in gara secca): si parte da zero.
          scartoAndataPerFixture.set(f.id, andata ? andata.gol_away - andata.gol_home : 0)
        }
      }

      const [teamsResult, instancesResult, lineupsResult, previousLineupsResult, xpResult, stileXpResult, indicazioniXpResult, medicoResult] = await Promise.all([
        ctx.supabaseAdmin.from('teams').select('id, nome, user_id, controllata_da_pc, capitano').eq('league_id', leagueId).in('id', teamIds),
        ctx.supabaseAdmin.from('player_instances').select('id, team_id, player_id, overall_corrente, eta_corrente, condizione, infortunato_fino_a, ammonizioni_stagione, squalificato_fino_a, posizioni_override, specializzazione_attiva, morale').eq('league_id', leagueId).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, modulo, titolari, panchina, tribuna, stile_gioco, automatica, rigorista, punizione_corta, punizione_lunga, angolo_dx, angolo_sx, disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere').eq('league_id', leagueId).eq('giornata', giornata).in('team_id', teamIds),
        ctx.supabaseAdmin.from('lineups').select('team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, rigorista, punizione_corta, punizione_lunga, angolo_dx, angolo_sx, disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere').eq('league_id', leagueId).lt('giornata', giornata).in('team_id', teamIds).order('automatica', { ascending: true }).order('giornata', { ascending: false }),
        ctx.supabaseAdmin.from('formation_xp').select('team_id, modulo, disposizione, partite_giocate').eq('league_id', leagueId).in('team_id', teamIds),
        ctx.supabaseAdmin.from('stile_xp').select('team_id, stile, partite_giocate').eq('league_id', leagueId).in('team_id', teamIds),
        ctx.supabaseAdmin.from('indicazioni_xp').select('team_id, partite_giocate').eq('league_id', leagueId).in('team_id', teamIds),
        // Reparto medico: moltiplicatore di resistenza agli infortuni per
        // squadra (1 = nessun effetto). Curva in private.effetti_ramo, letta
        // tramite l'unico varco pubblico (PostgREST non espone lo schema
        // private).
        ctx.supabaseAdmin.rpc('moltiplicatori_infortuni_squadre', { p_team_ids: teamIds }),
      ])
      const loadError = teamsResult.error ?? instancesResult.error ?? lineupsResult.error ?? previousLineupsResult.error ?? xpResult.error ?? stileXpResult.error ?? indicazioniXpResult.error ?? medicoResult.error
      if (loadError) throw loadError
      const moltiplicatoriInfortuni = new Map<number, number>((medicoResult.data ?? []).map((riga: { team_id: number; moltiplicatore: number }) => [riga.team_id, riga.moltiplicatore]))

      const instances = (instancesResult.data ?? []) as Instance[]
      const playerIds = [...new Set(instances.map((instance) => instance.player_id))]
      const { data: playersData, error: playersError } = await ctx.supabaseAdmin.from('players')
        .select('id, nome, posizioni, piede').in('id', playerIds)
      if (playersError) throw playersError
      const { data: attributiData, error: attributiError } = await ctx.supabaseAdmin
        .rpc('attributi_correnti', { p_instance_ids: instances.map((instance) => instance.id) })
      if (attributiError) throw attributiError
      const attributiCorrenti = new Map(((attributiData ?? []) as Array<{ instance_id: number; attributi: Record<string, number> }>)
        .map((riga) => [riga.instance_id, riga.attributi]))
      const catalog = new Map((playersData ?? []).map((player) => [player.id, player as DbPlayer]))
      const teamNames = new Map((teamsResult.data ?? []).map((team) => [team.id, team.nome]))
      const teamControllateDaPc = new Map((teamsResult.data ?? []).map((team) => [team.id, Boolean(team.controllata_da_pc)]))
      // Serve a sapere chi notificare: le notifiche sono per-persona, non
      // per-squadra, perche' la campanella e' una sola per tutte le leghe.
      const teamUsers = new Map((teamsResult.data ?? []).map((team) => [team.id, team.user_id as string]))
      // Chi porta la fascia, per squadra. Puo' essere null: finche' nessuno
      // sceglie un capitano il morale resta quello individuale e basta.
      const teamCapitani = new Map<number, number | null>((teamsResult.data ?? []).map((team: { id: number; capitano: number | null }) => [team.id, team.capitano ?? null]))
      const rosters = new Map<number, EngineRoster>()

      for (const teamId of teamIds) {
        const esperienzaModulo: Record<string, number> = {}
        for (const xp of xpResult.data ?? []) if (xp.team_id === teamId) esperienzaModulo[xp.modulo] = xp.partite_giocate
        const esperienzaStile: Record<string, number> = {}
        for (const xp of stileXpResult.data ?? []) if (xp.team_id === teamId) esperienzaStile[xp.stile] = xp.partite_giocate
        // Le DUE BARRE (vedi la migrazione 20260917010000). Si portano dietro i
        // dati grezzi: la quota vera dipende dallo schieramento che questa
        // squadra mette in campo oggi, e quello si sa solo con la formazione.
        const xpDisposizione = (xpResult.data ?? [])
          .filter((xp: { team_id: number }) => xp.team_id === teamId)
          .map((xp: { disposizione: string[]; partite_giocate: number }) => ({ disposizione: xp.disposizione, partite: xp.partite_giocate }))
        const xpIndicazioni = (indicazioniXpResult.data ?? [])
          .find((xp: { team_id: number }) => xp.team_id === teamId)?.partite_giocate ?? 0
        rosters.set(teamId, {
          nome: teamNames.get(teamId) ?? `Squadra ${teamId}`,
          giocatori: instances.filter((instance) => instance.team_id === teamId).map((instance) => adaptPlayer(instance, catalog.get(instance.player_id)!, attributiCorrenti.get(instance.id))),
          esperienzaModulo,
          esperienzaStile,
          xpDisposizione,
          xpIndicazioni,
          moltiplicatoreInfortuni: moltiplicatoriInfortuni.get(teamId),
        })
      }

      const lineups = new Map<number, DbLineup>((lineupsResult.data ?? []).map((lineup) => [lineup.team_id, lineup as DbLineup]))
      const inheritedLineups = new Map<number, DbLineup>()
      for (const lineup of previousLineupsResult.data ?? []) {
        if (!inheritedLineups.has(lineup.team_id)) inheritedLineups.set(lineup.team_id, lineup as DbLineup)
      }
      for (const teamId of teamIds) {
        if (lineups.has(teamId)) continue
        const roster = rosters.get(teamId)!
        // Il PC valuta ogni giornata la rosa aggiornata (condizione, infortuni e
        // arrivi del mercato) invece di ereditare una formazione ormai stantia.
        const inherited = teamControllateDaPc.get(teamId) ? undefined : inheritedLineups.get(teamId)
        let fallback: DbLineup
        if (inherited) {
          // La tattica e' l'identita' della squadra (registro, punto 27): chi
          // salta un salvataggio non perde schema, ruoli, compiti e indicazioni.
          // Prima si ereditavano solo modulo e giocatori.
          fallback = {
            team_id: teamId, modulo: inherited.modulo, titolari: inherited.titolari, panchina: inherited.panchina,
            tribuna: inherited.tribuna, stile_gioco: inherited.stile_gioco, automatica: true,
            disposizione: inherited.disposizione ?? null, ruoli: inherited.ruoli ?? null, compiti: inherited.compiti ?? null,
            focus_corsia: inherited.focus_corsia ?? null, linea_difensiva: inherited.linea_difensiva ?? null,
            ampiezza: inherited.ampiezza ?? null, ruolo_portiere: inherited.ruolo_portiere ?? null,
          }
        } else {
          // schiera() del motore scarta gia' da sola gli infortunati
          // (infortunatoFinoA), ma non sa nulla di squalifiche: buildLineup()
          // più avanti rimpiazzerebbe comunque un eventuale squalificato
          // scelto qui, ma solo nel suo slot specifico, senza poter
          // riottimizzare l'undici. Filtrando la rosa PRIMA di schiera() la
          // formazione automatica resta la migliore possibile fra i
          // davvero disponibili, non solo una toppa sopra un errore.
          const disponibiliPerAutomatica = { ...roster, giocatori: roster.giocatori.filter((player) => player.squalificatoFinoA <= 0) }
          const automatic = schiera(disponibiliPerAutomatica, '4-3-3')
          const starters = automatic.titolari.map((player: EnginePlayer) => player.id)
          const bench = automatic.panchina.map((player: EnginePlayer) => player.id)
          const tribuna = roster.giocatori.filter((player) => !starters.includes(player.id) && !bench.includes(player.id)).map((player) => player.id)
          fallback = { team_id: teamId, modulo: '4-3-3', titolari: starters, panchina: bench, tribuna, stile_gioco: 'equilibrato', automatica: true }
        }
        const { error: lineupError } = await ctx.supabaseAdmin.from('lineups').insert({ league_id: leagueId, giornata, ...fallback })
        if (lineupError) throw lineupError
        lineups.set(teamId, fallback)
      }

      // Fotografia prima delle partite: serve a distinguere un infortunio nuovo
      // da uno vecchio che il motore sta solo scalando di una giornata.
      const infortuniPrima = new Map<number, number>()
      for (const roster of rosters.values()) {
        for (const giocatore of roster.giocatori) {
          infortuniPrima.set(giocatore.id, giocatore.infortunatoFinoA)
        }
      }

      const summaries = []
      const cartelliniGiornata: Array<{ teamId: number; giocatore: number; colore: 'giallo' | 'rosso_diretto' | 'doppio_giallo' }> = []
      for (const fixture of fixtures) {
        const homeRoster = rosters.get(fixture.home_team_id)!
        const awayRoster = rosters.get(fixture.away_team_id)!
        const homeDbLineup = lineups.get(fixture.home_team_id)!
        const awayDbLineup = lineups.get(fixture.away_team_id)!
        const homeLineup = buildLineup(homeDbLineup, homeRoster, teamCapitani.get(fixture.home_team_id) ?? null, tatticheAttive)
        const awayLineup = buildLineup(awayDbLineup, awayRoster, teamCapitani.get(fixture.away_team_id) ?? null, tatticheAttive)
        // Gli scarti tattici si sommano su un canale solo (lineup.tattica).
        // Oggi c'e' il morale; ruoli e corsie si agganciano qui quando la
        // tattica arrivera' in produzione.
        // Il sistema tattico e' dietro un interruttore per lega, spento di
        // default (migrazione 20260917100000). Il morale in particolare si
        // applica a chiunque — ogni giocatore ne ha uno — quindi senza
        // interruttore un deploy lo accenderebbe ovunque, e non e' una
        // decisione da prendere con un deploy.
        if (tatticheAttive) {
          // Dove si attacca (engine/corsie.js) guarda la PROPRIA squadra: la
          // corsia dove si hanno i giocatori piu' forti. Le indicazioni di
          // squadra (engine/squadra.js) chiedono un profilo alla rosa: stile,
          // linea difensiva, ampiezza e portiere-libero. Registro, punti 27 e 30.
          const indicazioni = (l: DbLineup) => ({
            stile: l.stile_gioco, linea: l.linea_difensiva ?? 'media',
            ampiezza: l.ampiezza ?? 'normale', portiere: l.ruolo_portiere ?? 'normale',
          })
          const indCasa = indicazioni(homeDbLineup)
          const indOspite = indicazioni(awayDbLineup)
          homeLineup.tattica = sommaDelta(
            deltaMorale(homeLineup), deltaRuoli(homeLineup),
            deltaCorsie(homeLineup, homeDbLineup.focus_corsia ?? null),
            deltaSquadra(indCasa), deltaCoperturaLibero(homeLineup, indCasa))
          awayLineup.tattica = sommaDelta(
            deltaMorale(awayLineup), deltaRuoli(awayLineup),
            deltaCorsie(awayLineup, awayDbLineup.focus_corsia ?? null),
            deltaSquadra(indOspite), deltaCoperturaLibero(awayLineup, indOspite))
        }
        // Le due barre con cui si scende in campo oggi. Senza schemi
        // personalizzati coincidono con la vecchia familiarita' per modulo.
        homeRoster.familiarita = quoteFamiliarita(homeRoster, homeDbLineup)
        awayRoster.familiarita = quoteFamiliarita(awayRoster, awayDbLineup)
        // Fotografia dell'undici di partenza PRIMA del fischio d'inizio: le
        // sostituzioni dentro simulaPartita() mutano lineup.titolari in
        // posto (il subentrato prende il posto dell'uscito nello stesso
        // array), quindi leggerlo dopo la simulazione restituirebbe l'undici
        // di fine partita, non quello di inizio — esattamente lo scambio fra
        // titolari e subentrati segnalato nel tabellino.
        const titolariHomeIds = homeLineup.titolari.map((player: EnginePlayer) => player.id)
        const titolariAwayIds = awayLineup.titolari.map((player: EnginePlayer) => player.id)
        const seed = seedFor(fixture)
        setSeed(seed)
        // Supplementari solo nell'ultima mano di un'eliminatoria: nell'andata
        // si gioca sempre e solo 90 minuti.
        const decisiva = fixture.bracket_tie_id !== null && fixture.mano === 2
        const scartoAndata = scartoAndataPerFixture.get(fixture.id) ?? 0
        const result = simulaPartita(homeRoster, awayRoster, homeDbLineup.modulo, awayDbLineup.modulo, {
          usaCondizione: true,
          statsGiocatori: true,
          lineupCasa: homeLineup,
          lineupOspite: awayLineup,
          stileCasa: homeDbLineup.stile_gioco,
          stileOspite: awayDbLineup.stile_gioco,
          campoNeutro: fixture.campo_neutro,
          seedInfortuni: seed ^ 0x6d2b79f5,
          supplementariSeParita: decisiva,
          scartoAndata,
        })
        // Se l'aggregato resiste anche ai supplementari si va ai rigori. Le
        // lineup qui sono gia' quelle di fine partita: simulaPartita() le muta
        // in posto a ogni sostituzione, quindi tirano davvero gli undici
        // rimasti in campo, come vuole il design §10.7.
        const aiRigori = decisiva && scartoAndata + result.golC - result.golO === 0
        const rigori = aiRigori
          ? calciaRigori(
              { lato: 'casa', tiratori: tiratoriDaLineup(homeLineup), portiere: portiereDaLineup(homeLineup) },
              { lato: 'ospite', tiratori: tiratoriDaLineup(awayLineup), portiere: portiereDaLineup(awayLineup) },
            )
          : null
        const presenzePerBlocco = result.presenzePerBlocco as { casa: number[][]; ospite: number[][] }
        const eventi = costruisciEventiGol(result.golPerBlocco as GolBlocco[], [
          { lato: 'casa', teamId: fixture.home_team_id, lineup: homeLineup, marcatori: result.perGiocatore.casa.marcatoriIds as number[], presenzePerBlocco: presenzePerBlocco.casa },
          { lato: 'ospite', teamId: fixture.away_team_id, lineup: awayLineup, marcatori: result.perGiocatore.ospite.marcatoriIds as number[], presenzePerBlocco: presenzePerBlocco.ospite },
        ], seed)
        // Minuti veri dei cambi e dei cartellini, e chi e' in campo minuto per
        // minuto: i gol (e i loro assist) si adattano PRIMA di contare gli
        // assist, cosi' un assist tolto perche' l'uomo assist era gia' uscito
        // non resta nelle statistiche.
        const cambiCronaca = minutiCambi(result.cambiInPartita as CambioMotore[], seed)
        const finestre = finestreInCampo([
          { lato: 'casa', titolari: titolariHomeIds },
          { lato: 'ospite', titolari: titolariAwayIds },
        ], cambiCronaca, result.supplementari ? MINUTO_MASSIMO : BLOCCHI_REGOLAMENTARI * MINUTI_PER_BLOCCO)
        const cartelliniPartita = result.cartelliniInPartita as CartellinoMotore[]
        const cartelliniCronaca = minutiCartellini(cartelliniPartita, finestre, seed)
        adattaAiMinutiInCampo(eventi, finestre, creaRng(seed ^ 0x165667b1))
        eventi.sort((a, b) => a.minuto - b.minuto || a.blocco - b.blocco)
        minutiGiocati(finestre.get('casa'), result.perGiocatore?.casa.minuti as Map<number, number> | undefined)
        minutiGiocati(finestre.get('ospite'), result.perGiocatore?.ospite.minuti as Map<number, number> | undefined)
        // I gol per giocatore seguono la cronaca: costruisciEventiGol puo'
        // aver dato un gol a un compagno presente al posto di un marcatore
        // gia' sostituito.
        result.perGiocatore.casa.marcatoriIds = eventi.filter((evento) => evento.lato === 'casa').map((evento) => evento.marcatore)
        result.perGiocatore.ospite.marcatoriIds = eventi.filter((evento) => evento.lato === 'ospite').map((evento) => evento.marcatore)
        const assistPerGiocatore = new Map<number, number>()
        for (const evento of eventi) {
          if (evento.assist === null) continue
          assistPerGiocatore.set(evento.assist, (assistPerGiocatore.get(evento.assist) ?? 0) + 1)
        }

        const stats = [
          ...playerStats(fixture.home_team_id, result.perGiocatore.casa, result.statsCasa, assistPerGiocatore),
          ...playerStats(fixture.away_team_id, result.perGiocatore.ospite, result.statsOspite, assistPerGiocatore),
        ]
        rendiTiriCoerenti(stats.filter((stat) => stat.team_id === fixture.home_team_id), result.statsCasa)
        rendiTiriCoerenti(stats.filter((stat) => stat.team_id === fixture.away_team_id), result.statsOspite)
        const cronaca = normalizzaCronaca(costruisciEventiPartita(eventi, [
          { lato: 'casa', teamId: fixture.home_team_id, presenzePerBlocco: presenzePerBlocco.casa, stats: stats.filter((stat) => stat.team_id === fixture.home_team_id) },
          { lato: 'ospite', teamId: fixture.away_team_id, presenzePerBlocco: presenzePerBlocco.ospite, stats: stats.filter((stat) => stat.team_id === fixture.away_team_id) },
        ], cambiCronaca, cartelliniCronaca, finestre, seed))
        // Raccolti qui per la diffida (§ post-simulazione): serve sapere di
        // quale squadra e' ciascun cartellino, dato che il motore conosce
        // solo casa/ospite, non gli id reali.
        for (const cartellino of cartelliniPartita) {
          cartelliniGiornata.push({
            teamId: cartellino.lato === 'casa' ? fixture.home_team_id : fixture.away_team_id,
            giocatore: cartellino.giocatore,
            colore: cartellino.tipo,
          })
        }
        const { data: saved, error: saveError } = await ctx.supabaseAdmin.rpc('registra_risultato_partita', {
          p_fixture_id: fixture.id,
          p_seed: seed,
          p_modulo_home: homeDbLineup.modulo,
          p_modulo_away: awayDbLineup.modulo,
          p_stile_home: homeDbLineup.stile_gioco,
          p_stile_away: awayDbLineup.stile_gioco,
          p_gol_home: result.golC,
          p_gol_away: result.golO,
          p_blocchi: cronaca,
          p_stats_squadra: { home: result.statsCasa, away: result.statsOspite },
          p_player_stats: stats,
          // Chi e' sceso in campo davvero all'inizio, non chi era stato
          // scelto prima della partita: buildLineup() puo' aver gia'
          // rimpiazzato un titolare infortunato con un giocatore di
          // panchina. Presi PRIMA della simulazione (vedi sopra), non dopo:
          // dopo, l'array e' gia' stato mutato dalle sostituzioni.
          p_titolari_home: titolariHomeIds,
          p_titolari_away: titolariAwayIds,
          // Parziale dei 90' solo se i supplementari si sono davvero giocati:
          // altrimenti gol_home e' gia' il risultato dei regolamentari.
          p_gol_home_90: result.supplementari ? result.golRegolamentari.casa : null,
          p_gol_away_90: result.supplementari ? result.golRegolamentari.ospite : null,
          p_rigori_home: rigori ? rigori.golA : null,
          p_rigori_away: rigori ? rigori.golB : null,
          p_rigori_serie: rigori ? rigori.serie : null,
        })
        if (saveError) throw saveError
        summaries.push(saved)

        // Le pagelle (engine/pagelle.js, registro tattico punto 31): un voto
        // per chi ha giocato, dalle sue azioni riuscite e sbagliate. Seme suo,
        // quindi gol e risultato restano quelli appena registrati. Non bloccano
        // la giornata: se la scrittura fallisce, si registra l'errore e si va
        // avanti. Una partita gia' simulata non si rivota.
        if (saved && !saved.gia_simulata && saved.match_id) {
          try {
            const lato = (nome: Lato, roster: EngineRoster, lineup: EngineLineup, gf: number, gs: number) => ({
              giocatori: new Map(roster.giocatori.map((g) => [g.id, g])),
              lineup,
              stats: result.perGiocatore![nome],
              squadra: nome === 'casa' ? result.statsCasa : result.statsOspite,
              golFatti: gf, golSubiti: gs,
              assist: assistPerGiocatore,
              cartellini: cartelliniPartita.filter((c) => c.lato === nome).map((c) => ({ giocatore: c.giocatore, tipo: c.tipo })),
            })
            const voti = pagelle({
              casa: lato('casa', homeRoster, homeLineup, result.golC, result.golO),
              ospite: lato('ospite', awayRoster, awayLineup, result.golO, result.golC),
            }, (seed ^ 0x5eed1a6e) >>> 0)
            const migliore = migliorInCampo(voti)
            const righe = [...voti.entries()].map(([id, v]) => ({
              match_id: saved.match_id, league_id: leagueId,
              team_id: v.lato === 'ospite' ? fixture.away_team_id : fixture.home_team_id,
              player_instance_id: id, voto: v.voto, migliore_in_campo: id === migliore, dettaglio: v.dettaglio ?? null,
            }))
            const { error: pagelleError } = await ctx.supabaseAdmin.from('pagelle')
              .upsert(righe, { onConflict: 'match_id,player_instance_id', ignoreDuplicates: true })
            if (pagelleError) console.error(`Pagelle della partita ${saved.match_id} non salvate: ${pagelleError.message}`)
          } catch (errore) {
            console.error(`Pagelle della partita ${saved.match_id} non calcolate: ${errore instanceof Error ? errore.message : String(errore)}`)
          }
        }
      }

      // Condizione e infortuni tornano sul database: senza questo passaggio il
      // logoramento non si accumula, nessuno scende sotto la soglia di cambio e
      // le sostituzioni non scattano mai.
      const giornateTotali = Number(league.giornate_totali) || GIORNATE_DI_TARATURA
      const valoriCondizione = []
      const nuoviInfortuni: Array<{ teamId: number; playerId: number; nome: string; giornate: number }> = []
      for (const [teamId, roster] of rosters) {
        for (const giocatore of roster.giocatori) {
          const prima = infortuniPrima.get(giocatore.id) ?? 0
          const dopo = giocatore.infortunatoFinoA
          // Un valore cresciuto e' un infortunio nuovo, da riscalare sulla
          // lunghezza della stagione. Uno calato e' il conto alla rovescia.
          const giornateFuori = dopo > prima ? scalaInfortunio(dopo, giornateTotali) : dopo
          if (dopo > prima) {
            nuoviInfortuni.push({ teamId, playerId: giocatore.id, nome: giocatore.nome, giornate: Math.max(1, Math.round(giornateFuori)) })
          }

          // Nessuna amplificazione dell'usura: da quando il motore usa il
          // modello di fatica da partita, il consumo dentro i 90 minuti basta
          // da solo a far scattare i cambi in ogni giornata.
          valoriCondizione.push({
            id: giocatore.id,
            condizione: Math.round(Math.max(0, Math.min(100, giocatore.condizione))),
            infortunato_fino_a: Math.max(0, Math.round(giornateFuori)),
          })
        }
      }
      const { error: condizioneError } = await ctx.supabaseAdmin.rpc('aggiorna_condizione_rosa', {
        p_league_id: leagueId,
        p_valori: valoriCondizione,
      })
      if (condizioneError) throw condizioneError

      // Ammonizioni e squalifiche: chi ha giocato oggi sconta una giornata di
      // squalifica gia' in corso (come per gli infortuni, il conto alla
      // rovescia avanza a ogni giornata della SQUADRA, non solo per chi era
      // davvero in campo — non potrebbe esserlo, e' squalificato). Sopra
      // questo, applichiamo i cartellini di oggi: un giallo o un secondo
      // giallo aggiunge un'ammonizione stagionale; ogni 5 (DIFFIDA_SOGLIA)
      // scatta la diffida (si azzera il conto e si aggiunge una giornata di
      // squalifica); un rosso, diretto o da doppio giallo, aggiunge sempre
      // una giornata di squalifica per conto suo.
      // Riletti adesso, non presi da `instances`: registrando l'ultima partita
      // di stagione regolare private.crea_tabelloni azzera le ammonizioni, e
      // i valori letti a inizio giornata le riporterebbero in vita.
      const { data: cartelliniAttuali, error: cartelliniAttualiError } = await ctx.supabaseAdmin.from('player_instances')
        .select('id, ammonizioni_stagione, squalificato_fino_a').in('id', instances.map((instance) => instance.id))
      if (cartelliniAttualiError) throw cartelliniAttualiError
      type CartelliniAttuali = { id: number; ammonizioni_stagione: number; squalificato_fino_a: number }
      const instanceById = new Map(((cartelliniAttuali ?? []) as CartelliniAttuali[]).map((instance) => [instance.id, instance]))
      const valoriCartellini: Array<{ id: number; ammonizioni_stagione: number; squalificato_fino_a: number }> = []
      const nuoveSqualifiche: Array<{ teamId: number; playerId: number; nome: string; motivo: 'rosso_diretto' | 'doppio_giallo' | 'diffida' }> = []
      for (const [teamId, roster] of rosters) {
        for (const giocatore of roster.giocatori) {
          const instance = instanceById.get(giocatore.id)
          let ammonizioni = instance?.ammonizioni_stagione ?? 0
          let squalifica = Math.max(0, (instance?.squalificato_fino_a ?? 0) - 1)
          for (const cartellino of cartelliniGiornata) {
            if (cartellino.giocatore !== giocatore.id) continue
            let causa: 'rosso_diretto' | 'doppio_giallo' | 'diffida' | null = null
            if (cartellino.colore === 'giallo' || cartellino.colore === 'doppio_giallo') {
              ammonizioni++
              if (ammonizioni >= DIFFIDA_SOGLIA) { ammonizioni = 0; causa = 'diffida' }
            }
            if (cartellino.colore === 'rosso_diretto' || cartellino.colore === 'doppio_giallo') {
              causa = causa ?? cartellino.colore
            }
            if (causa) {
              squalifica = Math.max(squalifica, 1)
              nuoveSqualifiche.push({ teamId, playerId: giocatore.id, nome: giocatore.nome, motivo: causa })
            }
          }
          valoriCartellini.push({ id: giocatore.id, ammonizioni_stagione: ammonizioni, squalificato_fino_a: squalifica })
        }
      }
      const { error: cartelliniError } = await ctx.supabaseAdmin.rpc('aggiorna_cartellini_rosa', {
        p_league_id: leagueId,
        p_valori: valoriCartellini,
      })
      if (cartelliniError) throw cartelliniError

      // Aggiorna gli overall di tutte le rose. Gira a OGNI GIORNATA dal 10
      // settembre 2026 (migrazione 20260910120000): il campo "checkpoint" non
      // contiene piu' il numero del quarto ma quello della giornata, e la
      // formula annuale e' divisa per giornate_totali invece che per 4.
      // Questo commento diceva "ogni quarto" e ha ingannato chi e' venuto
      // dopo: i quattro meccanismi qui sotto NON hanno piu' tutti lo stesso
      // ritmo. La RPC e' idempotente e recupera un checkpoint rimasto in
      // sospeso dopo un eventuale ritentativo del cron.
      const { data: progressione, error: progressioneError } = await ctx.supabaseAdmin.rpc('applica_progressione_trimestrale', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (progressioneError) throw progressioneError

      // Il morale e' rimasto A QUARTI DI STAGIONE, a differenza della
      // progressione qui sopra: registro e funzione separati proprio per
      // questo, si e' potuto cambiare ritmo a una senza toccare l'altra.
      const { data: morale, error: moraleError } = await ctx.supabaseAdmin.rpc('applica_morale_checkpoint', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (moraleError) throw moraleError

      // Anche i punti abilita' da spendere sui rami vivaio/training/medico
      // restano a quarti di stagione. Registro e funzione separati dagli altri,
      // per la stessa ragione di sempre.
      const { error: puntiError } = await ctx.supabaseAdmin.rpc('assegna_punti_abilita', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (puntiError) throw puntiError

      // La crescita dei prospetti ancora in cantera: A OGNI GIORNATA come la
      // progressione, ed e' giusto che i due ritmi coincidano — sono la stessa
      // meccanica applicata a due tabelle diverse (vivaio_prospetti non e'
      // toccata dalla progressione qui sopra, che lavora su player_instances).
      const { error: vivaioCrescitaError } = await ctx.supabaseAdmin.rpc('cresci_vivaio_checkpoint', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (vivaioCrescitaError) throw vivaioCrescitaError

      // Il countdown di un prospetto vivaio: a ogni giornata, perche' scade in
      // giornate dal momento dell'acquisto e non a fine stagione.
      //
      // RIEPILOGO DEI RITMI, visto che non sono piu' uniformi:
      //   progressione overall   ogni giornata
      //   crescita vivaio        ogni giornata
      //   morale                 ogni quarto di stagione
      //   punti abilita'         ogni quarto di stagione
      //   countdown vivaio       ogni giornata
      //   guarigione svincolati  ogni giornata
      const { error: vivaioCountdownError } = await ctx.supabaseAdmin.rpc('decrementa_vivaio_giornate', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (vivaioCountdownError) throw vivaioCountdownError

      // L'infortunio di chi e' sul mercato scala come per chi e' in rosa. Il
      // recupero normale passa da aggiorna_condizione_rosa, che riceve solo i
      // giocatori DELLE SQUADRE CHE GIOCANO: uno svincolato non ci entra mai e
      // restava rotto per sempre. Registro e funzione separati dagli altri,
      // idempotente per (lega, giornata) come il countdown qui sopra.
      const { error: guarigioniError } = await ctx.supabaseAdmin.rpc('guarisci_svincolati', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (guarigioniError) throw guarigioniError

      // Lo stipendio e' una rata per giornata, non un addebito anticipato.
      // L'RPC e' idempotente: se il cron ritenta dopo un errore, ogni quota
      // gia' scritta nella tabella privata resta una sola volta.
      const { data: stipendiPagati, error: stipendiError } = await ctx.supabaseAdmin.rpc('addebita_ingaggi_giornata', {
        p_league_id: leagueId,
        p_giornata: giornata,
      })
      if (stipendiError) throw stipendiError

      // Notifiche: la giornata si gioca alle 00:00, quando tutti dormono.
      // Senza un avviso, il risultato lo si scopre solo riaprendo l'app.
      //
      // Un errore qui non deve far fallire la chiamata: la giornata e' gia'
      // scritta, e un 500 farebbe ritentare il cron su dati gia' registrati.
      let notificheInviate = 0
      try {
        const righe = []
        const squadreConPartitaNuova = new Set<number>()
        for (let i = 0; i < fixtures.length; i++) {
          const fixture = fixtures[i]
          const esito = summaries[i] as
            { match_id: number; gia_simulata: boolean; gol_home: number; gol_away: number } | null
          // Una partita gia' registrata e' un ritentativo: non si rinotifica.
          if (!esito || esito.gia_simulata) continue
          squadreConPartitaNuova.add(fixture.home_team_id)
          squadreConPartitaNuova.add(fixture.away_team_id)

          // Niente risultato nel testo: si spoilerebbe l'esito prima ancora
          // di aprire l'app. Il punteggio si scopre solo entrando.
          for (const teamId of [fixture.home_team_id, fixture.away_team_id]) {
            const userId = teamUsers.get(teamId)
            if (!userId) continue
            righe.push({
              user_id: userId,
              league_id: leagueId,
              tipo: 'giornata_simulata',
              titolo: `Giornata ${giornata} terminata`,
              corpo: 'Entra per controllare il risultato!',
              dati: { match_id: esito.match_id, giornata },
            })
          }
        }

        for (const infortunio of nuoviInfortuni) {
          if (!squadreConPartitaNuova.has(infortunio.teamId)) continue
          const userId = teamUsers.get(infortunio.teamId)
          if (!userId) continue
          righe.push({
            user_id: userId,
            league_id: leagueId,
            tipo: 'infortunio',
            titolo: `${infortunio.nome} si è infortunato`,
            corpo: `Sarà indisponibile per ${infortunio.giornate} ${infortunio.giornate === 1 ? 'giornata' : 'giornate'}. Controlla la formazione.`,
            dati: { view: 'squad', player_instance_id: infortunio.playerId, giornata },
          })
        }

        for (const squalifica of nuoveSqualifiche) {
          if (!squadreConPartitaNuova.has(squalifica.teamId)) continue
          const userId = teamUsers.get(squalifica.teamId)
          if (!userId) continue
          const motivo = squalifica.motivo === 'rosso_diretto' ? 'espulso con un cartellino rosso'
            : squalifica.motivo === 'doppio_giallo' ? 'espulso per doppia ammonizione'
            : `diffidato dopo ${DIFFIDA_SOGLIA} ammonizioni in stagione`
          righe.push({
            user_id: userId,
            league_id: leagueId,
            tipo: 'squalifica',
            titolo: `${squalifica.nome} salterà la prossima giornata`,
            corpo: `${motivo[0].toUpperCase()}${motivo.slice(1)}. Controlla la formazione.`,
            dati: { view: 'squad', player_instance_id: squalifica.playerId, giornata },
          })
        }

        if (righe.length) {
          const { error: notificheError } = await ctx.supabaseAdmin.from('notifications').insert(righe)
          if (notificheError) console.error('Notifiche non inviate:', notificheError)
          else notificheInviate = righe.length
        }
      } catch (errore) {
        console.error('Notifiche non inviate:', errore)
      }

      const { error: rinnoviPcError } = await ctx.supabaseAdmin.rpc('gestisci_rinnovi_squadre_pc', { p_league_id: leagueId })
      if (rinnoviPcError) console.error('Rinnovi squadre PC non eseguiti:', rinnoviPcError)

      return Response.json({ league_id: leagueId, giornata, modo: ctx.authMode, rose_aggiornate: valoriCondizione.length, stipendi_pagati: stipendiPagati, progressione, morale, notifiche: notificheInviate, partite: summaries })
    } catch (error) {
      console.error(error)
      return Response.json({ error: error instanceof Error ? error.message : 'Errore durante la simulazione.' }, { status: 500 })
    }
  }),
}
