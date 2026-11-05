-- Simulazione alle 22:00 invece che alle 23:00 (decisione del committente, 5/11/2026).
-- Tutto cio' che e' agganciato alla partita scala di un'ora: mercato 22:30-20:00 (chiusura, aste e scadenza
-- proposte alle 20:00), estrazione svincolati e under alle 22:30, crediti del casino' alle 22:10, promemoria
-- formazione alle 21:00, domande del QuizOne fino alle 21:00 e premio alle 21:30, risposte alle conferenze
-- entro le 21:30. Funzioni ricostruite dalle definizioni live. In fondo: partite non ancora giocate alle 22:00.


CREATE OR REPLACE FUNCTION private.primo_calcio_dopo(p_scadenza timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_locale timestamp := p_scadenza at time zone 'Europe/Rome';
  v_calcio timestamp;
begin
  v_calcio := date_trunc('day', v_locale) + interval '22 hours';
  if v_locale >= v_calcio then
    v_calcio := v_calcio + interval '1 day';
  end if;
  return v_calcio at time zone 'Europe/Rome';
end;
$function$;

CREATE OR REPLACE FUNCTION private.pianifica_prossima_giornata()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_programmata_conclusa timestamptz;
  v_prossima_giornata smallint;
  v_prossima timestamptz;
begin
  if new.stato <> 'simulata' or old.stato = 'simulata' then
    return new;
  end if;

  -- Si aspetta l'ultima partita della giornata: fino ad allora non si deve
  -- spostare il turno successivo.
  if exists (
    select 1 from public.fixtures f
    where f.league_id = new.league_id
      and f.giornata = new.giornata
      and f.stato <> 'simulata'
  ) then
    return new;
  end if;

  -- L'ANCORA E' L'ORARIO PROGRAMMATO, non matches.simulata_il: e' questa
  -- la riga che prima faceva derivare tutto il calendario.
  select max(f.data_sim) into v_programmata_conclusa
  from public.fixtures f
  where f.league_id = new.league_id and f.giornata = new.giornata;

  select min(f.giornata) into v_prossima_giornata
  from public.fixtures f
  where f.league_id = new.league_id
    and f.giornata > new.giornata
    and f.stato = 'programmata';

  if v_programmata_conclusa is null or v_prossima_giornata is null then
    return new;
  end if;

  -- +1 giorno calcolato in ora locale: attraverso il cambio dell'ora
  -- legale l'intervallo reale e' di 23 o 25 ore, ma l'orario di parete
  -- resta lo stesso — che e' quello che i partecipanti si aspettano.
  -- Il giorno dopo all'ora fissa delle partite (22:00 dal 5/11/2026): cosi' un cambio d'orario vale anche per
  -- le giornate gia' agganciate a una partita giocata all'ora vecchia.
  v_prossima := (date_trunc('day', v_programmata_conclusa at time zone 'Europe/Rome') + interval '1 day 22 hours')
                at time zone 'Europe/Rome';

  -- Solo per i fermi lunghi (piu' di un giorno di stop): evita che le
  -- giornate arretrate partano tutte in fila a un minuto di distanza.
  -- Nel caso normale la condizione e' gia' falsa al primo giro, perche'
  -- abbiamo appena simulato a ridosso di v_programmata_conclusa.
  while v_prossima <= now() loop
    v_prossima := ((v_prossima at time zone 'Europe/Rome') + interval '1 day')
                  at time zone 'Europe/Rome';
  end loop;

  update public.fixtures
  set data_sim = v_prossima
  where league_id = new.league_id
    and giornata = v_prossima_giornata
    and stato = 'programmata';

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.crea_fixtures_tie(p_tie_id bigint, p_giornata_andata integer)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_tie public.bracket_ties;
  v_bracket public.brackets;
  v_ultima_data timestamptz;
  v_ultima_giornata integer;
  v_n integer := 0;
begin
  select * into v_tie from public.bracket_ties where id = p_tie_id;
  select * into v_bracket from public.brackets where id = v_tie.bracket_id;

  -- Le eliminatorie si giocano alla stessa ora delle giornate di campionato,
  -- un turno al giorno: la data si ricava scalando dall'ultima giornata di
  -- stagione regolare, cosi' resta agganciata al ritmo gia' impostato.
  select max(data_sim), max(giornata) into v_ultima_data, v_ultima_giornata
  from public.fixtures where season_id = v_bracket.season_id and bracket_tie_id is null;
  -- All'ora fissa delle partite (22:00 dal 5/11/2026), anche se la stagione regolare si e' giocata all'ora vecchia.
  v_ultima_data := (date_trunc('day', v_ultima_data at time zone 'Europe/Rome') + interval '22 hours') at time zone 'Europe/Rome';

  if v_tie.gara_secca then
    insert into public.fixtures (season_id, league_id, giornata, home_team_id, away_team_id,
                                 data_sim, stato, campo_neutro, bracket_tie_id, mano)
    values (v_bracket.season_id, v_tie.league_id, p_giornata_andata,
            v_tie.alta_team_id, v_tie.bassa_team_id,
            v_ultima_data + make_interval(days => p_giornata_andata - v_ultima_giornata),
            'programmata', true, v_tie.id, 2);
    v_n := 1;
  else
    insert into public.fixtures (season_id, league_id, giornata, home_team_id, away_team_id,
                                 data_sim, stato, campo_neutro, bracket_tie_id, mano)
    values
      (v_bracket.season_id, v_tie.league_id, p_giornata_andata,
       v_tie.bassa_team_id, v_tie.alta_team_id,
       v_ultima_data + make_interval(days => p_giornata_andata - v_ultima_giornata),
       'programmata', false, v_tie.id, 1),
      (v_bracket.season_id, v_tie.league_id, p_giornata_andata + 1,
       v_tie.alta_team_id, v_tie.bassa_team_id,
       v_ultima_data + make_interval(days => p_giornata_andata + 1 - v_ultima_giornata),
       'programmata', false, v_tie.id, 2);
    v_n := 2;
  end if;

  update public.bracket_ties set stato = 'in_corso' where id = p_tie_id;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION private.apri_mercato_nuova_lega()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ora time := (now() at time zone 'Europe/Rome')::time;
begin
  if old.stato <> 'stagione' and new.stato = 'stagione'
     and (v_ora >= time '22:30' or v_ora < time '20:00') then
    perform private.estrai_svincolati_lega(new.id, (now() at time zone 'Europe/Rome')::date);
    perform private.offerte_mercato_squadre_pc(new.id);
    perform private.proposte_mercato_squadre_pc(new.id);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.mercato_aperto()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select (now() at time zone 'Europe/Rome')::time >= time '22:30'
      or (now() at time zone 'Europe/Rome')::time <  time '20:00';
$function$;

CREATE OR REPLACE FUNCTION private.mercato_aperto_lega(p_league_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ciclo as (
    select
      (select max(m.simulata_il)
       from public.matches m
       join public.fixtures f on f.id = m.fixture_id
       where f.league_id = p_league_id) as ultima_partita_il,
      (select min(f.data_sim)
       from public.fixtures f
       where f.league_id = p_league_id and f.stato = 'programmata') as prossima_partita_il
  )
  select not coalesce((select l.mercato_bloccato from public.leagues l where l.id = p_league_id), false)
  and (
    exists (
      select 1 from private.mercato_override_admin o
      where o.league_id = p_league_id
        and o.giorno = (now() at time zone 'Europe/Rome')::date
    ) or coalesce(
      (select now() >= ultima_partita_il + interval '30 minutes'
               and now() < prossima_partita_il - interval '2 hours'
       from ciclo
       where ultima_partita_il is not null and prossima_partita_il is not null),
      (now() at time zone 'Europe/Rome')::time >= time '22:30'
        or (now() at time zone 'Europe/Rome')::time < time '20:00'
    )
  );
$function$;

CREATE OR REPLACE FUNCTION private.chiudi_mercato_giornaliero()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 20 then
    return 0;
  end if;
  return private.scadi_proposte_giorno(null);
end;
$function$;

CREATE OR REPLACE FUNCTION private.risolvi_aste()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_oggi date := (now() at time zone 'Europe/Rome')::date;
  v_giorno record;
  v_assegnate integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 20 then
    return 0;
  end if;

  for v_giorno in
    select distinct a.giorno
    from public.free_agent_auctions a
    where a.stato = 'aperta'
      and a.giorno <= v_oggi
    order by a.giorno
  loop
    v_assegnate := v_assegnate + private.risolvi_aste_giorno(v_giorno.giorno);
  end loop;

  return v_assegnate;
end;
$function$;

CREATE OR REPLACE FUNCTION private.risolvi_aste_under()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_oggi date := (now() at time zone 'Europe/Rome')::date;
  v_giorno record;
  v_assegnate integer := 0;
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 20 then
    return 0;
  end if;
  for v_giorno in
    select distinct a.giorno from public.under_auctions a
    where a.stato = 'aperta' and a.giorno <= v_oggi
    order by a.giorno
  loop
    v_assegnate := v_assegnate + private.risolvi_aste_under_giorno(v_giorno.giorno);
  end loop;
  return v_assegnate;
end;
$function$;

CREATE OR REPLACE FUNCTION private.estrai_svincolati()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_oggi date;
  v_ora time;
  v_inizio_finestra timestamptz;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '22:30' and v_ora < time '22:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;

  -- Le 22:30 di stasera, ora di Roma: tutto cio' che e' stato estratto
  -- prima appartiene a un'apertura manuale dell'admin, non a questo giro.
  v_inizio_finestra := (v_oggi + time '22:30') at time zone 'Europe/Rome';

  for v_lega in select id from public.leagues where stato = 'stagione' and private.fase_mercato(id) = 'stagione' and fase_carriera <> 'offseason' and not mercato_bloccato loop
    -- Con la schedule a ogni minuto questa funzione rigira fino alle
    -- 22:45: senza questa guardia creerebbe una tornata nuova ogni volta.
    -- Le riesecuzioni servono da rete se il primo giro fallisce.
    if exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = v_lega
        and a.giorno = v_oggi
        and a.origine = 'estrazione'
        and a.creata_il >= v_inizio_finestra
    ) then
      continue;
    end if;

    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$function$;

CREATE OR REPLACE FUNCTION private.estrai_under()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ora time;
  v_oggi date;
  v_lega bigint;
  v_totale integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '22:30' and v_ora < time '22:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;
  for v_lega in select id from public.leagues where stato = 'stagione' and private.fase_mercato(id) = 'stagione' and not mercato_bloccato loop
    v_totale := v_totale + private.estrai_under_lega(v_lega, v_oggi);
  end loop;
  return v_totale;
end;
$function$;

CREATE OR REPLACE FUNCTION private.casino_premi_partita(p_league_id bigint, p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_tot integer := 0; v_esito text; v_crediti integer; v_biglietti integer;
begin
  for r in
    select m.id as match_id, t.id as team_id,
           case when f.home_team_id = t.id then f.away_team_id else f.home_team_id end as avversario,
           case when f.home_team_id = t.id then m.gol_home else m.gol_away end as gf,
           case when f.home_team_id = t.id then m.gol_away else m.gol_home end as gs,
           case when f.home_team_id = t.id then m.rigori_home else m.rigori_away end as rf,
           case when f.home_team_id = t.id then m.rigori_away else m.rigori_home end as rs,
           -- Biglietti (Season 3, diario §4): 50 crediti x livello dello stadio per ogni partita in casa.
           case when f.home_team_id = t.id and f.campo_neutro is not true and l.stadio_attivo
                then 50 * coalesce(tr.livello_stadio, 0) else 0 end as biglietti
      from public.teams t
      join public.fixtures f on f.league_id = t.league_id and t.id in (f.home_team_id, f.away_team_id)
      join public.matches m on m.fixture_id = f.id
      join public.leagues l on l.id = t.league_id
      left join public.team_risorse tr on tr.team_id = t.id
     where t.league_id = p_league_id and t.user_id = p_user and t.attiva
       and m.id > 1513
       -- non prima delle 22:10 della sera in cui la partita e' stata simulata (le 6 ore di margine reggono una simulazione in ritardo oltre la mezzanotte)
       and now() >= ((((coalesce(m.simulata_il, 'epoch'::timestamptz) at time zone 'Europe/Rome') - interval '6 hours')::date)::timestamp + interval '22 hours 10 minutes') at time zone 'Europe/Rome'
       and not exists (select 1 from public.casino_premi_partita p where p.match_id = m.id and p.user_id = p_user)
       and (exists (select 1 from public.match_reveals mr where mr.match_id = m.id and mr.user_id = p_user)
            or m.simulata_il < now() - interval '24 hours')
  loop
    v_esito := case when r.gf > r.gs then 'vittoria' when r.gf < r.gs then 'sconfitta'
                    when r.rf is not null and r.rs is not null and r.rf <> r.rs then case when r.rf > r.rs then 'vittoria' else 'sconfitta' end
                    else 'pareggio' end;
    v_crediti := case v_esito when 'vittoria' then 300 when 'pareggio' then 150 else 100 end;
    v_biglietti := r.biglietti;
    insert into public.casino_premi_partita (match_id, user_id, league_id, team_id, esito, avversario_id, crediti, biglietti)
    values (r.match_id, p_user, p_league_id, r.team_id, v_esito, r.avversario, v_crediti, v_biglietti)
    on conflict do nothing;
    if found then v_tot := v_tot + v_crediti + v_biglietti; end if;
  end loop;
  if v_tot > 0 then
    update public.casino_saldi set crediti = crediti + v_tot, aggiornato_il = now() where league_id = p_league_id and user_id = p_user;
  end if;
  return v_tot;
end $function$;

CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  v_speso bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.casino_bustine_speso(p_league_id);
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  select coalesce(sum(m.speso), 0) into v_speso from private.casino_movimenti(p_league_id) m where m.team_id = v.team_id;
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'bonus_aperto', (select jsonb_build_object('id', b.id, 'tipo', b.tipo) from public.casino_slot_bonus b where b.league_id = p_league_id and b.user_id = v_utente and b.stato = 'aperto' order by b.id limit 1),
    'bustina_spesi', greatest(0, v_speso - v.speso_base - 500 * v.bustine_speso),
    'bustine_oggi', case when v.bustine_giorno = private.casino_settimana() then v.bustine_oggi else 0 end,
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '22 hours 10 minutes') at time zone 'Europe/Rome'));
end $function$;

