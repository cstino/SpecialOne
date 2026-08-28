-- ============================================================
--  ORDINE DI SCELTA A REGIME: DAI RISULTATI DEI PLAYOFF
--  docs/decisioni-draft-picks.md §2, §6 bis
--
--  Fin qui esisteva solo assegna_posizioni_transizione (§2.1), la regola
--  una tantum per la stagione senza playoff a monte. Questa e' la regola
--  A REGIME: legge l'esito di Title Playoff e Draft Playoff della
--  stagione appena conclusa e assegna le posizioni delle scelte ON/OFF
--  della stagione successiva.
--
--  L'algoritmo generale, derivato dalla tabella di §2 invece di
--  copiarla riga per riga (cosi' regge anche N diverso da 14, incluso
--  il caso "sotto soglia" di §6 bis dove il Draft Playoff non esiste):
--
--  Per ogni squadra di un tabellone, "vittorie" = quante bracket_ties ha
--  vinto in quel tabellone (un bye conta: e' gia' registrato come vinto
--  in bracket_ties). Il campione ne ha vinte quante sono i turni, il
--  perdente della finale una in meno, e cosi' a scendere.
--
--  - Nel Draft Playoff PIU' vittorie = scelta MIGLIORE (posizione piu'
--    bassa): chi vince e' premiato, non compensato. Il campione del
--    Draft Playoff prende la 1a scelta assoluta.
--  - Nel Title Playoff PIU' vittorie = scelta PEGGIORE (posizione piu'
--    alta): il campione della lega non ha bisogno anche della scelta
--    migliore, sceglie per ultimo.
--  - Il blocco Draft Playoff (posizioni 1..M) viene sempre prima del
--    blocco Title Playoff (posizioni M+1..N) — anche quando M=0 (nessun
--    Draft Playoff, tutte le posizioni derivano dal Title Playoff:
--    §6 bis, deciso per LegaBot il 28 agosto).
--  - Parita' di vittorie: la peggio piazzata in classifica sceglie
--    prima (§2, "si spezza con la classifica della stagione regolare").
--
--  Verificato a mano che per un caso a 14 squadre (Title 8, Draft 6)
--  questo produce esattamente la tabella di §2: vedi il test qui sotto,
--  eseguito in transazione con rollback prima di applicare per davvero.
-- ============================================================

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
  v_stagione_scelte smallint := p_stagione_giocata + 1;
  v_season_id bigint;
  v_gia integer;
  v_non_concluso integer;
  v_assegnate integer;
begin
  select count(*) into v_gia
  from public.scelte_draft
  where league_id = p_league_id and stagione = v_stagione_scelte and stato <> 'futura';
  if v_gia > 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni della stagione ' || v_stagione_scelte || ' sono gia'' state assegnate.';
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
    and sd.stagione = v_stagione_scelte
    and sd.team_origine_id = f.team_id;

  get diagnostics v_assegnate = row_count;
  return v_assegnate;
end;
$$;

comment on function private.assegna_posizioni_playoff(bigint, smallint) is
  'Ordine di scelta a regime dai risultati di Title/Draft Playoff (docs/decisioni-draft-picks.md §2). Generalizza anche il caso senza Draft Playoff (§6 bis).';

revoke all on function private.assegna_posizioni_playoff(bigint, smallint) from public, anon, authenticated;
grant execute on function private.assegna_posizioni_playoff(bigint, smallint) to service_role;

