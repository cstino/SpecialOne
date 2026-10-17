-- ============================================================
--  SOCIALONE: risposte fra i personaggi e mi piace dei tifosi (17 ottobre 2026, committente)
--  * quasi tutti i post ricevono risposte (da frasi modello, nessun costo di AI), a fili:
--      domanda della testata  -> 2 tifosi              | risposta dell'allenatore -> 1 tifoso
--      risultato della lega   -> tifoso di chi vince e di chi perde (o di entrambe se pari)
--      scambio ufficiale      -> un tifoso per squadra | asta vinta -> 1 tifoso
--      gol di un giocatore    -> un compagno (chi ha fatto l'assist, se c'e'), un suo tifoso e un tifoso rivale
--      addio di un giocatore  -> un ex compagno e un tifoso della vecchia squadra (toni diversi se se n'e' andato amaro)
--  * FRECCIATINE FRA RIVALI: se la rivalita' fra le due squadre e' almeno 70%, il giocatore della perdente risponde
--    al marcatore della vincente e il marcatore replica.
--  * MI PIACE DEI TIFOSI: ogni post riceve un numero di mi piace "dei tifosi", calcolato una volta dall'importanza
--    e dall'umore del pubblico della squadra, separato dai cuori veri.
--  * Le risposte hanno un ritardo (3-42 minuti dopo il post) e il feed non mostra i post ancora "nel futuro".
-- ============================================================

begin;

alter table public.social_posts add column if not exists mi_piace_fan integer;

create table private.frasi_commenti (
  id        integer generated always as identity primary key,
  categoria text not null check (categoria in ('sotto_giornale','compagno_gol_assist','compagno_gol','fan_gol','rivale_gol','saluto_compagno','compagno_risposta_amaro','fan_addio_sereno','fan_addio_amaro','sotto_risultato_vince','sotto_risultato_perde','sotto_pareggio','sotto_scambio','sotto_asta','sotto_allenatore','rival_frecciatina','rival_replica')),
  testo     text not null check (char_length(testo) between 1 and 300),
  unique (categoria, testo)
);
-- Segnaposto: {NOME} giocatore, {S} squadra del tifoso (o del marcatore nelle frecciatine), {O} avversaria,
-- {F} {G} gol, {A} {B} le due squadre dello scambio, {X} nuova squadra, {V} vecchia.
insert into private.frasi_commenti (categoria, testo) values
  ('sotto_giornale', 'Domanda scontata, risposta ovvia: forza {S}!'),
  ('sotto_giornale', 'Finalmente qualcuno che chiede le cose giuste al mister {S} 👏'),
  ('sotto_giornale', 'Sempre le stesse domande... parlate di calcio vero {S}'),
  ('sotto_giornale', 'Il mister saprà rispondere, di lui mi fido {S}'),
  ('sotto_giornale', 'Bella domanda. Aspetto la risposta con ansia {S}'),
  ('sotto_giornale', 'Ma questi giornalisti non hanno altro da chiedere? Forza {S} 😂'),
  ('sotto_giornale', 'Una domanda che dovevano fare da tempo {S}'),
  ('sotto_giornale', 'Il mister avrà le palle di rispondere? Vediamo {S}'),
  ('sotto_giornale', 'Ottima domanda. La verità è sempre quella: conta il campo {S}'),
  ('sotto_giornale', 'Il solito giornale che ci tiene d''occhio. Siamo sotto i riflettori {S} 😎'),
  ('sotto_giornale', 'Rispondi senza peli sulla lingua mister! {S}'),
  ('sotto_giornale', 'Così si fa informazione. Forza {S}!'),
  ('sotto_giornale', 'Hanno ragione, a volte siamo davvero strani {S} 😅'),
  ('sotto_giornale', 'Fate bene a chiederlo. Noi tifosi vogliamo chiarezza {S}'),
  ('compagno_gol_assist', 'Grande {NOME}! L''assist era mio ma il gol è tuo 😎'),
  ('compagno_gol_assist', 'Ti ho dato il pallone, tu hai fatto il resto. Bravo {NOME}!'),
  ('compagno_gol_assist', '{NOME} sempre al posto giusto, io faccio solo i cross 😂'),
  ('compagno_gol_assist', 'Che coppia che siamo, {NOME}! Ancora insieme 🔥'),
  ('compagno_gol_assist', 'Gol tuo, merito mio. Offri la cena {NOME} 🍝'),
  ('compagno_gol_assist', 'Bella la partita, {NOME}. Avanti così fratello 💪'),
  ('compagno_gol_assist', 'Ti ho visto smarcarti e non ho avuto dubbi, {NOME}!'),
  ('compagno_gol_assist', 'Che goduria servirti, {NOME}. Ci riproviamo domenica? 😏'),
  ('compagno_gol_assist', 'Eri lì e io lo sapevo, {NOME}. Sei un killer ⚽'),
  ('compagno_gol_assist', 'L''assist più facile della mia vita. Bravo {NOME}!'),
  ('compagno_gol', 'Grande {NOME}! Che gol! 🔥'),
  ('compagno_gol', 'Sei un mostro {NOME}, ti voglio bene 💪'),
  ('compagno_gol', 'Siamo tutti con te {NOME}. Avanti così!'),
  ('compagno_gol', 'Bel gol {NOME}! Ora la prossima tocca a me 😂'),
  ('compagno_gol', 'Sempre decisivo, {NOME}. Orgoglioso di giocare con te ⚽'),
  ('compagno_gol', 'Che squadra siamo! Bravo {NOME}, e bravi tutti 🙌'),
  ('compagno_gol', 'Gol bellissimo {NOME}, ma l''abbraccio lo voglio io 😄'),
  ('compagno_gol', '{NOME} non sbaglia mai quando conta. Grandissimo!'),
  ('compagno_gol', 'Questa è la nostra forza: il gruppo. Bravo {NOME}!'),
  ('compagno_gol', 'Complimenti {NOME}, te lo meriti tutto 👏'),
  ('fan_gol', '{NOME} sei un mito!! Forza {S} ❤️'),
  ('fan_gol', 'Che gol {NOME}! Ti amiamo 😍'),
  ('fan_gol', 'Vai {NOME}, facci sognare! {S}'),
  ('fan_gol', '{NOME} per sempre con noi, grazie 🔥'),
  ('fan_gol', 'Ogni domenica ci regali emozioni, {NOME}. Grazie!'),
  ('fan_gol', 'Segna sempre quando serve. {NOME} il nostro bomber {S}'),
  ('fan_gol', 'Non cambierei {NOME} con nessuno. Forza {S}!'),
  ('fan_gol', 'Dai {NOME}, ancora così! Siamo con te {S} 💪'),
  ('fan_gol', '{NOME} mi fai dimenticare la settimana storta 😍 forza {S}'),
  ('fan_gol', 'Che talento {NOME}. Questo club ti merita {S}'),
  ('rivale_gol', 'Bravo {NOME}, ma è andata male a noi... il ritorno lo vinciamo noi {S}'),
  ('rivale_gol', 'Gol facile, {NOME}. Vediamo se lo rifai con noi 😏'),
  ('rivale_gol', 'Vi godete questa serata, poi ci rivediamo {S}'),
  ('rivale_gol', 'Bel gol {NOME}, devo dirlo. Ma non vincerete sempre {S}'),
  ('rivale_gol', 'Ridete ridete, tanto il campionato è lungo {S} 😤'),
  ('rivale_gol', 'Complimenti {NOME}, ma la prossima ve la facciamo pagare {S}'),
  ('rivale_gol', 'Fortuna sfacciata {S}. Il ritorno sarà un''altra storia'),
  ('rivale_gol', 'Ok {NOME} oggi vi è andata bene, godetevela finché dura {S}'),
  ('rivale_gol', 'Mi rode, lo ammetto. Bravo {NOME}, ma non è finita {S}'),
  ('rivale_gol', 'Niente da fare, stavolta avete vinto voi. Il ritorno è nostro {S} 💪'),
  ('saluto_compagno', 'Ci mancherai fratello {NOME}. In bocca al lupo! 💪'),
  ('saluto_compagno', 'Grande {NOME}, è stato un onore giocare con te. Ci vediamo in campo!'),
  ('saluto_compagno', 'Mi hai insegnato tanto, {NOME}. Spacca tutto laggiù 🔥'),
  ('saluto_compagno', 'Peccato, {NOME}. Spogliatoio più povero senza di te 😢'),
  ('saluto_compagno', 'Ti voglio bene {NOME}, torna a trovarci! ❤️'),
  ('saluto_compagno', 'In bocca al lupo {NOME}! Ci sentiamo dopo la partita 😄'),
  ('saluto_compagno', 'Che amico che perdiamo, {NOME}. Auguri veri 🙌'),
  ('saluto_compagno', '{NOME} sei stato un grande compagno. Buona fortuna!'),
  ('saluto_compagno', 'Non è un addio, è un arrivederci {NOME} 💪'),
  ('saluto_compagno', 'Quando segni contro di noi non esultare troppo eh {NOME} 😂'),
  ('compagno_risposta_amaro', '{NOME}, parliamone di persona. Certe cose non si dicono così.'),
  ('compagno_risposta_amaro', 'Siamo tutti rimasti male per come sono andate le cose, {NOME}. Ma resti un grande.'),
  ('compagno_risposta_amaro', 'Nessuno ti ha messo da parte, {NOME}. Ma ti capisco. In bocca al lupo.'),
  ('compagno_risposta_amaro', 'Ognuno ha la sua verità, {NOME}. Auguri comunque.'),
  ('compagno_risposta_amaro', 'Peccato per i toni, {NOME}. Qui nessuno ti vuole male.'),
  ('compagno_risposta_amaro', 'Mi spiace che finisca così {NOME}. Il campo parlerà per tutti.'),
  ('compagno_risposta_amaro', 'Il tempo dirà chi aveva ragione, {NOME}. Intanto buona fortuna.'),
  ('compagno_risposta_amaro', '{NOME}, il gruppo resta il gruppo. Sempre un abbraccio.'),
  ('compagno_risposta_amaro', 'Capisco la tua amarezza {NOME}, ma chi resta ha dato quanto te.'),
  ('compagno_risposta_amaro', 'Ne parleremo, {NOME}. Intanto spacca laggiù 💪'),
  ('fan_addio_sereno', 'Grazie di tutto {NOME}! Sempre uno di noi ❤️'),
  ('fan_addio_sereno', 'Ci mancherai {NOME}. Auguri per la nuova avventura con {X}!'),
  ('fan_addio_sereno', 'Resta nel cuore, {NOME}. Grazie {V} per averlo avuto 💪'),
  ('fan_addio_sereno', 'Quando torni da avversario ti applaudiamo lo stesso, {NOME}.'),
  ('fan_addio_sereno', 'Che peccato {NOME}. Ma ti auguriamo il meglio 🙏'),
  ('fan_addio_sereno', 'Mai dimenticherò i tuoi gol, {NOME}. Grazie!'),
  ('fan_addio_sereno', '{NOME} un esempio di professionalità. In bocca al lupo!'),
  ('fan_addio_sereno', 'Ti aspettiamo da avversario, {NOME}. Ma ti vogliamo bene lo stesso 😄'),
  ('fan_addio_sereno', 'Un pezzo di cuore se ne va. Grazie {NOME}!'),
  ('fan_addio_sereno', 'Buona fortuna {NOME}, ma non farci troppo male quando ci incontriamo 😂'),
  ('fan_addio_amaro', 'Tante parole dopo tutto quello che abbiamo fatto per te, {NOME}. Pazienza.'),
  ('fan_addio_amaro', 'Chi se ne va così non avrà il nostro rimpianto, {NOME}.'),
  ('fan_addio_amaro', '{NOME}, il cuore si dimostra restando, non scappando. Ciao.'),
  ('fan_addio_amaro', 'Le frecciatine potevi risparmiarle {NOME}. Noi ti abbiamo sempre sostenuto.'),
  ('fan_addio_amaro', 'Mi dispiace, ma {NOME} ha scelto. Forza {V}, andiamo avanti 💪'),
  ('fan_addio_amaro', 'Dispiace per i toni {NOME}. Nel bene e nel male ti abbiamo voluto bene.'),
  ('fan_addio_amaro', 'Se non eri felice, hai fatto bene ad andare. Ma i social non servono, {NOME}.'),
  ('fan_addio_amaro', 'Ognuno racconta la sua verità. La nostra è che abbiamo fatto di tutto {NOME}.'),
  ('fan_addio_amaro', 'Un grazie per i gol, un ciao per il resto {NOME}. Forza {V}!'),
  ('fan_addio_amaro', 'Non ti serbiamo rancore {NOME}, ma nemmeno ti rimpiangiamo 🙃'),
  ('sotto_risultato_vince', 'Che serata!! {F}-{G} e si vola! Forza {S} 🔥'),
  ('sotto_risultato_vince', 'Tre punti d''oro contro {O}. Orgoglio {S}!'),
  ('sotto_risultato_vince', 'Sempre con voi {S}! Che squadra!'),
  ('sotto_risultato_vince', 'Così si fa, ragazzi. Avanti {S} 💪'),
  ('sotto_risultato_vince', 'Notte da ricordare. {S} grandissimi ❤️'),
  ('sotto_risultato_vince', 'Vittoria meritata. {O} non ha avuto scampo, forza {S}!'),
  ('sotto_risultato_vince', 'Bravi tutti, giocatori e tifosi. {S} per sempre 🙌'),
  ('sotto_risultato_vince', 'Questo è il livello che ci aspettiamo. Complimenti {S}!'),
  ('sotto_risultato_vince', 'Che spettacolo {S}, ci siamo divertiti un sacco 😍'),
  ('sotto_risultato_vince', 'Un altro passo avanti. Continuate così {S}!'),
  ('sotto_risultato_perde', 'Oggi non è andata, ma ci rialziamo. Forza {S} ❤️'),
  ('sotto_risultato_perde', 'Complimenti a {O}, ma noi non molliamo mai {S} 💪'),
  ('sotto_risultato_perde', 'Giornata storta. Si riparte subito {S}!'),
  ('sotto_risultato_perde', 'Brucia, ma i veri tifosi restano. Sempre con voi {S}'),
  ('sotto_risultato_perde', 'Il campionato è lungo, la risposta la daremo in campo {S}'),
  ('sotto_risultato_perde', 'Che amarezza. Spero in una reazione {S} 😔'),
  ('sotto_risultato_perde', 'Sconfitta dura da digerire. Ora testa bassa e lavoro {S}'),
  ('sotto_risultato_perde', 'Non è finita finché non è finita. Avanti {S}!'),
  ('sotto_risultato_perde', 'Meritavamo di più, secondo me. Forza ragazzi {S}'),
  ('sotto_risultato_perde', 'Una partita storta non cancella tutto. Con voi sempre {S}'),
  ('sotto_pareggio', 'Un punto a testa, ma io volevo vincere. Forza {S}!'),
  ('sotto_pareggio', 'Pareggio che lascia l''amaro in bocca {S}'),
  ('sotto_pareggio', 'Meglio di niente contro {O}. Ora si torna a vincere {S}'),
  ('sotto_pareggio', 'Partita equilibrata, risultato giusto. Avanti {S}'),
  ('sotto_pareggio', 'Si poteva fare di più. Dai {S} 💪'),
  ('sotto_pareggio', 'Un pari che serve a poco. Alla prossima {S}'),
  ('sotto_pareggio', 'Non è un brutto risultato, ma non basta {S}'),
  ('sotto_pareggio', 'Punto d''oro o occasione persa? Dipende da come la si guarda {S}'),
  ('sotto_pareggio', '{O} ha tenuto botta, complimenti. Ma torniamo a vincere {S}'),
  ('sotto_pareggio', 'Alla fine va bene così. Adesso concentriamoci sulla prossima {S}'),
  ('sotto_scambio', 'Finalmente un po'' di movimento! Vediamo che succede {A} {B} 👀'),
  ('sotto_scambio', 'Scambio interessante, speriamo bene per tutti 🤞'),
  ('sotto_scambio', 'Da tifoso dico: aspettiamo il campo prima di giudicare {A}'),
  ('sotto_scambio', '{B} ha fatto un bel colpo, o almeno spero 😅'),
  ('sotto_scambio', 'Ogni scambio è una scommessa. Che vinca il migliore {A} {B}'),
  ('sotto_scambio', 'Il mercato non perdona mai. Vedremo chi ha ragione.'),
  ('sotto_scambio', 'Brava la dirigenza a muoversi. Ora tocca al campo {A} {B}'),
  ('sotto_scambio', 'Non mi convince del tutto ma mi fido {A}'),
  ('sotto_scambio', 'Due squadre, due strategie. Interessante {A} {B}'),
  ('sotto_scambio', 'HERE WE GO e speriamo che sia l''affare giusto 😎'),
  ('sotto_asta', 'Benvenuto! Dai {S}, facci divertire 🔥'),
  ('sotto_asta', 'Ottimo acquisto, mi piace {S}'),
  ('sotto_asta', 'Finalmente rinforzi. Forza {S}!'),
  ('sotto_asta', 'Bel colpo. Speriamo faccia la differenza {S} 🙏'),
  ('sotto_asta', 'Un nuovo arrivo che mi gasa. Avanti {S}!'),
  ('sotto_asta', 'Mercato intelligente, bravi {S} 👏'),
  ('sotto_asta', 'Aspettavamo un rinforzo così. Forza {S}!'),
  ('sotto_asta', 'Che dire, benvenuto in famiglia {S} ❤️'),
  ('sotto_asta', 'Se è bravo come dicono, ci divertiremo {S}'),
  ('sotto_asta', 'Colpo di mercato, punto. {S} 💪'),
  ('sotto_allenatore', 'Il mister dice sempre le cose giuste. Forza {S}!'),
  ('sotto_allenatore', 'Sono d''accordo con il mister. Fiducia totale {S} 💪'),
  ('sotto_allenatore', 'Troppo diplomatico stavolta mister, ma ti seguiamo {S}'),
  ('sotto_allenatore', 'Parole sagge. Avanti {S}!'),
  ('sotto_allenatore', 'Il mister ha ragione, bisogna lavorare {S}'),
  ('sotto_allenatore', 'Così si risponde! Bravo mister {S} 👏'),
  ('sotto_allenatore', 'Mi fido del mister, anche quando non capisco {S}'),
  ('sotto_allenatore', 'Il mister ha carattere. {S} è in buone mani'),
  ('sotto_allenatore', 'Su questo non sono d''accordo, ma gli voglio bene lo stesso {S} 😅'),
  ('sotto_allenatore', 'Chi critica il mister non capisce di calcio {S} 😤'),
  ('rival_frecciatina', 'Bravo {NOME}, goditi la serata. Il ritorno lo vediamo 😏'),
  ('rival_frecciatina', 'Gol di fortuna {NOME}. Alla prossima, e non sarà così facile.'),
  ('rival_frecciatina', 'Continua a esultare {NOME}, finché dura 😂'),
  ('rival_frecciatina', 'Bel gol, {NOME}. Peccato sia l''unica cosa buona di {S} stasera.'),
  ('rival_frecciatina', 'Non cantare vittoria {NOME}, il campionato è lungo.'),
  ('rival_frecciatina', 'Divertiti {NOME}, tanto il prossimo derby lo decidiamo noi.'),
  ('rival_frecciatina', 'Bravo bravo {NOME}. Ma ricordati chi ride per ultimo 😎'),
  ('rival_frecciatina', 'Complimenti {NOME}, ma la nostra memoria è lunga. Ci si vede.'),
  ('rival_frecciatina', 'Hai segnato? Ok. Ma una rondine non fa primavera, {NOME}.'),
  ('rival_frecciatina', '{NOME}, ti aspettiamo al ritorno. Porta anche i tuoi tifosi 😤'),
  ('rival_replica', 'Aspetto il ritorno con ansia, io intanto segno 😎'),
  ('rival_replica', 'Il campo ha parlato, il resto sono chiacchiere.'),
  ('rival_replica', 'Ridi pure, io intanto ho fatto gol. Ci vediamo al ritorno 😏'),
  ('rival_replica', 'Parla il risultato, non la bocca. Alla prossima!'),
  ('rival_replica', 'Se è fortuna, ve la regalo anche al ritorno 😂'),
  ('rival_replica', 'Contate i gol, poi ne riparliamo. ⚽'),
  ('rival_replica', 'Chi vince ha sempre ragione. Buon proseguimento 😉'),
  ('rival_replica', 'Ve l''ho già detto: sul campo non si scherza.'),
  ('rival_replica', 'Il prossimo derby lo aspetto più di voi 🔥'),
  ('rival_replica', 'Rispetto, ma oggi il campo è mio.')
on conflict (categoria, testo) do nothing;

-- Una frase della categoria, preferendo quelle non usate nella lega nelle ultime 24 ore.
create or replace function private.scegli_frase_commento(p_categoria text, p_league bigint, p_seed text)
returns table (id integer, testo text)
language sql stable security definer set search_path = ''
as $$
  select fr.id, fr.testo from private.frasi_commenti fr
  where fr.categoria = p_categoria
  order by exists (select 1 from public.social_posts sp where sp.league_id = p_league and sp.frase_origine = 'commento:' || fr.id
                    and sp.creato_il > now() - interval '24 hours'),
           hashtext(p_seed || ':' || fr.id), fr.id
  limit 1
$$;

-- Inserisce una risposta (una sola volta per post e "slot") e ne restituisce l'id.
create or replace function private.social_rispondi(
  p_parent bigint, p_slot text, p_tipo text, p_nome text, p_handle text, p_team bigint, p_team2 bigint, p_pi bigint,
  p_categoria text, p_sost jsonb, p_in_risposta bigint default null)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.social_posts;
  v_f record;
  v_t text;
  v_k text;
  v_v text;
  v_id bigint;
begin
  select * into v_p from public.social_posts where id = p_parent;
  if not found then return null; end if;
  select sp.id into v_id from public.social_posts sp where sp.league_id = v_p.league_id and sp.chiave = 'r:' || p_parent || ':' || p_slot;
  if v_id is not null then return null; end if;
  select * into v_f from private.scegli_frase_commento(p_categoria, v_p.league_id, 'r' || p_parent || p_slot);
  if v_f.id is null then return null; end if;
  v_t := v_f.testo;
  for v_k, v_v in select key, value from jsonb_each_text(coalesce(p_sost, '{}'::jsonb)) loop
    v_t := replace(v_t, '{' || v_k || '}', v_v);
  end loop;
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, team2_id, player_instance_id,
                                   in_risposta_a, testo, creato_il, frase_origine)
  values (v_p.league_id, 'r:' || p_parent || ':' || p_slot, p_tipo, p_nome, p_handle, p_team, p_team2, p_pi,
          coalesce(p_in_risposta, p_parent), v_t,
          v_p.creato_il + make_interval(mins => 3 + abs(hashtext(p_parent || ':' || p_slot)) % 40), 'commento:' || v_f.id)
  returning id into v_id;
  return v_id;
