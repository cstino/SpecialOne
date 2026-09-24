-- ============================================================
--  ORDINE DI SCELTA DAI PLAYOFF: IL PERCORSO DI CHI TI HA BATTUTO
--
--  Deciso con l'utente il 24 settembre 2026, col tabellone disegnato. Prima
--  l'ordine era "vittorie nel tabellone, spareggio per classifica di stagione
--  regolare": fra i due semifinalisti o fra i quattro eliminati ai quarti
--  decideva la classifica, non contro chi si era perso.
--
--  Ora ogni eliminato si mette subito dietro a chi l'ha battuto. Draft Playoff
--  a 8: campione 1, finalista 2, semifinalista battuto dal campione 3, battuto
--  dal finalista 4, e ai quarti 5-6-7-8 seguendo lo stesso filo. Title Playoff:
--  lo specchio, il campione sceglie per ultimo.
--
--  Chiude anche una contraddizione: sulle scelte 3-4 il codice usava la
--  classifica mentre decisioni-draft-picks.md §2 diceva gia' "lato del
--  campione" prima di "lato del finalista".
--
--  Definizione ripresa dal database vivo: cambia solo il calcolo del rango.
-- ============================================================

CREATE OR REPLACE FUNCTION private.assegna_posizioni_playoff(p_league_id bigint, p_stagione_giocata smallint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season_id bigint;
  v_gia integer;
  v_da_assegnare integer;
  v_non_concluso integer;
  v_assegnate integer;
  v_bracket record;
  v_turno smallint;
  v_taglia_draft integer;
  v_taglia_title integer;
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

  -- ORDINE DI SCELTA: IL PERCORSO DI CHI TI HA BATTUTO
  --
  -- Deciso con l'utente il 24 settembre 2026, sostituisce "vittorie nel
  -- tabellone + spareggio di classifica". Si parte dal campione e si scende
  -- turno per turno: ogni eliminato si mette SUBITO DIETRO a chi l'ha battuto,
  -- nell'ordine in cui quei vincitori sono gia' classificati. Perdere contro
  -- chi poi arriva lontano vale di piu'.
  --
  -- Draft Playoff, 8 squadre:
  --   1 campione · 2 finalista
  --   3 semifinalista battuto dal campione · 4 battuto dal finalista
  --   5 quarti, battuto dal campione · 6 battuto dal finalista
  --   7 battuto dal 3° · 8 battuto dal 4°
  -- Title Playoff: lo specchio esatto, il campione sceglie per ultimo.
  --
  -- Prima c'era lo spareggio per classifica anche sulle scelte 3-4, e questo
  -- contraddiceva decisioni-draft-picks.md §2 ("perdente di semifinale, lato
  -- del campione"). Il percorso lo risolve da se', e i bye si gestiscono senza
  -- casi speciali: una squadra che salta un turno compare nel turno dopo.
  create temp table if not exists _rango_playoff (
    bracket_id bigint, tipo text, team_id bigint, rango integer
  ) on commit drop;
  delete from _rango_playoff;

  for v_bracket in
    select b.id, b.tipo from public.brackets b where b.season_id = v_season_id
  loop
    select max(turno) into v_turno from public.bracket_ties where bracket_id = v_bracket.id;

    -- il campione, cioe' il vincitore della finale
    insert into _rango_playoff
    select v_bracket.id, v_bracket.tipo, bt.vincitore_team_id, 1
    from public.bracket_ties bt
    where bt.bracket_id = v_bracket.id and bt.turno = v_turno;

    -- dalla finale al primo turno: ogni perdente sta dietro al suo vincitore
    while v_turno >= 1 loop
      insert into _rango_playoff
      select v_bracket.id, v_bracket.tipo,
             case when bt.vincitore_team_id = bt.alta_team_id then bt.bassa_team_id else bt.alta_team_id end,
             (select coalesce(max(rango), 0) from _rango_playoff where bracket_id = v_bracket.id)
               + row_number() over (order by r.rango)
      from public.bracket_ties bt
      join _rango_playoff r on r.bracket_id = v_bracket.id and r.team_id = bt.vincitore_team_id
      where bt.bracket_id = v_bracket.id and bt.turno = v_turno
        and bt.alta_team_id is not null and bt.bassa_team_id is not null;
      v_turno := v_turno - 1;
    end loop;
  end loop;

  select count(*) into v_taglia_draft from _rango_playoff where tipo = 'draft';
  select count(*) into v_taglia_title from _rango_playoff where tipo = 'title';

  update public.scelte_draft sd
  set posizione = case when r.tipo = 'draft' then r.rango
                       else v_taglia_draft + (v_taglia_title + 1 - r.rango) end,
      stato = 'determinata',
      aggiornata_il = now()
  from _rango_playoff r
  where sd.league_id = p_league_id
    and sd.team_origine_id = r.team_id
    and sd.stato = 'futura'
    and ((sd.stagione = p_stagione_giocata and sd.finestra = 'off')
      or (sd.stagione = p_stagione_giocata + 1 and sd.finestra = 'on'));

  get diagnostics v_assegnate = row_count;
  return v_assegnate;
end;
$function$;
