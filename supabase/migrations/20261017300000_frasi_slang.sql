-- ============================================================
--  SOCIALONE: i testi meno "da bot", con lo slang dei social (17 ottobre 2026, committente)
--  Frasi riscritte da zero per tifosi, giocatori e compagni: piu' corte, in minuscolo, con il gergo vero
--  ("raga", "madonna", "no vabbe'", "daje", "aura", "cooked", emoji come 💀🤡😭) e il lessico del calcio
--  ("tiro telefonato", "campanile", "melina", "catenaccio", "viva il parroco").
--  Le tre tabelle di frasi (frasi_tifosi, frasi_social, frasi_commenti) vengono svuotate e riempite di nuovo;
--  cambiano gli id, ma i post gia' scritti restano com'erano. I post automatici dei giorni scorsi (tifosi,
--  marcatori, addii e tutte le risposte) si cancellano e si rigenerano con il tono nuovo.
-- ============================================================

begin;

delete from private.frasi_tifosi;
insert into private.frasi_tifosi (categoria, testo) values
  ('goleada', '{F}-{G}?? no vabbè siamo fuori scala 💀 {S}'),
  ('goleada', 'madonna che roba. {O} letteralmente umiliati. daje {S} 🔥'),
  ('goleada', '{F} gol ahahah sto ancora ridendo. {S} assurdi'),
  ('goleada', 'raga ma quanto siamo forti?? {S} 😍'),
  ('goleada', 'spettacolo puro. {S} oggi ha spento {O} 🔥'),
  ('goleada', '{O} cooked 💀 {S}'),
  ('goleada', 'che goduria, ve lo giuro. {S} {F}-{G} e tutti a nanna'),
  ('goleada', 'aura infinita stasera {S} 😎'),
  ('goleada', 'bestiali. non c''è altro da dire {S}'),
  ('goleada', '{S} non è una squadra, è un rullo compressore 🚜'),
  ('goleada', '{F}-{G}. leggete e piangete {O} 😂 {S}'),
  ('goleada', 'non ci credo ancora. {S} dominio totale'),
  ('goleada', 'tipo la partita più bella dell''anno. {S} ❤️'),
  ('goleada', '{O} ha preso una lezione. {S} spettacolo!'),
  ('goleada', 'stasera mi sento un dio. grazie {S} 🙌'),
  ('goleada', 'ho urlato così forte che i vicini mi odiano 😂 {S} {F}-{G}!!'),
  ('goleada', 'che squadra ragazzi... {S} sempre!! ❤️‍🔥'),
  ('goleada', 'qui si gioca a un altro sport. {S} 🔥'),
  ('goleada', '{S} che bestie!! {F}-{G} non si vede ogni giorno'),
  ('goleada', 'mamma mia che serata, potevo morire di gioia. {S} 😭'),
  ('goleada', '{O} chi? ah quelli che hanno preso {F} gol 😂 {S}'),
  ('goleada', 'daje {S}!!! ancora ancora ancora 🔥'),
  ('goleada', 'questa sì che è una squadra da scudetto. {S}'),
  ('goleada', 'se giocate sempre così ci portiamo a casa tutto. {S} 💪'),
  ('goleada', '{F}-{G} e passa la paura. grandissimi {S}'),
  ('goleada', 'che roba... {S} oggi pazzeschi 🤯'),
  ('goleada', 'roba da matti questa partita. {S} da standing ovation 👏'),
  ('goleada', 'serata perfetta. birra, divano e {F}-{G}. {S} 🍻'),
  ('vittoria', 'tre punti e zitti tutti. {S} 💪'),
  ('vittoria', 'sofferta ma vale doppio. daje {S}!'),
  ('vittoria', '{F}-{G} contro {O}, ce la portiamo a casa. {S} ❤️'),
  ('vittoria', 'non bellissimi ma chi se ne frega, conta vincere {S}'),
  ('vittoria', 'che ansia ragazzi... però vittoria!! {S} 🙌'),
  ('vittoria', 'brutta partita ma tre punti d''oro. {S}'),
  ('vittoria', '{O} battuto, andiamo avanti {S} 🔥'),
  ('vittoria', 'vittoria di cuore, di gambe e di palle. {S}'),
  ('vittoria', 'si vince anche così, tranquilli. {S}'),
  ('vittoria', 'oh finalmente, sto ancora tremando 😅 {S}'),
  ('vittoria', 'classifica che sorride, umore alle stelle. {S} 📈'),
  ('vittoria', 'tre punticini che profumano di scudetto. {S}'),
  ('vittoria', 'gol, sofferenza e vittoria. il calcio che amo {S} ❤️'),
  ('vittoria', '{S} ha dato tutto, e si è visto. grandi!'),
  ('vittoria', 'che fatica ma che gioia!! {S} non mollate mai 🔥'),
  ('vittoria', 'vittoria meritata contro {O}. bravi {S} 👏'),
  ('vittoria', 'non so voi ma io ho cambiato tre volte posizione sul divano 😂 {S}'),
  ('vittoria', '{F}-{G}. basta guardare il tabellino {S} ✌️'),
  ('vittoria', 'ci siamo, ci siamo. si inizia a ragionare {S}'),
  ('vittoria', 'stasera dormo bene. {S} grazie ragazzi 🫡'),
  ('vittoria', 'vinciamo anche quando non giochiamo bene, è da grandi {S}'),
  ('vittoria', 'serata da incorniciare. {S} 🙌'),
  ('vittoria', '{O} ci ha fatto soffrire ma ce l''abbiamo fatta {S}'),
  ('vittoria', 'daje {S}! ora non fermiamoci 🔥'),
  ('vittoria', 'un successo che vale più dei tre punti. {S}'),
  ('vittoria', 'grande mentalità stasera {S} 💪'),
  ('vittoria', 'vittoria di squadra, di gruppo, di tutti. {S} ❤️'),
  ('vittoria', 'abbiamo vinto. e basta. {S} 😎'),
  ('pareggio', 'un punto e via... ma io volevo vincere {S} 😤'),
  ('pareggio', '{F}-{G} contro {O}? mah. boh. {S}'),
  ('pareggio', 'pareggio che sa di sconfitta, che rabbia {S}'),
  ('pareggio', 'melina totale. {S} dov''è la voglia di vincere?'),
  ('pareggio', 'punto d''oro o occasione persa? io dico la seconda {S}'),
  ('pareggio', 'partita che mi ha fatto addormentare 🥱 {S}'),
  ('pareggio', '{S} così non si va da nessuna parte, serve un cambio di marcia'),
  ('pareggio', 'ci stava anche vincerla, onestamente. {S}'),
  ('pareggio', 'tiro telefonato al 90'' e addio vittoria 🤦 {S}'),
  ('pareggio', 'né carne né pesce. {S} svegliatevi'),
  ('pareggio', 'il minimo sindacale. {S} dai su'),
  ('pareggio', '1 punto è sempre meglio di niente ma che palle {S}'),
  ('pareggio', '{O} ha fatto catenaccio e noi ci siamo cascati {S}'),
  ('pareggio', 'dovevamo vincerla, non c''è storia. {S} 😠'),
  ('pareggio', 'onestamente mi aspettavo di più {S}'),
  ('pareggio', 'pari giusto, ma ci accontentiamo troppo {S}'),
  ('pareggio', 'pareggio con sapore amaro. {S} 😔'),
  ('pareggio', 'serviva più cattiveria sotto porta. {S}'),
  ('pareggio', 'non è un disastro ma neanche una festa {S}'),
  ('pareggio', 'ho visto partite di oratorio più divertenti {S} 😂'),
  ('pareggio', '{F}-{G}. mah. avanti {S}'),
  ('pareggio', 'dai su, la prossima la vinciamo {S} 💪'),
  ('pareggio', 'che noia questa partita, davvero {S}'),
  ('pareggio', 'punto guadagnato o punti persi? sempre la solita domanda {S}'),
  ('pareggio', 'niente di fatto. peccato {S}'),
  ('pareggio', 'con {O} bastava poco per vincere. {S}'),
  ('pareggio', 'ok così, ma poteva essere meglio. {S}'),
  ('pareggio', 'pareggio dal sapore strano. {S} boh'),
  ('batosta', '{F}-{G}?? madonna che vergogna 🤡 {S}'),
  ('batosta', 'spengo tutto e vado a letto. {S} fate pena'),
  ('batosta', 'presi a schiaffi da {O}. imbarazzanti {S} 💀'),
  ('batosta', 'non c''è niente da salvare, zero. {S}'),
  ('batosta', 'ma vi allenate o fate la gita? {S} così è ridicolo'),
  ('batosta', 'questa è la peggiore partita che ho visto in vita mia {S} 😭'),
  ('batosta', '{O} ci ha dato una lezione. {S} dovete fare di meglio'),
  ('batosta', 'aura -10000 stasera. {S} 💀'),
  ('batosta', 'sono letteralmente senza parole. {S}'),
  ('batosta', '{F}-{G}. ditemi che è un incubo {S} 😩'),
  ('batosta', 'chiudiamo tutto e ripartiamo da zero {S}'),
  ('batosta', 'che pagliacciata ragazzi. {S} 🤡'),
  ('batosta', '{S} giocatori svogliati, idee zero, cuore zero.'),
  ('batosta', 'mi vergogno di essere tifoso oggi. {S}'),
  ('batosta', 'ci hanno fatto il c*lo, e chi non lo ammette è cieco {S}'),
  ('batosta', 'mi state facendo passare la voglia del calcio. {S}'),
  ('batosta', 'che schifo. {S} sveglia, SVEGLIA!'),
  ('batosta', '{O} ci ha umiliati e noi lì a guardare. {S}'),
  ('batosta', 'campanile dopo campanile, zero idee. {S} 😤'),
  ('batosta', 'serata nera, nerissima. {S}'),
  ('batosta', 'tutti a casa. tutti. {S} 🙄'),
  ('batosta', 'ma se ne accorgono almeno del casino che stanno facendo? {S}'),
  ('batosta', 'batosta meritata, non c''è altro da dire. {S}'),
  ('batosta', 'mister fai qualcosa perché così non si può {S}'),
  ('batosta', 'scarpette al chiodo, tutti, ora. {S} 😡'),
  ('batosta', '{F}-{G}... che figura di merda ragazzi {S}'),
  ('batosta', 'la peggior {S} che io ricordi. complimenti 👏 (ironico)'),
  ('batosta', 'chi mi spiega cosa abbiamo guardato stasera? {S} 💀'),
  ('sconfitta', 'peccato, ci credevo stasera. dai {S} 💔'),
  ('sconfitta', 'perdere con {O} brucia, eccome se brucia {S}'),
  ('sconfitta', '{F}-{G}. ci sta ma fa male lo stesso {S}'),
  ('sconfitta', 'un''altra occasione buttata. {S} sveglia'),
  ('sconfitta', 'giornata storta ma ci rialziamo subito {S} 💪'),
  ('sconfitta', 'serviva più cattiveria, punto. {S}'),
  ('sconfitta', 'sconfitta immeritata secondo me. {S} avanti'),
  ('sconfitta', 'oh, ora però bisogna reagire {S} 😤'),
  ('sconfitta', 'che rabbia, potevamo anche pareggiarla {S}'),
  ('sconfitta', 'non è il momento di mollare. sempre con voi {S} ❤️'),
  ('sconfitta', '{O} ci ha puniti al primo errore. {S}'),
  ('sconfitta', 'mi sanguina il cuore. {S} dai che si riparte'),
  ('sconfitta', 'ci sta perdere ma non così. {S}'),
  ('sconfitta', 'perso contro {O}, mister svegliati {S}'),
  ('sconfitta', 'brutta sconfitta. cambiate qualcosa {S}'),
  ('sconfitta', 'dai cazzo, ancora una. {S} così non va'),
  ('sconfitta', 'ho il magone. {S} ma non è finita 😔'),
  ('sconfitta', 'errori banali e paghi tutto. {S}'),
  ('sconfitta', 'stasera niente aura, solo sconfitta. {S} 😭'),
  ('sconfitta', 'non siamo questi, lo sapete anche voi. {S}'),
  ('sconfitta', 'mi sono arrabbiato ma passa, forza {S}'),
  ('sconfitta', 'la prossima va meglio, la prossima va meglio... {S} 🙏'),
  ('sconfitta', 'che peccato, davvero. {S}'),
  ('sconfitta', 'persa ma con dignità, ci può stare. {S}'),
  ('sconfitta', '{O} meritava, ammettiamolo. ora rialziamoci {S}'),
  ('sconfitta', 'non si molla un cazzo. {S} su la testa!'),
  ('sconfitta', 'giornata no per tutti. {S} si ricomincia'),
  ('sconfitta', 'male, ma domani è un altro giorno. {S} ❤️');

