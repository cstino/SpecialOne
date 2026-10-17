-- ============================================================
--  SOCIALONE: piu' frasi per i tifosi (17 ottobre 2026)
--  Le frasi dei tifosi sui risultati passano dal codice a una tabella, cosi' se ne possono
--  aggiungere senza toccare il generatore: basta un insert in private.frasi_tifosi.
--  Categorie: goleada (vinta di 3+), vittoria, pareggio, batosta (persa di 3+), sconfitta.
--  Segnaposto: {S} tag della squadra, {O} tag dell'avversario, {F} gol fatti, {G} gol subiti.
--  135 frasi; la scelta e' a caso ma fissa per ogni post (hash della partita e della squadra).
-- ============================================================

begin;

create table if not exists private.frasi_tifosi (
  id        integer generated always as identity primary key,
  categoria text not null check (categoria in ('goleada', 'vittoria', 'pareggio', 'batosta', 'sconfitta')),
  testo     text not null check (char_length(testo) between 1 and 200),
  unique (categoria, testo)
);

insert into private.frasi_tifosi (categoria, testo) values
  ('goleada', 'Che spettacolo {S} 🔥 {F}-{G}, così si gioca!!'),
  ('goleada', 'Godo come un riccio. {S} asfalta {O}, avanti così ragazzi'),
  ('goleada', '{F}-{G} e a casa. Questa squadra è da scudetto, punto. {S}'),
  ('goleada', 'Ma quanto siamo forti?? {S} vi amo 😍'),
  ('goleada', 'Partita mai in discussione. {O} non pervenuti 😂 forza {S}'),
  ('goleada', 'Oggi si vola. {F}-{G}, {O} rimandati a casa con la valigia {S} 🚀'),
  ('goleada', 'Non c''è stata partita. Che squadra ragazzi, che squadra {S}'),
  ('goleada', 'Ho visto calcio vero stasera. {S} tutta la vita ❤️'),
  ('goleada', '{O} chi?? 😂 {S} devastanti'),
  ('goleada', 'Da brividi. Giocatori, mister, tutti: grazie {S}'),
  ('goleada', 'Stasera non c''era storia: {F}-{G} e {O} a casa a piangere. Forza {S} 🔥'),
  ('goleada', 'Ma che è successo?? Abbiamo fatto una goleada!! {S} vi voglio bene'),
  ('goleada', 'Calcio champagne. {S} oggi uno spettacolo per gli occhi'),
  ('goleada', '{F} gol a {O}. Ripeto: {F}. Che squadra {S} 😍'),
  ('goleada', 'Questa è la mia squadra. {S} da brividi stasera'),
  ('goleada', 'Lezione di calcio a {O}. Prendete appunti 😂 {S}'),
  ('goleada', 'Mai visto giocare così bene. Grazie {S}, serata perfetta'),
  ('goleada', 'Ditemi voi chi ci ferma. {S} macchina da gol'),
  ('goleada', 'Sono ancora in piedi sul divano. {S} che roba ragazzi'),
  ('goleada', '{O} umiliati. Non sempre si vince così, godiamocela {S} 🍾'),
  ('goleada', 'Che serata. Gol, spettacolo e tre punti. {S} sempre!!'),
  ('goleada', 'La gente al bar domani non parlerà d''altro. {S} da sogno'),
  ('goleada', 'Ok, adesso possiamo dirlo: siamo forti forti. {S}'),
  ('goleada', 'Tutti promossi stasera. Anche il magazziniere. {S} 🙌'),
  ('goleada', 'Avevo paura di questa partita e invece... {F}-{G}! {S} vi adoro'),
  ('goleada', '{O} chi l''ha vista? Noi no, eravamo troppo impegnati a segnare 😂 {S}'),
  ('goleada', 'Questa partita la racconterò ai miei nipoti. {S} immensi'),
  ('goleada', 'Che goduria ragazzi. {S} in versione schiacciasassi'),
  ('goleada', 'Si vede la mano del mister, che squadra. {S} ❤️‍🔥'),
  ('goleada', 'Il calcio quando è bello è così. Grazie {S}'),
  ('vittoria', 'Tre punti sudati ma pesantissimi. Forza {S}! 💪'),
  ('vittoria', 'Sofferto fino alla fine ma ce l''abbiamo fatta, grandi ragazzi {S}'),
  ('vittoria', 'Non bellissimi ma vincenti. Mi va benissimo così {S}'),
  ('vittoria', 'VITTORIAAAA 🙌 {S} cuore e grinta'),
  ('vittoria', '{F}-{G} a {O} e si va a letto felici. {S} ❤️'),
  ('vittoria', 'Che sofferenza ma che gioia!! {S} non mollare mai 🔥'),
  ('vittoria', 'Tre punti e zitti. Questo serve {S}'),
  ('vittoria', 'Ci siamo! Avanti così {S}, la strada è giusta'),
  ('vittoria', 'Partita sporca ma l''importante era vincere. Bravi {S} 👏'),
  ('vittoria', 'Battuti anche {O}. Testa alta e pedalare {S}'),
  ('vittoria', 'Vittoria!! Non sempre si gioca bene ma i punti contano {S} 💪'),
  ('vittoria', 'Che fatica ma ce l''abbiamo fatta. Forza {S} sempre'),
  ('vittoria', 'Tre punti contro {O}, si dorme sereni. {S}'),
  ('vittoria', '{F}-{G}, partita tosta ma vinta. Brava {S}!'),
  ('vittoria', 'Il cuore oltre l''ostacolo. Bravi ragazzi {S}'),
  ('vittoria', 'Sofferenza fino all''ultimo, ma quanto è bello vincere così {S}'),
  ('vittoria', 'Vinta con le unghie e con i denti. Questa è la mentalità {S} 🔥'),
  ('vittoria', 'Battuti anche loro. Avanti tutta {S}!'),
  ('vittoria', 'Partita da squadra vera. {S} così si fa'),
  ('vittoria', 'Non abbiamo brillato ma va benissimo così. Tre punti {S}'),
  ('vittoria', 'Gol, punti e a casa. Bravi tutti {S}'),
  ('vittoria', 'Quando conta {S} risponde presente. Grandi!'),
  ('vittoria', '{O} battuto. Ora non fermiamoci, si va avanti {S}'),
  ('vittoria', 'Che liberazione al fischio finale! {S} grandi'),
  ('vittoria', 'Vittoria di carattere. Mi piace questa {S}'),
  ('vittoria', 'Ho sofferto più io sul divano che loro in campo 😅 ma vinciamo {S}'),
  ('vittoria', 'La classifica sorride. Avanti così {S} 📈'),
  ('vittoria', 'Continuate così ragazzi, siamo tutti con voi {S}'),
  ('vittoria', 'Cinica e concreta. {S} a volte serve anche questo'),
  ('vittoria', 'Tre punti d''oro contro {O}. Forza {S}!!'),
  ('pareggio', 'Pareggio che non serve a niente. Dai {S} sveglia'),
  ('pareggio', 'Un punto è meglio di niente ma che fatica guardarvi {S}'),
  ('pareggio', '{F}-{G} con {O}... due punti buttati, ditemi che non sono l''unico incazzato {S}'),
  ('pareggio', 'Pari giusto, ma da {S} mi aspetto di più'),
  ('pareggio', 'Mah. Né carne né pesce. {S} così non si va da nessuna parte'),
  ('pareggio', 'Pareggino. Ok, ma prima o poi bisogna tornare a vincere {S}'),
  ('pareggio', 'Punto d''oro o occasione persa? Io dico la seconda {S}'),
  ('pareggio', 'Ci accontentiamo... ma che fatica {S} 😮‍💨'),
  ('pareggio', '{F}-{G}, partita brutta da vedere. {S} serve più coraggio'),
  ('pareggio', 'Contro {O} dovevamo vincerla. Punto. {S}'),
  ('pareggio', 'Pareggio... non so se essere contento o incazzato {S}'),
  ('pareggio', 'Un punto e via. Ma serve di più {S}'),
  ('pareggio', '{F}-{G}. Abbiamo fatto il minimo sindacale {S}'),
  ('pareggio', 'Bah. Partita grigia. {S} dobbiamo cambiare marcia'),
  ('pareggio', 'Se continuiamo a pareggiare così non andiamo da nessuna parte {S}'),
  ('pareggio', 'Contro {O} si poteva e si doveva vincere. {S} rimandati'),
  ('pareggio', 'Pari che sa di sconfitta. Peccato {S}'),
  ('pareggio', 'Meglio un punto che niente, ma che noia {S} 🥱'),
  ('pareggio', 'La palla in porta non entra mai. {S} serve un bomber'),
  ('pareggio', 'Un passo avanti o un passo indietro? Boh. {S}'),
  ('pareggio', 'Pareggio giusto, ma da {S} mi aspetto la vittoria in partite così'),
  ('pareggio', 'Altro pari. Comincio a perdere la pazienza {S}'),
  ('pareggio', 'Si muove la classifica, almeno quello. {S}'),
  ('pareggio', 'Due squadre stanche, partita da sbadigli. Forza {S} comunque'),
  ('pareggio', 'Mi sono addormentato al 70esimo. Svegliatevi {S}'),
  ('batosta', 'Dai ragazzi {S}, come cazzo si fa a perdere così? Vergogna'),
  ('batosta', '{F}-{G}. Non ho parole, solo rabbia. {S} svegliatevi'),
  ('batosta', 'Imbarazzanti. Ma vi rendete conto? {S} giocate per la maglia o no?'),
  ('batosta', 'Presi a pallonate da {O}. Che schifo {S}'),
  ('batosta', 'Spengo la tv e vado a dormire. {S} fate pena oggi'),
  ('batosta', '{F}-{G}?? Mi vergogno di avervi seguito stasera {S}'),
  ('batosta', 'Una disfatta. Qualcuno ci deve delle scuse {S}'),
  ('batosta', 'Tutti a casa. Così non si può andare avanti {S}'),
  ('batosta', 'Pagare per vedere questo schifo... {S} svegliatevi cazzo'),
  ('batosta', 'Umiliati da {O}. Giornata nera per {S}'),
  ('batosta', '{F}-{G}. Ho visto partite di oratorio giocate meglio {S}'),
  ('batosta', 'Che figura di merda. Scusate ma non riesco a dirlo diversamente {S}'),
  ('batosta', 'Presi a schiaffi da {O}. Vergognatevi {S}'),
  ('batosta', 'Una delle peggiori partite che io ricordi. {S} cosa vi succede??'),
  ('batosta', 'Non c''è niente da salvare. Niente. {S}'),
  ('batosta', 'Ma vi allenate o no? {S} così è imbarazzante'),
  ('batosta', '{O} ci ha fatto il culo. Punto. {S} riflettete'),
  ('batosta', 'Sono senza parole, e chi mi conosce sa che è difficile {S}'),
  ('batosta', 'Mi state facendo perdere la passione. {S} basta'),
  ('batosta', 'Ritiro immediato, tutti. {S} così non si può'),
  ('batosta', 'Giocatori svogliati, idee zero. {S} serve una scossa vera'),
  ('batosta', 'Batosta meritata. Testa bassa e lavorare {S}'),
  ('batosta', 'La maglia va onorata. Stasera no. {S}'),
  ('batosta', '{F}-{G}... ditemi che è un incubo {S} 😩'),
  ('batosta', 'Chi ha visto la partita mi capisce. Che schifo {S}'),
  ('sconfitta', 'Sconfitta che fa male. Dai {S}, rialziamoci subito'),
  ('sconfitta', 'Ma come si fa a perdere con {O}?? {S} serve una scossa'),
  ('sconfitta', 'Ennesima delusione. {S} così non va, qualcuno deve dare spiegazioni'),
  ('sconfitta', 'Brucia. {F}-{G} e niente da dire, testa alla prossima {S}'),
  ('sconfitta', 'Non ci siamo proprio. Dai {S}, tiratevi fuori le palle'),
  ('sconfitta', 'Perdere con {O} non è accettabile. {S} serve una reazione subito'),
  ('sconfitta', 'Che rabbia. {F}-{G} e torniamo a casa con niente {S}'),
  ('sconfitta', 'Ok la sconfitta, ma l''atteggiamento no. {S} più fame'),
  ('sconfitta', 'Un''altra domenica storta. Forza {S} che ci si rialza'),
  ('sconfitta', 'Siete lenti, molli, senza idee. Dai {S} cazzo'),
  ('sconfitta', 'Peccato, ci abbiamo provato. Forza {S} comunque'),
  ('sconfitta', 'Sconfitta immeritata secondo me. Testa alla prossima {S}'),
  ('sconfitta', 'Ci è mancato poco. Non molliamo {S}'),
  ('sconfitta', 'Così non va. Serve più cattiveria {S}'),
  ('sconfitta', 'Perdere con {O} brucia, eccome se brucia. {S}'),
  ('sconfitta', 'Un''altra occasione buttata. Dai {S} svegliatevi'),
  ('sconfitta', 'Ok, giornata storta. Ma ora reagite {S}'),
  ('sconfitta', 'Che rabbia, potevamo almeno pareggiarla {S}'),
  ('sconfitta', 'Le partite si vincono in area e noi lì non c''eravamo. {S}'),
  ('sconfitta', 'Sconfitta che fa riflettere. Forza {S}, ci rialzeremo'),
  ('sconfitta', 'Non è il momento di mollare. Sempre con voi {S} 💪'),
  ('sconfitta', 'Perso contro {O}... mister fai qualcosa {S}'),
  ('sconfitta', 'Brutta sconfitta. Qualcosa va cambiato {S}'),
  ('sconfitta', 'Dai cazzo, ancora una sconfitta. {S} così non si va avanti'),
  ('sconfitta', 'Ci credevo stasera. Delusione enorme {S}')
