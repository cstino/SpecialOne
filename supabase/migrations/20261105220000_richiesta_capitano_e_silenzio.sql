-- Richieste dei giocatori, Season 3 (docs/DIARIO-SEASON3.md voce 11, decisioni del committente del 5/11/2026).
-- 1) Il capitano puo' chiedere un giorno libero per la squadra (tipo 'giorno_libero'). Risposta a testo libero
--    valutata dall'AI come le altre: se il mister concede il giorno libero, condizione -8 a tutta la rosa e morale
--    +4 a tutti; se lo nega, morale -4 a tutti. Le parole spostano l'effetto del voto (da -3 a +1,5), arrotondato.
--    Nasce dopo una vittoria, al massimo 3 volte a stagione (2-3 per una squadra che vince spesso) e a distanza
--    di almeno 6 giornate, mai nei playoff.
-- 2) Una richiesta lasciata scadere non e' piu' gratis: vale come un rifiuto secco (voto -1,5) e il giocatore si
--    sfoga su SocialOne. Per il capitano il calo di morale tocca tutta la rosa.

alter table public.richieste_giocatori drop constraint richieste_giocatori_tipo_check;
alter table public.richieste_giocatori add constraint richieste_giocatori_tipo_check
  check (tipo = any (array['titolare', 'spazio', 'riposo', 'giorno_libero']));
alter table public.richieste_giocatori drop constraint richieste_giocatori_stato_check;
alter table public.richieste_giocatori add constraint richieste_giocatori_stato_check
  check (stato = any (array['aperta', 'risposta', 'promessa', 'mantenuta', 'tradita', 'decaduta', 'scaduta', 'accettata', 'rifiutata']));
-- Una richiesta personale e una del capitano possono cadere sulla stessa giornata.
alter table public.richieste_giocatori drop constraint richieste_giocatori_team_id_giornata_target_key;
create unique index richieste_giocatori_team_giornata_capitano
  on public.richieste_giocatori (team_id, giornata_target, (tipo = 'giorno_libero'));

-- Effetto di un voto sul morale di un giocatore: stessa formula delle risposte (smorzata vicino agli estremi,
-- arrotondamento casuale della parte decimale). Restituisce la variazione applicata.
create or replace function private.richiesta_morale_giocatore(p_instance_id bigint, p_voto numeric)
returns smallint
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_morale smallint;
  v_esatto numeric;
  v_nuovo smallint;
