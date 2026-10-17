-- ============================================================
--  SOCIALONE: i tifosi e i giocatori reagiscono agli scambi (17 ottobre 2026, committente)
--  * I tifosi di ciascuna squadra commentano lo scambio: bene se arriva un giocatore migliore di quello
--    che parte, male se parte il migliore, con dubbi altrimenti.
--  * I giocatori che cambiano squadra (al massimo i 2 migliori per lato) pubblicano un saluto:
--    amaro, con qualche frecciatina, se se ne andavano scontenti (morale prima dello scambio sotto 45),
--    sereno altrimenti. Il morale di prima si salva al passaggio (private.trasferimenti_giocatori),
--    perche' il trigger lo ricalcola (parte da almeno 60).
-- ============================================================

begin;

create table private.trasferimenti_giocatori (
  id                 bigint generated always as identity primary key,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  team_da            bigint,
  team_a             bigint,
  morale_prima       smallint not null,
  creato_il          timestamptz not null default now()
);
create index trasferimenti_giocatori_pi_idx on private.trasferimenti_giocatori (player_instance_id, creato_il desc);

create or replace function private.morale_al_trasferimento()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.team_id is not null and old.team_id is distinct from new.team_id then
    insert into private.trasferimenti_giocatori (player_instance_id, team_da, team_a, morale_prima)
    values (new.id, old.team_id, new.team_id, coalesce(old.morale, 50));
    new.morale := least(100, greatest(60, coalesce(old.morale, 50) + 20))::smallint;
  end if;
  return new;
end;
$$;

