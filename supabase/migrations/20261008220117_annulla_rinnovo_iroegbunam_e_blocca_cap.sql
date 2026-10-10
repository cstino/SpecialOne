-- Serie F, Coccialand: il rinnovo di T. Iroegbunam a 20 M€ ha portato il
-- monte della stagione 2 a 89,7 M€ contro un tetto di 80 M€.
-- docs/decisioni-economia.md §1-2: il monte di ogni stagione deve restare nel tetto.
-- La RPC controllava solo la stagione 3, ma aggiorna subito l'ingaggio anche
-- per la 2. Controlliamo entrambe le stagioni prima di accettare la firma.
do $migrazione$
declare
  v_definizione text;
  v_vecchio text := $frammento$
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );$frammento$;
  v_nuovo text := $frammento$
    -- Le due verifiche sono sotto lo stesso lock di squadra: due rinnovi
    -- contemporanei non possono consumare la medesima capienza.
    perform 1 from public.teams where id = v_team.id for update;
    perform private.verifica_capienza(
      v_team.id, p_ingaggio - v_inst.ingaggio, v_league.stagione_corrente
    );
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );$frammento$;
begin
  v_definizione := pg_get_functiondef('public.offri_rinnovo(bigint,bigint,smallint,text)'::regprocedure);
  if length(v_definizione) - length(replace(v_definizione, v_vecchio, '')) <> length(v_vecchio) then
    raise exception 'Il controllo di capienza di offri_rinnovo non coincide con la versione attesa.';
  end if;
  execute replace(v_definizione, v_vecchio, v_nuovo);
end;
$migrazione$;

-- Rettifica del solo rinnovo erroneo. Il movimento originale resta nel
-- registro append-only: una nuova riga ne storna la variazione di 17,8 M€.
do $rettifica$
declare
  v_istanza public.player_instances;
  v_lega public.leagues;
  v_movimento public.transactions;
begin
  select * into strict v_lega from public.leagues where id = 63 and nome = 'Serie F';
  if v_lega.stagione_corrente <> 2 or v_lega.tetto_ingaggi <> 80000000 then
    raise exception 'La Serie F non è nello stato verificato per la rettifica.';
  end if;

  select pi.* into strict v_istanza
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  join public.teams t on t.id = pi.team_id
  where pi.id = 5846 and pi.league_id = 63 and pi.team_id = 279
    and t.nome = 'Coccialand' and p.nome = 'T. Iroegbunam'
  for update of pi;
  if v_istanza.ingaggio <> 20000000 or v_istanza.contratto_scadenza <> 3
     or v_istanza.rinnovo_stagione <> 2 or v_istanza.morale <> 96 then
    raise exception 'Il contratto di Iroegbunam è cambiato: rettifica interrotta.';
  end if;

  select * into strict v_movimento from public.transactions
  where id = 13553 and league_id = 63 and team_id = 279
    and tipo = 'rinnovo_in_stagione' and importo = 17800000
    and descrizione = 'Rinnovo: T. Iroegbunam — 20.0 M€ fino alla stagione 3';
  if exists (select 1 from public.transactions
             where tipo = 'rettifica_rinnovo' and descrizione like 'Annullamento rinnovo 13553:%') then
    raise exception 'Il rinnovo 13553 risulta già rettificato.';
  end if;

  -- La firma precedente è la transazione 12396: 2,2 M€ fino alla stagione 2.
  -- Il bonus morale della firma a 20 M€ è +35 (20 base + 15 massimi).
  update public.player_instances
  set ingaggio = 2200000,
      contratto_scadenza = 2,
      rinnovo_stagione = 1,
      morale = 61
  where id = v_istanza.id;

  insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (63, 279, 'rettifica_rinnovo', -17800000,
          'Annullamento rinnovo 13553: T. Iroegbunam, ritorno a 2.2 M€ fino alla stagione 2', 0);

  if private.monte_ingaggi(279, 2::smallint) > v_lega.tetto_ingaggi then
    raise exception 'Coccialand resta sopra il tetto dopo la rettifica.';
  end if;
end;
$rettifica$;
