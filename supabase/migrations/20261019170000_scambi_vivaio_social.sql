-- ============================================================
--  SocialOne e scambi con prospetti del vivaio e sole scelte (19/10/2026, richiesta del committente).
--  - L'annuncio HERE WE GO elenca anche i prospetti del vivaio e le scelte di draft ("cede X, Y (vivaio), 2 scelte di draft").
--  - Gli scambi senza giocatori della rosa (solo prospetti o sole scelte) hanno frasi dei tifosi dedicate: categorie
--    tifosi_vivaio e tifosi_scelte. La notifica HERE WE GO partiva gia' per ogni scambio accettato.
--  Funzione social_genera riscritta dalla definizione viva.
-- ============================================================
begin;

create or replace function private.descrizione_cessione(p_giocatori bigint[], p_vivaio bigint[], p_scelte bigint[])
returns text language sql stable security definer set search_path = '' as $f$
  select coalesce(nullif(array_to_string(array_remove(array[
    (select string_agg(p.nome, ', ') from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = any (p_giocatori)),
    (select string_agg(p.nome || ' (vivaio)', ', ') from public.vivaio_prospetti v join public.players p on p.id = v.player_id where v.id = any (p_vivaio)),
    case when cardinality(coalesce(p_scelte, '{}')) > 0
         then cardinality(p_scelte) || case when cardinality(p_scelte) = 1 then ' scelta di draft' else ' scelte di draft' end end
  ], null), ', '), ''), 'niente')
$f$;

alter table private.frasi_social drop constraint frasi_social_categoria_check;
alter table private.frasi_social add constraint frasi_social_categoria_check
  check (categoria in ('tifosi_bene', 'tifosi_male', 'tifosi_neutro', 'giocatore_amaro', 'giocatore_sereno', 'tifosi_scelte', 'tifosi_vivaio'));