on conflict (categoria, testo) do nothing;

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
             then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
               'Il gol non basta. Si lavora in settimana per rialzarci.', 'Una serata amara: segnare non serve se non si vince.'])
           when p.mentalita_bandiera >= greatest(p.mentalita_economia, p.mentalita_vittorie) then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta con questa maglia addosso: non esiste emozione più grande.' else 'Segnare per questa maglia non ha prezzo. Grazie a chi ci ha spinto!' end,
             'Questa maglia è tutta la mia vita. Grazie ai tifosi per ogni voce.'])
           when p.mentalita_economia >= p.mentalita_vittorie then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta. Il lavoro paga, sempre.' else 'Un gol che fa bene. Il lavoro quotidiano paga.' end,
             'Contento del gol, ma ora si pensa alla prossima.'])
           else private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta, ma conta solo vincere. Avanti verso gli obiettivi.' else 'Un gol per la squadra: l''obiettivo è vincere tutto.' end,
             'Si vince, si segna, si va avanti. Questo è il nostro livello.'])
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
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, team2_id, testo, creato_il)
  select x.league_id, 'tifoso-partita:' || x.match_id || ':' || x.team_id, 'tifosi',
         (private.tifoso_finto('tp' || x.match_id || x.team_id, x.nome)).nome,
         (private.tifoso_finto('tp' || x.match_id || x.team_id, x.nome)).handle,
         x.team_id, x.avv_id,
         replace(replace(replace(replace(
           (select fr.testo from private.frasi_tifosi fr
             where fr.categoria = case
               when x.fatti - x.subiti >= 3 then 'goleada'
               when x.fatti > x.subiti then 'vittoria'
               when x.fatti = x.subiti then 'pareggio'
               when x.subiti - x.fatti >= 3 then 'batosta'
               else 'sconfitta' end
             order by hashtext('tp' || x.match_id || ':' || x.team_id || ':' || fr.id), fr.id limit 1),
           '{S}', '@' || private.handle_squadra(x.nome)), '{O}', '@' || private.handle_squadra(x.avv_nome)), '{F}', x.fatti::text), '{G}', x.subiti::text),
         x.simulata_il + interval '30 seconds'
  from (
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
  ) x
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  return v_nuovi;
end;
$function$;

commit;