end;
$$;

-- Id di una risposta gia' creata (per le catene: la frecciatina e la replica).
create or replace function private.social_id_risposta(p_parent bigint, p_slot text)
returns bigint
language sql stable security definer set search_path = ''
as $$ select sp.id from public.social_posts sp where sp.chiave = 'r:' || p_parent || ':' || p_slot limit 1 $$;

-- Un tifoso inventato di una squadra: (nome, handle).
create or replace function private.social_tifoso(p_seme text, p_team bigint, out nome text, out handle text)
language sql stable security definer set search_path = ''
as $$ select (private.tifoso_finto(p_seme, t.nome)).nome, (private.tifoso_finto(p_seme, t.nome)).handle from public.teams t where t.id = p_team $$;

create or replace function private.social_risposte()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_p record;
  v_n integer := 0;
  v_m record;
  v_tag_s text;
  v_tag_o text;
  v_id bigint;
  v_tf record;
  v_cat text;
  v_assist record;
  v_comp record;
  v_riv numeric;
  v_perdente bigint;
  v_vincente bigint;
  v_squadra_gol bigint;
  v_avv bigint;
  v_tit bigint[];
  v_scorer text;
begin
  -- Mi piace dei tifosi: una volta per post, in base al tipo, all'importanza e all'umore del pubblico della squadra.
  update public.social_posts p
     set mi_piace_fan = greatest(0, round(
           (case p.autore_tipo
              when 'lega' then case when p.chiave like 'partita:%' then 22 when p.chiave like 'scambio:%' then 32 else 12 end
              when 'testata' then 16 when 'allenatore' then 20 when 'tifosi' then 9 else 15 end)
           * (0.55 + coalesce((select t.pubblico from public.teams t where t.id = p.team_id), 70) / 100.0 * 0.9)
           * (0.6 + (abs(hashtext('lk' || p.id)) % 1000) / 1000.0 * 0.9)))::integer
   where p.mi_piace_fan is null
     and p.league_id in (select l.id from public.leagues l where l.conferenze_stampa);

  for v_p in
    select sp.* from public.social_posts sp
    join public.leagues l on l.id = sp.league_id and l.conferenze_stampa
    where sp.creato_il > now() - interval '3 days' and sp.in_risposta_a is null or (sp.chiave like 'conf-risposta:%' and sp.creato_il > now() - interval '3 days')
    order by sp.id
  loop
    -- domanda della testata: due tifosi della squadra intervistata
    if v_p.chiave like 'conf-domanda:%' and v_p.team_id is not null then
      v_tag_s := '@' || private.handle_squadra((select nome from public.teams where id = v_p.team_id));
      for i in 1..2 loop
        select * into v_tf from private.social_tifoso('rg' || v_p.id || i, v_p.team_id);
        if private.social_rispondi(v_p.id, 'f' || i, 'tifosi', v_tf.nome, v_tf.handle, v_p.team_id, null, null, 'sotto_giornale', jsonb_build_object('S', v_tag_s)) is not null then v_n := v_n + 1; end if;
      end loop;

    -- risposta dell'allenatore: un tifoso
    elsif v_p.chiave like 'conf-risposta:%' and v_p.team_id is not null then
      v_tag_s := '@' || private.handle_squadra((select nome from public.teams where id = v_p.team_id));
      select * into v_tf from private.social_tifoso('ra' || v_p.id, v_p.team_id);
      if private.social_rispondi(v_p.id, 'f1', 'tifosi', v_tf.nome, v_tf.handle, v_p.team_id, null, null, 'sotto_allenatore', jsonb_build_object('S', v_tag_s)) is not null then v_n := v_n + 1; end if;

    -- risultato della lega: un tifoso di chi vince e uno di chi perde (o di entrambe se pari)
    elsif v_p.chiave like 'partita:%' and v_p.team_id is not null and v_p.team2_id is not null then
      select m.gol_home, m.gol_away into v_m from public.matches m where m.id = split_part(v_p.chiave, ':', 2)::bigint;
      if found then
        v_vincente := case when v_m.gol_home > v_m.gol_away then v_p.team_id when v_m.gol_home < v_m.gol_away then v_p.team2_id end;
        for i in 1..2 loop
          declare
            v_team bigint := case i when 1 then v_p.team_id else v_p.team2_id end;
            v_altra bigint := case i when 1 then v_p.team2_id else v_p.team_id end;
            v_f int := case i when 1 then v_m.gol_home else v_m.gol_away end;
            v_g int := case i when 1 then v_m.gol_away else v_m.gol_home end;
          begin
            v_cat := case when v_vincente is null then 'sotto_pareggio' when v_vincente = v_team then 'sotto_risultato_vince' else 'sotto_risultato_perde' end;
            select * into v_tf from private.social_tifoso('rp' || v_p.id || i, v_team);
            if private.social_rispondi(v_p.id, 't' || i, 'tifosi', v_tf.nome, v_tf.handle, v_team, v_altra, null, v_cat,
                 jsonb_build_object('S', '@' || private.handle_squadra((select nome from public.teams where id = v_team)),
                                    'O', '@' || private.handle_squadra((select nome from public.teams where id = v_altra)), 'F', v_f, 'G', v_g)) is not null then
              v_n := v_n + 1;
            end if;
          end;
        end loop;
      end if;

    -- scambio ufficiale: un tifoso per squadra
    elsif v_p.chiave like 'scambio:%' and v_p.team_id is not null and v_p.team2_id is not null then
      for i in 1..2 loop
        declare
          v_team bigint := case i when 1 then v_p.team_id else v_p.team2_id end;
        begin
          select * into v_tf from private.social_tifoso('rs' || v_p.id || i, v_team);
          if private.social_rispondi(v_p.id, 't' || i, 'tifosi', v_tf.nome, v_tf.handle, v_team, null, null, 'sotto_scambio',
               jsonb_build_object('A', '@' || private.handle_squadra((select nome from public.teams where id = v_p.team_id)),
                                  'B', '@' || private.handle_squadra((select nome from public.teams where id = v_p.team2_id)))) is not null then
            v_n := v_n + 1;
          end if;
        end;
      end loop;

    -- asta o UNDER vinta: un tifoso di chi l'ha vinta
    elsif (v_p.chiave like 'asta:%' or v_p.chiave like 'under:%') and v_p.team_id is not null then
      select * into v_tf from private.social_tifoso('rq' || v_p.id, v_p.team_id);
      if private.social_rispondi(v_p.id, 'f1', 'tifosi', v_tf.nome, v_tf.handle, v_p.team_id, null, null, 'sotto_asta',
           jsonb_build_object('S', '@' || private.handle_squadra((select nome from public.teams where id = v_p.team_id)))) is not null then v_n := v_n + 1; end if;

    -- gol di un giocatore: un compagno (chi ha fatto l'assist, se c'e'), un suo tifoso, un tifoso rivale, e le frecciatine fra rivali
    elsif v_p.chiave like 'gol:%' and v_p.team_id is not null and v_p.player_instance_id is not null then
      select m.id, f.home_team_id, f.away_team_id, m.gol_home, m.gol_away,
             case when f.home_team_id = v_p.team_id then m.titolari_home else m.titolari_away end as tit,
             case when f.home_team_id = v_p.team_id then m.titolari_away else m.titolari_home end as tit_avv
        into v_m
        from public.matches m join public.fixtures f on f.id = m.fixture_id where m.id = split_part(v_p.chiave, ':', 2)::bigint;
      if found then
        v_squadra_gol := v_p.team_id;
        v_avv := case when v_m.home_team_id = v_squadra_gol then v_m.away_team_id else v_m.home_team_id end;
        v_scorer := v_p.autore_nome;
        v_tag_s := '@' || private.handle_squadra((select nome from public.teams where id = v_squadra_gol));
        -- compagno: chi ha fatto l'assist in quella partita, altrimenti un titolare a caso
        select pi.id, p.nome into v_assist
          from public.match_stats ms join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
         where ms.match_id = v_m.id and ms.team_id = v_squadra_gol and ms.assist > 0 and ms.player_instance_id <> v_p.player_instance_id
         order by ms.assist desc, ms.player_instance_id limit 1;
        if v_assist.id is not null then
          if private.social_rispondi(v_p.id, 'c', 'giocatore', v_assist.nome, null, v_squadra_gol, null, v_assist.id, 'compagno_gol_assist', jsonb_build_object('NOME', v_scorer)) is not null then v_n := v_n + 1; end if;
        else
          select pi.id, p.nome into v_comp
            from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (v_m.tit) and pi.id <> v_p.player_instance_id and pi.team_id = v_squadra_gol
           order by hashtext('rc' || v_p.id || pi.id) limit 1;
          if v_comp.id is not null and private.social_rispondi(v_p.id, 'c', 'giocatore', v_comp.nome, null, v_squadra_gol, null, v_comp.id, 'compagno_gol', jsonb_build_object('NOME', v_scorer)) is not null then v_n := v_n + 1; end if;
        end if;
        select * into v_tf from private.social_tifoso('rf' || v_p.id, v_squadra_gol);
        if private.social_rispondi(v_p.id, 'f', 'tifosi', v_tf.nome, v_tf.handle, v_squadra_gol, null, null, 'fan_gol', jsonb_build_object('NOME', v_scorer, 'S', v_tag_s)) is not null then v_n := v_n + 1; end if;
        select * into v_tf from private.social_tifoso('rr' || v_p.id, v_avv);
        if private.social_rispondi(v_p.id, 'r', 'tifosi', v_tf.nome, v_tf.handle, v_avv, v_squadra_gol, null, 'rivale_gol', jsonb_build_object('NOME', v_scorer, 'S', v_tag_s)) is not null then v_n := v_n + 1; end if;

        -- rivalita' alta (70% o piu') e la squadra del marcatore ha vinto: frecciatina del giocatore della perdente e replica
        select r.grado into v_riv from public.rivalita r where r.team_a = least(v_squadra_gol, v_avv) and r.team_b = greatest(v_squadra_gol, v_avv);
        if coalesce(v_riv, 0) >= 70
           and ((v_m.home_team_id = v_squadra_gol and v_m.gol_home > v_m.gol_away) or (v_m.away_team_id = v_squadra_gol and v_m.gol_away > v_m.gol_home)) then
          select pi.id, p.nome into v_comp
            from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (v_m.tit_avv) and pi.team_id = v_avv
           order by hashtext('rb' || v_p.id || pi.id) limit 1;
          if v_comp.id is not null then
            v_id := private.social_rispondi(v_p.id, 'b1', 'giocatore', v_comp.nome, null, v_avv, v_squadra_gol, v_comp.id, 'rival_frecciatina', jsonb_build_object('NOME', v_scorer, 'S', v_tag_s));
            if v_id is not null then v_n := v_n + 1; end if;
            v_id := private.social_id_risposta(v_p.id, 'b1');
            if v_id is not null and private.social_rispondi(v_p.id, 'b2', 'giocatore', v_scorer, null, v_squadra_gol, v_avv, v_p.player_instance_id, 'rival_replica', jsonb_build_object('NOME', v_comp.nome), v_id) is not null then v_n := v_n + 1; end if;
          end if;
        end if;
      end if;

    -- addio di un giocatore: un ex compagno e un tifoso della vecchia squadra (toni diversi se se n'e' andato amaro)
    elsif v_p.chiave like 'scambio-giocatore:%' and v_p.team_id is not null and v_p.team2_id is not null and v_p.player_instance_id is not null then
      select fr.categoria into v_cat from private.frasi_social fr where 'social:' || fr.id = v_p.frase_origine;
      v_tag_s := '@' || private.handle_squadra((select nome from public.teams where id = v_p.team_id));
      v_tag_o := '@' || private.handle_squadra((select nome from public.teams where id = v_p.team2_id));
      select pi.id, p.nome into v_comp
        from public.player_instances pi join public.players p on p.id = pi.player_id
       where pi.team_id = v_p.team2_id and not pi.ritirato and pi.id <> v_p.player_instance_id
       order by hashtext('rx' || v_p.id || pi.id) limit 1;
      if v_comp.id is not null and private.social_rispondi(v_p.id, 'c', 'giocatore', v_comp.nome, null, v_p.team2_id, v_p.team_id, v_comp.id,
           case when v_cat = 'giocatore_amaro' then 'compagno_risposta_amaro' else 'saluto_compagno' end, jsonb_build_object('NOME', v_p.autore_nome)) is not null then v_n := v_n + 1; end if;
      select * into v_tf from private.social_tifoso('ry' || v_p.id, v_p.team2_id);
      if private.social_rispondi(v_p.id, 'f', 'tifosi', v_tf.nome, v_tf.handle, v_p.team2_id, v_p.team_id, null,
           case when v_cat = 'giocatore_amaro' then 'fan_addio_amaro' else 'fan_addio_sereno' end,
           jsonb_build_object('NOME', v_p.autore_nome, 'V', v_tag_o, 'X', v_tag_s)) is not null then v_n := v_n + 1; end if;
    end if;
  end loop;
  return v_n;
