-- Le notifiche di conferenze stampa e richieste dei giocatori portano alla loro pagina (menu Extra campo)
-- e accendono il pallino sulla voce di menu (dati.view = 'salastampa' / 'spogliatoio').
begin;

CREATE OR REPLACE FUNCTION private.avvisa_conferenza()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.ordine = 1 then
    perform private.notifica(
      (select t.user_id from public.teams t where t.id = new.team_id),
      new.league_id, 'sistema', 'Conferenza stampa',
      'I giornalisti ti aspettano in sala stampa dopo la partita.',
      jsonb_build_object('conferenza_match_id', new.match_id, 'view', 'salastampa'));
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.applica_rivalita(p_domanda_id bigint, p_squadre jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_d public.conferenze_domande;
  v_s record;
  v_delta numeric;
  v_grado numeric;
  v_out jsonb := '[]'::jsonb;
  v_target public.teams;
  v_match bigint;
  v_attaccante text;
  v_tipo_squadra text;
begin
  select * into v_d from public.conferenze_domande where id = p_domanda_id;
  if not found then raise exception 'Domanda % inesistente.', p_domanda_id; end if;
  select coalesce(nullif(btrim(pr.nome_allenatore), ''), t.nome), t.nome into v_attaccante, v_tipo_squadra
    from public.teams t left join public.profiles pr on pr.user_id = t.user_id where t.id = v_d.team_id;

  for v_s in
    select (x->>'team_id')::bigint as team_id, x->>'direzione' as direzione
    from jsonb_array_elements(coalesce(p_squadre, '[]'::jsonb)) x
  loop
    continue when v_s.team_id = v_d.team_id;
    select * into v_target from public.teams where id = v_s.team_id and league_id = v_d.league_id;
    continue when not found;
    v_delta := case v_s.direzione when 'attacco' then 10 when 'elogio' then -6 else 0 end;
    continue when v_delta = 0;
    v_grado := private.sposta_rivalita(v_d.league_id, v_d.team_id, v_s.team_id, v_delta);
    v_out := v_out || jsonb_build_object('team_id', v_s.team_id, 'nome', v_target.nome, 'delta', v_delta, 'grado', v_grado);

    -- Diritto di replica: solo se attaccato e umano.
    if v_delta > 0 and v_target.user_id is not null and not v_target.controllata_da_pc then
      select m.id into v_match
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      where f.league_id = v_d.league_id and v_s.team_id in (f.home_team_id, f.away_team_id)
      order by m.simulata_il desc limit 1;
      if v_match is not null then
        insert into public.conferenze_domande (league_id, match_id, team_id, ordine, giornalista, domanda)
        values (v_d.league_id, v_match, v_s.team_id, 3,
                private.social_scegli('replica' || p_domanda_id || v_s.team_id, array['Sky Sport 24', 'Radio 24', 'Sport Mediaset', 'Corriere dello Sport', 'Rai Sport', 'Tuttosport']),
                'Mister, ' || v_attaccante || ' (' || v_tipo_squadra || ') ha parlato della vostra squadra: «' || left(coalesce(v_d.risposta, ''), 220) ||
                case when char_length(coalesce(v_d.risposta, '')) > 220 then '…' else '' end || '». Cosa risponde?')
        on conflict (match_id, team_id, ordine) do nothing;
        if found then
          perform private.notifica(v_target.user_id, v_d.league_id, 'sistema', 'Diritto di replica',
            v_attaccante || ' ha parlato di te in conferenza: i giornalisti vogliono la tua risposta.',
            jsonb_build_object('conferenza_match_id', v_match, 'view', 'salastampa'));
        end if;
      end if;
    end if;
  end loop;
  return v_out;
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
    continue when exists (select 1 from public.richieste_giocatori r where r.team_id = v_t.team_id and r.giornata_target = v_next);
    -- Solo dopo una simulazione recente (le richieste nascono a ridosso delle partite)...
    continue when not exists (select 1 from public.matches m where m.league_id = v_t.league_id and m.simulata_il > now() - interval '20 hours');
    -- ...e non ogni giornata: circa 6 su 10.
    -- Poche richieste: al massimo 7 a stagione per squadra, in media 6-7. Ogni giornata ha una
    -- probabilita' fissa (14 / giornate della stagione regolare, in modo deterministico: in simulazione 6-7 a stagione) e fra una
    -- richiesta e la successiva passano almeno 3 giornate.
    continue when (select count(*) from public.richieste_giocatori r where r.team_id = v_t.team_id and r.stagione = v_t.stagione_corrente) >= 7;
    continue when exists (select 1 from public.richieste_giocatori r where r.team_id = v_t.team_id and r.stagione = v_t.stagione_corrente
                          and r.giornata_target > v_next - 3);
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
    on conflict (team_id, giornata_target) do nothing;
    if found then
      perform private.notifica(v_t.user_id, v_t.league_id, 'sistema', 'Richiesta di ' || (v_p->>'nome'),
        'Mister, ' || (v_p->>'nome') || ' vuole parlarle. Apri la home per rispondere.', jsonb_build_object('richiesta', true, 'view', 'spogliatoio'));
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$function$;

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
  update public.richieste_giocatori set stato = 'scaduta' where stato = 'aperta' and scade_il < now();

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

-- Quelle gia' arrivate.
update public.notifications set dati = dati || '{"view": "salastampa"}'::jsonb
 where titolo in ('Conferenza stampa', 'Diritto di replica') and not (dati ? 'view');
update public.notifications set dati = dati || '{"view": "spogliatoio"}'::jsonb
 where (titolo like 'Richiesta di %' or titolo in ('Promessa mantenuta', 'Promessa non mantenuta')) and not (dati ? 'view');

commit;
