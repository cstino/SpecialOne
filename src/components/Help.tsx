import { useState, type ReactNode } from 'react'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'

type Props = { membership: Membership; onNavigate: (view: GameView) => void }

type Argomento = { id: string; titolo: string; corpo: ReactNode }

// Contenuto volutamente neutro: nessuna cifra assoluta legata a una lega
// specifica (budget, numero di squadre, partite a stagione sono tutti
// scelti liberamente dall'admin). Solo percentuali e formule relative, che
// sono regole fisse del gioco — quelle si possono citare. Questo elenco
// serve sia dentro una lega (Help, sotto) sia dalla pagina principale prima
// di sceglierne una (MenuIniziale.tsx), dove non esiste ancora nessuna
// lega da cui leggere numeri concreti.
export const ARGOMENTI_AIUTO: Argomento[] = [
  {
    id: 'stagione',
    titolo: 'Come funziona una stagione',
    corpo: <>
      <p>Una lega vive in cicli. Si parte con il <strong>draft</strong>, dove ogni squadra si
        costruisce la rosa; poi si entra in <strong>stagione</strong>, dove ogni notte alle{' '}
        <strong>23:00</strong> (fuso orario Europe/Rome) il sistema simula <strong>una
        giornata</strong> di campionato, mai di più. Di giorno c'è sempre un mercato aperto per
        buona parte delle ore, in cui si scambiano giocatori e si fanno offerte sugli
        svincolati.</p>
      <p>A fine campionato la lega entra in <strong>off-season</strong>: 24 ore in cui entrano
        gli eventuali nuovi partecipanti, il mercato degli svincolati accelera ed esce
        definitivamente chi aveva annunciato il ritiro, prima che riparta la stagione
        successiva. I rinnovi non c'entrano: si trattano sempre a stagione in corso, mai in
        questa finestra — vedi la voce "Contratti e rinnovi".</p>
      <p>Tutti gli orari del gioco — deadline formazioni, chiusura mercato, simulazione — sono
        sempre nel fuso di Roma, indipendentemente da dove ti trovi.</p>
    </>,
  },
  {
    id: 'draft',
    titolo: 'Il draft',
    corpo: <>
      <p>Il draft si gioca a <strong>pacchetti</strong>. Ogni volta che apri un pacchetto,
        il sistema pesca <strong>4 carte</strong>, una per macro-ruolo (portiere, difensore,
        centrocampista, attaccante), da tutto il pool di giocatori disponibili — non da un
        singolo club. Tu ne scegli <strong>2</strong> e le ingaggi; le altre 2 restano nel pool,
        ripescabili in un pacchetto futuro o dalle aste a stagione iniziata.</p>
      <p>Se meno di 2 carte su 4 sono davvero ingaggiabili (per budget o per il vincolo di
        solvibilità qui sotto), quelle giocabili restano ferme e solo le altre vengono
        ripescate automaticamente, senza consumarti un reroll — così la sfortuna non ti blocca
        il draft. Puoi anche usare un <strong>reroll</strong> per sostituire tutto il pacchetto,
        comprese le carte che potresti prendere.</p>
      <p>Non c'è un ordine di turno: ogni squadra pesca per conto proprio, quando vuole.</p>
      <p>Il tetto ingaggi utilizzabile in draft lo sceglie liberamente <strong>l'admin</strong>{' '}
        quando crea la lega, con un unico vincolo: non può mai superare il budget iniziale
        assegnato a ogni squadra. Quello che resta fra il tetto draft e il budget iniziale
        rimane liquido per il mercato della prima stagione. Prima di ogni scelta il sistema
        controlla anche che la rosa resti completabile — se prendere quella carta ti
        lascerebbe senza abbastanza budget per riempire gli slot rimasti, la carta è visibile
        ma non selezionabile, con l'etichetta "non sostenibile".</p>
      <p>La rosa iniziale è fissa: <strong>24 giocatori</strong> (12 pacchetti da 2 carte).
        Un giocatore preso da una squadra sparisce dalle scelte di tutte le altre — resta
        visibile in grigio, con lo stemma di chi lo possiede.</p>
    </>,
  },
  {
    id: 'finanza-entrate',
    titolo: 'Finanza — da dove arrivano i soldi',
    corpo: <>
      <p>All'inizio della prima stagione ogni squadra riceve una <strong>dotazione
        iniziale</strong>, il cui importo lo decide l'admin quando crea la lega. È <strong>una
        tantum</strong>: non si ripete alle stagioni successive. Da lì in poi le entrate sono
        tre, tutte ricorrenti:</p>
      <ul>
        <li><strong>Sponsor</strong>: fisso, il 20% della dotazione iniziale, incassato a
          inizio di ogni stagione.</li>
        <li><strong>Premi partita</strong>: si incassano dopo ogni giornata, in base al
          risultato. Una vittoria vale il doppio di un pareggio, che vale il doppio di una
          sconfitta; tutti e tre sono proporzionati al numero di partite della tua lega, così
          l'economia regge qualsiasi formato (più partite ci sono, più piccolo è il singolo
          premio, in modo che il totale a fine stagione resti equilibrato).</li>
        <li><strong>Premio posizione</strong>: si incassa una sola volta, a fine stagione, in
          base al piazzamento finale in classifica. È volutamente molto sbilanciato verso i
          primi posti — il primo guadagna diverse decine di volte più dell'ultimo — per rendere
          ogni piazzamento importante fino all'ultima giornata.</li>
      </ul>
      <p>I trasferimenti fra squadre non creano né distruggono denaro: quello che una squadra
        paga, l'altra lo incassa.</p>
    </>,
  },
  {
    id: 'finanza-ingaggi',
    titolo: 'Finanza — ingaggi e insolvenza',
    corpo: <>
      <p>L'ingaggio annuale di un giocatore dipende dal suo overall e dalla sua età: più forte
        è, più costa; un giovane già forte costa <strong>di più</strong> di un adulto di pari
        livello, perché sta pagando anche il suo potenziale futuro, non solo quello che rende
        oggi. Un veterano oltre i 30 anni costa invece progressivamente meno, verso fine
        carriera.</p>
      <p>Il monte ingaggi dell'intera rosa viene addebitato <strong>per intero a inizio di ogni
        stagione</strong>. Comprare un giocatore a stagione in corso costa il prezzo del
        trasferimento più l'ingaggio calcolato solo sulle giornate rimanenti, non su tutto
        l'anno. Svincolare un giocatore non dà mai nessun rimborso, ma se ha ancora stagioni di
        contratto oltre a quella in corso, per liberarlo devi pagargli una
        <strong> buonuscita</strong>: metà (arrotondata per difetto) dell'ingaggio che gli
        restava da percepire nelle stagioni residue. Se è l'ultima stagione di contratto, o il
        giocatore ha già annunciato il ritiro, lo svincolo resta gratuito.</p>
      <p>Il budget non può mai andare sotto zero. Se a inizio stagione il monte ingaggi della
        tua rosa non è copribile con quello che hai, il sistema svincola automaticamente i
        giocatori partendo da quello con l'ingaggio più alto, finché il conto non torna in
        pari — in modo pubblico, notificato a tutta la lega. Vendere in tempo, prima che
        scatti da sola, è una delle decisioni più importanti dell'off-season.</p>
      <p>Chi accumula un monte ingaggi molto alto (sopra l'85% della dotazione iniziale) paga
        anche una <strong>tassa progressiva</strong> a inizio stagione: più il monte supera
        quella soglia, più cresce il sovrapprezzo. Serve a rallentare la squadra che si
        accaparra tutti i campioni, senza vietarle nulla.</p>
    </>,
  },
  {
    id: 'overall-progressione',
    titolo: 'Overall e progressione',
    corpo: <>
      <p>Ogni giocatore ha un overall attuale e un <strong>potenziale</strong>: il tetto massimo
        a cui può arrivare. L'overall si aggiorna quattro volte a stagione (al 25%, 50%, 75% e
        100% delle giornate), non solo a fine anno.</p>
      <p>Sotto i 27 anni l'overall tende a salire verso il potenziale, più velocemente quanto
        più è giovane. Fra 27 e 31 anni oscilla poco, in entrambe le direzioni. Da 32 anni in
        su comincia a scendere, e il calo si fa più marcato dopo i 35. L'overall non supera mai
        il potenziale, ma il potenziale stesso può muoversi di un punto in più o in meno per i
        più giovani (i cosiddetti "breakout" o mancate esplosioni).</p>
      <p>Per lo stesso motivo un giovane già forte <strong>costa di più</strong> in ingaggio di
        un adulto con lo stesso overall attuale: sta pagando anche la crescita futura che gli
        altri devono ancora vedere.</p>
      <p>Il <strong>minutaggio conta</strong>: chi gioca di più cresce (o, da veterano, cala)
        più in fretta di chi resta spesso in panchina — fino a quasi il doppio di velocità fra
        chi non scende mai in campo e chi gioca sempre. Schierare un giovane meno forte al
        posto di un anziano più forte non è quindi solo una scommessa sul presente: è anche un
        investimento reale sulla sua crescita.</p>
      <p>Dai 34 anni in su comincia anche a esserci una probabilità di <strong>ritiro</strong>,
        crescente con l'età — vedi la voce dedicata più sotto.</p>
    </>,
  },
  {
    id: 'posizione-campo',
    titolo: 'Posizione in campo',
    corpo: <>
      <p>Ogni giocatore ha un overall "di scheda", ma quello che conta davvero in partita è il
        suo <strong>overall efficace</strong>, che dipende anche da dove lo schieri:</p>
      <table className="help-table">
        <thead><tr><th>Dove lo schieri</th><th>Effetto sull'overall</th></tr></thead>
        <tbody>
          <tr><td>Nel suo ruolo naturale</td><td>Nessuna penalità</td></tr>
          <tr><td>In un ruolo secondario che sa giocare</td><td>Penalità minima</td></tr>
          <tr><td>Fuori ruolo, ma nello stesso reparto</td><td>Penalità sensibile</td></tr>
          <tr><td>In un reparto adiacente (es. difensore a centrocampo)</td><td>Penalità forte</td></tr>
          <tr><td>Nel reparto opposto (es. difensore in attacco)</td><td>Penalità severissima</td></tr>
          <tr><td>Un portiere fuori porta, o un giocatore di movimento in porta</td><td>Overall quasi azzerato</td></tr>
        </tbody>
      </table>
      <p>Per questo conviene sempre schierare un giocatore dove sa davvero giocare, anche se sulla
        carta il suo overall assoluto sembra più alto altrove.</p>
      <p>C'è anche una <strong>familiarità col modulo</strong>: la prima volta che usi un modulo
        nuovo, tutta la squadra perde punti di overall su attacco e centrocampo, e quel malus si
        riduce partita dopo partita fino a sparire dopo un certo numero di gare con lo stesso
        modulo. Cambiare modulo spesso ha quindi un costo reale, non solo estetico.</p>
      <p>Nella pagina Formazione, il cerchio sotto il bottone "Salva" mostra l'overall medio
        reale degli undici titolari nello slot in cui li hai messi — non l'overall "di scheda":
        se qualcuno è fuori ruolo, quel giocatore pesa meno nella media, esattamente come pesa
        meno nella partita vera.</p>
    </>,
  },
  {
    id: 'tattiche',
    titolo: 'Moduli e stile di gioco',
    corpo: <>
      <p>Ci sono due leve tattiche, <strong>indipendenti</strong> fra loro, da scegliere insieme
        prima di ogni giornata: il <strong>modulo</strong> e lo <strong>stile di gioco</strong>.</p>
      <p>Il <strong>modulo</strong> (4-4-2, 4-3-3, 4-3-3 offensivo, 4-3-3 difensivo, 4-2-3-1,
        3-5-2, 3-4-3, 5-3-2, 4-2-4) decide
        quanti giocatori mandi in ciascun reparto e con che ruoli. Non esiste un modulo
        oggettivamente più forte: ognuno sposta un po' di equilibrio fra attacco, centrocampo e
        difesa, e chi ha più giocatori orientati all'attacco spinge di più ma si scopre
        dietro, e viceversa.</p>
      <p>Lo <strong>stile di gioco</strong> (equilibrato, contropiede, possesso palla, gioco
        sulle fasce, recupero veloce, gioco diretto, difesa a oltranza) sposta ulteriormente
        l'enfasi fra le tre linee, a prescindere dal modulo scelto. Nessuno stile è un vantaggio
        netto: è sempre uno spostamento — chi si chiude di più concede meno gol ma ne segna
        anche meno, chi attacca di più fa l'opposto. "Equilibrato" è il default e non sposta
        nulla.</p>
      <p>In casa la squadra ha anche un piccolo vantaggio fisso su attacco e centrocampo — il
        classico fattore campo. Unica eccezione: se il tuo campionato ha un numero
        <strong> dispari</strong> di gironi, l'ultimo si gioca sempre a <strong>campo
        neutro</strong> (nessun vantaggio per nessuna delle due squadre) — altrimenti chi era
        in casa nel primo girone lo sarebbe di nuovo nell'ultimo, con una partita in casa in
        più della sua avversaria in quello scontro diretto. Le partite coinvolte hanno
        l'etichetta "Campo neutro" al posto degli orari/del risultato orientato.</p>
    </>,
  },
  {
    id: 'schieramento',
    titolo: 'Come si schiera la squadra',
    corpo: <>
      <p>Prima di ogni giornata scegli modulo, stile e i tuoi <strong>undici titolari</strong>,
        più la panchina; chi resta fuori va in tribuna. La deadline è le <strong>23:00 Europe/
        Rome</strong>, lo stesso orario in cui parte la simulazione della giornata.</p>
      <p>Se non salvi una formazione in tempo, il sistema ne genera una automatica: riusa
        l'ultimo modulo che avevi usato (o il 4-3-3 se è la prima volta) e schiera gli undici
        che massimizzano l'overall efficace complessivo, garantendo almeno un portiere in
        panchina se ne hai uno disponibile. Meglio comunque schierare sempre di persona: la
        formazione automatica non conosce le tue preferenze tattiche.</p>
      <p>La panchina arriva fino a <strong>9</strong> giocatori, la tribuna fino al resto della
        rosa massima (10, con una rosa al tetto di 30). Se un posto è libero lo vedi come un
        riquadro vuoto: seleziona un giocatore e tocca lo slot libero per spostarcelo, senza
        doverlo per forza scambiare con qualcun altro.</p>
    </>,
  },
  {
    id: 'simulazione',
    titolo: 'Come vengono decise le partite',
    corpo: <>
      <p>Ogni notte il motore di simulazione gioca la partita minuto per minuto, a blocchi di
        gioco: calcola la forza effettiva delle due squadre in attacco, centrocampo e difesa
        (tenendo conto di overall, ruoli, modulo, stile, condizione fisica e fattore campo),
        e da lì decide occasioni, gol, tiri, passaggi e le altre statistiche che vedi nel
        tabellino.</p>
      <p>Non è un semplice confronto di overall medio: un modulo più offensivo spinge di più
        ma concede di più, uno stile difensivo chiude gli spazi ma segna meno. Il risultato
        non è mai scontato solo perché una squadra è "più forte" sulla carta — la partita
        specifica, la condizione dei giocatori in quel momento e un po' di variabilità
        contano sempre.</p>
      <p>Le formule esatte del motore sono state validate su migliaia di partite simulate
        prima del lancio del gioco, per restare realistiche, e non cambiano da una lega
        all'altra.</p>
    </>,
  },
  {
    id: 'condizione-infortuni',
    titolo: 'Condizione e infortuni',
    corpo: <>
      <p>Ogni giocatore ha una <strong>condizione fisica</strong> che scende quando gioca e
        risale quando riposa. Chi resta fuori dai convocati recupera più di chi va in panchina
        senza entrare, che a sua volta recupera più di chi gioca. Una condizione bassa riduce
        l'overall efficace in campo, quindi ruotare la rosa non è solo una scelta di gestione:
        è anche una scelta di prestazione.</p>
      <p>Ogni partita giocata comporta anche un piccolo rischio di <strong>infortunio</strong>,
        più alto quanto più bassa è la condizione del giocatore e quanto più è avanti con
        l'età (i giocatori sopra i 34 anni si infortunano più spesso). La maggior parte degli
        infortuni dura poche giornate, ma una minoranza può tenere fuori un giocatore per
        diverse settimane. Al rientro il giocatore riparte con una condizione ridotta e un
        piccolo malus temporaneo sull'overall per un paio di giornate, prima di tornare al
        100%.</p>
    </>,
  },
  {
    id: 'mercato-scambi',
    titolo: 'Mercato — scambi tra squadre',
    corpo: <>
      <p>In qualsiasi momento in cui il mercato è aperto puoi proporre a un'altra squadra un
        <strong> acquisto secco</strong> (soldi per un giocatore), uno <strong>scambio</strong>{' '}
        (giocatore per giocatore) o uno <strong>scambio con conguaglio</strong> (giocatore più
        soldi per un altro giocatore). Chi riceve la proposta può accettarla o rifiutarla; se
        non risponde entro la chiusura del mercato del giorno, la proposta scade da sola.</p>
      <p>Il sistema controlla sempre che chi compra abbia davvero il budget per coprire il
        costo e l'ingaggio residuo del giocatore, e che entrambe le rose restino fra 21 e 30
        giocatori dopo l'operazione.</p>
      <p>Tutte le trattative concluse sono visibili a <strong>tutta la lega</strong>, con
        giocatori scambiati e cifre: è una scelta deliberata, per scoraggiare accordi
        sottobanco fra amici.</p>
    </>,
  },
  {
    id: 'mercato-asta',
    titolo: 'Mercato — asta a busta chiusa sugli svincolati',
    corpo: <>
      <p>Ogni giorno, quando il mercato riapre, il sistema estrae automaticamente 12 nuovi
        giocatori svincolati (3 per ciascun macro-ruolo). Restano in evidenza per un giorno; se
        nessuno li prende, restano comunque nell'archivio e possono ricevere offerte nei giorni
        successivi.</p>
      <p>Puoi fare <strong>una sola offerta per giocatore</strong>, indicando l'ingaggio annuale
        che sei disposto a pagargli. L'interfaccia mostra un "ingaggio minimo" di riferimento,
        ma non è una garanzia: la soglia vera che il giocatore accetta è nascosta e può essere
        più alta. Offerte sotto soglia vengono scartate. Puoi modificare o ritirare la tua
        offerta finché l'asta è aperta — dalla card "Le mie proposte" nella pagina Mercato — ma
        modificarla ti fa perdere la precedenza in caso di parità con un'altra offerta identica.</p>
      <p>Offrire impegna subito budget e uno slot di rosa: puoi offrire su tutti i giocatori che
        vuoi, ma solo per l'importo totale che puoi davvero permetterti. Alla chiusura del
        mercato vince l'offerta più alta sopra soglia per ciascun giocatore, e tutte le offerte
        vincenti (chi ha preso chi, e per quanto) vengono rivelate a tutta la lega. Le offerte
        perdenti restano private.</p>
    </>,
  },
  {
    id: 'mercato-vetrina',
    titolo: 'Mercato — vetrina della lega',
    corpo: <>
      <p>Dalla scheda di un tuo giocatore puoi metterlo <strong>in lista</strong>: comparirà
        nella vetrina "Mercato della lega", visibile a tutti e filtrabile per ruolo, età e
        overall. Non è un canale di trattativa a sé: serve solo a segnalare "questo lo
        cederei", senza doverlo scrivere in chat. Chi è interessato ti fa comunque una normale
        proposta di scambio.</p>
      <p>Il flag non sopravvive a un passaggio di squadra: se compri o ricevi un giocatore già
        in vetrina da un'altra squadra, per te riparte come non messo in lista.</p>
    </>,
  },
  {
    id: 'rinnovi',
    titolo: 'Contratti e rinnovi',
    corpo: <>
      <p>A stagione in corso puoi aprire una trattativa di rinnovo dalla scheda di un tuo
        giocatore, anche se il suo contratto non è ancora scaduto. È il giocatore ad aprire con
        una sua richiesta di ingaggio e una durata: da lì <strong>tratti su entrambi gli
        assi</strong>. Se ti allontani dalla durata che chiede, per convincerlo devi offrire di
        più in ingaggio, e viceversa.</p>
      <p>Ogni giocatore ha una tolleranza personale — quanto è disposto a scendere sotto la sua
        richiesta iniziale — che dipende dal suo umore del momento e dalla sua personalità (vedi
        la voce "Mentalità e morale"): non è mai mostrata esplicitamente, va intuita
        trattando.</p>
      <p>Hai <strong>tre tentativi</strong>. Un rifiuto ti dice quanto eri lontano ("ci siamo
        quasi", "è troppo poco", "non se ne parla nemmeno") ma consuma comunque un tentativo. Se
        li esaurisci tutti e tre, il giocatore <strong>non rinnova più con la tua squadra</strong>:
        andrà a scadenza e lascerà la rosa a fine stagione, entrando nel pool degli svincolati. Il
        contatore dei tentativi si azzera solo quando il rinnovo va a buon fine.</p>
      <p>Rinnovare oggi non muove denaro oggi: la stagione corrente è già stata pagata per
        intero a inizio anno. Il nuovo ingaggio concordato parte dalle stagioni successive — è
        un impegno futuro, non una spesa immediata.</p>
    </>,
  },
  {
    id: 'mentalita-morale',
    titolo: 'Mentalità e morale',
    corpo: <>
      <p>Ogni giocatore ha una <strong>mentalità</strong> permanente, divisa in tre rami che
        insieme fanno 100 punti: <strong>bandiera</strong> (prima la maglia, soldi e vittorie
        vengono dopo), <strong>economia</strong> (prima il contratto, punta sempre al massimo
        ingaggio possibile) e <strong>vittorie</strong> (prima i risultati). È fissa per quel
        giocatore, in ogni lega, per sempre.</p>
      <p>Il <strong>morale</strong> è invece una cifra da 0 a 100 che cambia nel tempo, ricalcolata
        più volte a stagione. Sale se il giocatore gioca quanto si aspetta di giocare (in base
        al suo overall rispetto alla media della rosa), se è pagato in linea con quanto vale e
        se la squadra vince; scende nei casi opposti. Un giocatore con la mentalità "bandiera"
        alta si lamenta meno delle altre due cose, non perché sia sempre più felice, ma perché
        gli interessano meno.</p>
      <p><strong>Mentalità e morale non influenzano mai le prestazioni in campo.</strong> Contano
        solo per le trattative economiche: quanto chiede in un rinnovo, quanto è disposto a
        scendere, se accetta un'offerta sugli svincolati. Un giocatore scontento gioca esattamente
        come uno contento — semplicemente costa di più tenerlo, o rischia di andarsene.</p>
    </>,
  },
  {
    id: 'ritiro',
    titolo: 'Ritiro',
    corpo: <>
      <p>Dai 34 anni in su, a inizio di ogni stagione, ogni giocatore ha una probabilità
        crescente con l'età di annunciare il ritiro (dal 10% a 34 anni fino al 100% certo oltre
        i 42). Chi lo annuncia <strong>gioca comunque tutta la stagione appena iniziata</strong>,
        ma da quel momento non può più essere ceduto in nessuna trattativa, né offerto né
        richiesto.</p>
      <p>L'uscita vera avviene <strong>a fine di quella stessa stagione</strong>: il giocatore
        lascia la rosa in modo definitivo, e il posto libero conta per il minimo di 21
        giocatori. Se lo svincoli dopo l'annuncio, non torna disponibile per nessun'altra
        squadra: esce direttamente dal gioco, non passa dal pool degli svincolati.</p>
    </>,
  },
  {
    id: 'classifica',
    titolo: 'Classifica',
    corpo: <>
      <p>Vittoria: 3 punti. Pareggio: 1 punto a testa. Sconfitta: 0 punti.</p>
      <p>A parità di punti, l'ordine si decide così, in sequenza: prima gli
        <strong> scontri diretti</strong> fra le squadre a pari punti, poi la
        <strong> differenza reti</strong> generale, poi i <strong>gol fatti</strong> in
        generale, e solo se resta ancora tutto pari, un sorteggio.</p>
    </>,
  },
  {
    id: 'offseason',
    titolo: 'Off-season',
    corpo: <>
      <p>Quando la stagione finisce, la lega non riparte subito: si apre una finestra di
        <strong> 24 ore esatte</strong> di preparazione, che parte quando l'admin la avvia e
        non può essere accelerata.</p>
      <p>Prima di aprirla, l'admin sceglie una fra tre strade, alternative fra loro: chiudere
        la lega qui, rimuovere uno o più partecipanti, oppure farne entrare di nuovi.</p>
      <p>Durante le 24 ore, in parallelo: gli eventuali nuovi partecipanti fanno il loro draft
        d'ingresso (con lo stesso meccanismo a pacchetti dell'inizio lega, per restare equo con
        chi è già in corsa), e il mercato degli svincolati accelera, estraendo molti più
        giocatori del solito ogni giorno, con spin extra per ogni squadra.</p>
      <p>Allo scadere delle 24 ore l'off-season si chiude da sola. Se una squadra fosse rimasta
        sotto il minimo di 21 giocatori, il sistema la completa automaticamente scegliendo gli
        svincolati più economici e sostenibili per il suo budget. La prima giornata della nuova
        stagione si gioca alla prima mezzanotte di simulazione (23:00) utile dopo la chiusura.</p>
    </>,
  },
  {
    id: 'albo-avvisi',
    titolo: "Albo d'oro e centro avvisi",
    corpo: <>
      <p>L'<strong>Albo d'oro</strong> raccoglie lo storico dei vincitori di ogni stagione
        conclusa della lega, squadra per squadra.</p>
      <p>Gli <strong>Avvisi</strong> sono il centro notifiche personale: risultati delle tue
        partite, esiti di aste e trattative, avvisi di rinnovo, formazioni schierate
        automaticamente e tutto ciò che riguarda direttamente la tua squadra. L'avviso di fine
        giornata non svela il risultato — dice solo che è pronto da controllare, così non ti
        rovina la sorpresa prima ancora di aprire l'app.</p>
      <p>L'admin della lega può anche mandare un <strong>annuncio</strong> a tutti i
        partecipanti in un colpo solo, dal pannello Admin.</p>
    </>,
  },
]