end;
$$;

-- Il feed e i mi piace contano anche i mi piace dei tifosi. Il feed si pagina per CONVERSAZIONI intere: p_limite
-- e' il numero di post "radice" (quelli che non rispondono a nessuno) e ognuno arriva con tutte le sue risposte,
-- cosi' un filo non si spezza fra due pagine. Le risposte programmate nel futuro non si vedono ancora.
drop function if exists public.social_feed(bigint, boolean, integer, integer);
create or replace function public.social_feed(
  p_league_id bigint, p_per_te boolean default true, p_limite integer default 40, p_offset integer default 0)
returns table (
  id bigint, autore_tipo text, autore_nome text, autore_handle text, team_id bigint, team2_id bigint,
  player_instance_id bigint, in_risposta_a bigint, testo text, creato_il timestamptz,
  n_mi_piace bigint, mio_mi_piace boolean, riguarda_me boolean)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_utente uuid := (select auth.uid());
  v_mia bigint;
begin
  if not (p_league_id = any (private.mie_leghe())) then return; end if;
  select t.id into v_mia from public.teams t where t.league_id = p_league_id and t.user_id = v_utente;

  return query
    with recursive radici as (
      select p.id as radice_id,
             row_number() over (
               order by case when p_per_te and v_mia is not null and (p.team_id = v_mia or p.team2_id = v_mia)
                                  and p.creato_il > now() - interval '3 days' then 0 else 1 end,
                        p.creato_il desc, p.id desc) as ordine
        from public.social_posts p
       where p.league_id = p_league_id and p.in_risposta_a is null and p.creato_il <= now()
       order by 2
       limit greatest(1, least(p_limite, 60)) offset greatest(0, p_offset)
    ), albero as (
      select r.radice_id, r.ordine, r.radice_id as post_id from radici r
      union all
      select a.radice_id, a.ordine, c.id
        from albero a join public.social_posts c on c.in_risposta_a = a.post_id and c.creato_il <= now()
    )
    select p.id, p.autore_tipo, p.autore_nome, p.autore_handle, p.team_id, p.team2_id, p.player_instance_id, p.in_risposta_a, p.testo, p.creato_il,
           (select count(*) from public.social_mi_piace l where l.post_id = p.id) + coalesce(p.mi_piace_fan, 0),
           exists (select 1 from public.social_mi_piace l where l.post_id = p.id and l.user_id = v_utente),
           coalesce(p.team_id = v_mia or p.team2_id = v_mia, false)
      from albero a join public.social_posts p on p.id = a.post_id
     order by a.ordine, p.creato_il, p.id;