insert into private.frasi_social (id, categoria, testo) overriding system value values
(459, 'tifosi_scelte', $q$mi hanno venduto il futuro?? almeno la scelta era buona? {S} 🤔$q$),
(460, 'tifosi_scelte', $q$scambio di scelte, la dirigenza gioca a fare l'NBA eh {S} 😅$q$),
(461, 'tifosi_scelte', $q$ok la scelta è andata, speriamo che chi arriva valga il draft {S}$q$),
(462, 'tifosi_scelte', $q$scambiare le scelte come le figurine, mi piace {S} 🔥$q$),
(463, 'tifosi_scelte', $q$se la scelta finisce fra le prime vi prendo a pomodori {S} 🍅$q$),
(464, 'tifosi_scelte', $q$finalmente una dirigenza con le idee chiare... o forse no? {S}$q$),
(465, 'tifosi_scelte', $q$scelta ceduta, aspettiamo di vedere chi ci perde {S} 👀$q$),
(466, 'tifosi_scelte', $q$movimento intelligente sul draft, bravi {S} 👏$q$),
(467, 'tifosi_scelte', $q$ma che senso ha regalare le scelte?? {S} 🤦$q$),
(468, 'tifosi_scelte', $q$scelte scambiate, vediamo chi ride a fine stagione {S}$q$),
(469, 'tifosi_scelte', $q$il futuro è dei coraggiosi, e voi lo siete {S} 💪$q$),
(470, 'tifosi_scelte', $q$non capisco niente di scelte ma mi fido {S}$q$),
(471, 'tifosi_scelte', $q$se è un colpo di genio lo scopriamo al draft {S}$q$),
(472, 'tifosi_scelte', $q$mi sa che qui qualcuno ha fregato qualcuno {S} 😏$q$),
(473, 'tifosi_scelte', $q$scelte di qua, scelte di là: spero abbiate un piano {S}$q$),
(474, 'tifosi_scelte', $q$bella mossa sul draft, aspettiamo i frutti {S} 🌱$q$),
(475, 'tifosi_vivaio', $q${OUT} dal vivaio se ne va, speriamo non diventi un campione altrove {S} 😬$q$),
(476, 'tifosi_vivaio', $q$il ragazzo del vivaio cambia aria: auguri a {OUT} {S}$q$),
(477, 'tifosi_vivaio', $q$un giovane in più per noi: benvenuto {IN} {S} 🌱$q$),
(478, 'tifosi_vivaio', $q${IN} dal vivaio, vediamo se ha il talento giusto {S} 👀$q$),
(479, 'tifosi_vivaio', $q$cediamo {OUT} ma intanto arriva {IN}, il vivaio gira {S}$q$),
(480, 'tifosi_vivaio', $q$scambiare i giovani come le carte, mi piace il coraggio {S} 😎$q$),
(481, 'tifosi_vivaio', $q$se {IN} diventa forte siete dei geni {S} 🧠$q$),
(482, 'tifosi_vivaio', $q$il vivaio è il futuro, speriamo si sia scelto bene {S}$q$),
(483, 'tifosi_vivaio', $q$mi dispiace per {OUT}, aveva un bel potenziale {S} 😔$q$),
(484, 'tifosi_vivaio', $q$giovane promessa in arrivo: {IN}, ti aspettiamo {S} 💪$q$),
(485, 'tifosi_vivaio', $q$scambio di prospetti, vediamo chi ha fiutato l'affare {S}$q$),
(486, 'tifosi_vivaio', $q$se {OUT} spacca altrove mi mangio le mani {S} 😭$q$),
(487, 'tifosi_vivaio', $q$bel colpo di scouting con {IN} {S} 🔭$q$),
(488, 'tifosi_vivaio', $q$il vivaio non si tocca... e invece {S} 🤦$q$),
(489, 'tifosi_vivaio', $q$ok {IN} nel vivaio, ora serve pazienza {S}$q$),
(490, 'tifosi_vivaio', $q$fiducia piena nei giovani, forza {IN} {S} 🙌$q$);

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
         td.nome || ' cede ' || private.descrizione_cessione(tp.giocatori_offerti, tp.vivaio_offerti, tp.scelte_offerte) ||
         '; ' || tt.nome || ' cede ' || private.descrizione_cessione(tp.giocatori_richiesti, tp.vivaio_richiesti, tp.scelte_richieste) || '.',
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
         case when char_length(d.risposta) > 700 then left(d.risposta, 697) || '...' else d.risposta end, d.risposta_il - interval '1 second'
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
           tp.giocatori_offerti as out_ids, tp.giocatori_richiesti as in_ids,
           tp.vivaio_offerti as out_viv, tp.vivaio_richiesti as in_viv,
           cardinality(tp.scelte_offerte) + cardinality(tp.scelte_richieste) as n_scelte
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
    union all
    select tp.id, tp.league_id, tp.risolta_il, tp.a_team_id, tp.da_team_id, tp.giocatori_richiesti, tp.giocatori_offerti,
           tp.vivaio_richiesti, tp.vivaio_offerti, cardinality(tp.scelte_offerte) + cardinality(tp.scelte_richieste)
      from public.trade_proposals tp join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
     where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
  ), tifosi as (
    select x.*, case
        when x.out_best is null and x.in_best is null then
          case when cardinality(x.out_viv) + cardinality(x.in_viv) > 0 then 'tifosi_vivaio'
               when x.n_scelte > 0 then 'tifosi_scelte'
               else 'tifosi_neutro' end
        when x.in_best is null then case when x.out_best >= 78 then 'tifosi_male' else 'tifosi_neutro' end
        when x.out_best is null then case when x.in_best >= 78 then 'tifosi_bene' else 'tifosi_neutro' end
        when x.in_best >= x.out_best + 3 then 'tifosi_bene'
        when x.out_best >= x.in_best + 3 then 'tifosi_male'
        else 'tifosi_neutro' end as categoria
    from (
      select l.*, t.nome as nome_squadra,
        coalesce((select p.nome from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = any (l.out_ids) order by pi.overall_corrente desc, pi.id limit 1),
                 (select p.nome from public.vivaio_prospetti v join public.players p on p.id = v.player_id where v.id = any (l.out_viv) order by p.overall desc, v.id limit 1)) as out_nome,
        (select max(pi.overall_corrente) from public.player_instances pi where pi.id = any (l.out_ids)) as out_best,
        coalesce((select p.nome from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = any (l.in_ids) order by pi.overall_corrente desc, pi.id limit 1),
                 (select p.nome from public.vivaio_prospetti v join public.players p on p.id = v.player_id where v.id = any (l.in_viv) order by p.overall desc, v.id limit 1)) as in_nome,
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

commit;