/** Accordion riusabile: sia dentro una lega (Help, sotto) sia dalla pagina
 * principale prima di sceglierne una (MenuIniziale.tsx). */
export function GuidaArgomenti({ argomenti }: { argomenti: Argomento[] }) {
  const [apertoId, setApertoId] = useState<string | null>(null)
  function toggle(id: string) { setApertoId((corrente) => (corrente === id ? null : id)) }

  return <div className="help-list">
    {argomenti.map((argomento) => {
      const aperto = apertoId === argomento.id
      return <section className="help-item" key={argomento.id}>
        <button
          className="help-item__header"
          type="button"
          aria-expanded={aperto}
          aria-controls={`help-panel-${argomento.id}`}
          id={`help-header-${argomento.id}`}
          onClick={() => toggle(argomento.id)}
        >
          <span>{argomento.titolo}</span>
          <i aria-hidden="true">⌄</i>
        </button>
        <div
          className={`help-item__body ${aperto ? 'is-open' : ''}`}
          id={`help-panel-${argomento.id}`}
          role="region"
          aria-labelledby={`help-header-${argomento.id}`}
        >
          <div className="help-item__body-inner">{argomento.corpo}</div>
        </div>
      </section>
    })}
  </div>
}

export function Help({ membership, onNavigate }: Props) {
  const league = membership.league as League

  function naviga(view: GameView) { onNavigate(view) }

  return <main className="app-shell season-shell">
    <GameNav league={league} active="help" onNavigate={naviga} />
    <header className="topbar season-topbar"><div className="brand-lockup brand-lockup--dark"><img src="/specialone-mark.svg" alt="" /><span>SpecialOne</span></div><span>Aiuto</span></header>
    <div className="season-page season-page--narrow help-page">
      <section className="help-heading">
        <p className="kicker">{league.nome}</p>
        <h1>Aiuto</h1>
        <p>Tutte le regole del gioco, spiegate senza gergo tecnico. Tocca un argomento per
          aprirlo.</p>
      </section>
      <GuidaArgomenti argomenti={ARGOMENTI_AIUTO} />
    </div>
  </main>
}