-- ------------------------------------------------------------
--  Aggancio: quando l'ULTIMO tabellone di una stagione si conclude,
--  prova ad assegnare le posizioni della stagione successiva.
--  Best-effort come il resto dell'automazione del mercato a scelte:
--  avanza_bracket gestisce fixtures e classifiche finali, non deve mai
--  fallire per colpa di una funzione che sta solo preparando l'ordine
--  di scelta.
-- ------------------------------------------------------------
create or replace function private.avanza_bracket(p_bracket_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_bracket public.brackets;
  v_lega public.leagues;
  v_turno integer;
  v_rimasti integer;
  v_vincitori bigint[];
  v_seeds integer[];
  v_n_ties integer;
  v_base integer;
  v_turni_max integer;
  v_turno_globale integer;
  v_tie_id bigint;
  v_alta bigint; v_bassa bigint;
  v_seed_a integer; v_seed_b integer;
  v_finalista bigint;
  v_stagione_giocata smallint;
  v_altri_aperti integer;
begin
  select * into v_bracket from public.brackets where id = p_bracket_id for update;
  if v_bracket.stato = 'concluso' then return; end if;
  select * into v_lega from public.leagues where id = v_bracket.league_id;

  select max(turno) into v_turno from public.bracket_ties where bracket_id = p_bracket_id;
  select count(*) into v_rimasti from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno and stato <> 'concluso';
  if v_rimasti > 0 then return; end if;

  select count(*) into v_n_ties from public.bracket_ties
  where bracket_id = p_bracket_id and turno = v_turno;

  -- Turno finale concluso: si assegna il vincitore. Nessun premio in
  -- denaro (ne' per il title ne' per il draft playoff): il primo da'
  -- il titolo, il secondo determina l'ordine di scelta della prossima
  -- stagione.
  if v_n_ties = 1 then
    select vincitore_team_id,
           case when alta_team_id = vincitore_team_id then bassa_team_id else alta_team_id end
      into v_bracket.vincitore_team_id, v_finalista
    from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

    update public.brackets
    set stato = 'concluso', concluso_il = now(),
        vincitore_team_id = v_bracket.vincitore_team_id,
        finalista_team_id = v_finalista
    where id = p_bracket_id;

    -- Se questo era l'ultimo tabellone ancora aperto della stagione,
    -- l'ordine di scelta della prossima si puo' calcolare.
    select count(*) into v_altri_aperti
    from public.brackets where season_id = v_bracket.season_id and stato <> 'concluso';
    if v_altri_aperti = 0 then
      begin
        select s.numero into v_stagione_giocata from public.seasons s where s.id = v_bracket.season_id;
        perform private.assegna_posizioni_playoff(v_bracket.league_id, v_stagione_giocata);
      exception when others then
        raise warning 'mercato a scelte: assegnazione posizioni fallita per lega % stagione %: % (%)',
          v_bracket.league_id, v_stagione_giocata, sqlerrm, sqlstate;
      end;
    end if;

    return;
  end if;

  -- Altrimenti si costruisce il turno successivo accoppiando i vincitori
  -- adiacenti: 0 con 1, 2 con 3, e cosi' via.
  select array_agg(vincitore_team_id order by posizione),
         array_agg(coalesce(
           case when vincitore_team_id = alta_team_id then alta_seed else bassa_seed end,
           999) order by posizione)
    into v_vincitori, v_seeds
  from public.bracket_ties where bracket_id = p_bracket_id and turno = v_turno;

  select max(giornata) into v_base from public.fixtures
  where season_id = v_bracket.season_id and bracket_tie_id is null;
  select greatest(
      private.turni_tabellone(least(8, count(*))::integer),
      private.turni_tabellone(greatest(count(*) - 8, 0)::integer))
    into v_turni_max
  from public.standings st join public.teams t on t.id = st.team_id and t.attiva
  where st.season_id = v_bracket.season_id and st.posizione is not null;

  -- Quanti turni restano a questo tabellone, per allineare la finale.
  v_turno_globale := v_turni_max - (ceil(log(2, greatest(v_n_ties, 2)::numeric))::integer);

  for i in 1..(v_n_ties / 2) loop
    -- Fra i due qualificati, il seed migliore (numero piu' basso) e' la "alta".
    if v_seeds[i * 2 - 1] <= v_seeds[i * 2] then
      v_alta := v_vincitori[i * 2 - 1]; v_seed_a := v_seeds[i * 2 - 1];
      v_bassa := v_vincitori[i * 2];     v_seed_b := v_seeds[i * 2];
    else
      v_alta := v_vincitori[i * 2];     v_seed_a := v_seeds[i * 2];
      v_bassa := v_vincitori[i * 2 - 1]; v_seed_b := v_seeds[i * 2 - 1];
    end if;

    insert into public.bracket_ties (
      bracket_id, league_id, turno, posizione,
      alta_team_id, bassa_team_id, alta_seed, bassa_seed, gara_secca
    ) values (
      p_bracket_id, v_bracket.league_id, v_turno + 1, i - 1,
      v_alta, v_bassa, v_seed_a, v_seed_b,
      (v_n_ties / 2) = 1
    ) returning id into v_tie_id;

    perform private.crea_fixtures_tie(v_tie_id, private.giornata_turno(v_base, v_turno_globale + 1));
  end loop;
end;
$function$;
