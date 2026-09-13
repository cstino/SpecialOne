-- ============================================================
--  ANNULLAMENTO DI UN RINNOVO SBAGLIATO — G. Leoni, M'ARPZZC FC, Serie F
--
--  Il 13 settembre 2026 alle 14:17 il proprietario di M'ARPZZC ha offerto per
--  errore 23,1 M€ a G. Leoni (18 anni, overall 71), che era stato preso
--  all'asta il 9 settembre a 3,5 M€. Un salto di 19,6 M€ su una rosa che ne
--  aveva 7,3 di capienza residua: non un affare discutibile, un errore di
--  battitura. Richiesta di annullamento dall'amministratore della lega.
--
--  COME SO A COSA TORNARE, senza indovinare.
--  La transazione 12442 registra "Rinnovo: G. Leoni — 23.1 M€ fino alla
--  stagione 2" con importo +19,60 M€, e la 12337 registra l'asta vinta a 3,5
--  M€: la differenza torna esatta. Per gli altri tre campi il riferimento sono
--  due compagni di squadra presi alla stessa asta e mai rinnovati (A. Kinsky e
--  I. Jansson): entrambi hanno contratto_scadenza 1, rinnovo_tentativi 0 e
--  rinnovo_stagione NULL. Chi invece ha rinnovato in stagione (F. Balogun,
--  Sergi Cardona) ha scadenza 2 e rinnovo_stagione 1, esattamente come Leoni
--  adesso. Lo stato da ripristinare e' quindi quello dei primi due.
--
--  rinnovo_stagione torna a NULL e non resta a 1: e' il campo che segna "ha
--  gia' rinnovato in questa stagione". Lasciarlo pieno annullerebbe il
--  contratto ma impedirebbe di rifare il rinnovo a una cifra sensata, che e'
--  probabilmente cio' che la squadra vorra' fare.
--
--  IL REGISTRO NON SI CANCELLA. transactions e' append-only (CLAUDE.md §6) e
--  la riga 12442 resta dov'e'. L'annullamento aggiunge una riga di segno
--  opposto: il saldo torna giusto e la storia resta leggibile, che e'
--  esattamente il motivo per cui quel registro esiste.
-- ============================================================

do $$
declare
  v_istanza   bigint;
  v_team      bigint;
  v_ingaggio  bigint;
begin
  select pi.id, pi.team_id, pi.ingaggio into v_istanza, v_team, v_ingaggio
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  join public.teams t on t.id = pi.team_id
  where pi.league_id = 63 and p.nome = 'G. Leoni' and t.nome like 'M%ARPZZC%';

  if v_istanza is null then
    raise notice 'Leoni non trovato in M''ARPZZC: niente da annullare.';
    return;
  end if;

  -- Idempotente: se l'ingaggio e' gia' quello dell'asta, la migrazione e' gia'
  -- passata e non va rifatta (rifarla scriverebbe una seconda riga di storno).
  if v_ingaggio = 3500000 then
    raise notice 'Rinnovo gia'' annullato: ingaggio gia'' a 3,5 M€.';
    return;
  end if;

  update public.player_instances
  set ingaggio           = 3500000,
      contratto_scadenza = 1,
      rinnovo_tentativi  = 0,
      rinnovo_stagione   = null
  where id = v_istanza;

  insert into public.transactions
    (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values
    (63, v_team, 'rinnovo_in_stagione', -(v_ingaggio - 3500000),
     'Annullamento rinnovo errato: G. Leoni torna a 3,5 M€ fino alla stagione 1 '
       || '(storno della transazione del 13/09)', 0);
end $$;
