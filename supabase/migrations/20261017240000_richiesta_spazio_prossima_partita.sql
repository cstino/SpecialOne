-- Richieste dei giocatori: la richiesta di "piu' spazio" riguarda la PROSSIMA partita, con un numero preciso
-- (almeno mezz'ora), che e' quello che si verifica a fine partita. Prima diceva "nelle prossime partite",
-- che non si puo' controllare (17 ottobre 2026, committente).
begin;

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
        'Mister, ' || (v_p->>'nome') || ' vuole parlarle. Apri la home per rispondere.', jsonb_build_object('richiesta', true));
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$function$;

-- La richiesta di spazio ancora aperta usa il testo nuovo.
update public.richieste_giocatori
   set testo = 'Mister, so di poter dare di più alla squadra. Mi farebbe giocare almeno mezz''ora nella prossima partita?'
 where tipo = 'spazio' and stato = 'aperta' and testo like '%nelle prossime partite%';

commit;
