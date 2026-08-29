begin;

-- ============================================================
--  BOOTSTRAP DEL MERCATO A SCELTE PER LA STAGIONE 1, E CORREZIONE
--  DELLA REGOLA A REGIME PER OFF-SEASON
--  docs/decisioni-draft-picks.md §2, §2.1, §3.1 — decisioni del 29 agosto
--  2026 per la nuova lega, estese a tutte le leghe.
--
--  Problema 1 — ON-Season 1 e OFF-Season 1 non sono mai esistite.
--  private.genera_scelte_draft genera solo stagione_corrente+1..+4: per una
--  lega che comincia da zero (stagione_corrente=1 al primo inizializza_stagione),
--  questo produce 2,3,4,5 e non tocca mai la stagione 1. Confermato sui dati
--  reali: LegaBot non ha nessuna riga scelte_draft con stagione=1.
--
--  Decisione: alla primissima inizializzazione di una lega (stagione_corrente=1)
--  si generano ANCHE le scelte della stagione 1, e si assegna subito la
--  posizione della sola finestra ON-Season 1 in base alla spesa nel draft di
--  creazione squadra (crescente, pareggio spezzato a caso) — non esiste un
--  playoff precedente da cui derivarla. OFF-Season 1 resta 'futura': la
--  assegna il playoff della stagione 1 stessa, appena si conclude, con lo
--  stesso meccanismo a regime del problema 2.
--
--  Problema 2 — la regola a regime abbinava la finestra sbagliata.
--  private.assegna_posizioni_playoff, quando si concludono i playoff della
--  stagione N, assegnava finora ON-Season E OFF-Season di N+1 INSIEME, dallo
--  stesso piazzamento. Ma OFF-Season N si risolve alla fine dell'off-season
--  che segue la stagione N — cioe' quando il playoff di N e' gia' concluso
--  da un pezzo. Non ha senso farla dipendere dal piazzamento di N-1 quando
--  quello di N e' gia' noto e piu' recente.
--
--  Decisione: quando si concludono i playoff della stagione N si assegnano
--  OFF-Season N (la finestra della stagione appena giocata, che aspettava
--  proprio questo) e ON-Season N+1 (la prossima, che non ha ancora un
--  playoff piu' recente a disposizione) — non piu' ON-Season N+1 e
--  OFF-Season N+1 insieme. Il calcolo del piazzamento (vittorie nel tabellone,
--  spareggio di classifica) resta identico: cambia solo su quali due righe
--  si scrive.
--
--  Compatibilita' con le leghe in corso: LegaBot ha gia' OFF-Season 2
--  assegnata dalla vecchia regola una-tantum di transizione (§2.1, non
--  toccata da questo file). Quando i playoff della sua stagione 2 si
--  concluderanno, la nuova private.assegna_posizioni_playoff tentera' di
--  scrivere anche OFF-Season 2: il filtro "stato = 'futura'" nella UPDATE
--  la lascia stare (e' gia' determinata) e scrive solo ON-Season 3, che e'
--  ancora libera. Nessun errore, nessuna doppia assegnazione.
-- ============================================================


-- ------------------------------------------------------------
--  1. assegna_posizioni_transizione: aggiunge un parametro opzionale per
--     limitare l'assegnazione a una sola finestra. Default NULL = entrambe,
--     identico al comportamento storico per la chiamata gia' esistente
--     (stagione 2, transizione senza playoff a monte).
-- ------------------------------------------------------------

-- CREATE OR REPLACE non sostituisce una funzione quando cambia il numero di
-- parametri: crea un overload accanto alla vecchia. Va tolta esplicitamente,
-- altrimenti restano due funzioni quasi identiche.
drop function if exists private.assegna_posizioni_transizione(bigint, smallint);

create function private.assegna_posizioni_transizione(
  p_league_id bigint,
  p_stagione smallint,
  p_finestra text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_senza_draft text;
  v_gia         integer;
  v_squadre     integer;
  v_assegnate   integer;
begin
  if p_finestra is not null and p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: usa ''on'', ''off'' o NULL per entrambe.';
  end if;

  -- Non si rimescola un ordine gia' fissato: se qualcuno ha gia' composto
  -- la lista di preferenze sapendo di scegliere 3o, cambiargli la
  -- posizione sotto i piedi e' peggio che non assegnarla affatto.
  select count(*) into v_gia
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione
    and (p_finestra is null or finestra = p_finestra)
    and stato <> 'futura';
  if v_gia > 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni della stagione ' || p_stagione
        || coalesce(' (' || p_finestra || ')', '') || ' sono gia'' state assegnate.';
  end if;

  select count(*) into v_squadre
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione
    and finestra = coalesce(p_finestra, 'on');
  if v_squadre = 0 then
    raise exception using errcode = 'P0002',
      message = 'Nessuna scelta generata per la stagione ' || p_stagione || '.';
  end if;

  -- Una squadra entrata adesso e senza rosa non ha ancora draftato: la sua
  -- spesa varrebbe zero e si prenderebbe la prima scelta per un draft che
  -- non ha fatto.
  select string_agg(t.nome, ', ' order by t.nome) into v_senza_draft
  from public.teams t
  where t.league_id = p_league_id
    and t.entrata_stagione = p_stagione
    and t.attiva
    and not exists (select 1 from public.player_instances pi where pi.team_id = t.id);
  if v_senza_draft is not null then
    raise exception using errcode = '55000',
      message = 'Queste squadre non hanno ancora completato il draft: ' || v_senza_draft
                || '. Con la rosa vuota la spesa varrebbe zero e si prenderebbero le prime scelte.';
  end if;

  with ordine as (
    select
      t.id as team_id,
      row_number() over (
        order by
          -- prima le nuove
          (t.entrata_stagione is distinct from p_stagione),
          -- fra le nuove: chi ha speso meno al draft, poi sorteggio
          case when t.entrata_stagione = p_stagione then private.spesa_draft(t.id) end asc,
          -- fra le vecchie: ordine inverso di classifica
          case when t.entrata_stagione is distinct from p_stagione then st.posizione end desc,
          random()
      )::smallint as posizione
    from public.teams t
    left join public.seasons se
      on se.league_id = p_league_id and se.numero = (p_stagione - 1)::smallint
    left join public.standings st
      on st.season_id = se.id and st.team_id = t.id
    where t.league_id = p_league_id and t.attiva
  )
  update public.scelte_draft sd
  set posizione = o.posizione,
      stato     = 'determinata',
      aggiornata_il = now()
  from ordine o
  where sd.league_id = p_league_id
    and sd.stagione  = p_stagione
    and (p_finestra is null or sd.finestra = p_finestra)
    and sd.team_origine_id = o.team_id;

  get diagnostics v_assegnate = row_count;
  return v_assegnate;
end;
$$;

comment on function private.assegna_posizioni_transizione(bigint, smallint, text) is
  'Ordine di scelta senza playoff a monte: spesa crescente nel draft per le squadre nuove, classifica inversa per le vecchie (docs/decisioni-draft-picks.md §2.1). p_finestra=NULL assegna entrambe (transizione storica); ''on''/''off'' limita a una sola (bootstrap ON-Season 1, senza playoff nemmeno per OFF-Season 1).';

revoke all on function private.assegna_posizioni_transizione(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.assegna_posizioni_transizione(bigint, smallint, text) to service_role;


-- ------------------------------------------------------------
--  2. assegna_posizioni_playoff: quando si concludono i playoff della
--     stagione N, assegna OFF-Season N (non piu' N+1) e ON-Season N+1.
--     Il calcolo del piazzamento e' identico; cambia solo il bersaglio.
-- ------------------------------------------------------------

create or replace function private.assegna_posizioni_playoff(
  p_league_id bigint,
  p_stagione_giocata smallint
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_season_id bigint;
  v_gia integer;
  v_da_assegnare integer;
  v_non_concluso integer;
  v_assegnate integer;
begin
  -- Quante fra le due righe bersaglio (OFF di questa stagione, ON della
  -- prossima) sono ancora libere. Zero significa che il lavoro e' gia'
  -- stato fatto (o non c'e' nulla da fare): esce senza errori, e'
  -- legittimo — una lega puo' avere OFF-Season N gia' assegnata da
  -- assegna_posizioni_transizione (§2.1) quando i suoi playoff si
  -- concludono.
  select count(*) into v_da_assegnare
  from public.scelte_draft
  where league_id = p_league_id
    and ((stagione = p_stagione_giocata and finestra = 'off')
      or (stagione = p_stagione_giocata + 1 and finestra = 'on'))
    and stato = 'futura';
  if v_da_assegnare = 0 then
    return 0;
  end if;

  select id into v_season_id from public.seasons
  where league_id = p_league_id and numero = p_stagione_giocata;
  if not found then
    raise exception using errcode = 'P0002', message = 'Stagione ' || p_stagione_giocata || ' non trovata.';
  end if;

  select count(*) into v_non_concluso
  from public.brackets where season_id = v_season_id and stato <> 'concluso';
  if v_non_concluso > 0 then
    raise exception using errcode = '55000',
      message = 'I tabelloni della stagione ' || p_stagione_giocata || ' non sono ancora tutti conclusi.';
  end if;
  if not exists (select 1 from public.brackets where season_id = v_season_id) then
    raise exception using errcode = '55000',
      message = 'Nessun tabellone per la stagione ' || p_stagione_giocata || ': niente da cui derivare l''ordine.';
  end if;

  with squadre as (
    select distinct b.id as bracket_id, b.tipo, t.team_id
    from public.brackets b
    cross join lateral (
      select alta_team_id as team_id from public.bracket_ties bt
      where bt.bracket_id = b.id and bt.alta_team_id is not null
      union
      select bassa_team_id from public.bracket_ties bt
      where bt.bracket_id = b.id and bt.bassa_team_id is not null
    ) t
    where b.season_id = v_season_id
  ), punteggi as (
    select s.bracket_id, s.tipo, s.team_id,
      (select count(*) from public.bracket_ties bt
       where bt.bracket_id = s.bracket_id and bt.vincitore_team_id = s.team_id) as vittorie
    from squadre s
  ), con_classifica as (
    select p.*, coalesce(st.posizione, 999) as posizione_classifica
    from punteggi p
    left join public.standings st on st.season_id = v_season_id and st.team_id = p.team_id
  ), taglia_draft as (
    select count(*) as m from con_classifica where tipo = 'draft'
  ), ordinati as (
    select c.*,
      row_number() over (
        partition by c.tipo
        order by
          case when c.tipo = 'draft' then c.vittorie end desc,
          case when c.tipo = 'title' then c.vittorie end asc,
          c.posizione_classifica desc
      ) as rango
    from con_classifica c
  ), finali as (
    select o.team_id,
      case when o.tipo = 'draft' then o.rango else (select m from taglia_draft) + o.rango end::smallint as posizione
    from ordinati o
  )
  update public.scelte_draft sd
  set posizione = f.posizione,
      stato = 'determinata',
      aggiornata_il = now()
  from finali f
  where sd.league_id = p_league_id
    and sd.team_origine_id = f.team_id
    and sd.stato = 'futura'
    and ((sd.stagione = p_stagione_giocata and sd.finestra = 'off')
      or (sd.stagione = p_stagione_giocata + 1 and sd.finestra = 'on'));

  get diagnostics v_assegnate = row_count;
  return v_assegnate;
end;
$$;

comment on function private.assegna_posizioni_playoff(bigint, smallint) is
  'Quando si concludono i playoff della stagione N, assegna OFF-Season N (che aspettava proprio questo) e ON-Season N+1 (che non ha ancora un playoff piu'' recente). docs/decisioni-draft-picks.md §2, corretto il 29 agosto 2026: prima abbinava ON+OFF di N+1 insieme, sbagliando la finestra per OFF. Salta le righe gia'' assegnate da altre vie (es. la transizione una-tantum di §2.1) invece di sollevare errore.';

revoke all on function private.assegna_posizioni_playoff(bigint, smallint) from public, anon, authenticated;
grant execute on function private.assegna_posizioni_playoff(bigint, smallint) to service_role;


-- ------------------------------------------------------------
--  3. inizializza_stagione: al primissimo avvio di una lega (stagione 1,
--     nessuna stagione precedente da cui generare le solite +4), genera
--     anche le scelte della stagione 1 e assegna subito ON-Season 1 dalla
--     spesa nel draft di creazione. OFF-Season 1 resta 'futura' fino ai
--     playoff della stagione 1 (assegna_posizioni_playoff, sopra).
-- ------------------------------------------------------------

create or replace function private.inizializza_stagione(p_league_id bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
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
$$;

commit;