CREATE OR REPLACE FUNCTION private.promemoria_formazione_22()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_giornata smallint;
  v_team record;
  v_inviate integer := 0;
  v_inizio_giorno timestamptz := ((now() at time zone 'Europe/Rome')::date::timestamp at time zone 'Europe/Rome');
begin
  if extract(hour from (now() at time zone 'Europe/Rome')) <> 21 then
    return 0;
  end if;

  for v_lega in
    select l.id from public.leagues l where l.stato = 'stagione'
  loop
    select f.giornata into v_giornata
    from public.fixtures f
    where f.league_id = v_lega.id and f.stato = 'programmata'
    order by f.giornata
    limit 1;

    if v_giornata is null then
      continue;
    end if;

    for v_team in
      select distinct t.id as team_id, t.user_id
      from public.fixtures f
      join public.teams t on t.id in (f.home_team_id, f.away_team_id) and t.attiva
      where f.league_id = v_lega.id and f.giornata = v_giornata and f.stato = 'programmata'
    loop
      if exists (
        select 1 from public.lineups l
        where l.team_id = v_team.team_id and l.giornata = v_giornata
      ) or exists (
        select 1 from public.notifications n
        where n.user_id = v_team.user_id
          and n.league_id = v_lega.id
          and n.tipo = 'formazione_mancante'
          and n.dati ->> 'giornata' = v_giornata::text
          and n.creata_il >= v_inizio_giorno
      ) then
        continue;
      end if;

      perform private.notifica(
        v_team.user_id, v_lega.id, 'formazione_mancante',
        'Promemoria formazione',
        'Hai inserito la formazione? manca solamente un''ora alla prossima giornata.',
        jsonb_build_object('view', 'squad', 'giornata', v_giornata)
      );
      v_inviate := v_inviate + 1;
    end loop;
  end loop;

  return v_inviate;
end;
$function$;