end;
$function$;
revoke all on function public.social_feed(bigint, boolean, integer, integer) from public, anon;
grant execute on function public.social_feed(bigint, boolean, integer, integer) to authenticated;

CREATE OR REPLACE FUNCTION public.social_mi_piace(p_post_id bigint)
 RETURNS TABLE(mio boolean, totale bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_lega bigint;
begin
  select league_id into v_lega from public.social_posts where id = p_post_id;
  if v_lega is null or v_utente is null or not (v_lega = any (private.mie_leghe())) then
    raise exception using errcode = '42501', message = 'Post non disponibile.';
  end if;
  if exists (select 1 from public.social_mi_piace where post_id = p_post_id and user_id = v_utente) then
    delete from public.social_mi_piace where post_id = p_post_id and user_id = v_utente;
  else
    insert into public.social_mi_piace (post_id, user_id) values (p_post_id, v_utente);
  end if;
  return query select exists (select 1 from public.social_mi_piace where post_id = p_post_id and user_id = v_utente),
                      (select count(*) from public.social_mi_piace where post_id = p_post_id) + coalesce((select mi_piace_fan from public.social_posts where id = p_post_id), 0);
end;
$function$;

select cron.schedule('social-risposte', '*/5 * * * *', 'select private.social_risposte();');

commit;
