-- ============================================================
--  "MANCANO 17 GIORNATE" SU UN BLOCCO CHE DURA 10 GIORNATE.
--
--  Segnalato dall'utente su S. Al Shehri (LegaBot): il messaggio del
--  blocco svincolo diceva "Mancano 17 giornate" per una regola che ne
--  prevede al massimo 10. Non era solo il testo: il giocatore era
--  davvero bloccato, e lo sarebbe rimasto fino alla 29ª giornata.
--
--  Causa: private.svincola_giocatore_cassa_legacy calcola
--    giornate_trascorse = prossima_giornata - giornata_acquisizione
--  ma giornata_acquisizione e' un numero di giornata SENZA riferimento
--  alla stagione. Quel giocatore era stato acquistato alla giornata 19
--  della stagione 2; letto alla giornata 12 della stagione 3 il conto
--  faceva 12 - 19 = -7, e il messaggio stampava 10 - (-7) = 17.
--
--  Peggio del messaggio: superata la giornata 19 di QUESTA stagione il
--  conto sarebbe tornato positivo e il blocco si sarebbe riattivato da
--  solo a meta' campionato, su un giocatore in rosa dall'inizio. Per
--  questo non basta un guard sui valori negativi: serve azzerare il
--  dato quando cambia stagione.
--
--  Fix: private.inizializza_stagione (unico imbuto per la nascita di
--  ogni stagione, gia' idempotente — esce subito se la stagione esiste
--  gia') azzera giornata_acquisizione per tutta la lega. NULL e' il
--  valore che la regola tratta gia' come "mai bloccato" (draft, rose
--  iniziali, off-season), quindi non serve nessuna nuova colonna ne'
--  modifica alla funzione di svincolo.
--
--  Corpo di inizializza_stagione ri-fetchato dal vivo con
--  pg_get_functiondef e modificato in un solo punto: nient'altro cambia.
-- ============================================================

begin;

CREATE OR REPLACE FUNCTION private.inizializza_stagione(p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
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
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

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

  v_prima_giornata := private.primo_calcio_dopo(coalesce(v_scadenza, clock_timestamp()));
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

  insert into public.standings(season_id, league_id, team_id, posizione)
  select v_season_id, p_league_id, t.id,
         row_number() over(order by t.nome, t.id)::smallint
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
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
$function$

;

-- Backfill delle righe gia' rotte: un giornata_acquisizione MAGGIORE
-- della prossima giornata in programma e' impossibile dentro una stessa
-- stagione (il valore viene impostato proprio alla prossima giornata al
-- momento dell'acquisto, e da li' la stagione avanza), quindi identifica
-- con certezza un residuo di una stagione precedente.
update public.player_instances pi
set giornata_acquisizione = null
from public.leagues l
where l.id = pi.league_id
  and pi.giornata_acquisizione is not null
  and pi.giornata_acquisizione > coalesce(
    (select min(f.giornata) from public.fixtures f
      where f.league_id = l.id and f.stato = 'programmata'),
    l.giornate_totali + 1
  );

commit;
