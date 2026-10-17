-- Rimessi 'raga', 'ste', 'sta', 'no vabbe'': sono parlata normale. Restano vietate solo le abbreviazioni da chat vecchio stile (xke, nn, cmq, ke, tvb).
begin;
update private.frasi_tifosi set testo = $q${F}-{G}?? no vabbè siamo fuori scala 💀 {S}$q$ where id = 276;
update private.frasi_tifosi set testo = $q$ma basta con ste partite da pippe {S} 🤦$q$ where id = 429;
update private.frasi_social set testo = $q${IN} da noi?? no vabbè, non ci credo 😍 {S}$q$ where id = 301;
update private.frasi_social set testo = $q$no vabbè... via {OUT} e ci arriva {IN}? non capisco {S}$q$ where id = 332;
update private.frasi_social set testo = $q$raga che dire, grazie. {V} sarà sempre casa. ora via con {X}!$q$ where id = 431;
update private.frasi_commenti set testo = $q$raga ma {NOME} è un fenomeno o sbaglio? 🔥$q$ where id = 1091;
update private.frasi_commenti set testo = $q${NOME} raga, mi mancherai davvero. spacca 🔥$q$ where id = 1181;
update private.frasi_commenti set testo = $q$che tristezza leggere queste cose {NOME}. eravamo tuoi tifosi.$q$ where id = 1275;
update private.frasi_commenti set testo = $q$benvenuto raga! facci sognare {S} 🔥$q$ where id = 1432;
update private.frasi_commenti set testo = $q$ahahah sta domanda 💀 {S}$q$ where id = 1035;
update private.frasi_commenti set testo = $q$no vabbè ma questi giornalisti non hanno altro da chiedere? {S}$q$ where id = 1036;
update private.frasi_commenti set testo = $q$meritavamo di più secondo me. forza raga {S}$q$ where id = 1329;
update private.frasi_commenti set testo = $q$così si fa raga. avanti {S} 💪$q$ where id = 1294;
update private.frasi_commenti set testo = $q$no vabbè che scambio. {A} {B} 👀$q$ where id = 1391;
update private.frasi_commenti set testo = $q${A} {B} chi decide ste cose, un branco di incompetenti?$q$ where id = 1563;
update private.frasi_commenti set testo = $q$la vita va avanti {NOME}. e anche {V}. forza raga!$q$ where id = 1277;
commit;
