import { useState, type ReactNode } from 'react'
import type { League, Membership } from '../types'
import { GameNav, type GameView } from './GameNav'
import { EVENTO_VISITA } from './VisitaGuidata'

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
        <strong>22:00</strong> (fuso orario Europe/Rome) il sistema simula <strong>una
        giornata</strong> di campionato, mai di più. Il mercato è aperto dalle <strong>22:30</strong>{' '}
        alle <strong>20:00</strong> del giorno dopo: si scambiano giocatori e si fanno offerte sugli
        svincolati.</p>
      <p>Dopo la stagione regolare ci sono i <strong>playoff</strong>; poi la lega entra in
        <strong> off-season</strong>, una finestra che dura quanto deciso per la lega (il conto alla rovescia
        è nella sua pagina). Lì entrano gli eventuali nuovi partecipanti, si rinnovano i contratti, si
        fanno scambi e si prepara il draft; alla chiusura esce chi non è stato rinnovato e chi aveva
        annunciato il ritiro, e riparte la stagione successiva. Vedi la voce "Off-season".</p>
      <p>Tutti gli orari del gioco — deadline formazioni, chiusura mercato, simulazione — sono
        sempre nel fuso di Roma, indipendentemente da dove ti trovi.</p>
    </>,
  },
  {
    id: 'draft',
    titolo: 'Il draft',
    corpo: <>
      <p>Il draft si gioca a <strong>pacchetti</strong>. Ogni volta che apri un pacchetto,
        il sistema pesca <strong>7 carte</strong> — un portiere, due difensori, due
        centrocampisti, due attaccanti — da tutto il pool di giocatori disponibili — non da un
        singolo club. Tu ne scegli <strong>2</strong>, liberamente fra tutte e sette, e le
        ingaggi; le altre 5 restano nel pool, ripescabili in un pacchetto futuro o dalle aste a
        stagione iniziata.</p>
      <p>Se meno di 2 carte su 7 sono davvero ingaggiabili (per budget o per il vincolo di
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
    id: 'finanza-tetto',
    titolo: 'Finanza — il tetto salariale',
    corpo: <>
      <p>Non esistono entrate: niente sponsor, niente premi partita, niente premio di
        classifica, niente dotazione che si rinnova a ogni stagione. L'unica regola economica
        della lega è questa: <strong>la somma degli ingaggi attivi di una squadra non può mai
        superare il tetto</strong>. Il tetto lo sceglie l'admin quando crea la lega, è
        <strong> identico per tutte le squadre</strong> e <strong>non cambia mai</strong>, né tra
        una stagione e l'altra né in base ai risultati.</p>
      <p>Non è un portafoglio che si riempie e si svuota: è un limite di spazio. Ingaggiare un
        giocatore non "costa" denaro, <strong>occupa</strong> una fetta di quel limite; svincolarlo
        libera di nuovo lo spazio, senza alcun movimento di cassa. Vincere non porta nessun
        vantaggio economico: il premio per i risultati in classifica è solo sportivo, mai un
        euro in più di margine sotto il tetto.</p>
    </>,
  },
  {
    id: 'finanza-ingaggi',
    titolo: 'Finanza — ingaggi e contratti',
    corpo: <>
      <p>L'ingaggio annuale di un giocatore dipende dal suo overall e dalla sua età: più forte
        è, più occupa; un giovane già forte occupa <strong>di più</strong> di un adulto di pari
        livello, perché sta "pagando" anche il suo potenziale futuro, non solo quello che rende
        oggi. Un veterano oltre i 30 anni occupa invece progressivamente meno, verso fine
        carriera.</p>
      <p>Un contratto dura <strong>una stagione</strong>, salvo i contratti pluriennali dove sono
        attivi (Serie F dalla Season 3: da 1 a 3 stagioni, vedi "Contratti e rinnovi"). Un giocatore
        preso a stagione in corso — da un'asta sugli svincolati o da uno scambio — ha un contratto che
        scade comunque a fine della stagione in corso: entro la fine dell'off-season va rinnovato come
        tutti gli altri, o lascia la rosa. Svincolare un
        giocatore libera subito il posto in rosa, ma <strong>il suo ingaggio resta sul tuo tetto</strong>
        finché il contratto non scade o finché un'altra squadra non lo prende. La regola vale
        dall'inizio della stagione: in off-season si svincola come prima, liberando subito anche
        l'ingaggio.</p>
      <p>Il sistema verifica la capienza <strong>prima</strong> di eseguire un acquisto, un'asta
        vinta o un rinnovo, quindi in condizioni normali non si supera mai il tetto. Alla
        chiusura dell'off-season c'è comunque un controllo finale di sicurezza: se una rosa
        risultasse sopra il tetto, il sistema svincola automaticamente i giocatori partendo da
        quello con l'ingaggio più alto, finché non rientra — in modo pubblico, notificato a tutta
        la lega.</p>
    </>,
  },
  {
    id: 'overall-progressione',
    titolo: 'Overall e progressione',
    corpo: <>
      <p>Ogni giocatore ha un overall attuale e un <strong>potenziale</strong>: il tetto massimo
        a cui può arrivare. L'overall si aggiorna <strong>a ogni giornata</strong>, un poco alla volta,
        non solo a fine anno.</p>
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
    id: 'gestione-risorse',
    titolo: 'Gestione risorse',
    corpo: <>
      <p>Ogni squadra riceve <strong>punti abilità</strong> quattro volte a stagione (agli stessi
        checkpoint della progressione overall), fino a un tetto massimo per tutta la vita della
        lega. Si investono su tre rami — <strong>Vivaio</strong>, <strong>Training</strong> e
        <strong> Reparto medico</strong> — ciascuno fino a un livello massimo: i punti totali non
        bastano a riempirli tutti, quindi la direzione che scegli conta davvero. Non si possono
        riassegnare: una volta messi su un ramo restano lì per il resto della lega.</p>
      <p><strong>Vivaio</strong> allarga quanti prospetti puoi tenere in cantera e restringe la
        fascia di incertezza sul loro potenziale nascosto (vedi "Vivaio e mercato UNDER").
        <strong> Training</strong> accelera la crescita dei giovani e riduce i tempi di cambio
        ruolo e di piano di sviluppo (vedi le voci dedicate). <strong>Reparto medico</strong>
        riduce il rischio di infortunio e fa recuperare più condizione a fine partita.</p>
      <p>Dalla Season 3 c'è un quarto ramo, lo <strong>Stadio</strong>, e il tetto dei punti sale da 20
        a 26. Lo stadio decide il massimo del bonus casa che il tuo pubblico può darti: +1,0 di overall a
        livello 0, +0,2 a ogni livello, fino a +3,0 a livello 10. Ogni partita in casa porta anche
        crediti del casinò dai biglietti, 50 per livello. Ogni stadio ha già un nome: dalla Season 3 lo puoi
        cambiare nella pagina Club, con "Modifica squadra" (al massimo 25 caratteri).</p>
    </>,
  },
  {
    id: 'prestiti',
    titolo: 'Prestiti',
    corpo: <>
      <p>Dalla Season 3 puoi mandare un giocatore in prestito dalla sua scheda: va in un club reale scelto
        dal sistema e ci resta fino a fine stagione. Ne puoi fare <strong>al massimo 5 a stagione</strong>, e
        ogni giocatore ci va una volta sola per stagione.</p>
      <p>In prestito cresce come chi gioca più di metà delle partite, con l'allenamento del club che lo
        ospita: è il club a scegliere il piano di sviluppo e, a volte, a cambiargli ruolo. Non si infortuna,
        il morale resta fermo e la promessa di minuti è sospesa. Resta sul tuo tetto ingaggi e in rosa, ma
        non puoi schierarlo, scambiarlo né svincolarlo.</p>
      <p>Puoi <strong>richiamarlo</strong> quando vuoi: torna disponibile dalla giornata successiva, ma in
        quella stagione non potrà più ripartire. A fine stagione rientrano tutti da soli, prima dei rinnovi.
        Dopo un prestito devono restarti almeno 18 giocatori e un portiere.</p>
    </>,
  },
  {
    id: 'vivaio-under',
    titolo: 'Vivaio e mercato UNDER',
    corpo: <>
      <p>Ogni sera alle 22:30 il sistema estrae un piccolo gruppo di quindicenni per il
        <strong> mercato UNDER</strong>, con un'asta a busta chiusa identica nel meccanismo a
        quella degli svincolati (vedi quella voce), ma con un ingaggio minimo molto più basso. Come
        il mercato degli svincolati, è chiuso durante i playoff e l'off-season.
        Chi vince porta il giovane nel proprio <strong>vivaio</strong>, non nella rosa vera: non
        conta nel minimo né nel massimo di rosa, e ha un tetto di slot a parte, legato al livello
        Vivaio.</p>
      <p>L'overall che vedi su un prospetto è sempre quello vero, ma il <strong>potenziale è
        nascosto</strong>: si mostra come una fascia (es. "68-88"), apposta non centrata sul
        valore reale — fare la media dei due estremi non lo svela. La fascia si stringe salendo
        di livello nel ramo Vivaio, fino a diventare un valore esatto al livello massimo.</p>
      <p>Un prospetto resta in cantera al massimo <strong>tante giornate quante ne ha la stagione
        regolare</strong> in cui entra (il conto lo vedi sulla sua scheda): entro quel tempo va
        <strong> promosso</strong> in prima squadra (da quel momento è un giocatore come tutti gli altri,
        con ingaggio e contratto) oppure <strong>rilasciato</strong>: se non decidi in tempo, torna
        comunque sul mercato UNDER.</p>
    </>,
  },
  {
    id: 'cambio-ruolo',
    titolo: 'Cambio ruolo',
    corpo: <>
      <p>Dalla scheda di un giocatore in rosa puoi avviare una <strong>riqualificazione</strong>
        verso un ruolo vicino a quello che gioca oggi — un difensore centrale può diventare
        terzino o mediano, non ala; un centrocampista centrale può spostarsi su una fascia, non
        diventare portiere. Il nuovo ruolo <strong>sostituisce</strong> quello attuale, non si
        affianca.</p>
      <p>Il tempo di attesa (in giornate, non in giorni di calendario) dipende da quanti ruoli il
        giocatore conosce già — chi è già versatile impara più in fretta un ruolo vicino — e si
        riduce ulteriormente salendo di livello nel ramo Training.</p>
      <p>Un giocatore segue <strong>un allenamento alla volta</strong>: non puoi avviare un
        cambio di ruolo se sta già cambiando piano di sviluppo, e viceversa. Puoi annullarlo in
        qualsiasi momento prima che si completi, senza penalità.</p>
    </>,
  },
  {
    id: 'specializzazione',
    titolo: 'Piano di sviluppo',
    corpo: <>
      <p>Come in EA FC, restando nel ruolo che gioca oggi un giocatore può seguire un
        <strong> piano di sviluppo</strong>: un archetipo di quella posizione — un centrocampista
        centrale può diventare regista, box-to-box, recupera palloni o mezz'ala d'inserimento, e
        così via per ogni ruolo, portiere compreso. Oppure il piano <strong>Bilanciato</strong>,
        che lascia la crescita naturale.</p>
      <p>Il piano <strong>non regala punti</strong>. Ogni giocatore cresce o cala a ogni giornata
        in base a età, potenziale e minuti (vedi "Overall e progressione"); il piano decide
        <strong> dove</strong> va quella crescita. Come in FC 26 pesa tutte le abilità: le due che
        definiscono il ruolo crescono circa il 75% in più, via via meno quelle che lo completano,
        e quelle lontane dal ruolo circa il 17% in meno (l'anteprima dice abilità per abilità).
        L'overall resta quello che sarebbe stato comunque.</p>
      <p>Per questo rende molto su un giovane che crescerà tanto e poco su chi è già arrivato al
        suo potenziale. Su un veterano in calo fa il contrario: le abilità del piano calano meno.
        Cambiare piano non toglie quello che il giocatore ha già maturato; il nuovo parte da lì.
        Il piano entra in vigore alla fine del training, e vale il vincolo di "un allenamento
        alla volta" del cambio ruolo. Per il portiere, "Para rigori" dà in più un vantaggio dal
        dischetto.</p>
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
        3-5-2, 3-4-3, 5-3-2, 4-2-4, 4-5-1, 4-4-1-1) decide
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
    id: 'tattiche-season2',
    titolo: 'Tattiche — ruoli, compiti e familiarità',
    corpo: <>
      <p>Dove sono attive le tattiche (dalla Season 2), la card dello stile nella pagina Formazione
        decide <strong>come gioca la squadra</strong>: uno stile di gioco già pronto oppure
        <strong> Personalizzato</strong>, per scegliere tu dove attacca, quanto alta sta la linea
        difensiva, quanto si allarga e a che velocità fa girare la palla. Lì scegli anche come gioca il
        portiere.</p>
      <p>A ogni titolare puoi dare un <strong>ruolo</strong> e un <strong>compito</strong>. Un ruolo
        adatto alle sue caratteristiche dà un bonus, uno sbagliato una penalità. Il compito sposta il
        suo peso fra <strong>più difesa</strong>, <strong>equilibrio</strong> e <strong>più
        attacco</strong>. Se non vuoi perderci tempo, i <strong>preset tattici</strong> sistemano
        tutto con un tocco.</p>
      <p>La squadra rende meglio con ciò che conosce. La <strong>familiarità</strong> ha due barre: una
        per la disposizione in campo (il modulo) e una per le indicazioni (stile, ruoli e compiti).
        Si riempiono in circa <strong>5 partite</strong>. Cambiare modulo non cancella quello già
        imparato: tornando al vecchio lo ritrovi.</p>
      <p>Hai <strong>due schemi</strong>. Quello segnato "Attivo" va in partita; l'altro lo prepari
        per dopo, e il suo modulo si impara un po' a ogni partita anche senza schierarlo. Per
        mandarlo in campo selezionalo e salva.</p>
    </>,
  },
  {
    id: 'schieramento',
    titolo: 'Come si schiera la squadra',
    corpo: <>
      <p>Prima di ogni giornata scegli modulo, stile e i tuoi <strong>undici titolari</strong>,
        più la panchina; chi resta fuori va in tribuna. La deadline è le <strong>22:00 Europe/
        Rome</strong>, lo stesso orario in cui parte la simulazione della giornata.</p>
      <p>La formazione salvata <strong>resta valida</strong> per le giornate successive, finché non la
        cambi: non serve rifarla ogni sera. Se un titolare non è disponibile (infortunato o
        squalificato) il sistema lo sostituisce al momento della partita. Solo se non hai mai salvato
        una formazione il sistema ne genera una automatica, con gli undici che rendono di più nel tuo
        ultimo modulo (o nel 4-3-3).</p>
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
    id: 'cartellini',
    titolo: 'Cartellini e squalifiche',
    corpo: <>
      <p>In partita i giocatori possono essere ammoniti o espulsi, con lo stesso regolamento
        del calcio vero. Un'<strong>espulsione</strong> (rosso diretto o secondo giallo) toglie
        subito quel giocatore dalla partita in corso, senza sostituzione: la sua squadra resta
        in inferiorità numerica per il resto del match, con l'effetto reale che questo comporta
        in campo, non solo simbolico.</p>
      <p>Ogni cartellino giallo si accumula in un contatore personale del giocatore, valido per
        tutta la stagione. Al <strong>quinto giallo</strong> scatta la <strong>diffida</strong>:
        automatica, come un'espulsione vera — una giornata di squalifica, e il contatore torna a
        zero. Anche un'espulsione, diretta o per doppio giallo, comporta sempre una giornata di
        squalifica automatica, oltre all'uscita dalla partita in cui è avvenuta.</p>
      <p>Un giocatore squalificato non è selezionabile in formazione per la giornata che deve
        scontare, né come titolare né in panchina — condivide lo stesso vincolo di un
        infortunato, e se non schieri di persona la formazione automatica lo esclude comunque.
        Nella pagina Formazione lo riconosci dal simbolo <strong>■</strong> sul ritratto (contro
        il <strong>✚</strong> dell'infortunio), e la sua scheda indica quante giornate gli
        restano da scontare.</p>
      <p>Il contatore delle ammonizioni si azzera anche all'inizio dei playoff, per ripartire
        con una lavagna pulita nella fase decisiva della stagione — ma una squalifica già
        maturata resta valida e si sconta comunque, playoff compresi.</p>
    </>,
  },
  {
    id: 'mercato-scambi',
    titolo: 'Mercato — scambi tra squadre',
    corpo: <>
      <p>In qualsiasi momento in cui il mercato è aperto puoi proporre a un'altra squadra uno
        <strong> scambio</strong>: giocatori contro giocatori, giocatori contro scelte del
        draft, o scelte contro scelte, anche in pacchetti misti. Non passa mai denaro: qui non
        esiste un "acquisto secco" né un conguaglio in soldi, solo giocatori e scelte. Chi riceve
        la proposta può accettarla o rifiutarla; se non risponde entro la chiusura del mercato
        del giorno, la proposta scade da sola.</p>
      <p>Il sistema controlla sempre che, dopo l'operazione, il monte ingaggi di
        <strong> entrambe</strong> le squadre resti sotto il tetto, e che entrambe le rose
        restino fra 21 e 30 giocatori.</p>
      <p>Tutte le trattative concluse sono visibili a <strong>tutta la lega</strong>, con il
        dettaglio di cosa è passato da una squadra all'altra: è una scelta deliberata, per
        scoraggiare accordi sottobanco fra amici.</p>
    </>,
  },
  {
    id: 'mercato-asta',
    titolo: 'Mercato — asta a busta chiusa sugli svincolati',
    corpo: <>
      <p>Ogni sera alle 22:30, quando il mercato riapre, il sistema estrae <strong>un giocatore
        per ruolo</strong> (portiere, difensore, centrocampista, attaccante). Chi viene svincolato da
        una squadra si aggiunge invece garantito, oltre a quella quota — così chi è stato appena
        tagliato torna subito visibile a tutti: capita quindi che un ruolo mostri più giocatori degli
        altri in un giorno con parecchi svincoli. Durante i playoff e l'off-season questo mercato è
        chiuso. Gli estratti a sorte restano in vetrina un giorno. Gli svincolati ancora pagati dal vecchio
        club, quelli sopra 75 di overall e i non scelti del Draft tornano invece ogni giorno, ma al massimo
        per <strong>30 giorni di mercato</strong>: poi escono dalla vetrina se nessuno li ha presi.</p>
      <p>Puoi fare <strong>una sola offerta per giocatore</strong>, indicando l'ingaggio annuale
        che sei disposto a pagargli. L'interfaccia mostra un "ingaggio minimo" di riferimento,
        ma non è una garanzia: la soglia vera che il giocatore accetta è nascosta e può essere
        più alta. Offerte sotto soglia vengono scartate. Puoi modificare o ritirare la tua
        offerta finché l'asta è aperta — dalla card "Le mie proposte" nella pagina Mercato — ma
        modificarla ti fa perdere la precedenza in caso di parità con un'altra offerta identica.</p>
      <p>Offrire impegna subito lo spazio salariale corrispondente e uno slot di rosa: puoi
        offrire su tutti i giocatori che vuoi, ma solo entro la capienza che ti resta sotto il
        tetto. Alla chiusura del
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
    id: 'mercato-scelte',
    titolo: 'Mercato a scelte (Draft)',
    corpo: <>
      <p>Oltre agli svincolati, i giocatori migliori arrivano dal <strong>mercato a scelte</strong>,
        nella pagina Draft. Ogni squadra ha dei <strong>ticket</strong>: ognuno è una scelta in una
        finestra futura. Ci sono due finestre a stagione: l'<strong>ON-Season</strong>, a metà
        stagione, e l'<strong>OFF-Season</strong>, che si estrae alla chiusura dell'off-season.</p>
      <p>Nell'OFF-Season l'ordine di scelta dipende da come è andato il <strong>Draft
        Playoff</strong> (vedi "Playoff"). Nell'ON-Season dipende dal monte ingaggi misurato alla
        chiusura dell'off-season: chi spende meno sceglie prima.</p>
      <p>Quando una finestra è aperta vedi la tua posizione e il pool degli eleggibili. Componi una
        <strong> lista di preferenze</strong>, una sola anche se hai più ticket nella stessa finestra.
        All'estrazione ogni scelta prende la prima preferenza ancora libera che entra sotto il tuo
        tetto ingaggi. La lista si cambia fino a <strong>un'ora prima</strong> dell'estrazione. Se
        nessuna preferenza è più disponibile, quella scelta resta vuota per la finestra.</p>
      <p>Ogni eleggibile chiede un <strong>minutaggio</strong>: chi lo prende firma con quella
        promessa e deve mantenerla (vedi "Contratti e rinnovi").</p>
      <p>I ticket si <strong>scambiano</strong> come i giocatori. Lo stemma sul ticket resta quello
        della squadra da cui viene la scelta, perché è il suo piazzamento a decidere la posizione;
        cambia solo il proprietario.</p>
    </>,
  },
  {
    id: 'rinnovi',
    titolo: 'Contratti e rinnovi',
    corpo: <>
      <p>A stagione in corso e per tutta l'off-season puoi aprire una trattativa di rinnovo dalla
        scheda di un tuo giocatore, anche se il suo contratto non è ancora scaduto. È il giocatore ad aprire con
        una sua richiesta di ingaggio, e da lì <strong>tratti solo su quello</strong>: la
        durata non si negozia mai, un rinnovo estende il contratto di
        <strong> esattamente una stagione</strong>.</p>
      <p><strong>Contratti pluriennali</strong> (Serie F dalla Season 3): il rinnovo si tratta
        solo nell'<strong>ultima stagione</strong> del contratto e puoi scegliere da
        <strong> 1 a 3 stagioni</strong>, più un'eventuale <strong>opzione +1</strong>. L'ingaggio
        resta lo stesso per tutta la durata. Per ogni stagione in più un giovane che sa di poter
        crescere chiede di più, chi ha passato i 30 anni si accontenta di meno; il morale alto fa
        sconto, quello basso fa chiedere di più (sotto 30 firma solo per un anno). Con
        l'<strong>opzione squadra</strong> decidi tu, entro fine stagione, se tenerlo un anno in
        più: se non decidi vale come rifiutata (chiede l'8% in più). Con
        l'<strong>opzione giocatore</strong> decide lui a fine stagione: resta se il contratto
        vale ancora quanto lui e non è scontento (fa il 5% di sconto). Svincolare un contratto
        lungo: l'ingaggio pesa per intero fino a fine stagione, poi a metà fino alla scadenza.</p>
      <p>Insieme all'ingaggio tratti il <strong>minutaggio promesso</strong>: titolare fisso
        (gioca la maggior parte delle partite), turnover (entra quando i titolari sono stanchi),
        sporadico (poche partite) o promessa futura (solo sotto i 21 anni). Più minuti prometti,
        meno chiede; un giocatore tra i migliori della rosa non accetta di fare panchina.
        Finché non lo tratti, il gradino lo decide la gerarchia della rosa.</p>
      <p>Una promessa va mantenuta. Ogni 5 giornate (dalla 8ª) chi ha un minutaggio promesso e
        gioca molto meno del pattuito ti scrive un <strong>richiamo</strong>; se al controllo dopo
        la situazione non è cambiata, <strong>chiede la cessione</strong> e non rinnova più il
        contratto.</p>
      <p>Ogni giocatore ha una tolleranza personale — quanto è disposto a scendere sotto la sua
        richiesta iniziale — che dipende dal suo umore del momento e dalla sua personalità (vedi
        la voce "Mentalità e morale"): non è mai mostrata esplicitamente, va intuita
        trattando.</p>
      <p>Hai <strong>tre tentativi</strong>. Un rifiuto ti dice quanto eri lontano ("ci siamo
        quasi", "è troppo poco", "non se ne parla nemmeno") ma consuma comunque un tentativo. Se
        li esaurisci tutti e tre, il giocatore <strong>non rinnova più con la tua squadra</strong>:
        andrà a scadenza e lascerà la rosa a fine stagione, entrando nel pool degli svincolati. Il
        contatore dei tentativi si azzera solo quando il rinnovo va a buon fine.</p>
      <p>Rinnovare non muove nulla subito: il nuovo ingaggio concordato occupa spazio sotto il
        tetto solo dalla stagione successiva in poi, non su quella in corso — è un impegno
        futuro, verificato per essere sempre sostenibile, non una spesa immediata.</p>
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
        più volte a stagione. Sale se il giocatore gioca quanto si aspetta di giocare (il suo
        minutaggio promesso, vedi "Contratti e rinnovi"), se è pagato in linea con quanto vale e
        se la squadra vince; scende nei casi opposti. Un giocatore con la mentalità "bandiera"
        alta si lamenta meno delle altre due cose, non perché sia sempre più felice, ma perché
        gli interessano meno.</p>
      <p>Il morale conta soprattutto nelle trattative: quanto chiede in un rinnovo, quanto è
        disposto a scendere, se accetta un'offerta sugli svincolati. In campo pesa poco: un
        giocatore molto scontento rende un filo meno, uno entusiasta un filo di più.</p>
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
      <p>Nelle leghe con le <strong>conference</strong> (East e West) ogni conference ha la sua
        classifica: i posti per i playoff si contano lì dentro.</p>
    </>,
  },
  {
    id: 'playoff',
    titolo: 'Playoff',
    corpo: <>
      <p>A fine stagione regolare la classifica si divide in due tabelloni a eliminazione diretta,
        giocati in parallelo. Il <strong>Title Playoff</strong> prende le prime 8 e assegna il
        titolo; il <strong>Draft Playoff</strong> prende tutte le altre squadre.</p>
      <p>Nelle leghe con le <strong>conference</strong> ogni conference si divide in due: le prime
        posizioni vanno al Title Playoff, le altre al Draft Playoffs. Le prime due di ogni conference
        passano direttamente ai quarti; le altre si giocano l'accesso in un
        <strong> play-in</strong> incrociato con l'altra conference. Nel Draft Playoffs vale il
        contrario: le ultime due vanno dirette ai quarti. I posti esatti li trovi nel Tabellone.</p>
      <p>Ogni sfida è di <strong>andata e ritorno</strong>: passa chi segna di più nella somma (i gol
        in trasferta non valgono doppio); in caso di parità il ritorno va ai supplementari e poi ai
        rigori. La <strong>finale</strong> è una gara secca in campo neutro.</p>
      <p>Il Draft Playoff non è un ripiego: come va lì, e chi ti elimina, decide l'ordine nel
        mercato a scelte OFF-Season.</p>
      <p>Durante i playoff sono chiusi gli scambi e i mercati degli svincolati e UNDER: gli scambi
        riaprono con l'off-season. I rinnovi restano aperti.</p>
    </>,
  },
  {
    id: 'offseason',
    titolo: 'Off-season',
    corpo: <>
      <p>Quando i playoff finiscono, la lega non riparte subito: dopo 24 ore per rivedere i
        risultati l'admin apre l'<strong>off-season</strong>, una finestra di preparazione che dura
        quanto deciso per la lega (il conto alla rovescia è nella sua pagina). Prima di aprirla
        l'admin conferma quali squadre proseguono e se entrano squadre nuove.</p>
      <p>Durante l'off-season si <strong>rinnovano i contratti</strong> e si <strong>fanno scambi</strong>;
        i mercati degli svincolati e UNDER sono chiusi. Gli eventuali nuovi partecipanti fanno il loro
        draft d'ingresso (con lo stesso meccanismo a pacchetti dell'inizio lega), e si prepara il
        draft OFF-Season delle scelte: ordine ed eleggibili sono già visibili, l'estrazione avviene
        alla chiusura.</p>
      <p>Alla scadenza l'off-season si chiude da sola: escono i contratti non rinnovati e chi aveva
        annunciato il ritiro, poi si estrae il draft. Nelle leghe con le conference segue il
        sorteggio East/West in diretta. Se una squadra fosse rimasta
        sotto il minimo di 21 giocatori, il sistema la completa automaticamente scegliendo gli
        svincolati più economici e sostenibili sotto il suo tetto ingaggi. La prima giornata della nuova
        stagione si gioca alla prima mezzanotte di simulazione (22:00) utile dopo la chiusura.</p>
    </>,
  },
  {
    id: 'extra-campo',
    titolo: 'Extra campo — spogliatoio, stampa, tifosi',
    corpo: <>
      <p>Nelle leghe dove sono attive, queste pagine raccontano quello che succede intorno alla
        squadra, e alcune toccano il morale dei giocatori.</p>
      <p><strong>Spogliatoio</strong>: i tuoi giocatori ti scrivono, per esempio chi vuole più minuti
        o il capitano che chiede un giorno libero. Rispondi con parole tue e la risposta muove il loro
        morale. Una richiesta lasciata scadere vale come un no.</p>
      <p><strong>Sala stampa</strong>: prima e dopo le partite i giornalisti ti fanno domande. Le tue
        risposte vengono valutate e toccano il morale dei giocatori.</p>
      <p><strong>SocialOne</strong>: il social della lega, dove giornali, giornalisti, influencer e
        tifosi commentano partite e mercato. Se segui un profilo, in «Per te» vedi prima i suoi
        post.</p>
      <p><strong>Rivalità</strong>: il grado di rivalità con ogni altra squadra, da 0 a 100%, visibile
        solo a te e all'altra squadra. Da qui scegli anche il tuo rivale fisso, il derby.</p>
      <p><strong>Pubblico</strong>: l'umore dei tuoi tifosi, da 0 a 100. Più sono contenti, più è
        grande il vantaggio quando giochi in casa; il massimo lo decide il livello dello stadio.</p>
      <p><strong>Sponsor</strong>: le aziende ti propongono contratti a breve e a lungo termine. Ne
        firmi uno per colonna e, se centri l'obiettivo, incassi crediti. Alcuni sponsor piacciono ai
        tifosi, altri no.</p>
    </>,
  },
  {
    id: 'crediti-betone-album',
    titolo: 'Crediti, BetOne e Album',
    corpo: <>
      <p>I <strong>crediti</strong> sono una moneta a parte: <strong>non toccano mai la squadra</strong>
        né il tetto ingaggi. Si vincono con sponsor, schedine, giochi, quiz e pagine dell'album
        completate. A ogni stagione nuova i crediti ripartono da zero e i doppioni dell'album
        vecchio non si riciclano né si scambiano più.</p>
      <p><strong>SchedOne</strong>: la schedina della prossima giornata. Metti 1, X o 2 su ogni
        partita, con al massimo 2 doppie, e punti dei crediti. Chiude 15 minuti prima della simulazione
        delle 22:00.</p>
      <p><strong>CasinOne</strong>: AviatOne, CrazyOne, BlackjackOne e SlotOne, tutti a crediti.</p>
      <p><strong>QuizOne</strong>: ogni ora una domanda sulla lega, uguale per tutti. Si entra nei
        primi 10 minuti, gratis o puntando, e chi risponde giusto vince crediti.</p>
      <p><strong>Album</strong>: le figurine della lega, una pagina per squadra. Compri le bustine con i
        crediti, ricicli i doppioni e scambi le figurine con gli altri. Ogni pagina completa ti dà
        crediti.</p>
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
        {league.stato !== 'draft' && <button className="visita-rifai" type="button" onClick={() => window.dispatchEvent(new Event(EVENTO_VISITA))}>
          <b>Visita guidata</b><span>Un giro su tutte le pagine del gioco, dentro l'app</span><i aria-hidden="true">›</i>
        </button>}
      </section>
      <GuidaArgomenti argomenti={ARGOMENTI_AIUTO} />
    </div>
  </main>
}
