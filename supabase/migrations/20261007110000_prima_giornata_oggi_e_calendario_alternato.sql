-- Prima giornata lo stesso giorno del sorteggio e calendario delle conferenze con casa/fuori alternati (7 ottobre 2026).
--  * La prima giornata e' alle 23:00 del primo giorno utile dopo la fine del sorteggio (oggi, se finisce prima delle 23:00).
--  * Calendario di Berger con ritorno speculare per le conferenze (girone doppio, squadre pari): ogni coppia due volte a
--    campi invertiti, al massimo due partite di fila nello stesso campo, 5 o 6 in casa per girone. Il vecchio metodo del
--    cerchio con inversione per turno dava fino a 4 rotture a squadra e gironi da 4 a 7 partite in casa.
--  Le altre leghe (senza conferenze, o con gironi dispari) usano il metodo di prima. Funzione ricostruita dalla definizione live.

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
  -- dell'off-season: la prima giornata e' alle 23:00 del primo giorno utile dopo la fine
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