delete from private.frasi_social;
insert into private.frasi_social (categoria, testo) values
  ('tifosi_bene', '{IN} da noi?? no vabbè, non ci credo 😍 {S}'),
  ('tifosi_bene', 'madonna che colpo. {IN} è nostro!! {S} 🔥'),
  ('tifosi_bene', 'questo è mercato vero. benvenuto {IN} {S}'),
  ('tifosi_bene', '{IN} per {OUT}? firmo con il sangue {S}'),
  ('tifosi_bene', 'chi ha fatto questo scambio merita un monumento {S} 🏆'),
  ('tifosi_bene', 'oh finalmente un acquisto serio. {IN} sei dei nostri {S} 🙌'),
  ('tifosi_bene', 'con {IN} cambia tutto, lo sento {S}'),
  ('tifosi_bene', 'benvenuto {IN}!! ora fai vedere chi sei {S} 💪'),
  ('tifosi_bene', 'mamma mia {IN}... {S} oggi vince il mercato'),
  ('tifosi_bene', 'questo sì che è un colpo. bravi bravi bravi {S}'),
  ('tifosi_bene', '{IN} bestiale. se gioca come sa qui facciamo il botto {S}'),
  ('tifosi_bene', 'mi tremano le mani: {IN} è un nostro giocatore {S} 😭'),
  ('tifosi_bene', 'bel colpo, davvero. {S} sta crescendo 📈'),
  ('tifosi_bene', 'avevo perso la speranza e invece... {IN}!! {S}'),
  ('tifosi_bene', '{S} mercato da prima pagina. {IN} benvenuto!'),
  ('tifosi_bene', 'daje {S}! con {IN} si ragiona 🔥'),
  ('tifosi_bene', 'questa dirigenza mi sta facendo ricredere. {IN} {S}'),
  ('tifosi_bene', 'altro livello. {IN} è un grande acquisto {S}'),
  ('tifosi_bene', 'ho già ordinato la maglia di {IN} 😂 {S}'),
  ('tifosi_bene', 'scambio che vale mezzo campionato. {IN} {S} 🚀'),
  ('tifosi_bene', 'che affare ragazzi, che affare. {IN} {S}'),
  ('tifosi_bene', '{IN} da noi è un sogno. grazie {S} ❤️'),
  ('tifosi_bene', '{OUT} auguri, ma {IN} è un''altra cosa {S}'),
  ('tifosi_bene', 'colpo di genio. {IN} {S} 😎'),
  ('tifosi_bene', 'non ci credo. non ci credo. {IN} {S} 🤯'),
  ('tifosi_bene', '{S} oggi il mercato lo vince lei. {IN} benvenuto'),
  ('tifosi_bene', 'siamo più forti di prima, punto. {IN} {S} 💪'),
  ('tifosi_bene', '{IN} è proprio quello che serviva. daje {S}'),
  ('tifosi_bene', 'che bello leggere certe notizie. {IN} {S} ❤️‍🔥'),
  ('tifosi_bene', 'mercato da grande squadra. {IN} {S} 👏'),
  ('tifosi_male', '{OUT} ceduto?? ma siete scemi? {S} 🤡'),
  ('tifosi_male', 'no vabbè... via {OUT} e ci arriva {IN}? non capisco {S}'),
  ('tifosi_male', '{OUT} non si tocca, e voi lo regalate. {S} bravi (ironico)'),
  ('tifosi_male', 'madonna che delusione. {OUT} era il nostro simbolo {S} 😔'),
  ('tifosi_male', 'chi ha deciso questo scambio vada a casa {S} 😤'),
  ('tifosi_male', 'ma {OUT} per {IN}?? ditemi che è uno scherzo {S}'),
  ('tifosi_male', 'ci avete tolto il migliore e dovremmo ringraziare? {S}'),
  ('tifosi_male', 'addio {OUT}, mi dispiace da morire. alla dirigenza dico solo: speriamo bene {S} 💔'),
  ('tifosi_male', 'scambio che non capisco e non voglio capire. {S}'),
  ('tifosi_male', '{OUT} se ne va e ci resta il vuoto. {S} 😭'),
  ('tifosi_male', 'se questo è il piano, siamo messi male {S}'),
  ('tifosi_male', 'mi è passata la voglia di guardare le partite. via {OUT} {S}'),
  ('tifosi_male', 'cedere {OUT}?? ma stiamo scherzando? {S} 😡'),
  ('tifosi_male', '{S} la dirigenza ha toppato alla grande. {OUT} era intoccabile'),
  ('tifosi_male', 'senza {OUT} siamo molto più deboli. dai su {S}'),
  ('tifosi_male', '{IN} è bravo ma non vale {OUT}. fine {S}'),
  ('tifosi_male', 'che mercato è questo? {S} mi cadono le braccia'),
  ('tifosi_male', 'ho letto la notizia e ho spento il telefono 💀 {S}'),
  ('tifosi_male', '{OUT} era l''anima della squadra. {S} perché?'),
  ('tifosi_male', 'scambio da denuncia. {OUT} {S} 🤦'),
  ('tifosi_male', '{OUT} non si vende, punto. {S}'),
  ('tifosi_male', 'qualcuno mi spieghi che senso ha. {S}'),
  ('tifosi_male', '{OUT} nel cuore per sempre. alla società: complimenti per niente {S}'),
  ('tifosi_male', 'ci state smantellando. {S} 😠'),
  ('tifosi_male', 'se perdiamo ora dopo questo scambio, sapete di chi è la colpa {S}'),
  ('tifosi_male', 'e adesso senza {OUT} chi segna? {S}'),
  ('tifosi_male', 'mercato da incubo. {OUT} {S}'),
  ('tifosi_male', 'ciao {OUT}, eri uno dei pochi che ci metteva il cuore {S} 😢'),
  ('tifosi_male', 'giornata nera per {S}. {OUT} ci mancherai'),
  ('tifosi_male', 'ma {OUT} no, dai. tutti ma lui no {S}'),
  ('tifosi_neutro', 'scambio fatto. boh, vediamo cosa succede in campo {S}'),
  ('tifosi_neutro', 'non sono né contento né incazzato, aspetto il campo {S}'),
  ('tifosi_neutro', 'mah. sulla carta non mi convince, ma magari mi sbaglio {S}'),
  ('tifosi_neutro', 'il mister sa quello che fa, mi fido {S} 🤞'),
  ('tifosi_neutro', 'un po'' di rimescolamento ci può stare. {S}'),
  ('tifosi_neutro', 'vediamo che combinano. {S} 👀'),
  ('tifosi_neutro', 'scambio da valutare tra qualche giornata {S}'),
  ('tifosi_neutro', 'fiducia alla società, ancora una volta {S}'),
  ('tifosi_neutro', 'non so se è un affare o una fregatura, lo dirà il campo {S}'),
  ('tifosi_neutro', 'movimento di mercato e io aspetto. {S}'),
  ('tifosi_neutro', 'chissà se è la mossa giusta. speriamo {S} 🙏'),
  ('tifosi_neutro', 'scambio che divide. io ancora non ho un''idea {S}'),
  ('tifosi_neutro', 'se il mister l''ha voluto, ci sarà un motivo {S}'),
  ('tifosi_neutro', 'ai posteri l''ardua sentenza. {S}'),
  ('tifosi_neutro', 'boh, che dire. {S} si vedrà'),
  ('tifosi_neutro', 'sembra una mossa sensata, ma attendiamo. {S}'),
  ('tifosi_neutro', 'né un colpo né un disastro. {S} vediamo'),
  ('tifosi_neutro', 'spero sia la scossa giusta {S} 🤞'),
  ('tifosi_neutro', 'scambio interessante, soprattutto per capire che idea ha il mister {S}'),
  ('tifosi_neutro', 'io intanto aspetto prima di dire la mia. {S}'),
  ('tifosi_neutro', '{S} ha fatto uno scambio. e ora? ora si gioca'),
  ('tifosi_neutro', 'per ora mi tengo il dubbio. {S}'),
  ('tifosi_neutro', 'o è geniale o è un errore, via di mezzo non c''è {S} 😅'),
  ('tifosi_neutro', 'qualunque cosa sia, forza {S}!'),
  ('tifosi_neutro', 'cambia qualcosa nella squadra, non nella fede. {S} ❤️'),
  ('tifosi_neutro', 'se funziona bravi, altrimenti ne riparliamo {S}'),
  ('tifosi_neutro', 'mercato movimentato. portate punti e va bene tutto {S}'),
  ('tifosi_neutro', 'non mi sbilancio. dopo tre partite vi dico {S}'),
  ('tifosi_neutro', 'nuovo scambio, nuovi dubbi. {S} 🤷'),
  ('tifosi_neutro', 'fiducia fiducia fiducia. {S}'),
  ('giocatore_amaro', 'ho sempre dato tutto per questa maglia, vado via con la coscienza a posto. un giorno la verità verrà a galla. ora concentrato e felice per la nuova avventura 💪'),
  ('giocatore_amaro', 'c''è chi ha saputo apprezzarmi e chi no. a chi ha creduto in me: grazie di cuore. si volta pagina, forza {X}'),
  ('giocatore_amaro', 'alcune cose è meglio non dirle. il campo parlerà per me. adesso solo {X} 🔥'),
  ('giocatore_amaro', 'quando non sei più al centro del progetto è giusto andare dove ti vogliono. grazie a chi c''è stato davvero'),
  ('giocatore_amaro', 'ho passato mesi a dimostrare il mio valore. ora lo faccio altrove. chi ha capito ha capito'),
  ('giocatore_amaro', 'non ho niente da rimproverarmi. il campo ha sempre risposto per me. si riparte con {X} 🔥'),
  ('giocatore_amaro', 'ho lasciato tutto me stesso. qualcun altro lasci un po'' di onestà. nuova avventura, nuova energia'),
  ('giocatore_amaro', 'ai tifosi il mio grazie vero. agli altri nessun messaggio. forza {X}'),
  ('giocatore_amaro', 'la verità prima o poi esce sempre. intanto vado via a testa alta'),
  ('giocatore_amaro', 'mi hanno messo da parte ma ora è tutto alle spalle. felicissimo di ripartire con {X}'),
  ('giocatore_amaro', 'ho dato anima e corpo, ricevuto poco. adesso penso solo a me e a {X}'),
  ('giocatore_amaro', 'non servono tanti giri di parole. chi mi conosce sa che persona sono. avanti {X}!'),
  ('giocatore_amaro', 'io i fatti li ho sempre messi in campo. le parole le lascio agli altri. {X} 💪'),
  ('giocatore_amaro', 'vado via sereno, anche se non tutto è stato bello. grazie a chi mi ha voluto bene'),
  ('giocatore_amaro', 'sono felice di essere qui. di come ci sono arrivato ne parlerò un giorno'),
  ('giocatore_amaro', 'non dimentico niente, né il bello né il resto. ora testa a {X}'),
  ('giocatore_amaro', 'tutti abbiamo i nostri momenti, io ho dato più di quanto mi è stato riconosciuto'),
  ('giocatore_amaro', 'ora si respira aria nuova. grazie {V} per le emozioni, non per tutto il resto'),
  ('giocatore_amaro', 'mi hanno detto che non ero più importante. spero di dimostrare il contrario con {X} 😏'),
  ('giocatore_amaro', 'chi doveva capire ha capito, chi no pazienza. ora solo {X}'),
  ('giocatore_amaro', 'mi sono sentito ospite a casa mia. oggi mi sento a casa altrove. forza {X}'),
  ('giocatore_amaro', 'un pensiero ai compagni veri. per il resto buona fortuna {V}'),
  ('giocatore_amaro', 'avrei voluto salutare diversamente, ma va bene così. {X}, eccomi!'),
  ('giocatore_amaro', 'zero polemiche. solo una cosa da dire: ci vediamo in campo 😏'),
  ('giocatore_amaro', 'il tempo dice sempre la verità. io intanto vado avanti {X}'),
  ('giocatore_amaro', 'grazie a chi ha creduto in me quando nessuno ci credeva. {X}, ci siamo'),
  ('giocatore_amaro', 'ho la coscienza pulita e la valigia pronta. avanti {X} 💪'),
  ('giocatore_amaro', 'c''è chi mi ha voluto bene, e a loro un grazie enorme. agli altri un sorriso 🙂'),
  ('giocatore_amaro', 'mi mancheranno tante cose, non tutte. forza {X}'),
  ('giocatore_amaro', 'nuova squadra, stessa fame. {X} 🔥'),
  ('giocatore_sereno', 'grazie a tutti: compagni, mister e tifosi. è stato un onore indossare questa maglia. ora nuova sfida con {X}!'),
  ('giocatore_sereno', 'si chiude un capitolo bellissimo. porto con me ricordi indimenticabili. carico per {X} 💪'),
  ('giocatore_sereno', 'grazie per ogni momento passato con {V}. il cuore resterà sempre lì. forza {X} da oggi!'),
  ('giocatore_sereno', 'lascio {V} col sorriso e tanta gratitudine. ora testa e cuore a {X}'),
  ('giocatore_sereno', 'grazie a tutti per questi mesi. nuova avventura, tanta voglia di fare bene con {X} 🔥'),
  ('giocatore_sereno', 'un abbraccio ai compagni e ai tifosi di {V}. ci vediamo in campo, ora forza {X}!'),
  ('giocatore_sereno', 'cambio maglia ma non dimentico niente: grazie {V}. carico per {X}!'),
  ('giocatore_sereno', 'si va! grazie di cuore a chi mi ha voluto bene. da oggi con {X} per dare il massimo'),
  ('giocatore_sereno', 'che bella esperienza è stata. grazie {V}. ora sono felicissimo di essere qui, forza {X}!'),
  ('giocatore_sereno', 'tanta emozione nel salutare {V}. ora solo voglia di ripartire con {X} 💪'),
  ('giocatore_sereno', 'raga che dire, grazie. {V} sarà sempre casa. ora via con {X}!'),
  ('giocatore_sereno', 'un grazie enorme a {V}. è stata una bella tappa. ora {X}, andiamo! 🚀'),
  ('giocatore_sereno', 'saluto lo spogliatoio con un nodo in gola ma tanta felicità. forza {X}'),
  ('giocatore_sereno', 'nuova avventura, stessa voglia di sempre. grazie {V}, forza {X}!'),
  ('giocatore_sereno', 'fratelli di {V}, grazie di tutto. ci vediamo presto. adesso {X} 🔥'),
  ('giocatore_sereno', 'emozionante salutare {V}, ma altrettanto emozionante iniziare con {X}. si parte!'),
  ('giocatore_sereno', 'grazie dell''affetto di questi mesi. continuo a dare tutto, ora con {X}'),
  ('giocatore_sereno', 'avete reso questi mesi speciali, {V}. un abbraccio a tutti. {X} ci siamo!'),
  ('giocatore_sereno', 'non è un addio, è un arrivederci {V}. grazie di tutto!'),
  ('giocatore_sereno', 'ho imparato tanto qui. grazie {V}. ora una nuova sfida con {X} 💪'),
  ('giocatore_sereno', 'nuova maglia, nuova energia. grazie {V}, forza {X}!'),
  ('giocatore_sereno', 'si cambia aria ma il cuore resta. grazie {V}'),
  ('giocatore_sereno', 'che mesi. grazie {V}, vi voglio bene. ora {X}, carico!'),
  ('giocatore_sereno', 'un saluto a tutta {V}: siete stati fantastici. ora tutto il mio impegno va a {X}'),
  ('giocatore_sereno', 'orgoglioso di aver indossato quella maglia. grazie {V}. ora {X}, andiamo!'),
  ('giocatore_sereno', 'grazie a compagni e staff di {V}. felicissimo di iniziare con {X}'),
  ('giocatore_sereno', 'sono contento: nuova casa, nuovi obiettivi. grazie {V}, forza {X} 🙌'),
  ('giocatore_sereno', 'porto con me tutto quello che ho imparato da voi {V}. ora il meglio per {X}'),
  ('giocatore_sereno', 'ci vediamo in campo, ma intanto grazie {V}. {X} pronto a spaccare!'),
  ('giocatore_sereno', 'un bacio ai tifosi di {V}. si ricomincia con {X}, più carico che mai!');

