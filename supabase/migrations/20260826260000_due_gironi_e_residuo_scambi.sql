-- Due cose, entrambe legate a leagues.giornate_totali.
--
-- 1) Real Fampionato passa da 3 a 2 gironi dalla stagione 2, su richiesta
--    dell'admin: il campionato si accorcia (22 giornate invece di 33) e la
--    stagione si chiude con playoff e playout (design §10.7). Con un numero
--    PARI di gironi sparisce anche il campo neutro dell'ultimo girone (§6.6),
--    che serviva solo a compensare lo squilibrio dei gironi dispari: andata e
--    ritorno si bilanciano da soli.
--
-- 2) rispondi_a_proposta calcolava l'ingaggio residuo di uno scambio su
--    leagues.giornate_totali. E' la stessa colonna generata che aveva gia'
--    rotto svincola_giocatore: cambia quando l'admin tocca squadre o gironi, e
--    conta partite che la stagione in corso non ha mai avuto. Oggi, a stagione
--    conclusa e con 21 giornate giocate su 33 dichiarate, uno scambio avrebbe
--    spostato il 36% dell'ingaggio annuale come "residuo" — su uno stipendio
--    da 10 M€ erano 3,64 M€ inesistenti, perche' la stagione e' gia' pagata
--    per intero. Ora conta le giornate della stagione vera, escluse quelle dei
--    tabelloni, e a stagione conclusa il residuo e' zero.
--
-- L'ordine conta: prima la correzione, poi il cambio di gironi. Al contrario,
-- fra le due istruzioni resterebbe una finestra in cui uno scambio userebbe
-- ancora il conteggio sbagliato.

CREATE OR REPLACE FUNCTION public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p public.trade_proposals; v_l public.leagues; v_da public.teams; v_a public.teams;
  v_g integer; v_totale integer; v_season_id bigint; v_off bigint; v_ric bigint; v_off_annuo bigint; v_ric_annuo bigint;
  v_esito public.trade_proposals; v_saldo bigint;
begin
  if not coalesce(p_accetta, false) then return public.rispondi_a_proposta_cassa_legacy(p_proposta_id, false); end if;
  select * into v_p from public.trade_proposals where id = p_proposta_id;
  select * into v_l from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a from public.teams where id = v_p.a_team_id;
  -- Giornate della STAGIONE in corso, escluse quelle dei tabelloni. Usare
  -- leagues.giornate_totali era sbagliato due volte: e' una colonna generata
  -- che cambia se l'admin tocca squadre o gironi, e conta partite che questa
  -- stagione non ha mai avuto. A stagione conclusa faceva comparire un residuo
  -- del 36% su un ingaggio gia' saldato per intero. Stesso errore gia'
  -- corretto per svincola_giocatore.
  select id into v_season_id from public.seasons
  where league_id = v_l.id and numero = v_l.stagione_corrente;
  select count(distinct f.giornata)::integer,
         count(distinct f.giornata) filter (where f.stato = 'simulata')::integer
    into v_totale, v_g
  from public.fixtures f
  where f.season_id = v_season_id and f.bracket_tie_id is null;
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio, coalesce(v_g, 0), coalesce(v_totale, 0))), 0) into v_off from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.ingaggio_residuo_stagione(ingaggio, coalesce(v_g, 0), coalesce(v_totale, 0))), 0) into v_ric from public.player_instances where id = any(v_p.giocatori_richiesti);
  if v_da.budget - v_p.conguaglio - (v_da.budget_ingaggi_riservato - v_off + v_ric) < 0 or v_a.budget + v_p.conguaglio - (v_a.budget_ingaggi_riservato - v_ric + v_off) < 0 then
    raise exception using errcode = '22023', message = 'Budget disponibile insufficiente per coprire il trasferimento e gli ingaggi residui.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_off_annuo from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(ingaggio), 0) into v_ric_annuo from public.player_instances where id = any(v_p.giocatori_richiesti);
  -- Contano solo i giocatori il cui contratto copre la prossima stagione:
  -- scambiarsi contratti in scadenza non sposta nulla dell'anno prossimo.
  select coalesce(sum(pi.ingaggio),0) into v_off_annuo from public.player_instances pi
  where pi.id = any(v_p.giocatori_offerti) and pi.contratto_scadenza > v_l.stagione_corrente;
  select coalesce(sum(pi.ingaggio),0) into v_ric_annuo from public.player_instances pi
  where pi.id = any(v_p.giocatori_richiesti) and pi.contratto_scadenza > v_l.stagione_corrente;
  perform private.verifica_sostenibilita(v_da.id, v_ric_annuo - v_off_annuo);
  perform private.verifica_sostenibilita(v_a.id, v_off_annuo - v_ric_annuo);

  v_esito := public.rispondi_a_proposta_cassa_legacy(p_proposta_id, true);
  update public.teams set budget = budget - v_off + v_ric, budget_ingaggi_riservato = budget_ingaggi_riservato - v_off + v_ric where id = v_da.id returning budget into v_saldo;
  update public.teams set budget = budget - v_ric + v_off, budget_ingaggi_riservato = budget_ingaggi_riservato - v_ric + v_off where id = v_a.id;
  return v_esito;
end;
$function$;

update public.leagues set n_gironi = 2 where id = 37;
