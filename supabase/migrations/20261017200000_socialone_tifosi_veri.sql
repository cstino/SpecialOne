-- ============================================================
--  SOCIALONE: i tifosi come persone vere (17 ottobre 2026)
--  Ogni post dei tifosi lo firma una persona diversa (nome e @nome inventati, verosimili, mai
--  persone reali), che scrive come sui social: linguaggio informale, anche qualche parolaccia, e
--  cita la squadra con @ (es. "dai ragazzi @cocacolers, come cazzo si fa a perdere cosi'?").
--  Reagiscono alle conferenze (testo dall'AI) e ai risultati (frasi modello, nessun costo di AI).
-- ============================================================

begin;

alter table public.social_posts add column if not exists autore_handle text check (autore_handle is null or char_length(autore_handle) between 1 and 30);

-- La @ di una squadra: stessa regola dell'app (minuscolo, senza accenti, '_' al posto del resto).
create or replace function private.handle_squadra(p_nome text)
returns text
language sql immutable set search_path = ''
as $$
  select left(trim(both '_' from regexp_replace(lower(translate(coalesce(p_nome, ''),
    'àáâäãèéêëìíîïòóôöõùúûüçñÀÁÂÄÈÉÊËÌÍÎÏÒÓÔÖÙÚÛÜÇÑ', 'aaaaaeeeeiiiiooooouuuucnAAAAEEEEIIIIOOOOUUUUCN')), '[^a-z0-9]+', '_', 'g')), 22)
$$;

-- Un tifoso inventato, sempre lo stesso per lo stesso seme: nome visibile e @nome.
create or replace function private.tifoso_finto(p_seme text, p_squadra text, out nome text, out handle text)
language plpgsql immutable set search_path = ''
as $$
declare
  v_h integer := abs(hashtext(p_seme));
  v_nomi text[] := array['Marco','Luca','Giuseppe','Andrea','Francesco','Alessandro','Davide','Simone','Matteo','Lorenzo',
    'Stefano','Fabio','Antonio','Roberto','Paolo','Gianluca','Federico','Riccardo','Daniele','Emanuele',
    'Giulia','Chiara','Sara','Martina','Francesca','Elena','Valentina','Alessia','Ilaria','Silvia','Nicola','Gabriele','Mattia','Tommaso','Salvatore'];
  v_cognomi text[] := array['R.','B.','C.','D.','F.','G.','L.','M.','P.','S.','T.','V.','Esposito','Russo','Ferrari','Romano','Colombo','Ricci','Marino','Greco','Bruno','Gallo','Conti','De Luca','Costa','Fontana'];
  v_sq text := private.handle_squadra(p_squadra);
  v_primo text := v_nomi[1 + v_h % array_length(v_nomi, 1)];
  v_sec text := v_cognomi[1 + (v_h / 7) % array_length(v_cognomi, 1)];
  v_anno text := (1975 + (v_h / 13) % 32)::text;
  v_stile integer := (v_h / 101) % 8;
begin
  nome := case v_stile
    when 0 then 'Ultrà ' || p_squadra
    when 1 then v_primo || ' 🔥'
    when 2 then v_primo || ' ' || v_sec || ' ⚽'
    when 3 then 'Curva ' || p_squadra
    else v_primo || ' ' || v_sec end;
  handle := left(case v_stile
    when 0 then 'ultras_' || v_sq
    when 1 then lower(v_primo) || '_' || right(v_anno, 2)
    when 2 then lower(v_primo) || '_' || rtrim(left(v_sq, 10), '_')
    when 3 then 'curva_' || v_sq || '_' || right(v_anno, 2)
    when 4 then left(v_sq, 12) || '_forever_' || right(v_anno, 2)
    when 5 then lower(v_primo) || '.' || lower(left(regexp_replace(v_sec, '[^A-Za-z]', '', 'g'), 8))
    when 6 then 'forza_' || left(v_sq, 14) || '_' || right(v_anno, 2)
    else lower(v_primo) || v_anno end, 30);
  handle := rtrim(handle, '_.');
end;
$$;

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
         replace(replace(replace(replace(private.social_scegli('tp' || x.match_id || ':' || x.team_id,
           case
             when x.fatti - x.subiti >= 3 then array[
               'Che spettacolo {S} 🔥 {F}-{G}, così si gioca!!',
               'Godo come un riccio. {S} asfalta {O}, avanti così ragazzi',
               '{F}-{G} e a casa. Questa squadra è da scudetto, punto. {S}',
               'Ma quanto siamo forti?? {S} vi amo 😍',
               'Partita mai in discussione. {O} non pervenuti 😂 forza {S}',
               'Oggi si vola. {F}-{G}, {O} rimandati a casa con la valigia {S} 🚀',
               'Non c''è stata partita. Che squadra ragazzi, che squadra {S}',
               'Ho visto calcio vero stasera. {S} tutta la vita ❤️',
               '{O} chi?? 😂 {S} devastanti',
               'Da brividi. Giocatori, mister, tutti: grazie {S}']
             when x.fatti > x.subiti then array[
               'Tre punti sudati ma pesantissimi. Forza {S}! 💪',
               'Sofferto fino alla fine ma ce l''abbiamo fatta, grandi ragazzi {S}',
               'Non bellissimi ma vincenti. Mi va benissimo così {S}',
               'VITTORIAAAA 🙌 {S} cuore e grinta',
               '{F}-{G} a {O} e si va a letto felici. {S} ❤️',
               'Che sofferenza ma che gioia!! {S} non mollare mai 🔥',
               'Tre punti e zitti. Questo serve {S}',
               'Ci siamo! Avanti così {S}, la strada è giusta',
               'Partita sporca ma l''importante era vincere. Bravi {S} 👏',
               'Battuti anche {O}. Testa alta e pedalare {S}']
             when x.fatti = x.subiti then array[
               'Pareggio che non serve a niente. Dai {S} sveglia',
               'Un punto è meglio di niente ma che fatica guardarvi {S}',
               '{F}-{G} con {O}... due punti buttati, ditemi che non sono l''unico incazzato {S}',
               'Pari giusto, ma da {S} mi aspetto di più',
               'Mah. Né carne né pesce. {S} così non si va da nessuna parte',
               'Pareggino. Ok, ma prima o poi bisogna tornare a vincere {S}',
               'Punto d''oro o occasione persa? Io dico la seconda {S}',
               'Ci accontentiamo... ma che fatica {S} 😮‍💨',
               '{F}-{G}, partita brutta da vedere. {S} serve più coraggio',
               'Contro {O} dovevamo vincerla. Punto. {S}']
             when x.subiti - x.fatti >= 3 then array[
               'Dai ragazzi {S}, come cazzo si fa a perdere così? Vergogna',
               '{F}-{G}. Non ho parole, solo rabbia. {S} svegliatevi',
               'Imbarazzanti. Ma vi rendete conto? {S} giocate per la maglia o no?',
               'Presi a pallonate da {O}. Che schifo {S}',
               'Spengo la tv e vado a dormire. {S} fate pena oggi',
               '{F}-{G}?? Mi vergogno di avervi seguito stasera {S}',
               'Una disfatta. Qualcuno ci deve delle scuse {S}',
               'Tutti a casa. Così non si può andare avanti {S}',
               'Pagare per vedere questo schifo... {S} svegliatevi cazzo',
               'Umiliati da {O}. Giornata nera per {S}']
             else array[
               'Sconfitta che fa male. Dai {S}, rialziamoci subito',
               'Ma come si fa a perdere con {O}?? {S} serve una scossa',
               'Ennesima delusione. {S} così non va, qualcuno deve dare spiegazioni',
               'Brucia. {F}-{G} e niente da dire, testa alla prossima {S}',
               'Non ci siamo proprio. Dai {S}, tiratevi fuori le palle',
               'Perdere con {O} non è accettabile. {S} serve una reazione subito',
               'Che rabbia. {F}-{G} e torniamo a casa con niente {S}',
               'Ok la sconfitta, ma l''atteggiamento no. {S} più fame',
               'Un''altra domenica storta. Forza {S} che ci si rialza',
               'Siete lenti, molli, senza idee. Dai {S} cazzo']
           end),
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