delete from private.frasi_commenti;
insert into private.frasi_commenti (categoria, testo) values
  ('sotto_giornale', 'se il mister risponde bene io firmo subito {S} ✍️'),
  ('sotto_giornale', 'giornalisti sempre sul pezzo, bravi. noi sempre con {S}!'),
  ('sotto_giornale', 'la domanda giusta al momento giusto {S}'),
  ('sotto_giornale', 'basta chiacchiere, parlate di campo {S} ⚽'),
  ('sotto_giornale', 'su questo il mister dovrà dare spiegazioni {S}'),
  ('sotto_giornale', 'io sono convinto che la risposta sia nei risultati {S}'),
  ('sotto_giornale', 'titolo da prima pagina, questa domanda {S} 😅'),
  ('sotto_giornale', 'ai tifosi interessa una cosa: si vince? {S}'),
  ('sotto_giornale', 'domanda dura ma onesta. rispondi mister {S}'),
  ('sotto_giornale', 'ogni volta che parlano di noi mi sale l''ansia {S} 😬'),
  ('sotto_giornale', 'queste interviste le leggo tutte. forza {S}!'),
  ('sotto_giornale', 'il mister non si tira mai indietro, lo so {S} 💪'),
  ('sotto_giornale', 'i giornali ci studiano, segno che siamo forti {S} 😎'),
  ('sotto_giornale', 'voglio una risposta chiara, senza giri di parole {S}'),
  ('sotto_giornale', 'ahahah sta domanda 💀 {S}'),
  ('sotto_giornale', 'no vabbè ma questi giornalisti non hanno altro da chiedere? {S}'),
  ('sotto_giornale', 'finalmente qualcuno che chiede quello che pensiamo tutti {S} 👏'),
  ('sotto_giornale', 'il mister avrà le palle di rispondere? vediamo {S}'),
  ('sotto_giornale', 'domanda scontata, risposta ovvia: forza {S}'),
  ('sotto_giornale', 'che bella domanda... ora voglio sapere {S}'),
  ('sotto_giornale', 'sempre le stesse domande. parlate di calcio vero {S} 🙄'),
  ('sotto_giornale', 'il mister è un fenomeno, risponderà come si deve {S}'),
  ('sotto_giornale', 'mi piace questa stampa, sa dove colpire {S}'),
  ('sotto_giornale', 'leggete bene: non è una critica, è una domanda. vediamo che dice {S}'),
  ('sotto_giornale', 'mister dai, non girarci intorno {S}'),
  ('sotto_giornale', 'siamo sotto i riflettori, e questo è bello {S}'),
  ('sotto_giornale', 'se il mister è sincero, ci siamo {S}'),
  ('sotto_giornale', 'la verità è nel campo, non nelle interviste. forza {S}'),
  ('sotto_giornale', 'che domanda tosta. voglio vedere come se la cava {S} 👀'),
  ('sotto_giornale', 'sembra una domanda facile, non lo è affatto {S}'),
  ('compagno_gol_assist', 'grande {NOME}! l''assist era mio ma il gol è tuo 😎'),
  ('compagno_gol_assist', 'ti ho dato il pallone, tu hai fatto il resto. bravo {NOME}!'),
  ('compagno_gol_assist', '{NOME} sempre al posto giusto, io faccio solo i cross 😂'),
  ('compagno_gol_assist', 'che coppia siamo, {NOME}! ancora insieme 🔥'),
  ('compagno_gol_assist', 'gol tuo, merito mio. offri tu la cena {NOME} 🍝'),
  ('compagno_gol_assist', 'bella partita {NOME}. avanti così fratè 💪'),
  ('compagno_gol_assist', 'ti ho visto smarcarti e non ho avuto dubbi {NOME}!'),
  ('compagno_gol_assist', 'che goduria servirti {NOME}. si replica domenica? 😏'),
  ('compagno_gol_assist', 'eri lì e io lo sapevo {NOME}. sei un killer ⚽'),
  ('compagno_gol_assist', 'l''assist più facile della mia vita. bravo {NOME}!'),
  ('compagno_gol_assist', '{NOME} segna, io servo. equilibrio perfetto 😄'),
  ('compagno_gol_assist', 'l''ho vista partire e ho pensato ''è di {NOME}'' 😂'),
  ('compagno_gol_assist', 'gol meritato {NOME}. anche l''assist non era male eh 😉'),
  ('compagno_gol_assist', 'che gioia giocare con {NOME}! il pallone lo ama ❤️'),
  ('compagno_gol_assist', 'cross perfetto, finalizzazione perfetta. bravi noi {NOME}! 🙌'),
  ('compagno_gol_assist', 'quando la palla arriva a {NOME} è già gol. fiducia totale'),
  ('compagno_gol_assist', 'ti ho servito il gol su un piatto d''argento {NOME} 🍽️'),
  ('compagno_gol_assist', 'sono fiero dell''intesa con {NOME}. ci riproviamo? 💥'),
  ('compagno_gol_assist', 'il merito è di {NOME}. io ho solo portato la palla 😊'),
  ('compagno_gol_assist', 'un''azione da manuale. {NOME} il bomber, io il regista 😎'),
  ('compagno_gol_assist', '{NOME} ti ho fatto un regalo, vedi di ricordartene 😂'),
  ('compagno_gol_assist', 'questo assist vale più del gol {NOME} 😌'),
  ('compagno_gol_assist', 'l''intesa con {NOME} è telepatia pura'),
  ('compagno_gol_assist', 'non so come fai {NOME}, ma ti trovo sempre 🔥'),
  ('compagno_gol_assist', 'un mio passaggio, un tuo gol. il calcio è semplice {NOME}'),
  ('compagno_gol_assist', 'stasera siamo stati un orologio {NOME} 🕰️'),
  ('compagno_gol_assist', '{NOME} bomber di razza, e io il suo fornitore ufficiale 😎'),
  ('compagno_gol_assist', 'quando segni tu, esulto io. ma l''assist è mio {NOME} 😂'),
  ('compagno_gol_assist', 'grande gol {NOME}, ora offri da bere 🍻'),
  ('compagno_gol_assist', '{NOME} ti voglio bene, ma l''assist è mio e lo scrivo ovunque 😂'),
  ('compagno_gol', 'grande {NOME}! che gol! 🔥'),
  ('compagno_gol', 'sei un mostro {NOME}, ti voglio bene 💪'),
  ('compagno_gol', 'siamo tutti con te {NOME}. avanti così!'),
  ('compagno_gol', 'bel gol {NOME}! ora la prossima tocca a me 😂'),
  ('compagno_gol', 'sempre decisivo {NOME}. orgoglioso di giocare con te ⚽'),
  ('compagno_gol', 'che squadra siamo! bravo {NOME}, e bravi tutti 🙌'),
  ('compagno_gol', 'gol bellissimo {NOME}, ma l''abbraccio lo voglio io 😄'),
  ('compagno_gol', '{NOME} non sbaglia mai quando conta. grandissimo!'),
  ('compagno_gol', 'questa è la nostra forza: il gruppo. bravo {NOME}!'),
  ('compagno_gol', 'complimenti {NOME}, te lo meriti tutto 👏'),
  ('compagno_gol', 'raga ma {NOME} è un fenomeno o sbaglio? 🔥'),
  ('compagno_gol', '{NOME} ha fatto una roba da matti. bravo fratè!'),
  ('compagno_gol', '{NOME} è on fire. ci siamo capiti 🔥'),
  ('compagno_gol', 'che istinto, {NOME}! ti stimo tanto 👏'),
  ('compagno_gol', '{NOME}, sei un esempio per tutti noi. grande!'),
  ('compagno_gol', 'l''abbraccio più forte è per {NOME}, stasera hai deciso tu 🫶'),
  ('compagno_gol', 'gol che pesa, {NOME}. siamo tutti con te!'),
  ('compagno_gol', 'questa squadra ha un bomber. si chiama {NOME} 🔥'),
  ('compagno_gol', 'vederti segnare mi dà energia {NOME}. grazie!'),
  ('compagno_gol', '{NOME} ha fatto un gol da incorniciare. bravissimo!'),
  ('compagno_gol', 'ci voleva proprio {NOME}. grande testa, grande piede ⚽'),
  ('compagno_gol', 'sempre sul pezzo {NOME}. un orgoglio averti in squadra'),
  ('compagno_gol', 'bravo {NOME}! domani si riposa, domenica si ricomincia 💥'),
  ('compagno_gol', '{NOME} stasera aura infinita 😎'),
  ('compagno_gol', 'che gol {NOME}, madonna. standing ovation 👏'),
  ('compagno_gol', '{NOME} mostro. non c''è altro da dire 🔥'),
  ('compagno_gol', 'complimenti {NOME}. ma ora lasciaci un po'' di gloria 😂'),
  ('compagno_gol', '{NOME} segna e noi godiamo. semplice così ❤️'),
  ('compagno_gol', 'il nostro {NOME}! 💪 questi sono i gol che amo'),
  ('compagno_gol', '{NOME} sei una bestia. grazie per la serata 🙏'),
  ('fan_gol', '{NOME} ti voglio bene!! gol pazzesco {S} ❤️'),
  ('fan_gol', 'madonna {NOME}, che gol! la curva esplode {S} 🔥'),
  ('fan_gol', 'sei il nostro orgoglio {NOME}. avanti {S}!'),
  ('fan_gol', 'altro gol di {NOME}: la mia domenica è perfetta 😍 {S}'),
  ('fan_gol', '{NOME} ci fa sognare ogni settimana. grazie {S}!'),
  ('fan_gol', 'non so come faremmo senza {NOME}. forza {S} 💪'),
  ('fan_gol', 'gol da pelle d''oca {NOME}. grande {S}!'),
  ('fan_gol', '{NOME} segna e io mi emoziono. sempre {S} ❤️'),
  ('fan_gol', 'vai {NOME}!! un altro gol per la storia di {S} 🏆'),
  ('fan_gol', 'questo ragazzo è un fenomeno. {NOME} {S} per sempre!'),
  ('fan_gol', 'che classe {NOME}. siamo fortunati ad averti {S} 😍'),
  ('fan_gol', '{NOME} sei un grande. il cuore è tutto per {S}!'),
  ('fan_gol', 'con {NOME} in campo mi sento al sicuro {S} 💪'),
  ('fan_gol', 'quanto sei forte {NOME}! orgogliosi di te {S}'),
  ('fan_gol', 'sempre decisivo {NOME}, sempre. grazie {S}!'),
  ('fan_gol', '{NOME} mi ha fatto urlare dal divano. grazie {S} 😂'),
  ('fan_gol', 'ogni tuo gol mi dà una gioia incredibile {NOME} {S} 🙏'),
  ('fan_gol', 'niente da dire, {NOME} è il migliore. forza {S}!'),
  ('fan_gol', 'questo gol vale doppio {NOME}. grande {S}!'),
  ('fan_gol', 'ti amiamo {NOME}! avanti così {S} 🔥'),
  ('fan_gol', '{NOME} bestiale. punto. {S}'),
  ('fan_gol', 'che roba {NOME}, che roba!! {S} 🤯'),
  ('fan_gol', '{NOME} fai quello che vuoi, sei il nostro idolo {S}'),
  ('fan_gol', '{NOME} stasera aura infinita. daje {S} 😎'),
  ('fan_gol', 'altro che fortuna, {NOME} è un campione vero {S}'),
  ('fan_gol', '{NOME} io per te mi tatuo la maglia {S} 😂'),
  ('fan_gol', '{NOME} gol di un altro livello. grazie {S} 🙌'),
  ('fan_gol', 'se segna {NOME} si vince, è una legge {S}'),
  ('fan_gol', '{NOME} il nostro eroe. {S} 🔥'),
  ('fan_gol', 'grande {NOME}!!! non smettere mai {S} ❤️'),
  ('rivale_gol', 'bel gol {NOME}, ma il ritorno lo vinciamo noi {S}'),
  ('rivale_gol', 'gol facile, {NOME}. vediamo se lo rifai con noi 😏'),
  ('rivale_gol', 'godetevi la serata, poi ci rivediamo {S}'),
  ('rivale_gol', 'bel gol {NOME}, devo dirlo. ma non vincerete sempre {S}'),
  ('rivale_gol', 'ridete ridete, tanto il campionato è lungo {S} 😤'),
  ('rivale_gol', 'complimenti {NOME}, ma la prossima ve la facciamo pagare {S}'),
  ('rivale_gol', 'fortuna sfacciata {S}. il ritorno sarà un''altra storia'),
  ('rivale_gol', 'ok {NOME} oggi vi è andata bene, godetevela finché dura {S}'),
  ('rivale_gol', 'mi rode, lo ammetto. bravo {NOME}, ma non è finita {S}'),
  ('rivale_gol', 'niente da fare, stavolta avete vinto voi. il ritorno è nostro {S} 💪'),
  ('rivale_gol', 'oggi vi sorride il culo, ammettiamolo {S} 😤'),
  ('rivale_gol', 'bravo {NOME}, ma una rondine non fa primavera {S}'),
  ('rivale_gol', 'ok {NOME} ha segnato, tutto il resto è stato brutto {S} 🙄'),
  ('rivale_gol', 'fatevi sentire fra un mese quando ci rivediamo {S}'),
  ('rivale_gol', 'hai segnato {NOME}? ok. continua a sognare {S}'),
  ('rivale_gol', 'sfottete pure, la partita di ritorno la vinciamo noi {S} 😏'),
  ('rivale_gol', 'il gol è bello, il risultato un po'' meno. bravo {NOME} {S}'),
  ('rivale_gol', 'non è finita finché non è finita. {S} ci rivediamo'),
  ('rivale_gol', 'ok vi è andata bene. ma ricordate: il calcio è crudele {S}'),
  ('rivale_gol', 'complimenti {NOME} ma la prossima non vi regaliamo niente {S}'),
  ('rivale_gol', 'bravo {NOME}, ma non montatevi la testa {S}'),
  ('rivale_gol', 'gol bello. sconfitta brutta. ritorno nostro {S} 💀'),
  ('rivale_gol', 'stasera avete avuto fortuna. non succederà più {S}'),
  ('rivale_gol', 'vi lascio questa serata, mi tengo la prossima {S} 😎'),
  ('rivale_gol', '{NOME} gol da campione. me lo dico a denti stretti {S}'),
  ('rivale_gol', 'ridete finché potete {S}. ci vediamo presto 😏'),
  ('rivale_gol', 'sono incazzato ma bravo {NOME}. ritorno nostro {S}'),
  ('rivale_gol', 'occhio {S}: questa ve la ricordiamo. {NOME} sei bravo, ma tranquillo'),
  ('rivale_gol', 'fate pure la festa, noi non dimentichiamo {S} 😤'),
  ('rivale_gol', 'non è finita qui {S}. ci vediamo a campi invertiti'),
  ('saluto_compagno', 'ci mancherai fratè {NOME}. in bocca al lupo! 💪'),
  ('saluto_compagno', 'grande {NOME}, è stato un onore giocare con te. ci vediamo in campo!'),
  ('saluto_compagno', 'mi hai insegnato tanto {NOME}. spacca tutto laggiù 🔥'),
  ('saluto_compagno', 'peccato {NOME}. spogliatoio più povero senza di te 😢'),
  ('saluto_compagno', 'ti voglio bene {NOME}, torna a trovarci! ❤️'),
  ('saluto_compagno', 'in bocca al lupo {NOME}! ci sentiamo dopo la partita 😄'),
  ('saluto_compagno', 'che amico perdiamo, {NOME}. auguri veri 🙌'),
  ('saluto_compagno', '{NOME} sei stato un grande compagno. buona fortuna!'),
  ('saluto_compagno', 'non è un addio, è un arrivederci {NOME} 💪'),
  ('saluto_compagno', 'quando segni contro di noi non esultare troppo eh {NOME} 😂'),
  ('saluto_compagno', '{NOME} raga, mi mancherai davvero. spacca 🔥'),
  ('saluto_compagno', 'fratello {NOME}, grazie di tutto. ci vediamo presto!'),
  ('saluto_compagno', '{NOME} non scomparire, scrivimi quando arrivi 😄'),
  ('saluto_compagno', 'nello spogliatoio mancherà la tua voce {NOME}. a presto!'),
  ('saluto_compagno', 'sei stato un amico prima che un compagno {NOME}. ci vediamo 🫶'),
  ('saluto_compagno', '{NOME} spaccate tutto laggiù. e ricordati di noi 😂'),
  ('saluto_compagno', 'ho giocato con grandi campioni, e tu sei uno di loro {NOME}'),
  ('saluto_compagno', '{NOME} il campo parlerà per te. in bocca al lupo!'),
  ('saluto_compagno', 'un abbraccio forte {NOME}. ci rivediamo presto in campo 🔥'),
  ('saluto_compagno', 'mi mancheranno le tue battute in allenamento {NOME} 😂'),
  ('saluto_compagno', '{NOME} qualunque cosa succeda, sarai sempre uno di noi ❤️'),
  ('saluto_compagno', 'buona fortuna {NOME}! ti seguirò dalla panchina 😉'),
  ('saluto_compagno', 'non sarà facile senza di te {NOME}. ma auguri sinceri'),
  ('saluto_compagno', 'sono sicuro che ti farai amare anche laggiù {NOME} 🙌'),
  ('saluto_compagno', 'grazie per tutto quello che hai dato a questo gruppo {NOME}'),
  ('saluto_compagno', 'sei partito troppo presto {NOME}. ma ti capisco. auguri!'),
  ('saluto_compagno', '{NOME} lascia il segno anche nella nuova squadra 💥'),
  ('saluto_compagno', '{NOME} ci vediamo in campo da avversario. ma oggi un abbraccio ❤️'),
  ('saluto_compagno', 'fra {NOME} ci mancherai tantissimo, davvero 🥲'),
  ('saluto_compagno', 'un pezzo di spogliatoio se ne va con {NOME}. in bocca al lupo!'),
  ('compagno_risposta_amaro', '{NOME}, certe parole potevi risparmiartele. ma ti auguro il meglio.'),
  ('compagno_risposta_amaro', 'ho letto, {NOME}. ne parliamo faccia a faccia, ok?'),
  ('compagno_risposta_amaro', 'nessuno qui ti ha trattato male {NOME}. ci resto male.'),
  ('compagno_risposta_amaro', '{NOME}, chiudiamola senza veleno. in bocca al lupo comunque.'),
  ('compagno_risposta_amaro', 'capisco la tua rabbia {NOME}, ma il gruppo ti vuole bene lo stesso.'),
  ('compagno_risposta_amaro', 'peccato finisca così {NOME}. ti ricorderò per il campo, non per i post.'),
  ('compagno_risposta_amaro', 'chi ha dato tutto, come te e come noi, non ha bisogno di frecciatine {NOME}'),
  ('compagno_risposta_amaro', 'ognuno ha il diritto di dire la sua {NOME}. ma qui siamo uniti.'),
  ('compagno_risposta_amaro', '{NOME}, buona fortuna davvero. il resto lascia il tempo che trova.'),
  ('compagno_risposta_amaro', 'mi dispiace per come è finita {NOME}. ma ti auguro il successo.'),
  ('compagno_risposta_amaro', 'il tuo valore qui non l''ha mai messo in dubbio nessuno {NOME}'),
  ('compagno_risposta_amaro', 'spero che laggiù tu trovi la serenità che cercavi {NOME}'),
  ('compagno_risposta_amaro', 'mi spiace per l''amarezza {NOME}. qualcosa non ha funzionato, ma non per colpa del gruppo.'),
  ('compagno_risposta_amaro', '{NOME}, per te c''è sempre una porta aperta, anche se non la apri'),
  ('compagno_risposta_amaro', 'capisco tutto {NOME}. non serve litigare. ci vediamo in campo 💪'),
  ('compagno_risposta_amaro', 'ti stimo sempre {NOME}, anche se oggi non condivido le tue parole.'),
  ('compagno_risposta_amaro', 'il campo dirà come sono andate le cose {NOME}. intanto in bocca al lupo.'),
  ('compagno_risposta_amaro', 'spero che tu sia felice {NOME}. è tutto quello che conta.'),
  ('compagno_risposta_amaro', 'non c''è cattiveria in questo spogliatoio {NOME}. ci tenevamo a te.'),
  ('compagno_risposta_amaro', 'buona fortuna {NOME}. e pace, di nemici ne abbiamo già abbastanza fuori 😅'),
  ('compagno_risposta_amaro', '{NOME} dai, non facciamone un dramma. ci vediamo in campo 💪'),
  ('compagno_risposta_amaro', 'ognuno ha la sua verità {NOME}. la mia è che ti voglio bene lo stesso.'),
  ('compagno_risposta_amaro', '{NOME} avremmo potuto parlarne prima. peccato davvero.'),
  ('compagno_risposta_amaro', '{NOME} auguri, davvero. ma non era il caso di certe frasi.'),
  ('compagno_risposta_amaro', 'non ti rinfaccio niente {NOME}. buona fortuna 🙏'),
  ('compagno_risposta_amaro', '{NOME}, sappi che qui nessuno ti ha mai fatto sentire solo.'),
  ('compagno_risposta_amaro', 'fratè {NOME}, di queste cose parliamo di persona. in bocca al lupo.'),
  ('compagno_risposta_amaro', '{NOME} la verità la sai tu e la sappiamo noi. pace.'),
  ('compagno_risposta_amaro', 'sei un grande {NOME}, a prescindere dai post. ci vediamo.'),
  ('compagno_risposta_amaro', 'tutto passa {NOME}. in bocca al lupo, il resto lo sistema il campo.'),
  ('fan_addio_sereno', 'grazie di tutto {NOME}! sempre uno di noi ❤️'),
  ('fan_addio_sereno', 'ci mancherai {NOME}. auguri per la nuova avventura con {X}!'),
  ('fan_addio_sereno', 'resta nel cuore {NOME}. grazie {V} per averlo avuto 💪'),
  ('fan_addio_sereno', 'quando torni da avversario ti applaudiamo lo stesso {NOME}'),
  ('fan_addio_sereno', 'che peccato {NOME}. ma ti auguriamo il meglio 🙏'),
  ('fan_addio_sereno', 'mai dimenticherò i tuoi gol {NOME}. grazie!'),
  ('fan_addio_sereno', '{NOME} un esempio di professionalità. in bocca al lupo!'),
  ('fan_addio_sereno', 'ti aspettiamo da avversario {NOME}. ma ti vogliamo bene lo stesso 😄'),
  ('fan_addio_sereno', 'un pezzo di cuore se ne va. grazie {NOME}!'),
  ('fan_addio_sereno', 'buona fortuna {NOME}, ma non farci troppo male quando ci incontriamo 😂'),
  ('fan_addio_sereno', 'non sarà più lo stesso senza {NOME}. grazie di tutto 🥲'),
  ('fan_addio_sereno', '{NOME} sei stato un grande. spacca con {X}!'),
  ('fan_addio_sereno', 'un applauso a {NOME}, signore dentro e fuori dal campo 👏'),
  ('fan_addio_sereno', 'hai dato tanto a {V}, ora vai a prenderti il resto. auguri {NOME}!'),
  ('fan_addio_sereno', 'un abbraccio dalla curva {NOME}. ci rivediamo presto!'),
  ('fan_addio_sereno', '{NOME} per noi sarai sempre un grande. grazie di tutto davvero'),
  ('fan_addio_sereno', 'sarà strano non vederti più con questa maglia {NOME}. ma ti seguiremo 🙏'),
  ('fan_addio_sereno', 'resti nel cuore {NOME}. il resto è solo calcio ❤️'),
  ('fan_addio_sereno', 'un grazie enorme {NOME}. {V} non ti dimenticherà'),
  ('fan_addio_sereno', 'che piacere averti visto con questi colori {NOME}. forza {X}!'),
  ('fan_addio_sereno', 'tutti i tifosi di {V} ti applaudono {NOME}. auguri!'),
  ('fan_addio_sereno', 'da tifoso ti ringrazio {NOME}. hai onorato questa maglia 🙌'),
  ('fan_addio_sereno', '{NOME} qualunque sarà la tua strada, sappi che qui hai casa 🏠'),
  ('fan_addio_sereno', 'che dispiacere! ma tutto il bene possibile a {NOME} con {X}'),
  ('fan_addio_sereno', 'non ti dimenticheremo {NOME}. forza {X}, e che sia una grande stagione!'),
  ('fan_addio_sereno', 'ci mancherai tantissimo {NOME}. ma sei sempre dei nostri ❤️'),
  ('fan_addio_sereno', 'grazie per ogni emozione {NOME}. ci vediamo in giro 😄'),
  ('fan_addio_sereno', '{NOME} ti voglio bene. spacca con {X}!'),
  ('fan_addio_sereno', 'ciao {NOME}, e grazie per tutti i gol. {X} è fortunata 😢'),
  ('fan_addio_sereno', 'sono triste ma felice per te {NOME}. in bocca al lupo!'),
  ('fan_addio_amaro', 'capisco la rabbia {NOME}, ma i toni potevi evitarli. auguri lo stesso.'),
  ('fan_addio_amaro', 'sei andato via sbattendo la porta {NOME}. peccato, ti stimavamo.'),
  ('fan_addio_amaro', 'chi ama una maglia non fa polemiche quando se ne va {NOME}'),
  ('fan_addio_amaro', 'dispiace {NOME}. ma non puoi dire che nessuno ti abbia voluto bene.'),
  ('fan_addio_amaro', '{NOME}, noi eravamo sempre con te. forse non lo hai visto.'),
  ('fan_addio_amaro', 'ti auguro il meglio {NOME}, ma le frecciatine non ti fanno onore'),
  ('fan_addio_amaro', 'i tifosi non dimenticano i gol, ma nemmeno i toni. ciao {NOME}.'),
  ('fan_addio_amaro', 'se la verità è questa {NOME}, preferisco non saperla. auguri con {X}'),
  ('fan_addio_amaro', 'ognuno ha le sue ragioni {NOME}. noi ne abbiamo molte, e tutte con {V}'),
  ('fan_addio_amaro', 'troppo rumore per un addio {NOME}. peccato davvero.'),
  ('fan_addio_amaro', 'ti ringrazio per quello che hai dato {NOME}, ma i messaggi li potevi evitare'),
  ('fan_addio_amaro', 'ci hai delusi {NOME}. non per l''addio, ma per come l''hai raccontato.'),
  ('fan_addio_amaro', '{NOME}, per chi resta contano i fatti. e noi restiamo, sempre con {V}'),
  ('fan_addio_amaro', 'se non eri felice {NOME}, nessuno ti obbligava a restare. auguri con {X}'),
  ('fan_addio_amaro', 'che tristezza leggere queste cose {NOME}. eravamo tuoi tifosi.'),
  ('fan_addio_amaro', 'bravo {NOME}, bel messaggio. chi ti ha sostenuto ringrazia 🙃'),
  ('fan_addio_amaro', 'la vita va avanti {NOME}. e anche {V}. forza raga!'),
  ('fan_addio_amaro', 'si chiude così {NOME}. pazienza. non c''è rancore, ma nemmeno rimpianto.'),
  ('fan_addio_amaro', '{NOME}, ti sei perso un grande gruppo. peggio per te 🙂'),
  ('fan_addio_amaro', 'noi tifiamo {V}, non singoli giocatori. ciao {NOME}, in bocca al lupo.'),
  ('fan_addio_amaro', '{NOME} ma le polemiche proprio ora? ci stavamo anche ai gol 🤦'),
  ('fan_addio_amaro', 'ognuno racconta la sua verità. noi ci teniamo la nostra {NOME}'),
  ('fan_addio_amaro', 'non ti rimpiangiamo {NOME}. ma ti auguriamo il meglio comunque'),
  ('fan_addio_amaro', 'quanta amarezza {NOME}... spero che con {X} tu stia meglio'),
  ('fan_addio_amaro', 'ciao {NOME}. noi restiamo qui, a tifare {V} come sempre.'),
  ('fan_addio_amaro', 'dai {NOME}, nessuno ti ha mai fatto del male. smettila con le frecciatine'),
  ('fan_addio_amaro', '{NOME} andare è un diritto, offendere no. auguri lo stesso'),
  ('fan_addio_amaro', 'quanto rumore per un addio {NOME}. buona fortuna 🙃'),
  ('fan_addio_amaro', '{NOME} un grazie per i gol, un ciao per il resto. forza {V}!'),
  ('fan_addio_amaro', 'ce ne faremo una ragione {NOME}. forza {V}, avanti 💪'),
  ('sotto_risultato_vince', 'che serata!! {F}-{G} e si vola. forza {S} 🔥'),
  ('sotto_risultato_vince', 'tre punti d''oro contro {O}. orgoglio {S}!'),
  ('sotto_risultato_vince', 'sempre con voi {S}! che squadra!'),
  ('sotto_risultato_vince', 'così si fa raga. avanti {S} 💪'),
  ('sotto_risultato_vince', 'notte da ricordare. {S} grandissimi ❤️'),
  ('sotto_risultato_vince', 'vittoria meritata. {O} non ha avuto scampo, forza {S}!'),
  ('sotto_risultato_vince', 'bravi tutti, giocatori e tifosi. {S} per sempre 🙌'),
  ('sotto_risultato_vince', 'questo è il livello che ci aspettiamo. complimenti {S}!'),
  ('sotto_risultato_vince', 'che spettacolo {S}, ci siamo divertiti un sacco 😍'),
  ('sotto_risultato_vince', 'un altro passo avanti. continuate così {S}!'),
  ('sotto_risultato_vince', 'madonna che gioia. {S} 🔥'),
  ('sotto_risultato_vince', 'siamo in forma, e si vede. {S} avanti così 💪'),
  ('sotto_risultato_vince', '{F}-{G} e passa la paura. grazie {S} 🙏'),
  ('sotto_risultato_vince', 'daje {S}! ancora ancora 🔥'),
  ('sotto_risultato_vince', '{O} ko e noi sul divano a godere. {S} 😎'),
  ('sotto_risultato_vince', 'i miei complimenti alla squadra, davvero {S} 👏'),
  ('sotto_risultato_vince', 'una vittoria che fa bene al cuore. {S} ❤️'),
  ('sotto_risultato_vince', 'stasera si dorme felici. grazie {S}!'),
  ('sotto_risultato_vince', 'quanto è bello vincere. {S} sempre nel cuore'),
  ('sotto_risultato_vince', 'che spettacolo di squadra. {S} 🙌'),
  ('sotto_risultato_vince', 'se giochiamo così ce la giochiamo con tutti {S}'),
  ('sotto_risultato_vince', 'serata perfetta. {S} 🔥'),
  ('sotto_risultato_vince', '{S} ha giocato da grande squadra. complimenti {O}, ma oggi no'),
  ('sotto_risultato_vince', 'vittoria che vale doppio. {S} ❤️'),
  ('sotto_risultato_vince', 'questa squadra mi emoziona ogni volta. grazie {S}'),
  ('sotto_risultato_vince', 'che gioia ragazzi. {S} {F}-{G} ❤️'),
  ('sotto_risultato_vince', 'campioni, ecco cosa siete. {S} 🏆'),
  ('sotto_risultato_vince', 'grandissimi! {S} oggi sul pezzo'),
  ('sotto_risultato_vince', 'finalmente una vittoria da urlo. {S} 🔥'),
  ('sotto_risultato_vince', 'bellissimo vedervi così. {S} avanti!'),
  ('sotto_risultato_perde', 'oggi non è andata, ma ci rialziamo. forza {S} ❤️'),
  ('sotto_risultato_perde', 'complimenti a {O}, ma noi non molliamo mai {S} 💪'),
  ('sotto_risultato_perde', 'giornata storta. si riparte subito {S}!'),
  ('sotto_risultato_perde', 'brucia, ma i veri tifosi restano. sempre con voi {S}'),
  ('sotto_risultato_perde', 'il campionato è lungo, la risposta la diamo in campo {S}'),
  ('sotto_risultato_perde', 'che amarezza. spero in una reazione {S} 😔'),
  ('sotto_risultato_perde', 'sconfitta dura da digerire. ora testa bassa e lavoro {S}'),
  ('sotto_risultato_perde', 'non è finita finché non è finita. avanti {S}!'),
  ('sotto_risultato_perde', 'meritavamo di più secondo me. forza raga {S}'),
  ('sotto_risultato_perde', 'una partita storta non cancella tutto. con voi sempre {S}'),
  ('sotto_risultato_perde', 'che rabbia. ma domani è un altro giorno {S}'),
  ('sotto_risultato_perde', 'mi sanguina il cuore, ma il tifo è il tifo {S} ❤️'),
  ('sotto_risultato_perde', '{F}-{G}. non ci rappresenta. {S} ci rialziamo'),
  ('sotto_risultato_perde', 'fa male, non lo nascondo. ma resto con voi {S}'),
  ('sotto_risultato_perde', 'serata no. capita. {S} testa alla prossima'),
  ('sotto_risultato_perde', 'che peccato davvero. {S} ci siamo ancora'),
  ('sotto_risultato_perde', 'un passo indietro, ma poi due avanti. {S} 💪'),
  ('sotto_risultato_perde', 'complimenti {O}. ora tocca a noi dimostrare chi siamo {S}'),
  ('sotto_risultato_perde', 'non siamo questi, e lo sapete. {S}'),
  ('sotto_risultato_perde', 'oggi ha vinto {O}, domani vediamo {S}'),
  ('sotto_risultato_perde', 'ho il magone, ma si va avanti. {S} 🙏'),
  ('sotto_risultato_perde', 'è dura, ma non molliamo mai. {S}'),
  ('sotto_risultato_perde', 'una sconfitta non cancella tutto quello che avete fatto {S}'),
  ('sotto_risultato_perde', 'male ma non morti. {S} 💪'),
  ('sotto_risultato_perde', '{S} reazione immediata, prego. grazie.'),
  ('sotto_risultato_perde', 'la fede non si tocca, i risultati sì. forza {S}'),
  ('sotto_risultato_perde', 'che serata difficile. {S} domani passa'),
  ('sotto_risultato_perde', '{O} è stato più bravo oggi. rialziamoci {S}'),
  ('sotto_risultato_perde', 'mi dispiace per voi ragazzi. {S} sempre con voi'),
  ('sotto_risultato_perde', 'brutta, ma ci ripigliamo. {S} 🙏'),
  ('sotto_pareggio', 'un punto a testa, ma io volevo vincere. forza {S}!'),
  ('sotto_pareggio', 'pareggio che lascia l''amaro in bocca {S}'),
  ('sotto_pareggio', 'meglio di niente contro {O}. ora si torna a vincere {S}'),
  ('sotto_pareggio', 'partita equilibrata, risultato giusto. avanti {S}'),
  ('sotto_pareggio', 'si poteva fare di più. dai {S} 💪'),
  ('sotto_pareggio', 'un pari che serve a poco. alla prossima {S}'),
  ('sotto_pareggio', 'non è un brutto risultato, ma non basta {S}'),
  ('sotto_pareggio', 'punto d''oro o occasione persa? dipende da come la si guarda {S}'),
  ('sotto_pareggio', '{O} ha tenuto botta, complimenti. ma torniamo a vincere {S}'),
  ('sotto_pareggio', 'alla fine va bene così. adesso concentriamoci sulla prossima {S}'),
  ('sotto_pareggio', 'boh. pareggio. {S}'),
  ('sotto_pareggio', 'né carne né pesce. {S} dai'),
  ('sotto_pareggio', 'ci stava anche vincere onestamente {S}'),
  ('sotto_pareggio', 'un punto fa classifica, ma non fa felici {S}'),
  ('sotto_pareggio', 'partita pallosa, risultato inevitabile. {S} 🥱'),
  ('sotto_pareggio', 'sul pari non mi esalto. {S}'),
  ('sotto_pareggio', 'uno a testa, ognuno a casa. {S} avanti'),
  ('sotto_pareggio', 'dai {S}, la prossima si vince 💪'),
  ('sotto_pareggio', 'occasione persa. {S}'),
  ('sotto_pareggio', '{O} dura da battere, alla fine ci stiamo. {S}'),
  ('sotto_pareggio', 'non ci lamentiamo, ma serve di più. {S}'),
  ('sotto_pareggio', 'un punto in più è meglio di niente. {S}'),
  ('sotto_pareggio', 'vediamo di rialzare il livello. {S} 😤'),
  ('sotto_pareggio', '{S} sveglia! tutti a casa con un punto... meh'),
  ('sotto_pareggio', 'questo punto peserà alla fine. {S}'),
  ('sotto_pareggio', 'pari giusto, nessun rimpianto. {S}'),
  ('sotto_pareggio', 'dobbiamo vincere queste partite. {S}'),
  ('sotto_pareggio', '{O} ha giocato bene, ma noi di più. {S} 😏'),
  ('sotto_pareggio', 'pareggio onesto, niente di più. {S}'),
  ('sotto_pareggio', 'contro {O} meglio di così non si poteva. {S}'),
  ('sotto_scambio', 'finalmente un po'' di movimento! vediamo che succede {A} {B} 👀'),
  ('sotto_scambio', 'scambio interessante, speriamo bene per tutti 🤞'),
  ('sotto_scambio', 'da tifoso dico: aspettiamo il campo prima di giudicare {A}'),
  ('sotto_scambio', '{B} ha fatto un bel colpo, o almeno spero 😅'),
  ('sotto_scambio', 'ogni scambio è una scommessa. che vinca il migliore {A} {B}'),
  ('sotto_scambio', 'il mercato non perdona mai. vedremo chi ha ragione.'),
  ('sotto_scambio', 'brava la dirigenza a muoversi. ora tocca al campo {A} {B}'),
  ('sotto_scambio', 'non mi convince del tutto ma mi fido {A}'),
  ('sotto_scambio', 'due squadre, due strategie. interessante {A} {B}'),
  ('sotto_scambio', 'here we go e speriamo che sia l''affare giusto 😎'),
  ('sotto_scambio', 'no vabbè che scambio. {A} {B} 👀'),
  ('sotto_scambio', 'io intanto metto il popcorn. {A} {B} 🍿'),
  ('sotto_scambio', 'il campo dirà chi ha vinto, per ora boh {A} {B}'),
  ('sotto_scambio', '{A} e {B} si sono mosse, e io sono curioso'),
  ('sotto_scambio', 'qualcuno ha fatto un affare, qualcuno no. ma chi? {A} {B}'),
  ('sotto_scambio', 'spero davvero che sia la mossa giusta {A} 🙏'),
  ('sotto_scambio', 'mercato animato, mi piace {A} {B}'),
  ('sotto_scambio', 'scambio che fa discutere, come piace a me {A} {B}'),
  ('sotto_scambio', 'da questa mossa dipende parecchio. {A} {B}'),
  ('sotto_scambio', '{B} sembra aver colpito meglio, ma vedremo {A}'),
  ('sotto_scambio', '{A} coraggiosa, come sempre. speriamo bene'),
  ('sotto_scambio', 'il mercato non dorme mai. {A} {B}'),
  ('sotto_scambio', 'scambio con un pizzico di follia, mi piace {A} {B} 😅'),
  ('sotto_scambio', 'non so chi ha vinto ma mi diverto {A} {B}'),
  ('sotto_scambio', 'se funziona sono geni, altrimenti li mandiamo a casa {A} {B} 😂'),
  ('sotto_scambio', 'qui qualcuno ha scommesso grosso. {A} {B}'),
  ('sotto_scambio', 'la dirigenza ha parlato. ora parli il campo {A} {B}'),
  ('sotto_scambio', 'un po'' di coraggio fa bene al calcio {A} {B}'),
  ('sotto_scambio', 'interessante per tutti e due. vediamo {A} {B} 👀'),
  ('sotto_scambio', 'here we go. e adesso si gioca {A} {B}'),
  ('sotto_asta', 'che bel colpo! benvenuto in famiglia {S} ❤️'),
  ('sotto_asta', 'rinforzo che aspettavamo, bravi {S} 👏'),
  ('sotto_asta', 'finalmente qualcuno di valido! forza {S}'),
  ('sotto_asta', 'ottimo acquisto, mi piace molto {S} 🔥'),
  ('sotto_asta', 'con questo arrivo ci divertiamo {S}'),
  ('sotto_asta', 'ho fiducia: sarà un grande innesto {S}'),
  ('sotto_asta', 'mercato intelligente, bravi {S} 💪'),
  ('sotto_asta', 'benvenuto! fai vedere di che pasta sei fatto {S}'),
  ('sotto_asta', 'se è davvero forte come dicono, sarà un''estate bollente {S}'),
  ('sotto_asta', 'un''altra pedina importante per {S}. bravi!'),
  ('sotto_asta', 'mi piace la direzione che stiamo prendendo {S} 🙌'),
  ('sotto_asta', 'colpo da maestri {S}. complimenti alla società'),
  ('sotto_asta', 'adesso sì che la squadra è più completa {S}'),
  ('sotto_asta', 'mi aspetto grandi cose, benvenuto {S}!'),
  ('sotto_asta', 'rinforzo azzeccato direi {S} 😎'),
  ('sotto_asta', 'quanto ci serviva uno così! forza {S}'),
  ('sotto_asta', 'mercato che mi convince finalmente {S}'),
  ('sotto_asta', 'il tifo ti aspetta a braccia aperte {S} ❤️'),
  ('sotto_asta', 'ora si ragiona. bravi {S}!'),
  ('sotto_asta', 'che soddisfazione vedere questo arrivo. avanti {S} 💥'),
  ('sotto_asta', 'dai che si inizia a fare sul serio. {S}'),
  ('sotto_asta', 'benvenuto raga! facci sognare {S} 🔥'),
  ('sotto_asta', 'colpo di mercato, punto. {S} 💪'),
  ('sotto_asta', 'un nuovo arrivo che mi gasa. avanti {S}!'),
  ('sotto_asta', 'che dire, benvenuto in famiglia {S} ❤️'),
  ('sotto_asta', 'finalmente rinforzi veri. daje {S}'),
  ('sotto_asta', 'questo acquisto vale oro {S} 💰'),
  ('sotto_asta', 'bravi {S}, avete fiutato l''affare 👏'),
  ('sotto_asta', 'mercato mica male. {S} avanti così'),
  ('sotto_asta', 'benvenuto nuovo arrivo, ora tocca a te {S} 🙌'),
  ('sotto_allenatore', 'il mister dice sempre le cose giuste. forza {S}!'),
  ('sotto_allenatore', 'sono d''accordo con il mister. fiducia totale {S} 💪'),
  ('sotto_allenatore', 'troppo diplomatico stavolta mister, ma ti seguiamo {S}'),
  ('sotto_allenatore', 'parole sagge. avanti {S}!'),
  ('sotto_allenatore', 'il mister ha ragione, bisogna lavorare {S}'),
  ('sotto_allenatore', 'così si risponde! bravo mister {S} 👏'),
  ('sotto_allenatore', 'mi fido del mister anche quando non capisco {S}'),
  ('sotto_allenatore', 'il mister ha carattere. {S} è in buone mani'),
  ('sotto_allenatore', 'su questo non sono d''accordo, ma gli voglio bene lo stesso {S} 😅'),
  ('sotto_allenatore', 'chi critica il mister non capisce di calcio {S} 😤'),
  ('sotto_allenatore', 'no vabbè mister che risposta 👏 {S}'),
  ('sotto_allenatore', 'il mister parla poco ma dice cose giuste {S}'),
  ('sotto_allenatore', 'non è facile ma il mister sta lavorando bene {S}'),
  ('sotto_allenatore', 'ottimo mister, ottima risposta. avanti {S} ❤️'),
  ('sotto_allenatore', 'quando parla il mister ascolto sempre {S}'),
  ('sotto_allenatore', 'parole giuste nel momento giusto {S} 🙌'),
  ('sotto_allenatore', 'questo mister ha le idee chiare. forza {S}!'),
  ('sotto_allenatore', 'siamo in buone mani, lo sento {S}'),
  ('sotto_allenatore', 'sulla risposta nulla da dire: bravo mister {S}'),
  ('sotto_allenatore', 'il mister ci mette la faccia, e questo conta {S} 💪'),
  ('sotto_allenatore', 'non so se ha ragione, ma ha coraggio {S}'),
  ('sotto_allenatore', 'il tempo darà ragione al mister {S}'),
  ('sotto_allenatore', 'il mister parla, la squadra risponde in campo. forza {S}!'),
  ('sotto_allenatore', 'ottimo, seguiamolo ancora {S} 🔥'),
  ('sotto_allenatore', 'bravo mister. così si guida un gruppo {S}'),
  ('sotto_allenatore', 'onesto come sempre, mi piace {S}'),
  ('sotto_allenatore', 'tutto giusto. però adesso voglio i fatti {S}'),
  ('sotto_allenatore', 'il mister è un grande, punto {S} ❤️'),
  ('sotto_allenatore', 'qua c''è un mister vero. {S}'),
  ('sotto_allenatore', 'quando il mister risponde così mi fido {S} 💪'),
  ('rival_frecciatina', 'bel gol {NOME}, ma il vero test sarà il ritorno 😏'),
  ('rival_frecciatina', 'sfruttate il vantaggio di oggi {NOME}: domani non ci sarà più 😤'),
  ('rival_frecciatina', '{NOME} ti ricordo che il campionato ha anche una seconda metà 😎'),
  ('rival_frecciatina', 'un gol e già festeggiate? calma {NOME}, la strada è lunga.'),
  ('rival_frecciatina', 'bravo {NOME}, ma il tuo gol non cancella il nostro orgoglio.'),
  ('rival_frecciatina', 'gol di rapina {NOME}. alla prossima vi presentiamo il conto 😏'),
  ('rival_frecciatina', 'ti godi la serata {NOME}? fai bene, perché il ritorno è un''altra storia.'),
  ('rival_frecciatina', '{NOME} stasera vi è andata bene. non capiterà sempre.'),
  ('rival_frecciatina', 'complimenti sinceri {NOME}, ma non siamo qui a regalare nulla.'),
  ('rival_frecciatina', '{NOME} le partite si giocano in due. il ritorno è tutto nostro 🔥'),
  ('rival_frecciatina', 'esulta pure {NOME}. noi ci rivediamo con calma.'),
  ('rival_frecciatina', 'non montarti la testa {NOME}. gli equilibri cambiano 😤'),
  ('rival_frecciatina', 'ricorda {NOME}: non vince chi ride oggi, ma chi ride a maggio.'),
  ('rival_frecciatina', 'un gol per {S} non è la fine del mondo. ci vediamo al ritorno {NOME}'),
  ('rival_frecciatina', 'ottimo gol {NOME}, ma la vendetta è un piatto che si serve freddo 😎'),
  ('rival_frecciatina', 'un bel gol {NOME}. peccato sia servito a così poco.'),
  ('rival_frecciatina', 'ridi finché puoi {NOME}. il ritorno ti aspetta.'),
  ('rival_frecciatina', 'non è finita {NOME}. chi ha vinto oggi può perdere domani.'),
  ('rival_frecciatina', 'sei stato bravo {NOME}. ma non scordare chi ha vinto lo scorso anno 😏'),
  ('rival_frecciatina', 'questo gol lo ricorderai poco {NOME}. il ritorno lo ricorderò io 😤'),
  ('rival_frecciatina', '{NOME} godetevela. per ora 😏'),
  ('rival_frecciatina', '{NOME} bravo bravo. ora però non farti prendere dall''aura 💀'),
  ('rival_frecciatina', 'questa ve la lasciamo {NOME}. la prossima no.'),
  ('rival_frecciatina', '{NOME} sono contento per te. un po'' meno per {S} 😅'),
  ('rival_frecciatina', 'complimenti {NOME}, davvero. ma tienilo per te il sorriso'),
  ('rival_frecciatina', 'aspetta il ritorno {NOME}, poi ne riparliamo 😎'),
  ('rival_frecciatina', 'tutto bello {NOME}. ma il bello deve ancora venire.'),
  ('rival_frecciatina', '{NOME} segni oggi, piangi domani 😏'),
  ('rival_frecciatina', 'la prossima volta avrete più difficoltà {NOME}, fidati.'),
  ('rival_frecciatina', 'occhio {NOME}: la rivincita arriva sempre.'),
  ('rival_replica', 'vieni pure al ritorno {NOME}: l''avversario preferito 😏'),
  ('rival_replica', 'ti ricordo che sono io ad aver segnato {NOME}. il resto sono parole.'),
  ('rival_replica', 'sarà un piacere rifarlo al ritorno {NOME} ⚽'),
  ('rival_replica', '{NOME} chi ha il pallino del gioco ha anche il vantaggio. ricordalo 😎'),
  ('rival_replica', 'tranquillo {NOME}, ti ho già dedicato il prossimo gol.'),
  ('rival_replica', 'i fatti contano più dei post {NOME}. tabellino alla mano.'),
  ('rival_replica', 'il ritorno lo aspetto più di te {NOME}, non preoccuparti 🔥'),
  ('rival_replica', 'hai detto bene {NOME}: non finisce qui. ma intanto il risultato è questo 😉'),
  ('rival_replica', 'quando vuoi {NOME}. io sono sempre pronto.'),
  ('rival_replica', 'parla chi ha perso {NOME}. chi ha vinto fa gol ⚽'),
  ('rival_replica', 'sono sereno {NOME}. e anche in vantaggio 😌'),
  ('rival_replica', 'aspetto il ritorno con piacere {NOME}. porta anche i tuoi tifosi.'),
  ('rival_replica', '{NOME} non mi spaventano le parole. mi interessano i punti 💪'),
  ('rival_replica', 'le tue minacce mi fanno solo ridere {NOME} 😂'),
  ('rival_replica', 'segnerò anche al ritorno {NOME}. prenditi un portiere nuovo.'),
  ('rival_replica', 'mi piace la rivalità {NOME}. fa sempre bene al calcio 🤝'),
  ('rival_replica', 'non c''è nessuna fretta {NOME}. il campo ci rivedrà presto ⚽'),
  ('rival_replica', 'parole al vento {NOME}. ci vediamo il giorno della partita 😏'),
  ('rival_replica', 'sei simpatico {NOME}. ma resti il mio avversario preferito 😎'),
  ('rival_replica', 'che vinca la miglior squadra {NOME}. oggi sono stato io 😉'),
  ('rival_replica', '{NOME} stai tranquillo, il gol di ritorno è già scritto 😎'),
  ('rival_replica', 'aura mia {NOME}: +1000, la tua: -1000 💀'),
  ('rival_replica', '{NOME} ridi ridi, io intanto segno'),
  ('rival_replica', 'accetto la sfida {NOME}. e porto anche il sorriso 😏'),
  ('rival_replica', '{NOME} ti aspetto. e comunque oggi ho vinto io.'),
  ('rival_replica', 'chi ha vinto parla meno {NOME}. io non parlo, segno ⚽'),
  ('rival_replica', '{NOME} sulla carta sembravi forte. sul campo meno 😅'),
  ('rival_replica', 'contate i gol {NOME}, poi ne riparliamo 😉'),
  ('rival_replica', 'avversario preferito {NOME}, ma tu lo sai già.'),
  ('rival_replica', 'se è fortuna, la ripeto al ritorno {NOME} 😎');