begin
  select morale into v_morale from public.player_instances where id = p_instance_id for update;
  if v_morale is null then return 0; end if;
  v_esatto := v_morale + p_voto * 3 * case when p_voto > 0 then greatest(0.35, least(1, (100 - v_morale) / 50.0))
                                            else greatest(0.35, least(1, v_morale / 50.0)) end;
  v_nuovo := greatest(0, least(100, floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;
  update public.player_instances set morale = v_nuovo where id = p_instance_id;
  return v_nuovo - v_morale;
end $$;

-- Giorno libero del capitano: morale (+4 se concesso, -4 se negato, piu' il voto) a tutta la rosa disponibile
-- (esclusi ritirati e giocatori in prestito); se concesso, condizione -8. Restituisce la variazione di morale.
create or replace function private.applica_giorno_libero(p_team_id bigint, p_voto numeric, p_concesso boolean)
returns smallint
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_delta smallint := round(case when p_concesso then 4 else -4 end + p_voto)::smallint;
begin
  update public.player_instances
     set morale = greatest(0, least(100, morale + v_delta)),
         condizione = case when p_concesso then greatest(0, condizione - 8) else condizione end
   where team_id = p_team_id and not ritirato and prestito_id is null;
  return v_delta;
end $$;

CREATE OR REPLACE FUNCTION public.applica_richiesta(p_id bigint, p_voto numeric, p_promessa boolean, p_reazione text, p_valutazione jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r public.richieste_giocatori;
  v_voto numeric := greatest(-3, least(1.5, coalesce(p_voto, 0)));
  v_effetto smallint;
begin
  select * into v_r from public.richieste_giocatori where id = p_id;
  if not found then raise exception 'Richiesta % inesistente.', p_id; end if;
  -- Richiesta del capitano: p_promessa vuol dire "giorno libero concesso"; l'effetto tocca tutta la rosa.
  if v_r.tipo = 'giorno_libero' then
    v_effetto := private.applica_giorno_libero(v_r.team_id, v_voto, p_promessa);
    update public.richieste_giocatori
       set stato = case when p_promessa then 'accettata' else 'rifiutata' end,
           voto = v_voto, reazione = left(p_reazione, 200), effetto_morale = v_effetto, valutazione = p_valutazione
     where id = p_id;
    return v_effetto::numeric;
  end if;
  v_effetto := private.richiesta_morale_giocatore(v_r.player_instance_id, v_voto);
  update public.richieste_giocatori
     set stato = case when p_promessa then 'promessa' else 'risposta' end,
         voto = v_voto, reazione = left(p_reazione, 200), effetto_morale = v_effetto, valutazione = p_valutazione
   where id = p_id;
  return v_effetto::numeric;
end;
$function$;

-- Richieste lasciate scadere: rifiuto secco (voto -1,5) e sfogo su SocialOne.
create or replace function private.scadi_richieste()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_r record;
  v_effetto smallint;
  v_n integer := 0;
begin
  for v_r in
    select r.*, p.nome, t.user_id
    from public.richieste_giocatori r
    join public.player_instances pi on pi.id = r.player_instance_id
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = r.team_id
    -- una risposta in valutazione da piu' di 10 minuti e' rimasta a meta' (AI caduta): conta come nessuna risposta
    where r.stato = 'aperta' and r.scade_il < now() and (r.risposta is null or r.risposta_il < now() - interval '10 minutes')
    for update of r skip locked
  loop
    if v_r.tipo = 'giorno_libero' then
      v_effetto := private.applica_giorno_libero(v_r.team_id, -1.5, false);
    else
      v_effetto := private.richiesta_morale_giocatore(v_r.player_instance_id, -1.5);
    end if;
    update public.richieste_giocatori set stato = 'scaduta', voto = -1.5, effetto_morale = v_effetto where id = v_r.id;

    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
    values (v_r.league_id, 'ignorata:' || v_r.id, 'giocatore', v_r.nome, v_r.team_id, v_r.player_instance_id,
      case when v_r.tipo = 'giorno_libero' then private.social_scegli('ig' || v_r.id, array[
             'Ho chiesto al mister un giorno di riposo a nome di tutto il gruppo. Nessuna risposta. Lo spogliatoio se lo ricorderà.',
             'Da capitano ho portato al mister una richiesta della squadra. Silenzio totale. Non è così che si guida un gruppo.',
             'Volevamo solo un giorno libero, lo abbiamo chiesto con rispetto. Il mister non si è nemmeno degnato di rispondere.'])
      else private.social_scegli('ig' || v_r.id, array[
             'Ho scritto al mister. Nemmeno una risposta. Evidentemente non conto niente qui. 😶',
             'Chiedere un confronto e ricevere il silenzio: questa è la considerazione che ho in questa squadra.',
             'Messaggio al mister: visualizzato e ignorato. Ne prendo atto.',
             'Non pretendevo un sì, mi bastava una risposta. Neanche quella.'])
      end, now())
    on conflict (league_id, chiave) do nothing;

    perform private.notifica(v_r.user_id, v_r.league_id, 'sistema', 'Richiesta ignorata',
      case when v_r.tipo = 'giorno_libero'
        then 'Non hai risposto al capitano ' || v_r.nome || ': morale ' || v_effetto || ' a tutta la squadra, e si è sfogato sui social.'
        else v_r.nome || ' si è sentito ignorato: morale ' || v_effetto || ', e si è sfogato sui social.' end,
      jsonb_build_object('player_instance_id', v_r.player_instance_id, 'view', 'spogliatoio'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Richiesta del capitano: dopo una vittoria nell'ultima partita giocata, con probabilita' 8 / giornate della stagione
-- regolare (deterministico, come le altre; Serie F 8/22 = 36%), al massimo 3 a stagione e a 6 giornate di distanza.
-- In simulazione: 2 a stagione per una squadra media, 2-3 per chi vince spesso, 1-2 per chi vince poco. Serve un capitano
-- disponibile (non infortunato, non squalificato, non in prestito).
create or replace function private.genera_richiesta_capitano(p_team_id bigint, p_league_id bigint, p_user_id uuid, p_stagione smallint, p_giornata smallint)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_cap bigint;
  v_nome text;
  v_gf smallint;
  v_gs smallint;
  v_testo text;
begin
  if exists (select 1 from public.richieste_giocatori r where r.team_id = p_team_id and r.giornata_target = p_giornata and r.tipo = 'giorno_libero') then
    return false;
  end if;
  if (select count(*) from public.richieste_giocatori r where r.team_id = p_team_id and r.stagione = p_stagione and r.tipo = 'giorno_libero') >= 3 then
    return false;
  end if;
  if exists (select 1 from public.richieste_giocatori r where r.team_id = p_team_id and r.stagione = p_stagione and r.tipo = 'giorno_libero'
             and r.giornata_target > p_giornata - 6) then
    return false;
  end if;
  if abs(hashtext('cap' || p_team_id || ':' || p_giornata)) % 1000 >=
     1000.0 * 8 / greatest(1, (select giornate_totali from public.leagues where id = p_league_id)) then
    return false;
  end if;

  select case when f.home_team_id = p_team_id then m.gol_home else m.gol_away end,
         case when f.home_team_id = p_team_id then m.gol_away else m.gol_home end
    into v_gf, v_gs
  from public.fixtures f join public.matches m on m.fixture_id = f.id
  where f.league_id = p_league_id and f.stato = 'simulata' and p_team_id in (f.home_team_id, f.away_team_id)
  order by f.data_sim desc, m.id desc limit 1;
  if v_gf is null or v_gf <= v_gs then return false; end if;

  select pi.id, p.nome into v_cap, v_nome
  from public.teams t join public.player_instances pi on pi.id = t.capitano and pi.team_id = t.id
  join public.players p on p.id = pi.player_id
  where t.id = p_team_id and not pi.ritirato and pi.prestito_id is null and pi.infortunato_fino_a <= 0 and pi.squalificato_fino_a <= 0;
  if v_cap is null then return false; end if;

  v_testo := private.social_scegli('cap' || p_team_id || ':' || p_giornata, array[
    'Mister, a nome di tutto lo spogliatoio: dopo questa vittoria i ragazzi le chiedono un giorno libero dagli allenamenti. Ce lo siamo meritato.',
    'Mister, parlo da capitano. Il gruppo ha dato tanto: un giorno libero per staccare la testa ci farebbe bene. Che ne dice?',
    'Buongiorno mister, la squadra mi ha chiesto di farmi portavoce: ci concederebbe un giorno di riposo dagli allenamenti?',
    'Mister, vittoria importante. I ragazzi vorrebbero festeggiare con un giorno libero. Le chiedo di pensarci, per il gruppo.']);
  insert into public.richieste_giocatori (league_id, team_id, player_instance_id, tipo, testo, giornata_target, stagione)
  values (p_league_id, p_team_id, v_cap, 'giorno_libero', v_testo, p_giornata, p_stagione)
  on conflict do nothing;
  if not found then return false; end if;
  perform private.notifica(p_user_id, p_league_id, 'sistema', 'Il capitano vuole parlarle',
    'Mister, ' || v_nome || ' le chiede un giorno libero per la squadra. Apri la home per rispondere.',
    jsonb_build_object('richiesta', true, 'view', 'spogliatoio'));
  return true;
end $$;

CREATE OR REPLACE FUNCTION private.verifica_richieste()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r record;
  v_m record;
  v_in_campo boolean;
  v_minuti numeric;
  v_casa boolean;
  v_manca boolean;
  v_ok boolean;
  v_nome text;
  v_user uuid;
  v_n integer := 0;
begin
  -- Scadute senza risposta: rifiuto secco e sfogo sui social (5/11/2026).
  perform private.scadi_richieste();

  for v_r in
    select r.* from public.richieste_giocatori r
    join public.leagues l on l.id = r.league_id and l.conferenze_stampa
    where r.stato = 'promessa'
  loop
    select m.id, m.titolari_home, m.titolari_away, f.home_team_id into v_m
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    where f.league_id = v_r.league_id and f.giornata = v_r.giornata_target and v_r.team_id in (f.home_team_id, f.away_team_id)
      and f.season_id in (select s.id from public.seasons s join public.leagues l2 on l2.id = s.league_id and s.numero = l2.stagione_corrente where s.league_id = v_r.league_id)
    order by m.id desc limit 1;
    continue when v_m.id is null;

    v_casa := v_m.home_team_id = v_r.team_id;
    v_in_campo := v_r.player_instance_id = any(case when v_casa then v_m.titolari_home else v_m.titolari_away end);
    select coalesce(sum(ms.minuti), 0) into v_minuti from public.match_stats ms where ms.match_id = v_m.id and ms.player_instance_id = v_r.player_instance_id;
    select p.nome, t.user_id,
           (pi.infortunato_fino_a > 0 or pi.squalificato_fino_a > 0) and not v_in_campo and v_minuti = 0
      into v_nome, v_user, v_manca
    from public.player_instances pi join public.players p on p.id = pi.player_id join public.teams t on t.id = v_r.team_id
    where pi.id = v_r.player_instance_id;

    if v_manca then
      update public.richieste_giocatori set stato = 'decaduta', esito_morale = 0 where id = v_r.id;
      continue;
    end if;

    v_ok := case v_r.tipo when 'titolare' then v_in_campo when 'spazio' then v_minuti >= 30 else not v_in_campo end;
    update public.player_instances set morale = greatest(0, least(100, morale + case when v_ok then 8 else -20 end)) where id = v_r.player_instance_id;
    update public.richieste_giocatori set stato = case when v_ok then 'mantenuta' else 'tradita' end,
           esito_morale = case when v_ok then 8 else -20 end where id = v_r.id;

    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
    values (v_r.league_id, 'promessa:' || v_r.id, 'giocatore', v_nome, v_r.team_id, v_r.player_instance_id,
      case when v_ok then private.social_scegli('pm' || v_r.id, array[
             'Grazie mister per la fiducia: la parola data conta. Stasera ho dato tutto. 💪',
             'Il mister ha mantenuto la promessa e io ho cercato di ripagarlo in campo. Grazie.',
             'Quando un allenatore mantiene la parola, si vede. Grazie mister.'])
      else case v_r.tipo
        when 'titolare' then private.social_scegli('pt' || v_r.id, array[
             'Mi era stato promesso un posto da titolare. Parole al vento... 😒',
             'Promessa tradita: dovevo giocare dall''inizio e sono rimasto fuori. Mi sento preso in giro.',
             'Ci avevo creduto. Mi hanno detto "giochi tu" e poi niente. Che amarezza.'])
        when 'spazio' then private.social_scegli('ps' || v_r.id, array[
             'Mi avevano promesso più spazio. Ancora una volta niente. Basta promesse, servono i fatti.',
             'Più minuti, mi era stato detto. Sono ancora qui ad aspettare. Che delusione.'])
        else private.social_scegli('pr' || v_r.id, array[
             'Mi avevano detto che avrei riposato e invece sono sceso in campo comunque, stanco morto. Così non va.',
             'Ho chiesto di tirare il fiato, mi era stato promesso. E invece eccomi qui a giocare. Mah.'])
      end end,
      (select coalesce(m2.simulata_il, now()) from public.matches m2 where m2.id = v_m.id) + interval '2 minutes')
    on conflict (league_id, chiave) do nothing;

    perform private.notifica(v_user, v_r.league_id, 'sistema',
      case when v_ok then 'Promessa mantenuta' else 'Promessa non mantenuta' end,
      case when v_ok then v_nome || ' ha apprezzato che tu abbia mantenuto la parola: morale +8.'
           else v_nome || ' si sente tradito: morale -20, e si è sfogato sui social.' end,
      jsonb_build_object('player_instance_id', v_r.player_instance_id, 'view', 'spogliatoio'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION private.genera_richieste_giocatori()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_t record;
  v_next smallint;
  v_riposo jsonb;
  v_titolare jsonb;
  v_spazio jsonb;
  v_scelte text[];
  v_tipo text;
  v_p jsonb;
  v_seed text;
  v_testo text;
  v_n integer := 0;
begin
  for v_t in
    select t.id as team_id, t.league_id, t.user_id, l.giornate_totali, l.stagione_corrente
    from public.teams t
    join public.leagues l on l.id = t.league_id and l.conferenze_stampa and l.stato = 'stagione' and l.fase_carriera = 'normale'
    where t.attiva and t.user_id is not null and not t.controllata_da_pc
  loop
    select min(f.giornata) into v_next from public.fixtures f
    where f.league_id = v_t.league_id and f.stato = 'programmata' and f.bracket_tie_id is null  -- mai nei playoff
      and v_t.team_id in (f.home_team_id, f.away_team_id);
    continue when v_next is null;
    perform private.genera_richiesta_capitano(v_t.team_id, v_t.league_id, v_t.user_id, v_t.stagione_corrente, v_next);
    continue when exists (select 1 from public.richieste_giocatori r where r.team_id = v_t.team_id and r.giornata_target = v_next
                          and r.tipo <> 'giorno_libero');
    -- Solo dopo una simulazione recente (le richieste nascono a ridosso delle partite)...
    continue when not exists (select 1 from public.matches m where m.league_id = v_t.league_id and m.simulata_il > now() - interval '20 hours');
    -- ...e non ogni giornata: circa 6 su 10.
    -- Poche richieste: al massimo 7 a stagione per squadra, in media 6-7. Ogni giornata ha una
    -- probabilita' fissa (14 / giornate della stagione regolare, in modo deterministico: in simulazione 6-7 a stagione) e fra una
    -- richiesta e la successiva passano almeno 3 giornate.
    continue when (select count(*) from public.richieste_giocatori r where r.team_id = v_t.team_id and r.stagione = v_t.stagione_corrente and r.tipo <> 'giorno_libero') >= 7;
    continue when exists (select 1 from public.richieste_giocatori r where r.team_id = v_t.team_id and r.stagione = v_t.stagione_corrente
                          and r.tipo <> 'giorno_libero' and r.giornata_target > v_next - 3);
    continue when abs(hashtext(v_t.team_id || ':' || v_next)) % 1000 >= 1000.0 * 14 / greatest(1, v_t.giornate_totali);

    with rosa as (
      select pi.id, p.nome, pi.overall_corrente, pi.morale, pi.condizione, ms.partite,
             case when coalesce(ms.partite, 0) > 0 then ms.minuti / (90.0 * ms.partite) end as pct,
             pi.id = any(coalesce((select l2.titolari from public.lineups l2 where l2.team_id = v_t.team_id
                                   order by l2.giornata desc, l2.salvata_il desc limit 1), '{}'::bigint[])) as titolare,
             row_number() over (order by pi.overall_corrente desc) as pos
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      left join lateral private.minuti_stagione(pi.id) ms on true
      where pi.team_id = v_t.team_id and not pi.ritirato and pi.infortunato_fino_a <= 0 and pi.squalificato_fino_a <= 0
        and not exists (select 1 from public.richieste_giocatori r where r.player_instance_id = pi.id and r.creata_il > now() - interval '6 days')
    )
    select
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where r.titolare and r.condizione < 55 order by r.condizione limit 1),
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where not r.titolare and r.partite >= 3 and r.pct < 0.45 and r.morale < 80 and r.pos <= 16
        order by r.overall_corrente desc limit 1),
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where r.partite >= 3 and r.pct < 0.30 and r.morale < 65 order by r.pct, r.id limit 1)
    into v_riposo, v_titolare, v_spazio;

    v_scelte := array[]::text[];
    if v_riposo is not null then v_scelte := array_append(v_scelte, 'riposo'); end if;
    if v_titolare is not null then v_scelte := array_append(v_scelte, 'titolare'); end if;
    if v_spazio is not null then v_scelte := array_append(v_scelte, 'spazio'); end if;
    continue when array_length(v_scelte, 1) is null;
    v_tipo := v_scelte[1 + abs(hashtext('tipo' || v_t.team_id || ':' || v_next)) % array_length(v_scelte, 1)];
    v_p := case v_tipo when 'riposo' then v_riposo when 'titolare' then v_titolare else v_spazio end;
    v_seed := 'rg' || v_t.team_id || ':' || v_next;
    v_testo := case v_tipo
      when 'titolare' then private.social_scegli(v_seed, array[
        'Ehi mister, mi sono allenato bene ultimamente. Volevo dunque chiederle se nella prossima partita potesse schierarmi tra i titolari.',
        'Mister, sento di essere in forma e di meritare una chance dall''inizio. Mi farebbe giocare nella prossima partita da titolare?',
        'Buongiorno mister, in settimana ho dato tutto negli allenamenti. Le chiedo la possibilità di partire titolare alla prossima.',
        'Mister, so che la concorrenza è forte, ma mi sento pronto. Posso avere una maglia da titolare nella prossima partita?'])
      when 'spazio' then private.social_scegli(v_seed, array[
        'Mister, vorrei sentirmi più parte del progetto. Le chiedo di darmi più spazio nella prossima partita: anche mezz''ora farebbe la differenza.',
        'Ehi mister, gioco troppo poco e non è quello che mi aspettavo. Mi darebbe almeno mezz''ora nella prossima partita?',
        'Mister, so di poter dare di più alla squadra. Mi farebbe giocare almeno mezz''ora nella prossima partita?',
        'Buongiorno mister, sento di avere più da offrire di quanto stia facendo vedere. Le chiedo più minuti nella prossima partita, almeno mezz''ora.'])
      else private.social_scegli(v_seed, array[
        'Mister, sento le gambe pesanti dopo gli ultimi impegni. Se possibile, vorrei riposare nella prossima partita.',
        'Ehi mister, sono stanco e non vorrei rischiare l''infortunio. Mi lascerebbe a riposo la prossima?',
        'Mister, il fisico mi sta presentando il conto. Posso riposare nella prossima partita, così torno al meglio?',
        'Buongiorno mister, non sono al meglio della condizione. Le chiedo di farmi tirare il fiato nella prossima partita.'])
    end;

    insert into public.richieste_giocatori (league_id, team_id, player_instance_id, tipo, testo, giornata_target, stagione)
    values (v_t.league_id, v_t.team_id, (v_p->>'id')::bigint, v_tipo, v_testo, v_next, v_t.stagione_corrente)
    on conflict do nothing;
    if found then
      perform private.notifica(v_t.user_id, v_t.league_id, 'sistema', 'Richiesta di ' || (v_p->>'nome'),
        'Mister, ' || (v_p->>'nome') || ' vuole parlarle. Apri la home per rispondere.', jsonb_build_object('richiesta', true, 'view', 'spogliatoio'));
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$function$;