CREATE OR REPLACE FUNCTION private.proposte_mercato_squadre_pc(p_league_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pc public.teams;
  v_bersaglio record;
  v_dai record;
  v_ruolo text;
  v_scadenza timestamptz;
  v_preferisce_pc boolean;
  v_stagione smallint;
  v_delta_pc bigint;
  v_inserite integer := 0;
begin
  v_stagione := private.stagione_contratto(p_league_id);

  for v_pc in
    select t.* from public.teams t
    where t.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.da_team_id = t.id and tp.stato = 'in_attesa'
      )
    order by random()
  loop
    if random() > 0.34 then continue; end if;

    select ruoli.ruolo into v_ruolo
    from (values ('GK'), ('DEF'), ('MID'), ('ATT')) as ruoli(ruolo)
    left join (
      select private.macro_ruolo(p.posizioni) as ruolo,
             count(*) as quanti,
             avg(pi.overall_corrente) as media
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.team_id = v_pc.id
      group by private.macro_ruolo(p.posizioni)
    ) rosa using (ruolo)
    order by coalesce(rosa.quanti, 0), coalesce(rosa.media, 0), random()
    limit 1;

    v_preferisce_pc := random() < 0.60;
    select pi.id, pi.team_id, pi.ingaggio, pi.overall_corrente, t.controllata_da_pc
      into v_bersaglio
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id
    where pi.league_id = p_league_id
      and t.id <> v_pc.id and t.attiva
      and not pi.ritiro_annunciato
      and private.macro_ruolo(p.posizioni) = coalesce(v_ruolo, 'MID')
      and (select count(*) from public.player_instances x where x.team_id = t.id) > private.rosa_minima()
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.stato = 'in_attesa'
          and pi.id = any(tp.giocatori_richiesti)
      )
    order by (t.controllata_da_pc = v_preferisce_pc) desc,
             abs(pi.overall_corrente - 74 + floor(random() * 9)::integer), random()
    limit 1;
    if not found then continue; end if;

    -- Cosa cedere in cambio: un giocatore fuori dal ruolo appena cercato
    -- (altrimenti si riapre subito lo stesso buco), di ingaggio simile al
    -- bersaglio — proxy di valore comparabile senza dover stimare
    -- l'overall di entrambi.
    select pi.id, pi.ingaggio into v_dai
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.team_id = v_pc.id
      and not pi.ritiro_annunciato
      and private.macro_ruolo(p.posizioni) <> coalesce(v_ruolo, 'MID')
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.stato = 'in_attesa'
          and pi.id = any(tp.giocatori_offerti)
      )
    order by abs(pi.ingaggio - v_bersaglio.ingaggio), random()
    limit 1;
    if not found then continue; end if;

    v_delta_pc := v_bersaglio.ingaggio - v_dai.ingaggio;
    if v_delta_pc > 0 and private.capienza_residua(v_pc.id, v_stagione) < v_delta_pc then continue; end if;

    v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '20 hours') at time zone 'Europe/Rome';
    if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

    insert into public.trade_proposals(
      league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti, messaggio, scade_il
    ) values (
      p_league_id, v_pc.id, v_bersaglio.team_id, array[v_dai.id], array[v_bersaglio.id],
      'Proposta di scambio del direttore sportivo.', v_scadenza
    );

    if not v_bersaglio.controllata_da_pc then
      perform private.notifica(
        (select user_id from public.teams where id = v_bersaglio.team_id),
        p_league_id, 'mercato_proposta', 'Offerta di scambio da ' || v_pc.nome,
        'Il club propone uno scambio per un tuo giocatore.', jsonb_build_object('team_id', v_pc.id)
      );
    end if;
    v_inserite := v_inserite + 1;
  end loop;
  return v_inserite;
end;
$function$;

CREATE OR REPLACE FUNCTION public.proponi_scambio(p_a_team_id bigint, p_giocatori_offerti bigint[] DEFAULT '{}'::bigint[], p_giocatori_richiesti bigint[] DEFAULT '{}'::bigint[], p_scelte_offerte bigint[] DEFAULT '{}'::bigint[], p_scelte_richieste bigint[] DEFAULT '{}'::bigint[], p_messaggio text DEFAULT NULL::text, p_vivaio_offerti bigint[] DEFAULT '{}'::bigint[], p_vivaio_richiesti bigint[] DEFAULT '{}'::bigint[])
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_dest public.teams;
  v_mia public.teams;
  v_lega public.leagues;
  v_g_off bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_g_ric bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_s_off bigint[] := coalesce(p_scelte_offerte, '{}');
  v_s_ric bigint[] := coalesce(p_scelte_richieste, '{}');
  v_v_off bigint[] := coalesce(p_vivaio_offerti, '{}');
  v_v_ric bigint[] := coalesce(p_vivaio_richiesti, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_scambi_aperto(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  -- Niente regali (19/10/2026): entrambe le squadre devono cedere almeno qualcosa (giocatore, prospetto o scelta).
  if cardinality(v_g_off) + cardinality(v_s_off) + cardinality(v_v_off) = 0 then
    raise exception using errcode = '22023', message = 'Devi offrire almeno un giocatore, un prospetto o una scelta: non si cedono asset senza niente in cambio.';
  end if;
  if cardinality(v_g_ric) + cardinality(v_s_ric) + cardinality(v_v_ric) = 0 then
    raise exception using errcode = '22023', message = 'Devi chiedere almeno un giocatore, un prospetto o una scelta: non si regalano asset.';
  end if;
  if cardinality(v_g_off) + cardinality(v_g_ric) + cardinality(v_s_off) + cardinality(v_s_ric) + cardinality(v_v_off) + cardinality(v_v_ric) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore o una scelta.';
  end if;

  if cardinality(array(select distinct unnest(v_g_off))) <> cardinality(v_g_off)
     or cardinality(array(select distinct unnest(v_g_ric))) <> cardinality(v_g_ric)
     or v_g_off && v_g_ric then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;
  if cardinality(array(select distinct unnest(v_s_off))) <> cardinality(v_s_off)
     or cardinality(array(select distinct unnest(v_s_ric))) <> cardinality(v_s_ric)
     or v_s_off && v_s_ric then
    raise exception using errcode = '22023', message = 'Una scelta compare due volte nella proposta.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_g_off) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_g_ric) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;
  if exists (select 1 from public.player_instances where id = any(v_g_off || v_g_ric) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;

  -- Prospetti del vivaio (19/10/2026): passano nel VIVAIO di chi li riceve, che deve avere slot liberi. Le squadre del
  -- PC non li trattano. Mantengono le giornate rimaste per la promozione e l'ingaggio (che pesa sul tetto).
  if cardinality(v_v_off) + cardinality(v_v_ric) > 0 then
    if v_dest.controllata_da_pc then
      raise exception using errcode = '22023', message = v_dest.nome || ' non tratta i giocatori del vivaio.';
    end if;
    if cardinality(array(select distinct unnest(v_v_off))) <> cardinality(v_v_off)
       or cardinality(array(select distinct unnest(v_v_ric))) <> cardinality(v_v_ric) or v_v_off && v_v_ric then
      raise exception using errcode = '22023', message = 'Un giocatore del vivaio compare due volte nella proposta.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_v_off) and team_id = v_mia.id and league_id = v_lega.id;
    if v_n <> cardinality(v_v_off) then
      raise exception using errcode = '22023', message = 'Stai offrendo un giocatore del vivaio che non e'' tuo.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_v_ric) and team_id = v_dest.id and league_id = v_lega.id;
    if v_n <> cardinality(v_v_ric) then
      raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore del vivaio che non e'' di quella squadra.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_dest.id) - cardinality(v_v_ric) + cardinality(v_v_off) > private.vivaio_slot_massimi(v_dest.id) then
      raise exception using errcode = '22023', message = v_dest.nome || ' non ha slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_mia.id) - cardinality(v_v_off) + cardinality(v_v_ric) > private.vivaio_slot_massimi(v_mia.id) then
      raise exception using errcode = '22023', message = 'Non hai slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
  end if;

  -- Una scelta si offre solo finche' non e' stata esercitata: 'usata' e
  -- 'vuota' sono gia' storia, non piu' un asset.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_off) and team_proprietario_id = v_mia.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo una scelta che non possiedi o gia'' esercitata.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_ric) and team_proprietario_id = v_dest.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo una scelta che quella squadra non possiede o gia'' esercitata.';
  end if;

  -- Regola Stepien: nessuna delle due squadre puo' restare senza la
  -- propria scelta d'origine in due stagioni consecutive della stessa
  -- finestra (docs/decisioni-draft-picks.md §7).
  if cardinality(v_s_off) > 0 and private.viola_regola_stepien(v_mia.id, v_s_off) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;
  if cardinality(v_s_ric) > 0 and private.viola_regola_stepien(v_dest.id, v_s_ric) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_dest.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '20 hours') at time zone 'Europe/Rome';
  if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id,
    giocatori_offerti, giocatori_richiesti, scelte_offerte, scelte_richieste, vivaio_offerti, vivaio_richiesti,
    messaggio, scade_il
  ) values (
    v_lega.id, v_mia.id, v_dest.id,
    v_g_off, v_g_ric, v_s_off, v_s_ric, v_v_off, v_v_ric,
    nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza
  ) returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 20:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  return v_proposta;
end;
$function$;