-- Il post del giocatore che segna usa frasi nuove, scelte secondo il carattere (bandiera, economia, vittorie).
CREATE OR REPLACE FUNCTION private.social_genera()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nuovi integer := 0;
  v_n integer;
begin
  -- 1. Risultati: l'account della lega (ultimi 3 giorni).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, testo, creato_il)
  select f.league_id, 'partita:' || m.id, 'lega', 'SpecialOne Lega', f.home_team_id, f.away_team_id,
         'FINALE · ' || th.nome || ' ' || m.gol_home || '-' || m.gol_away || ' ' || ta.nome || '. ' ||
         case
           when m.gol_home = 0 and m.gol_away = 0 then private.social_scegli('p' || m.id, array[
             'Tanta tattica e zero gol: le difese vincono la serata.', 'Nessuna rete, tanti rimpianti da una parte e dall''altra.'])
           when m.gol_home = m.gol_away then private.social_scegli('p' || m.id, array[
             'Pari e patta: un punto a testa, e qualcuno recrimina.', 'Si divide la posta, con gol da entrambe le parti.'])
           when abs(m.gol_home - m.gol_away) >= 4 then private.social_scegli('p' || m.id, array[
             'Goleada: ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' non lascia scampo.',
             'Serata da dimenticare per ' || case when m.gol_home > m.gol_away then ta.nome else th.nome end || '.'])
           when abs(m.gol_home - m.gol_away) = 1 then private.social_scegli('p' || m.id, array[
             case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' la spunta di misura.',
             'Tre punti sofferti per ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || '.'])
           else private.social_scegli('p' || m.id, array[
             case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' porta a casa i tre punti con merito.',
             'Vittoria chiara per ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || '.'])
         end,
         m.simulata_il
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  join public.leagues l on l.id = f.league_id and l.conferenze_stampa
  join public.teams th on th.id = f.home_team_id
  join public.teams ta on ta.id = f.away_team_id
  where m.simulata_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 2. Chi segna: il miglior marcatore di ogni squadra pubblica dopo la partita, col tono del suo
  --    carattere (uno per squadra e partita, per non coprire il resto del feed).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
  select distinct on (ms.match_id, ms.team_id) f.league_id, 'gol:' || ms.match_id || ':' || ms.player_instance_id, 'giocatore', p.nome, ms.team_id, ms.player_instance_id,
         case
           when (case when ms.team_id = f.home_team_id then m.gol_home - m.gol_away else m.gol_away - m.gol_home end) < 0
             then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array['il gol non basta. si lavora in settimana per rialzarci.', 'serata amara: segnare non serve se non si vince 😔', 'gol inutile oggi. testa bassa e si riparte', 'non è questa la serata che volevamo. ci rifaremo 💪', 'male. ma ci rialziamo, come sempre.', 'il gol non mi consola. la squadra viene prima.', 'amarezza. ma si va avanti.', 'oggi si perde e il gol conta zero. ci vediamo domenica 😤'])
           when p.mentalita_bandiera >= greatest(p.mentalita_economia, p.mentalita_vittorie) then private.social_scegli('g' || ms.match_id || ms.player_instance_id,
             case when ms.gol >= 2 then array['doppietta con questa maglia addosso: non esiste emozione più grande 😭', 'due gol per questa gente. non ho parole 🔥', 'doppietta! la dedico ai nostri tifosi ❤️', 'doppietta e cuore in gola. grazie raga 🙏'] else array['segnare per questa maglia non ha prezzo. grazie a chi ci ha spinto 🙌', 'questa maglia è tutta la mia vita. grazie ai tifosi per ogni voce ❤️', 'gol per voi, per questa maglia, per questa gente ❤️', 'non c''è sensazione più bella. grazie raga 🙏', 'per questa maglia sempre. punto.', 'il cuore parla sempre prima dei piedi ⚽ grazie tifosi', 'grazie al gruppo, a chi mi ha servito, a chi ci crede 🫶', 'ogni gol è per voi. grazie di esserci 💪'] end)
           when p.mentalita_economia >= p.mentalita_vittorie then private.social_scegli('g' || ms.match_id || ms.player_instance_id,
             case when ms.gol >= 2 then array['doppietta. il lavoro paga, sempre 😎', 'due gol e tanta fatica. ora si pensa alla prossima 💪', 'doppietta: il lavoro ripaga. grazie raga', 'due gol, tre punti, zero chiacchiere 😎'] else array['un gol che fa bene. il lavoro paga, sempre 💪', 'contento del gol, ma testa già alla prossima', 'ho lavorato tanto per questo. grazie a chi ci ha creduto', 'il gol arriva con il lavoro. avanti', 'segnare è bello, ma contano i tre punti', 'soddisfatto, ora concentrati sulla prossima 👊', 'lavoro, costanza, risultati. si va avanti', 'bel gol, ma il merito è del gruppo'] end)
           else private.social_scegli('g' || ms.match_id || ms.player_instance_id,
             case when ms.gol >= 2 then array['doppietta, ma conta vincere. avanti verso gli obiettivi 🔥', 'due gol per il gruppo. ora vogliamo tutto 🏆', 'doppietta e tre punti. adesso la prossima 😎', 'doppietta per la squadra. si punta al massimo 💥'] else array['un gol per la squadra: l''obiettivo è vincere tutto 🏆', 'si vince, si segna, si va avanti. questo è il nostro livello 😎', 'conta solo vincere. il gol è un di più', 'non mi accontento mai. avanti verso gli obiettivi 🔥', 'bel gol, ma abbiamo fame di trofei', 'cresciamo partita dopo partita. ora il prossimo traguardo', 'un gol che serve al progetto. mentalità vincente 💪', 'vincere è l''unica cosa che conta. il resto è contorno'] end)
         end,
         m.simulata_il + interval '1 second'
  from public.match_stats ms
  join public.matches m on m.id = ms.match_id
  join public.fixtures f on f.id = m.fixture_id
  join public.leagues l on l.id = f.league_id and l.conferenze_stampa
  join public.player_instances pi on pi.id = ms.player_instance_id
  join public.players p on p.id = pi.player_id
  where ms.gol >= 1 and m.simulata_il > now() - interval '3 days'
  order by ms.match_id, ms.team_id, ms.gol desc, ms.player_instance_id
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 3. Scambi ufficiali: "HERE WE GO".
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, testo, creato_il)
  select tp.league_id, 'scambio:' || tp.id, 'lega', 'SpecialOne Lega', tp.da_team_id, tp.a_team_id,
         '‼️ HERE WE GO ‼️ Adesso è ufficiale lo scambio tra ' || td.nome || ' e ' || tt.nome || '. ' ||
         td.nome || ' cede ' || coalesce(nullif((
           select string_agg(p.nome, ', ') from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (tp.giocatori_offerti)), ''), 'solo scelte') ||
         '; ' || tt.nome || ' cede ' || coalesce(nullif((
           select string_agg(p.nome, ', ') from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (tp.giocatori_richiesti)), ''), 'solo scelte') || '.',
         tp.risolta_il
  from public.trade_proposals tp
  join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
  join public.teams td on td.id = tp.da_team_id
  join public.teams tt on tt.id = tp.a_team_id
  where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 4. Aste vinte (svincolati e UNDER).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select a.league_id, 'asta:' || a.id, 'lega', 'SpecialOne Lega', a.vincitore_team_id,
         t.nome || ' si aggiudica ' || p.nome || ' per ' || to_char(a.ingaggio_finale / 1000000.0, 'FM990.0') || ' M€.',
         a.risolta_il
  from public.free_agent_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > now() - interval '3 days' and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select a.league_id, 'under:' || a.id, 'lega', 'SpecialOne Lega', a.vincitore_team_id,
         'UNDER · ' || t.nome || ' porta in casa il giovane ' || p.nome || ' per ' || to_char(a.ingaggio_finale / 1000000.0, 'FM990.0') || ' M€.',
         a.risolta_il
  from public.under_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > now() - interval '3 days' and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 5. Conferenze stampa risposte: la domanda della testata, la risposta dell'allenatore
  --    (in risposta alla domanda) e il post dei tifosi (in risposta all'allenatore).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select d.league_id, 'conf-domanda:' || d.id, 'testata', d.giornalista, d.team_id, d.domanda, d.risposta_il - interval '2 seconds'
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  where d.voto is not null and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, in_risposta_a, testo, creato_il)
  select d.league_id, 'conf-risposta:' || d.id, 'allenatore',
         coalesce(nullif(btrim(pr.nome_allenatore), ''), t.nome), d.team_id,
         (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-domanda:' || d.id),
         d.risposta, d.risposta_il - interval '1 second'
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  join public.teams t on t.id = d.team_id
  left join public.profiles pr on pr.user_id = t.user_id
  where d.voto is not null and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
  select d.league_id, 'conf-tifosi:' || d.id, 'tifosi',
         (private.tifoso_finto('conf' || d.id, t.nome)).nome, (private.tifoso_finto('conf' || d.id, t.nome)).handle, d.team_id,
         (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-risposta:' || d.id),
         d.reazione_pubblico, d.risposta_il
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  join public.teams t on t.id = d.team_id
  where d.voto is not null and d.reazione_pubblico is not null and btrim(d.reazione_pubblico) <> ''
    and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 6. Il capitano risponde ai tifosi arrabbiati (protesta forte: pubblico -2 o peggio).
  --    Un buon capitano calma i tifosi: da 0 a +3 punti di pubblico, una volta per protesta.
  with protesta as (
    select d.id as domanda_id, d.league_id, d.team_id, d.risposta_il,
           coalesce(t.capitano, private.capitano_automatico(t.id)) as cap_id,
           (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-tifosi:' || d.id) as post_tifosi
    from public.conferenze_domande d
    join public.leagues l on l.id = d.league_id and l.conferenze_stampa
    join public.teams t on t.id = d.team_id
    where d.voto is not null and coalesce(d.effetto_pubblico, 0) <= -8
      and d.risposta_il > now() - interval '3 days'
  ), inseriti as (
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, in_risposta_a, testo, creato_il)
    select pr.league_id, 'conf-capitano:' || pr.domanda_id, 'giocatore', p.nome, pr.team_id, pi.id, pr.post_tifosi,
           private.social_scegli('cap' || pr.domanda_id, array[
             'Capisco la rabbia, ragazzi. Siamo i primi a volerci rialzare: restateci vicino.',
             'Avete ragione ad arrabbiarvi. Ci rimbocchiamo le maniche, lo promettiamo.',
             'Questa maglia pesa e sappiamo cosa dobbiamo a voi. Si riparte dal campo.']),
           pr.risposta_il + interval '5 seconds'
    from protesta pr
    join public.player_instances pi on pi.id = pr.cap_id and not pi.ritirato
    join public.players p on p.id = pi.player_id
    where pr.post_tifosi is not null
    on conflict (league_id, chiave) do nothing
    returning team_id, player_instance_id
  )
  update public.teams t
     set pubblico = least(100, t.pubblico + 3 * greatest(0, private.qualita_capitano(i.player_instance_id)))
    from inseriti i
   where t.id = i.team_id;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 7. I tifosi commentano il risultato: una persona diversa per squadra e partita, che scrive come
  --    sui social veri (anche qualche parolaccia) e cita la squadra con @.
  -- La frase non si ripete mai nello stesso giorno nella stessa lega (finche' ce ne sono di libere), e nello
  -- stesso giro ogni post prende una frase diversa: si assegnano in ordine da una lista rimescolata ogni giorno.
  with x as (
    select f.league_id, m.id as match_id, m.simulata_il, f.home_team_id as team_id, th.nome, f.away_team_id as avv_id, ta.nome as avv_nome,
           m.gol_home as fatti, m.gol_away as subiti
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      join public.leagues l on l.id = f.league_id and l.conferenze_stampa
      join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
     where m.simulata_il > now() - interval '3 days'
    union all
    select f.league_id, m.id, m.simulata_il, f.away_team_id, ta.nome, f.home_team_id, th.nome, m.gol_away, m.gol_home
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      join public.leagues l on l.id = f.league_id and l.conferenze_stampa
      join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
     where m.simulata_il > now() - interval '3 days'
  ), c as (
    select x.*, case when x.fatti - x.subiti >= 3 then 'goleada' when x.fatti > x.subiti then 'vittoria' when x.fatti = x.subiti then 'pareggio'
                  when x.subiti - x.fatti >= 3 then 'batosta' else 'sconfitta' end as categoria
    from x
    where not exists (select 1 from public.social_posts sp where sp.league_id = x.league_id and sp.chiave = 'tifoso-partita:' || x.match_id || ':' || x.team_id)
  ), r as (
    select c.*, row_number() over (partition by c.league_id, c.categoria order by hashtext(c.match_id::text || ':' || c.team_id)) as n,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_tifosi fr where fr.categoria = c.categoria
          and not exists (select 1 from public.social_posts sp where sp.league_id = c.league_id
                           and sp.frase_origine = 'tifosi:' || fr.id and sp.creato_il > now() - interval '24 hours')) as libere,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_tifosi fr where fr.categoria = c.categoria) as tutte
    from c
  ), s as (
    select r.*, case when coalesce(array_length(r.libere, 1), 0) > 0 then r.libere else r.tutte end as elenco from r
  )
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, team2_id, testo, creato_il, frase_origine)
  select x.league_id, 'tifoso-partita:' || x.match_id || ':' || x.team_id, 'tifosi',
         (private.tifoso_finto('tp' || x.match_id || x.team_id, x.nome)).nome,
         (private.tifoso_finto('tp' || x.match_id || x.team_id, x.nome)).handle,
         x.team_id, x.avv_id,
         replace(replace(replace(replace(fr.testo,
           '{S}', '@' || private.handle_squadra(x.nome)), '{O}', '@' || private.handle_squadra(x.avv_nome)), '{F}', x.fatti::text), '{G}', x.subiti::text),
         x.simulata_il + interval '30 seconds',
         'tifosi:' || fr.id
  from s x
  join private.frasi_tifosi fr on fr.id = x.elenco[1 + (x.n - 1) % array_length(x.elenco, 1)]
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 8. Scambi: i tifosi di ciascuna squadra reagiscono (bene, male o con dubbi a seconda del giocatore migliore
  --    che arriva e di quello che parte), e i giocatori che cambiano squadra salutano: amaro se se ne vanno
  --    scontenti (morale prima dello scambio sotto 45), sereno altrimenti.
  with lati as (
    select tp.id as trade_id, tp.league_id, tp.risolta_il, tp.da_team_id as team_id, tp.a_team_id as altra_id,
           tp.giocatori_offerti as out_ids, tp.giocatori_richiesti as in_ids
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
    union all
    select tp.id, tp.league_id, tp.risolta_il, tp.a_team_id, tp.da_team_id, tp.giocatori_richiesti, tp.giocatori_offerti
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
  ), tifosi as (
    select x.*, case
        when x.out_best is null and x.in_best is null then 'tifosi_neutro'
        when x.in_best is null then case when x.out_best >= 78 then 'tifosi_male' else 'tifosi_neutro' end
        when x.out_best is null then case when x.in_best >= 78 then 'tifosi_bene' else 'tifosi_neutro' end
        when x.in_best >= x.out_best + 3 then 'tifosi_bene'
        when x.out_best >= x.in_best + 3 then 'tifosi_male'
        else 'tifosi_neutro' end as categoria
    from (
      select l.*, t.nome as nome_squadra,
        (select p.nome from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = any (l.out_ids) order by pi.overall_corrente desc, pi.id limit 1) as out_nome,
        (select max(pi.overall_corrente) from public.player_instances pi where pi.id = any (l.out_ids)) as out_best,
        (select p.nome from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = any (l.in_ids) order by pi.overall_corrente desc, pi.id limit 1) as in_nome,
        (select max(pi.overall_corrente) from public.player_instances pi where pi.id = any (l.in_ids)) as in_best
      from lati l join public.teams t on t.id = l.team_id
    ) x
  )
  , t2 as (
    select f.*, row_number() over (partition by f.league_id, f.categoria order by hashtext(f.trade_id::text || ':' || f.team_id)) as n,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_social fr where fr.categoria = f.categoria
          and not exists (select 1 from public.social_posts sp where sp.league_id = f.league_id
                           and sp.frase_origine = 'social:' || fr.id and sp.creato_il > now() - interval '24 hours')) as libere,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_social fr where fr.categoria = f.categoria) as tutte
    from tifosi f
    where not exists (select 1 from public.social_posts sp where sp.league_id = f.league_id and sp.chiave = 'scambio-tifosi:' || f.trade_id || ':' || f.team_id)
  )
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, team2_id, testo, creato_il, frase_origine)
  select f.league_id, 'scambio-tifosi:' || f.trade_id || ':' || f.team_id, 'tifosi',
         (private.tifoso_finto('st' || f.trade_id || f.team_id, f.nome_squadra)).nome,
         (private.tifoso_finto('st' || f.trade_id || f.team_id, f.nome_squadra)).handle,
         f.team_id, f.altra_id,
         replace(replace(replace(fr.testo,
           '{S}', '@' || private.handle_squadra(f.nome_squadra)),
           '{IN}', coalesce(f.in_nome, 'il nuovo arrivato')), '{OUT}', coalesce(f.out_nome, 'il giocatore ceduto')),
         f.risolta_il + interval '20 seconds',
         'social:' || fr.id
  from t2 f
  join private.frasi_social fr on fr.id = (case when coalesce(array_length(f.libere, 1), 0) > 0 then f.libere else f.tutte end)[1 + (f.n - 1) % array_length(case when coalesce(array_length(f.libere, 1), 0) > 0 then f.libere else f.tutte end, 1)]
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  with lati as (
    select tp.id as trade_id, tp.league_id, tp.risolta_il, tp.da_team_id as team_da, tp.a_team_id as team_a, unnest(tp.giocatori_offerti) as pi_id
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
    union all
    select tp.id, tp.league_id, tp.risolta_il, tp.a_team_id, tp.da_team_id, unnest(tp.giocatori_richiesti)
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
  ), spostati as (
    select l.*, p.nome, pi.overall_corrente, tn.nome as nome_nuova, tv.nome as nome_vecchia,
           coalesce((select tg.morale_prima from private.trasferimenti_giocatori tg
                      where tg.player_instance_id = pi.id and tg.creato_il between l.risolta_il - interval '10 minutes' and l.risolta_il + interval '1 hour'
                      order by tg.creato_il desc limit 1),
                    case when pi.morale <= 60 then 35 else pi.morale - 20 end) as morale_prima,
           row_number() over (partition by l.trade_id, l.team_da order by pi.overall_corrente desc, pi.id) as ordine
    from lati l
    join public.player_instances pi on pi.id = l.pi_id
    join public.players p on p.id = pi.player_id
    join public.teams tn on tn.id = l.team_a
    join public.teams tv on tv.id = l.team_da
  )
  , g2 as (
    select s.*, case when s.morale_prima < 45 then 'giocatore_amaro' else 'giocatore_sereno' end as categoria
    from spostati s
    where s.ordine <= 2
      and not exists (select 1 from public.social_posts sp where sp.league_id = s.league_id and sp.chiave = 'scambio-giocatore:' || s.trade_id || ':' || s.pi_id)
  ), g3 as (
    select g.*, row_number() over (partition by g.league_id, g.categoria order by hashtext(g.trade_id::text || ':' || g.pi_id)) as n,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_social fr where fr.categoria = g.categoria
          and not exists (select 1 from public.social_posts sp where sp.league_id = g.league_id
                           and sp.frase_origine = 'social:' || fr.id and sp.creato_il > now() - interval '24 hours')) as libere,
           (select array_agg(fr.id order by hashtext(to_char(now() at time zone 'Europe/Rome', 'YYYYMMDD') || fr.id), fr.id)
         from private.frasi_social fr where fr.categoria = g.categoria) as tutte
    from g2 g
  )
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, player_instance_id, testo, creato_il, frase_origine)
  select s.league_id, 'scambio-giocatore:' || s.trade_id || ':' || s.pi_id, 'giocatore', s.nome, s.team_a, s.team_da, s.pi_id,
         replace(replace(fr.testo,
           '{X}', '@' || private.handle_squadra(s.nome_nuova)), '{V}', '@' || private.handle_squadra(s.nome_vecchia)),
         s.risolta_il + interval '45 seconds',
         'social:' || fr.id
  from g3 s
  join private.frasi_social fr on fr.id = (case when coalesce(array_length(s.libere, 1), 0) > 0 then s.libere else s.tutte end)[1 + (s.n - 1) % array_length(case when coalesce(array_length(s.libere, 1), 0) > 0 then s.libere else s.tutte end, 1)]
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  return v_nuovi;
end;
$function$;

-- Via i post automatici con il tono vecchio; si rigenerano subito.
delete from public.social_posts where chiave ~ '^(tifoso-partita|scambio-tifosi|scambio-giocatore|gol|r):';
select private.social_genera();
select private.social_risposte();

commit;