create table private.frasi_social (
  id        integer generated always as identity primary key,
  categoria text not null check (categoria in ('tifosi_bene', 'tifosi_male', 'tifosi_neutro', 'giocatore_amaro', 'giocatore_sereno')),
  testo     text not null check (char_length(testo) between 1 and 300),
  unique (categoria, testo)
);
-- Segnaposto: {S} tag della squadra del tifoso, {IN} miglior giocatore in arrivo, {OUT} miglior giocatore
-- in uscita, {X} tag della nuova squadra del giocatore, {V} tag della vecchia.
insert into private.frasi_social (categoria, testo) values
  ('tifosi_bene', 'Che colpo!! {IN} da noi, la dirigenza ha fatto un capolavoro {S} 🔥'),
  ('tifosi_bene', 'Finalmente un acquisto serio. Benvenuto {IN}! {S}'),
  ('tifosi_bene', 'Con {IN} adesso possiamo sognare in grande. Forza {S}!'),
  ('tifosi_bene', '{IN} in maglia {S}?? Ditemi che non sto sognando 😍'),
  ('tifosi_bene', 'Mercato da applausi. {IN} è esattamente quello che ci serviva {S}'),
  ('tifosi_bene', 'Benvenuto {IN}! Ora tocca a te farci godere {S} 💪'),
  ('tifosi_bene', 'Un affare, punto. {IN} per {OUT}? Lo rifarei mille volte {S}'),
  ('tifosi_bene', 'Bravi, bravissimi. {IN} alza il livello della squadra {S}'),
  ('tifosi_bene', 'Finalmente qualcuno che sa fare mercato. {IN} benvenuto {S} ❤️'),
  ('tifosi_bene', 'Notte insonne: {IN} è nostro!! Forza {S}'),
  ('tifosi_male', 'Cedere {OUT}?? Ma siete impazziti? Vergogna {S}'),
  ('tifosi_male', 'Se ne va {OUT} e ci arriva {IN}... non capisco proprio {S}'),
  ('tifosi_male', 'Addio {OUT}, mi dispiace da morire. Spero sappiate cosa state facendo {S}'),
  ('tifosi_male', 'Ma che mercato è questo? Senza {OUT} siamo più deboli {S} 😡'),
  ('tifosi_male', 'Ci avete tolto {OUT}. Qualcuno mi spieghi il piano perché io non lo vedo {S}'),
  ('tifosi_male', 'Il migliore se ne va e noi stiamo zitti? Dai {S}, ma stiamo scherzando?'),
  ('tifosi_male', '{OUT} era uno dei pochi che ci metteva il cuore. Che peccato {S}'),
  ('tifosi_male', 'Mi è passata la voglia di guardare le partite. Via {OUT}, ma perché {S}'),
  ('tifosi_male', 'Mercato da incubo. {OUT} non si tocca, scusate ma non lo accetto {S}'),
  ('tifosi_male', 'Ciao {OUT}, ti volevamo bene. Alla dirigenza dico solo: speriamo bene {S} 😔'),
  ('tifosi_neutro', 'Scambio fatto. Aspettiamo di vedere cosa fanno in campo, io ho fiducia {S}'),
  ('tifosi_neutro', 'Mah, vedremo. Mi fido del mister {S}'),
  ('tifosi_neutro', 'Non so se sia un affare o una fregatura, la risposta la dà il campo {S}'),
  ('tifosi_neutro', 'Un po'' di movimento fa sempre bene. Vediamo che succede {S}'),
  ('tifosi_neutro', 'Scambio che divide, io non ho ancora un''idea. {S}'),
  ('tifosi_neutro', 'Se il mister lo ha voluto ci sarà un motivo. Forza {S}'),
  ('tifosi_neutro', 'Si cambia qualcosa, speriamo sia la mossa giusta {S}'),
  ('tifosi_neutro', 'Né carne né pesce questo scambio. Ai fatti {S}'),
  ('tifosi_neutro', 'Fiducia alla società, anche stavolta. {S} 🤞'),
  ('tifosi_neutro', 'Vedremo se ha senso. Intanto forza {S}'),
  ('giocatore_amaro', 'Ho sempre dato tutto per questa maglia, vado via con la coscienza a posto. Un giorno la verità verrà a galla. Ora concentrato e felice per la nuova avventura 💪'),
  ('giocatore_amaro', 'Non tutti hanno saputo apprezzarmi, ma io non dimentico chi ha creduto in me. Si volta pagina, forza {X}.'),
  ('giocatore_amaro', 'Alcune cose è meglio non dirle. Ho dato tutto, il resto lo sa chi c''era. Ora solo {X}.'),
  ('giocatore_amaro', 'Quando non sei più al centro del progetto, è giusto andare dove ti vogliono. Grazie a chi mi è stato vicino davvero.'),
  ('giocatore_amaro', 'Ho passato mesi a dimostrare il mio valore. Ora lo farò altrove. Chi ha capito, ha capito.'),
  ('giocatore_amaro', 'Non ho nulla da rimproverarmi: il campo ha sempre parlato per me. Si riparte con {X} 🔥'),
  ('giocatore_amaro', 'Ho lasciato tutto me stesso, qualcun altro lasci un po'' di onestà. Nuova avventura, nuova energia.'),
  ('giocatore_amaro', 'Ai tifosi va il mio grazie sincero. Ad altri, nessun messaggio. Forza {X}.'),
  ('giocatore_amaro', 'La verità prima o poi esce sempre. Intanto vado via a testa alta.'),
  ('giocatore_amaro', 'Mi hanno messo da parte, ma ora è tutto alle spalle. Felice di ripartire con {X}.'),
  ('giocatore_amaro', 'Ho dato anima e corpo e ho ricevuto poco in cambio. Ora è il momento di pensare solo a me stesso e a {X}.'),
  ('giocatore_amaro', 'Non servono tanti discorsi. Chi mi conosce sa che persona sono. Avanti, {X}!'),
  ('giocatore_sereno', 'Grazie a tutti: compagni, mister e tifosi. È stato un onore indossare questa maglia. Ora una nuova sfida con {X}!'),
  ('giocatore_sereno', 'Si chiude un capitolo bellissimo. Porto con me ricordi indimenticabili. Pronto per {X} 💪'),
  ('giocatore_sereno', 'Grazie per ogni singolo momento a {V}. Il mio cuore resterà sempre lì. Forza {X} da oggi!'),
  ('giocatore_sereno', 'Lascio {V} con un sorriso e tanta gratitudine. Adesso testa e cuore a {X}.'),
  ('giocatore_sereno', 'Ringrazio tutti per questi mesi insieme. Nuova avventura, tanta voglia di fare bene {X} 🔥'),
  ('giocatore_sereno', 'Un abbraccio ai compagni e ai tifosi di {V}. Ci vediamo in campo, ora forza {X}!'),
  ('giocatore_sereno', 'Cambio maglia ma non dimentico niente: grazie {V}. Carico per {X}!'),
  ('giocatore_sereno', 'Si va! Grazie di cuore a chi mi ha voluto bene. Da oggi con {X} per dare il massimo.'),
  ('giocatore_sereno', 'Che bella esperienza è stata. Grazie {V}. Ora sono felicissimo di essere qui, forza {X}!'),
  ('giocatore_sereno', 'Tanta emozione nel salutare {V}. Adesso solo voglia di ripartire con {X} 💪')
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
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, team2_id, testo, creato_il)
  select f.league_id, 'scambio-tifosi:' || f.trade_id || ':' || f.team_id, 'tifosi',
         (private.tifoso_finto('st' || f.trade_id || f.team_id, f.nome_squadra)).nome,
         (private.tifoso_finto('st' || f.trade_id || f.team_id, f.nome_squadra)).handle,
         f.team_id, f.altra_id,
         replace(replace(replace(
           (select fr.testo from private.frasi_social fr where fr.categoria = f.categoria
             order by hashtext('st' || f.trade_id || ':' || f.team_id || ':' || fr.id), fr.id limit 1),
           '{S}', '@' || private.handle_squadra(f.nome_squadra)),
           '{IN}', coalesce(f.in_nome, 'il nuovo arrivato')), '{OUT}', coalesce(f.out_nome, 'il giocatore ceduto')),
         f.risolta_il + interval '20 seconds'
  from tifosi f
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
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, player_instance_id, testo, creato_il)
  select s.league_id, 'scambio-giocatore:' || s.trade_id || ':' || s.pi_id, 'giocatore', s.nome, s.team_a, s.team_da, s.pi_id,
         replace(replace(
           (select fr.testo from private.frasi_social fr
             where fr.categoria = case when s.morale_prima < 45 then 'giocatore_amaro' else 'giocatore_sereno' end
             order by hashtext('sg' || s.trade_id || ':' || s.pi_id || ':' || fr.id), fr.id limit 1),
           '{X}', '@' || private.handle_squadra(s.nome_nuova)), '{V}', '@' || private.handle_squadra(s.nome_vecchia)),
         s.risolta_il + interval '45 seconds'
  from spostati s
  where s.ordine <= 2
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  return v_nuovi;
end;
$function$;

commit;