CREATE OR REPLACE FUNCTION public.offri_per_svincolato(p_auction_id bigint, p_ingaggio bigint)
 RETURNS free_agent_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_asta       public.free_agent_auctions;
  v_squadra    public.teams;
  v_rosa       integer;
  v_slot_altri integer;
  v_offerta    public.free_agent_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.free_agent_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  -- In off-season gli svincolati non si trattano: si muovono solo scambi e
  -- rinnovi. Il mercato degli svincolati riapre con la nuova stagione.
  if exists (select 1 from public.leagues l where l.id = v_asta.league_id and l.fase_carriera = 'offseason') then
    raise exception using errcode = '55000',
      message = 'In off-season il mercato degli svincolati è chiuso: riapre con la nuova stagione.';
  end if;
  if not private.mercato_giocatori_aperto(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 22:30 alle 20:00 o quando l''admin lo apre.';
  end if;

  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;

  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  v_slot_altri := private.slot_impegnati(v_squadra.id, p_auction_id);
  if v_rosa + v_slot_altri + 1 > private.rosa_massima() then
    raise exception using errcode = '22023',
      message = 'Non hai più posti liberi: ' || v_rosa || ' giocatori in rosa e '
                || v_slot_altri || ' offerte già in gioco, su un massimo di ' || private.rosa_massima() || ' giocatori.';
  end if;

  perform private.verifica_capienza(
    v_squadra.id,
    p_ingaggio,
    private.stagione_contratto(v_asta.league_id),
    p_auction_id);

  insert into public.free_agent_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

CREATE OR REPLACE FUNCTION public.offri_per_under(p_auction_id bigint, p_ingaggio bigint)
 RETURNS under_bids
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_asta public.under_auctions;
  v_squadra public.teams;
  v_slot_max integer;
  v_slot_impegnati integer;
  v_offerta public.under_bids;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_asta from public.under_auctions where id = p_auction_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Asta inesistente.';
  end if;
  if v_asta.stato <> 'aperta' then
    raise exception using errcode = '55000', message = 'Questa asta è già stata risolta.';
  end if;
  if not private.mercato_giocatori_aperto(v_asta.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato è chiuso: si offre dalle 22:30 alle 20:00 o quando l''admin lo apre.';
  end if;

  select * into v_squadra from public.teams
  where league_id = v_asta.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if p_ingaggio < 100000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo per un prospetto UNDER è 0,1 M€.';
  end if;

  v_slot_max := private.vivaio_slot_massimi(v_squadra.id);
  v_slot_impegnati := private.vivaio_slot_impegnati(v_squadra.id, p_auction_id);
  if v_slot_impegnati + 1 > v_slot_max then
    raise exception using errcode = '22023',
      message = 'Non hai più slot vivaio liberi: ' || v_slot_impegnati || ' su ' || v_slot_max
                || '. Promuovi o libera un prospetto prima di offrire per un altro.';
  end if;

  perform private.verifica_capienza(
    v_squadra.id, p_ingaggio, private.stagione_contratto(v_asta.league_id),
    null, p_auction_id);

  insert into public.under_bids (auction_id, league_id, team_id, ingaggio_offerto)
  values (p_auction_id, v_asta.league_id, v_squadra.id, p_ingaggio)
  on conflict (auction_id, team_id) do update
    set ingaggio_offerto = excluded.ingaggio_offerto, aggiornata_il = now()
  returning * into v_offerta;
  return v_offerta;
end;
$function$;

CREATE OR REPLACE FUNCTION public.richiama_svincolato(p_instance_id bigint)
 RETURNS player_instances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_nome text;
  v_rosa integer;
  v_asta record;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per richiamare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_squadra from public.teams where id = v_istanza.peso_team_id and user_id = v_utente for update;
  if not found or v_istanza.team_id is not null then
    raise exception using errcode = '42501', message = 'Puoi richiamare solo un giocatore che hai svincolato e che nessuno ha ancora preso.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  select nome into v_nome from public.players where id = v_istanza.player_id;
  if v_lega.stato <> 'stagione' or v_lega.fase_carriera = 'offseason' then
    raise exception using errcode = '55000', message = 'Puoi richiamare un giocatore solo durante la stagione.';
  end if;
  if not private.mercato_giocatori_aperto(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi richiamare dalle 22:30 alle 20:00, o quando l''admin lo apre.';
  end if;
  if v_istanza.ritirato or v_istanza.contratto_scadenza < private.stagione_contratto(v_lega.id) then
    raise exception using errcode = '22023', message = v_nome || ' non e'' piu'' sotto contratto con te: non puoi richiamarlo.';
  end if;
  if v_istanza.richiamato_stagione = v_lega.stagione_corrente then
    raise exception using errcode = '22023', message = v_nome || ' e'' gia'' stato richiamato una volta in questa stagione: non si puo'' richiamare di nuovo.';
  end if;
  select count(*) into v_rosa from public.player_instances where team_id = v_squadra.id;
  if v_rosa >= private.rosa_massima() then
    raise exception using errcode = '22023', message = 'La rosa e'' piena (' || private.rosa_massima() || ' giocatori): libera un posto per richiamare ' || v_nome || '.';
  end if;

  -- Le aste aperte su di lui decadono: chi aveva offerto lo viene a sapere.
  for v_asta in
    select a.id from public.free_agent_auctions a
    where a.league_id = v_lega.id and a.player_id = v_istanza.player_id and a.stato = 'aperta'
    for update
  loop
    perform private.notifica(t.user_id, v_lega.id, 'mercato_esito', 'Asta annullata',
      v_nome || ' e'' stato richiamato dalla sua squadra: l''asta e'' annullata e la tua offerta non vale piu''.',
      jsonb_build_object('player_id', v_istanza.player_id))
    from public.free_agent_bids b join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id and t.user_id is not null and t.id <> v_squadra.id;
    delete from public.free_agent_bids where auction_id = v_asta.id;
    update public.free_agent_auctions set stato = 'deserta', risolta_il = now() where id = v_asta.id;
  end loop;
  delete from private.rilasci_in_coda where league_id = v_lega.id and player_id = v_istanza.player_id;

  -- Torna in rosa con il suo contratto (il trigger azzera peso_team_id: l'ingaggio torna a pesare come titolare in rosa).
  update public.player_instances
  set team_id = v_squadra.id, richiamato_stagione = v_lega.stagione_corrente, sul_mercato = false
  where id = v_istanza.id returning * into v_istanza;

  perform private.notifica(v_utente, v_lega.id, 'mercato_esito', 'Giocatore richiamato',
    v_nome || ' torna nella tua rosa con il suo contratto. Non potrai richiamarlo di nuovo in questa stagione.',
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id));
  return v_istanza;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if cardinality(v_p.giocatori_offerti) + cardinality(v_p.scelte_offerte) + cardinality(v_p.vivaio_offerti) = 0
     or cardinality(v_p.giocatori_richiesti) + cardinality(v_p.scelte_richieste) + cardinality(v_p.vivaio_richiesti) = 0 then
    raise exception using errcode = '22023', message = 'Uno scambio deve avere qualcosa da entrambe le parti: questa proposta non e'' piu'' valida.';
  end if;

  if not private.mercato_scambi_aperto(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 22:30 alle 20:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_da.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva). La proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  -- Prospetti del vivaio: ancora nei vivai giusti e posto libero in quello di chi li riceve.
  if cardinality(v_p.vivaio_offerti) + cardinality(v_p.vivaio_richiesti) > 0 then
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_p.vivaio_offerti) and team_id = v_da.id;
    if v_n <> cardinality(v_p.vivaio_offerti) then
      raise exception using errcode = '55000', message = 'Un giocatore del vivaio offerto non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
    end if;
    select count(*) into v_n from public.vivaio_prospetti where id = any(v_p.vivaio_richiesti) and team_id = v_a.id;
    if v_n <> cardinality(v_p.vivaio_richiesti) then
      raise exception using errcode = '55000', message = 'Un giocatore del tuo vivaio richiesto non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_a.id) - cardinality(v_p.vivaio_richiesti) + cardinality(v_p.vivaio_offerti) > private.vivaio_slot_massimi(v_a.id) then
      raise exception using errcode = '22023', message = 'Non hai slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
    if (select count(*) from public.vivaio_prospetti where team_id = v_da.id) - cardinality(v_p.vivaio_offerti) + cardinality(v_p.vivaio_richiesti) > private.vivaio_slot_massimi(v_da.id) then
      raise exception using errcode = '22023', message = v_da.nome || ' non ha piu'' slot liberi nel vivaio per ricevere questo giocatore.';
    end if;
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  update public.player_instances set team_id = v_a.id,  giornata_acquisizione = v_prossima where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id, giornata_acquisizione = v_prossima where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);
  update public.vivaio_prospetti set team_id = v_a.id  where id = any(v_p.vivaio_offerti);
  update public.vivaio_prospetti set team_id = v_da.id where id = any(v_p.vivaio_richiesti);

  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    -- Le formazioni NON si cancellano piu' (8 ottobre 2026): si tolgono solo i giocatori ceduti, e il resto
    -- (modulo, stile, ruoli, compiti, schieramento, panchina) resta com'era. Il posto lasciato libero in campo
    -- lo riempie la formazione automatica alla simulazione, o l'allenatore prima.
    v_form_tolte := private.togli_giocatori_dalle_formazioni(v_lega.id, array[v_da.id, v_a.id], v_tutti, v_prossima);
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_da := v_delta_da + coalesce((select sum(ingaggio) from public.vivaio_prospetti where id = any(v_p.vivaio_richiesti)), 0)
                           - coalesce((select sum(ingaggio) from public.vivaio_prospetti where id = any(v_p.vivaio_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', -v_delta_da, 'Scambio con ' || v_a.nome, 0);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', -v_delta_a, 'Scambio con ' || v_da.nome, 0);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica_scambio_ufficiale(v_lega.id, v_da.id, v_a.id, v_p.id);

  return v_p;
end;
$function$;

CREATE OR REPLACE FUNCTION public.svincola_giocatore_cassa_legacy(p_instance_id bigint)
 RETURNS player_instances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_giocatore public.players;
  v_rosa integer;
  v_portieri integer;
  v_prossima integer;
  v_giornate_trascorse integer;
  v_formazione public.lineups;
  v_indice integer;
  v_slot text;
  v_sostituto bigint;
  v_formazioni_aggiornate integer := 0;
  v_nota text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza from public.player_instances
  where id = p_instance_id and team_id = v_squadra.id for update;
  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi svincolare dalle 22:30 alle 20:00, o quando l''admin lo apre.';
  end if;

  select min(f.giornata) into v_prossima from public.fixtures f
  where f.league_id = v_lega.id and f.stato = 'programmata';

  -- Blocco svincolo su acquisti recenti (deciso il 29 agosto 2026): un
  -- giocatore preso via asta svincolati o scambio non puo' essere
  -- svincolato dalla stessa squadra prima di 10 giornate. NULL (draft, rose
  -- iniziali, offseason) non e' mai bloccato. coalesce su giornate_totali+1
  -- copre il caso limite di fine campionato senza altre giornate
  -- programmate, cosi' il conteggio non resta "in sospeso" a stagione finita.
  if v_istanza.giornata_acquisizione is not null then
    v_giornate_trascorse := coalesce(v_prossima,
        (select max(f.giornata) + 1 from public.fixtures f
           join public.seasons s on s.id = f.season_id
          where s.league_id = v_lega.id and s.numero = v_lega.stagione_corrente and f.stato = 'simulata'),
        v_lega.giornate_totali + 1) - v_istanza.giornata_acquisizione;
    if v_giornate_trascorse < 10 then
      raise exception using errcode = '22023',
        message = 'Questo giocatore e'' arrivato da meno di 10 giornate (mercato o scambio): non puoi ancora svincolarlo. Mancano ' ||
          (10 - v_giornate_trascorse) || ' giornate.';
    end if;
  end if;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK') into v_rosa, v_portieri
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id and pi.id <> v_istanza.id;
  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  -- Economia a tetto salariale (docs/decisioni-economia.md par 2 e par 4): lo
  -- svincolo libera spazio senza penalita' in contanti. Il vecchio addebito
  -- esisteva per impedire di firmare lungo e tagliare a piacere; con i
  -- contratti annuali quell'impegno non esiste piu'. Era anche una trappola
  -- concreta: le squadre col monte ingaggi piu' alto (quelle che piu'
  -- avevano bisogno di liberare spazio) erano spesso proprio quelle senza
  -- abbastanza cassa per pagarsela, e restavano bloccate.
  select * into v_giocatore from public.players where id = v_istanza.player_id;

  if v_prossima is not null then
    for v_formazione in
      select * from public.lineups
      where league_id = v_lega.id
        and team_id = v_squadra.id
        and giornata >= v_prossima
        and (titolari && array[v_istanza.id]::bigint[] or panchina && array[v_istanza.id]::bigint[] or tribuna && array[v_istanza.id]::bigint[])
      for update
    loop
      v_sostituto := null;
      v_indice := array_position(v_formazione.titolari, v_istanza.id);

      if v_indice is not null then
        v_slot := (case v_formazione.modulo
          when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']
          when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']
          when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']
          when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']
          when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']
          when '3-5-2' then array['GK','CB','CB','CB','LM','CM','CDM','CM','RM','ST','ST']
          when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']
          when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']
          when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']
        end)[v_indice];

        select pi.id into v_sostituto
        from public.player_instances pi join public.players p on p.id = pi.player_id
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by
          case
            when v_slot = any(p.posizioni) then 0
            when v_slot in ('CB','LB','RB','LWB','RWB') and p.posizioni && array['CB','LB','RB','LWB','RWB']::text[] then 1
            when v_slot in ('CDM','CM','CAM','LM','RM') and p.posizioni && array['CDM','CM','CAM','LM','RM']::text[] then 1
            when v_slot in ('LW','RW','ST','CF') and p.posizioni && array['LW','RW','ST','CF']::text[] then 1
            when v_slot = 'GK' or p.posizioni && array['GK']::text[] then 3
            else 2
          end,
          case when pi.infortunato_fino_a <= 0 then 0 else 1 end,
          pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set titolari = array_replace(titolari, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      elsif array_position(v_formazione.panchina, v_istanza.id) is not null then
        select pi.id into v_sostituto
        from public.player_instances pi
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by case when pi.infortunato_fino_a <= 0 then 0 else 1 end, pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set panchina = array_replace(panchina, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      else
        update public.lineups set tribuna = array_remove(tribuna, v_istanza.id) where id = v_formazione.id;
      end if;
    end loop;
  end if;

  -- Dal 4 ottobre 2026 l'ingaggio resta a carico del club che svincola
  -- (peso_team_id) fino a scadenza del contratto o firma con un'altra squadra.
  -- Chi aveva gia' annunciato il ritiro chiude la carriera: nessun peso.
  update public.player_instances set team_id = null,
    ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end,
    -- In off-season si svincola come prima: il peso vale dalla stagione nuova.
    peso_team_id = case when v_istanza.ritiro_annunciato then null
                        when v_lega.fase_carriera = 'offseason' then null
                        else v_squadra.id end
  where id = v_istanza.id returning * into v_istanza;
  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente) on conflict do nothing;
  else
    -- Entra subito nella coda dei rilasci (docs/decisioni-economia.md): se il
    -- mercato e' gia' aperto non puo' aggiungersi alla tornata in corso (chi
    -- ha gia' fatto offerte non lo saprebbe), quindi aspetta la prossima
    -- estrazione. Li' si aggiunge IN PIU' rispetto alle 5 (o 10) per ruolo
    -- gia' previste, non al loro posto: private.estrai_svincolati_lega lo
    -- consuma e lo inserisce nella stessa tornata, extra quota.
    insert into private.rilasci_in_coda(league_id, player_id)
    values (v_lega.id, v_istanza.player_id)
    on conflict (league_id, player_id) do nothing;
  end if;

  if v_formazioni_aggiornate > 0 then v_nota := ' Formazione aggiornata con un sostituto.'; end if;
  perform private.notifica(
    v_utente, v_lega.id, 'mercato_esito', 'Giocatore svincolato',
    (case
      when v_istanza.ritiro_annunciato then 'Il giocatore aveva già annunciato il ritiro: la carriera termina qui e non torna disponibile.'
      else 'Il giocatore non fa più parte della tua rosa e torna tra gli svincolati. Il suo ingaggio resta sul tuo tetto finché il contratto non scade o un''altra squadra non lo prende.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id)
  );
  return v_istanza;
end;
$function$;

CREATE OR REPLACE FUNCTION private.quiz_genera(p_league_id bigint, p_ora timestamp with time zone)
 RETURNS quizzone_domande
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_stagione bigint; v_tipi text[] := array['gol','assist','punti','posizione','vittorie','subiti','risultato','capocannoniere','capolista','attacco','difesa'];
  v_recenti text[]; v_tipo text; v_tentativo int; r record; v_testo text; v_giusta text; v_sbagliate text[]; v_mix jsonb; d public.quizzone_domande;
  v_lega text; v_gruppo text; v_n int; v_notte boolean;
begin
  -- stessa stagione che mostra l'app (classifica_giocatori_stagione): quella corrente della lega, se e' in corso
  -- Domande solo dalle 8:00 alle 21:00 (decisione del committente, 21/10/2026; partita alle 22 dal 5/11/2026): niente dalle 22 e di notte.
  if extract(hour from p_ora at time zone 'Europe/Rome') >= 22 or extract(hour from p_ora at time zone 'Europe/Rome') < 8 then return null; end if;
  select s.id into v_stagione from public.seasons s join public.leagues l on l.id = s.league_id
   where l.id = p_league_id and s.numero = l.stagione_corrente and s.stato = 'in_corso';
  if v_stagione is null then return null; end if;
  select nome into v_lega from public.leagues where id = p_league_id;
  v_recenti := array(select tipo from public.quizzone_domande where league_id = p_league_id order by ora desc limit 4);
  -- Niente spoiler (scelta del committente): dalle 22:00 a mezzogiorno niente domande su classifica e statistiche, che
  -- conterrebbero le partite della sera; solo risultati di giornate passate (partite giocate da piu' di 14 ore).
  v_notte := false;   -- dal 21/10/2026 di notte non ci sono domande: dalle 8 tutti i tipi, con i dati della sera prima
  if v_notte then v_tipi := array['risultato']; v_recenti := '{}'; end if;
  for v_tentativo in 1..30 loop
    v_tipo := v_tipi[1 + floor(random() * array_length(v_tipi, 1))::int];
    continue when v_tipo = any(v_recenti) and v_tentativo < 25;
    v_testo := null;
    if v_tipo in ('gol', 'assist') then
      select p.nome as giocatore, t.nome as squadra, x.n into r
        from (select ms.player_instance_id, coalesce(pi.team_id, max(ms.team_id)) as team_id,
                     sum(case when v_tipo = 'gol' then ms.gol else ms.assist end)::int as n
                from public.match_stats ms join public.matches m on m.id = ms.match_id
                join public.fixtures f on f.id = m.fixture_id and f.season_id = v_stagione and f.stato = 'simulata'
                left join public.player_instances pi on pi.id = ms.player_instance_id
               where ms.league_id = p_league_id group by ms.player_instance_id, pi.team_id) x
        join public.player_instances pi on pi.id = x.player_instance_id join public.players p on p.id = pi.player_id join public.teams t on t.id = x.team_id
       where x.n >= 2
         and (select count(*) from public.player_instances pi2 join public.players p2 on p2.id = pi2.player_id where pi2.league_id = p_league_id and p2.nome = p.nome) = 1
       order by random() limit 1;
      if r.n is not null then
        v_testo := case v_tipo when 'gol' then format('Quanti gol ha segnato %s (%s) in questa stagione?', r.giocatore, r.squadra)
                               else format('Quanti assist ha fatto %s (%s) in questa stagione?', r.giocatore, r.squadra) end;
        v_giusta := r.n::text; v_sbagliate := private.quiz_numeri(r.n, 0);
      end if;
    elsif v_tipo in ('punti', 'vittorie', 'subiti') then
      select t.nome as squadra, s.punti, s.vittorie, s.gol_subiti into r from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null then
        v_testo := case v_tipo when 'punti' then format('Quanti punti ha in classifica %s?', r.squadra)
                               when 'vittorie' then format('Quante partite ha vinto %s in campionato?', r.squadra)
                               else format('Quanti gol ha subito %s in campionato?', r.squadra) end;
        v_n := case v_tipo when 'punti' then r.punti when 'vittorie' then r.vittorie else r.gol_subiti end;
        v_giusta := v_n::text; v_sbagliate := private.quiz_numeri(v_n, 0);
      end if;
    elsif v_tipo = 'posizione' then
      select t.nome as squadra, s.posizione, s.conferenza,
             (select count(*) from public.standings s2 where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza)::int as tot into r
        from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.posizione is not null and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null and r.tot >= 4 then
        v_gruppo := case r.conferenza when 'est' then ' nella Conference Est' when 'ovest' then ' nella Conference Ovest' else '' end;
        v_testo := format('In che posizione è %s in classifica%s?', r.squadra, v_gruppo);
        v_giusta := r.posizione || 'º';
        v_sbagliate := array(select x || 'º' from (select r.posizione + dd as x from unnest(array[-3,-2,-1,1,2,3]) dd where r.posizione + dd between 1 and r.tot order by random() limit 3) s);
      end if;
    elsif v_tipo = 'risultato' then
      select th.nome as casa, ta.nome as ospite, f.giornata, m.gol_home as gh, m.gol_away as ga into r
        from public.matches m join public.fixtures f on f.id = m.fixture_id join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
       where m.league_id = p_league_id and f.season_id = v_stagione and f.stato = 'simulata' and f.bracket_tie_id is null
         and m.simulata_il < now() - case when v_notte then interval '14 hours' else interval '30 minutes' end order by random() limit 1;
      if r.casa is not null then
        v_testo := format('Com''è finita %s - %s della giornata %s?', r.casa, r.ospite, r.giornata);
        v_giusta := r.gh || '-' || r.ga;
        v_sbagliate := array(select x from (select distinct x from unnest(array[r.ga || '-' || r.gh, (r.gh + 1) || '-' || r.ga, r.gh || '-' || (r.ga + 1),
                               greatest(r.gh - 1, 0) || '-' || r.ga, (r.gh + 1) || '-' || (r.ga + 1), r.gh || '-' || greatest(r.ga - 1, 0)]) x
                             where x <> r.gh || '-' || r.ga) s order by random() limit 3);
      end if;
    elsif v_tipo = 'capocannoniere' then
      with marcatori as (
        select p.nome, sum(ms.gol)::int as g from public.match_stats ms join public.matches m on m.id = ms.match_id
          join public.fixtures f on f.id = m.fixture_id and f.season_id = v_stagione and f.stato = 'simulata'
          join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
         where ms.league_id = p_league_id group by pi.id, p.nome having sum(ms.gol) > 0 order by g desc limit 6)
      select (select nome from marcatori order by g desc limit 1) as primo,
             (select count(*) from marcatori where g = (select max(g) from marcatori))::int as pari,
             (select array_agg(nome) from (select nome from marcatori order by g desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 and not (r.primo = any(r.altri)) and (select count(distinct x) from unnest(r.altri) x) = 3 then
        v_testo := format('Chi è il capocannoniere di %s in questa stagione?', v_lega);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo = 'capolista' then
      select s.conferenza, (select t.nome from public.standings s1 join public.teams t on t.id = s1.team_id where s1.season_id = v_stagione and s1.conferenza is not distinct from s.conferenza and s1.posizione = 1) as primo,
             (select array_agg(t.nome order by s2.posizione) from public.standings s2 join public.teams t on t.id = s2.team_id where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza and s2.posizione between 2 and 4) as altri into r
        from public.standings s where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.primo is not null and array_length(r.altri, 1) = 3 then
        v_gruppo := case r.conferenza when 'est' then 'della Conference Est' when 'ovest' then 'della Conference Ovest' else 'in classifica' end;
        v_testo := format('Chi è prima %s in questo momento?', v_gruppo);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo in ('attacco', 'difesa') then
      with ordine as (select t.nome, case when v_tipo = 'attacco' then s.gol_fatti else s.gol_subiti end as n from public.standings s join public.teams t on t.id = s.team_id
                       where s.season_id = v_stagione and s.giocate > 0 order by 2 desc limit 5)
      select (select nome from ordine order by n desc limit 1) as primo, (select count(*) from ordine where n = (select max(n) from ordine))::int as pari,
             (select array_agg(nome) from (select nome from ordine order by n desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 then
        v_testo := case v_tipo when 'attacco' then format('Quale squadra ha segnato più gol in campionato in %s?', v_lega) else format('Quale squadra ha subito più gol in campionato in %s?', v_lega) end;
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    end if;
    -- la stessa identica domanda non torna prima di 2 giorni
    if v_testo is not null and exists (select 1 from public.quizzone_domande x where x.league_id = p_league_id and x.testo = v_testo and x.ora > p_ora - interval '2 days') then v_testo := null; end if;
    if v_testo is not null and array_length(v_sbagliate, 1) = 3 and not (v_giusta = any(v_sbagliate)) and (select count(distinct x) from unnest(v_sbagliate) x) = 3 then
      v_mix := private.quiz_mescola(v_giusta, v_sbagliate);
      insert into public.quizzone_domande (league_id, ora, tipo, testo, risposte, corretta)
      values (p_league_id, p_ora, v_tipo, v_testo, v_mix -> 'risposte', (v_mix ->> 'corretta')::int)
      on conflict (league_id, ora) do nothing returning * into d;
      if d.id is null then select * into d from public.quizzone_domande where league_id = p_league_id and ora = p_ora; end if;
      return d;
    end if;
  end loop;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION private.quiz_prossima_ora(p_ora timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select min(x) from generate_series(date_trunc('hour', p_ora) + interval '1 hour', date_trunc('hour', p_ora) + interval '25 hours', interval '1 hour') x
   where extract(hour from x at time zone 'Europe/Rome') between 8 and 21
$function$;

CREATE OR REPLACE FUNCTION private.quizzone_cron()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l record; v_ora timestamptz := date_trunc('hour', now()) + interval '1 hour'; d public.quizzone_domande; v_h int;
  v_roma timestamp := now() at time zone 'Europe/Rome';
begin
  -- Le notifiche di avviso non servono a domanda passata: via dopo 4 minuti (la domanda e' alle :00, si chiude alle :00:26).
  delete from public.notifications where titolo = 'QuizOne' and dati ->> 'view' = 'quizzone' and creata_il < now() - interval '4 minutes';
  if v_roma::time >= time '21:30' then
    for l in select id from public.leagues where quizzone loop
      continue when exists (select 1 from public.quizzone_vincitori where league_id = l.id and giorno = v_roma::date);
      continue when not exists (select 1 from public.quizzone_domande where league_id = l.id
                                 and ora >= v_roma::date::timestamp at time zone 'Europe/Rome');
      perform private.quiz_premia_giorno(l.id, v_roma::date);
    end loop;
  end if;
  if now() < v_ora - interval '190 seconds' then return; end if;
  v_h := extract(hour from v_ora at time zone 'Europe/Rome');
  -- Domande nuove solo a stagione in corso con almeno una giornata giocata (private.quizzone_in_corso).
  for l in select id from public.leagues where quizzone and private.quizzone_in_corso(id) loop
    continue when exists (select 1 from public.quizzone_domande where league_id = l.id and ora = v_ora);
    d := private.quiz_genera(l.id, v_ora);
    if d.id is not null and v_h between 8 and 21 then
      insert into public.notifications (user_id, league_id, tipo, titolo, corpo, dati)
      select t.user_id, l.id, 'sistema', 'QuizOne', format('Tra 3 minuti la domanda delle %s! Apri QuizOne: avrai 10 secondi per entrare.', v_h || ':00'), '{"view": "quizzone"}'::jsonb
        from public.teams t where t.league_id = l.id and t.attiva and t.user_id is not null;
    end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION private.scadenza_conferenza(p_da timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select (((p_da at time zone 'Europe/Rome')::date + 1) + time '21:30') at time zone 'Europe/Rome'
$function$;

CREATE OR REPLACE FUNCTION private.lancia_conferenze_pre()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chiave text;
  v_fx bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_fx in
    select f.id
    from public.fixtures f
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa and l.stato = 'stagione' and l.fase_carriera = 'normale'
    where f.stato = 'programmata'
      -- Orario della domanda: per ogni partita un momento fisso tra 10 e 5 ore prima della simulazione
      -- (12:00-17:00 per le 22:00), a scatti di 5 minuti, cosi' i giornalisti arrivano a orari diversi.
      and f.data_sim - interval '10 hours' + (abs(hashtext('pre' || f.id::text)) % 61) * interval '5 minutes' <= now()
      and f.data_sim > now() + interval '30 minutes'
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc
                    and not exists (select 1 from public.conferenze_domande d where d.fixture_id = f.id and d.team_id = t.id))
      and not exists (select 1 from private.conferenze_pre_richieste r
                      where r.fixture_id = f.id and (r.richiesta_il > now() - interval '3 minutes' or r.tentativi >= 8))
    order by f.id
    limit 1
  loop
    insert into private.conferenze_pre_richieste (fixture_id) values (v_fx)
    on conflict (fixture_id) do update set richiesta_il = now(), tentativi = private.conferenze_pre_richieste.tentativi + 1;
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
      body := jsonb_build_object('azione', 'genera_pre', 'fixture_id', v_fx),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 60000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end $function$;

CREATE OR REPLACE FUNCTION private.completa_sorteggi_scaduti()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_s record;
begin
  perform private.notifica_scelte_rivelate();
  for v_s in
    select s.*
    from public.sorteggi_conferenze s
    join public.leagues l on l.id = s.league_id
    where s.completato_il is null
      and l.fase_carriera = 'sorteggio'
      and l.stagione_corrente = s.stagione
      and clock_timestamp() >= s.avviato_il + (s.totale * s.passo_secondi + 20) * interval '1 second'
    order by s.id
  loop
    begin
      update public.leagues set fase_carriera = 'normale' where id = v_s.league_id;
      perform private.inizializza_stagione(v_s.league_id);
      update public.sorteggi_conferenze set completato_il = clock_timestamp() where id = v_s.id;
      perform private.notifica(
        t.user_id, v_s.league_id, 'sistema', 'Le conferenze sono pronte',
        'La stagione e'' iniziata: la prima giornata si giochera'' alle 22:00. Prepara la formazione.',
        jsonb_build_object('view', 'overview')
      )
      from public.teams t
      where t.league_id = v_s.league_id and t.attiva;
    exception when others then
      raise warning 'sorteggio conferenze: lega % non completata: % (%)', v_s.league_id, sqlerrm, sqlstate;
    end;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION private.finalizza_offseason(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
  v_scelte_live integer;
  v_avvio_live timestamptz;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      -- In diretta le notifiche delle scelte partono alla rivelazione.
      if v_league.conferenze_attive then perform set_config('private.silenzia_scelte', '1', true); end if;
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  perform set_config('private.silenzia_scelte', '', true);

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  -- Contratti scaduti e non rinnovati: i giocatori restano senza squadra E finiscono nella coda dei rilasci, cosi' alla
  -- prima estrazione dopo la riapertura del mercato compaiono tutti fra i free agent (non solo per sorteggio).
  with liberati as (
    update public.player_instances
    set team_id = null
    where league_id = p_league_id
      and team_id is not null
      and not ritirato
      and contratto_scadenza <= v_league.stagione_corrente
    returning player_id
  )
  insert into private.rilasci_in_coda (league_id, player_id)
  select p_league_id, l.player_id from liberati l
  on conflict (league_id, player_id) do nothing;

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile sotto il tetto, si applica
    -- l'insolvenza del design: escono prima gli ingaggi piu' alti finche'
    -- restano finanziabili anche i posti mancanti al minimo di 21. Sotto
    -- il tetto questo non dovrebbe piu' accadere per una rosa costruita
    -- interamente dopo la migrazione (ogni acquisizione verifica gia' la
    -- capienza), ma resta il paracadute per le rose ereditate dal vecchio
    -- modello a cassa (v. private.capienza_residua).
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_league.tetto_ingaggi;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      insert into private.rilasci_in_coda (league_id, player_id)
      select p_league_id, pi.player_id from public.player_instances pi where pi.id = v_candidate.id
      on conflict (league_id, player_id) do nothing;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome,
             coalesce(fap.overall_corrente, p.overall) as overall, coalesce(fap.eta_corrente, p.eta) as eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      left join public.free_agent_progression fap
        on fap.league_id = p_league_id and fap.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))
          <= v_league.tetto_ingaggi - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))) asc,
               coalesce(fap.overall_corrente, p.overall) asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
        delete from public.free_agent_progression
        where league_id = p_league_id and player_id = v_candidate.player_id;
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_league.tetto_ingaggi < v_ingaggi then
      raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il tetto ingaggi.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  -- Il rilascio automatico dei prospetti non promossi in tempo non e' piu'
  -- legato alla chiusura dell'off-season (deciso con l'utente il 4
  -- settembre 2026: comprare un giovane a ridosso della fine stagione non
  -- deve costringere a promuoverlo quasi subito). Ora e' un conto alla
  -- rovescia in giornate dal momento dell'acquisto, decrementato ogni
  -- giornata simulata da public.decrementa_vivaio_giornate — qui non
  -- resta piu' nulla da fare.

  -- ON-Season della nuova stagione: l'ordine dal monte ingaggi (minore -> maggiore),
  -- misurato ora che draft e rose sono completi.
  perform private.assegna_posizioni_on_per_monte_ingaggi(p_league_id, v_off.stagione_a);

  -- Le formazioni della stagione chiusa non devono sopravvivere nella nuova: lineups non ha la stagione,
  -- quindi una riga "giornata 2" di agosto verrebbe scambiata per quella della giornata 2 di questa
  -- stagione (simulazione, promemoria, pagina Formazione). Si archiviano e si tolgono: restano solo le
  -- formazioni preparate durante l'off-season (giornata 1 salvata dopo l'apertura dell'off-season).
  insert into private.lineups_archivio
  select l.*, v_off.stagione_da::smallint
  from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);
  delete from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
      offseason_fine = null,
      stato = 'stagione',
      stadio_attivo = true
  where id = p_league_id;

  -- Season 3 (diario §2): ogni stagione riparte con morale dei giocatori e pubblico a meta'. Si fa qui, alla
  -- chiusura dell'off-season, perche' durante l'off-season il morale serve ancora ai rinnovi.
  update public.player_instances set morale = 50
  where league_id = p_league_id and not ritirato and morale <> 50;
  update public.teams set pubblico = 50
  where league_id = p_league_id and pubblico <> 50;

  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Ritiro dei mai-scelti: legge l'eta' vera tracciata in
  -- free_agent_progression (non piu' un'eta' ipotetica ricalcolata),
  -- e ripulisce la riga tracciata quando il giocatore esce dal pool.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, fap.player_id, v_off.stagione_a
  from public.free_agent_progression fap
  where fap.league_id = p_league_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = fap.player_id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = fap.player_id
    )
    and fap.eta_corrente >= 34
    and random() < private.probabilita_ritiro(fap.eta_corrente)
  on conflict do nothing;

  delete from public.free_agent_progression fap
  using public.retired_players rp
  where fap.league_id = p_league_id and rp.league_id = p_league_id and rp.player_id = fap.player_id;

  -- Con le conferenze la stagione non parte subito: prima il sorteggio East/West
  -- in diretta, e solo a sorteggio concluso nasce il calendario
  -- (private.completa_sorteggi_scaduti).
  if v_league.conferenze_attive then
    perform private.crea_sorteggio_conferenze(p_league_id, v_off.stagione_a);
    v_season := null;
    -- Draft dei giocatori in diretta (30 s a scelta) e, 3 minuti dopo l'ultima
    -- scelta, il sorteggio. Parte al minuto pieno successivo alla chiusura.
    select count(*)::integer into v_scelte_live
    from public.scelte_draft
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off' and stato in ('usata', 'vuota');
    if v_scelte_live > 0 then
      v_avvio_live := date_trunc('minute', clock_timestamp()) + interval '1 minute';
      insert into public.scelte_live (league_id, stagione, finestra, avviato_il, totale)
      values (p_league_id, v_off.stagione_da, 'off', v_avvio_live, v_scelte_live)
      on conflict (league_id, stagione, finestra) do nothing;
      update public.sorteggi_conferenze
      set avviato_il = v_avvio_live + (v_scelte_live * 30 + 180) * interval '1 second'
      where league_id = p_league_id and stagione = v_off.stagione_a and completato_il is null;
    end if;
  else
    v_season := private.inizializza_stagione(p_league_id);
  end if;

  perform private.notifica(
    t.user_id, p_league_id, 'sistema',
    case when v_league.conferenze_attive then 'Draft e sorteggio in diretta' else 'La nuova stagione e'' iniziata' end,
    case when v_league.conferenze_attive then 'Entra ora: prima il draft dei giocatori, poi il sorteggio delle conferenze Eastern e Western.'
         else 'La prima giornata si giochera'' alle 22:00. Prepara la formazione.' end,
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.inizializza_stagione(p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_k integer;
  v_i integer;
  v_r integer;
  v_x integer;
  v_y integer;
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_scadenza timestamptz;
  v_prima_giornata timestamptz;
  v_start date;
  v_campo_neutro boolean;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_gia_assegnate integer;
  v_gruppo text;
  v_conferenze boolean;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  v_conferenze := v_league.conferenze_attive;

  select id into v_season_id
  from public.seasons
  where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;

  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.';
  end if;

  select o.scade_il into v_scadenza
  from public.offseasons o
  where o.league_id = p_league_id and o.stagione_a = v_league.stagione_corrente
  order by o.id desc limit 1;

  -- Con le conferenze il calendario nasce a sorteggio concluso, non alla scadenza
  -- dell'off-season: la prima giornata e' alle 22:00 del primo giorno utile dopo la fine
  -- del sorteggio (7 ottobre 2026: si parte lo stesso giorno, deciso col committente).
  v_prima_giornata := private.primo_calcio_dopo(case when v_conferenze then clock_timestamp() else coalesce(v_scadenza, clock_timestamp()) end);
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine, giornate_totali)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1), v_league.giornate_totali)
  returning id into v_season_id;

  -- Il blocco "non svincolabile per 10 giornate dall'acquisto" confronta
  -- giornata_acquisizione con la prossima giornata in programma, ma
  -- giornata_acquisizione e' un numero di giornata SENZA stagione: a
  -- cavallo di due stagioni il confronto perde senso. Un acquisto alla
  -- giornata 19 della stagione scorsa, letto alla giornata 12 di questa,
  -- dava -7 giornate trascorse — messaggio assurdo ("mancano 17
  -- giornate") e blocco attivo fino alla 29ª di una stagione in cui il
  -- giocatore era in rosa dall'inizio. Un acquisto della stagione
  -- precedente non e' per definizione "recente": si azzera qui, alla
  -- nascita di ogni stagione, dove NULL significa gia' "mai bloccato"
  -- (draft, rose iniziali, off-season).
  update public.player_instances
  set giornata_acquisizione = null
  where league_id = p_league_id and giornata_acquisizione is not null;

  insert into public.standings(season_id, league_id, team_id, posizione, conferenza)
  select v_season_id, p_league_id, t.id,
         row_number() over(partition by c.conferenza order by t.nome, t.id)::smallint,
         c.conferenza
  from public.teams t
  left join (
    select x.team_id, x.conferenza
    from public.sorteggio_estrazioni x
    join public.sorteggi_conferenze s on s.id = x.sorteggio_id
    where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and v_conferenze
  ) c on c.team_id = t.id
  where t.league_id = p_league_id and t.attiva;

  -- Con le conferenze (East/West) si gioca solo dentro la propria: stesso
  -- metodo del cerchio, applicato a ciascun gruppo, sulle STESSE giornate.
  -- Senza conferenze c'e' un solo gruppo con tutte le squadre.
  foreach v_gruppo in array case when v_conferenze then array['est', 'ovest'] else array[''] end loop
    if v_conferenze then
      select coalesce(array_agg(x.team_id order by x.ordine), array[]::bigint[])
      into v_teams
      from public.sorteggio_estrazioni x
      join public.sorteggi_conferenze s on s.id = x.sorteggio_id
      where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and x.conferenza = v_gruppo;
      v_team_count := cardinality(v_teams);
    end if;
  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  if v_conferenze and v_league.n_gironi = 2 and v_team_count % 2 = 0 then
    -- Calendario di Berger (de Werra) con il ritorno speculare: ogni coppia si incontra due volte a campi invertiti,
    -- ogni squadra gioca ogni giornata, e casa/fuori si alternano con il minimo di rotture (al massimo due partite
    -- di fila nello stesso campo, 5 o 6 partite in casa per girone). Il ritorno riparte dal secondo turno
    -- dell'andata (ordine 1, 2, ..., ultimo, 0): cosi' nessuna coppia si rivede nella giornata dopo.
    -- Squadre 1..n-1 sul cerchio, l'ultima fissa; turno r: la fissa contro la r-esima, poi (r+k) contro (r-k).
    for v_leg in 1..2 loop
      for v_i in 0..(v_rounds - 1) loop
        v_r := case when v_leg = 1 then v_i else (v_i + 1) % v_rounds end;
        v_giornata := (v_leg - 1) * v_rounds + v_i + 1;
        for v_k in 0..(v_team_count / 2 - 1) loop
          if v_k = 0 then
            if v_r % 2 = 0 then v_home := v_teams[v_team_count]; v_away := v_teams[v_r + 1];
            else v_home := v_teams[v_r + 1]; v_away := v_teams[v_team_count]; end if;
          else
            v_x := (v_r + v_k) % v_rounds;
            v_y := (((v_r - v_k) % v_rounds) + v_rounds) % v_rounds;
            if v_k % 2 = 1 then v_home := v_teams[v_x + 1]; v_away := v_teams[v_y + 1];
            else v_home := v_teams[v_y + 1]; v_away := v_teams[v_x + 1]; end if;
          end if;
          if v_leg = 2 then v_swap := v_home; v_home := v_away; v_away := v_swap; end if;
          insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
          values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                  v_prima_giornata + ((v_giornata - 1) * interval '1 day'), false);
        end loop;
      end loop;
    end loop;
  else
  for v_leg in 1..v_league.n_gironi loop
    v_campo_neutro := (v_league.n_gironi % 2 = 1 and v_leg = v_league.n_gironi);
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];
        if v_home is null or v_away is null then continue; end if;
        if mod(v_round, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'), v_campo_neutro);
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;
  end if;
  end loop;

  -- ------------------------------------------------------------
  --  Mercato a scelte: inventario, posizioni di transizione, apertura
  --  ON-Season. Tutto best-effort — non deve mai impedire alla stagione
  --  di iniziare (docs/decisioni-draft-picks.md §2.1, §3.1).
  -- ------------------------------------------------------------
  begin
    -- Bootstrap: solo alla primissima stagione di una lega nuova, che non
    -- ha ne' un draft precedente ne' un playoff precedente da cui
    -- ereditare le scelte 1..4. genera_scelte_draft parte da
    -- stagione_corrente+1 e non tocca mai la stagione 1: la si genera qui,
    -- una tantum, e si assegna subito ON-Season 1 dalla spesa del draft di
    -- creazione (nessun playoff esiste ancora). OFF-Season 1 resta
    -- 'futura' fino ai playoff di questa stessa stagione.
    if v_league.stagione_corrente = 1 then
      insert into public.scelte_draft (league_id, team_origine_id, team_proprietario_id, stagione, finestra)
      select p_league_id, t.id, t.id, 1, f.finestra
      from public.teams t
      cross join (values ('on'), ('off')) as f(finestra)
      where t.league_id = p_league_id and t.attiva
      on conflict (league_id, team_origine_id, stagione, finestra) do nothing;

      perform private.assegna_posizioni_transizione(p_league_id, 1::smallint, 'on');
    end if;

    perform private.genera_scelte_draft(p_league_id);

    if v_league.stagione_corrente = 2 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = 2 and stato <> 'futura';
      if v_gia_assegnate = 0 then
        perform private.assegna_posizioni_transizione(p_league_id, 2::smallint);
      end if;
    end if;

    if v_league.stagione_corrente >= 1 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = v_league.stagione_corrente
        and finestra = 'on' and stato = 'determinata';
      if v_gia_assegnate > 0 and not exists (
        select 1 from public.finestre_scelte
        where league_id = p_league_id and stagione = v_league.stagione_corrente and finestra = 'on'
      ) then
        v_giornata_mezza := v_league.giornate_totali / 2;
        select f.data_sim into v_data_mezza
        from public.fixtures f
        where f.season_id = v_season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
        limit 1;
        if v_data_mezza is not null then
          perform private.svela_finestra_scelte(
            p_league_id, v_league.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
          );
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'mercato a scelte: inizializzazione fallita per lega %: % (%)', p_league_id, sqlerrm, sqlstate;
  end;

  return v_season_id;
end;
$function$;

-- Partite gia' in calendario e non ancora giocate: stesso giorno, alle 22:00.
update public.fixtures
set data_sim = (date_trunc('day', data_sim at time zone 'Europe/Rome') + interval '22 hours') at time zone 'Europe/Rome'
where stato = 'programmata'
  and (data_sim at time zone 'Europe/Rome')::time = time '23:00';
