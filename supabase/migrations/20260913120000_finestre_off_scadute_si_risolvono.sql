-- ============================================================
--  LE FINESTRE OFF SCADUTE NON SI RISOLVEVANO MAI
--
--  private.avanza_finestre_scelte selezionava da giorni anche le finestre OFF
--  arrivate a scadenza — il commento dentro la funzione lo dichiarava — ma poi
--  chiamava sempre risolvi_finestra_scelte(..., 'on', ...), con 'on' scritto
--  fisso. La ON di quella stagione era gia' risolta, quindi la funzione usciva
--  subito restituendo 0 e la OFF restava aperta in eterno.
--
--  COME E' SALTATO FUORI
--  Il 13 settembre 2026, mentre si provava il draft in diretta su LegaBot:
--  l'utente ha mostrato la schermata del mercato a scelte con un conto alla
--  rovescia fermo su 00:00:00 e il messaggio "le preferenze sono congelate".
--  Era la OFF-Season della stagione 3, scaduta il giorno prima alle 13:48, con
--  sei preferenze gia' compilate e nessuna estrazione in arrivo.
--
--  QUANTO E' GRANDE IL DANNO: una finestra sola, in tutto il progetto.
--  Verificato riga per riga su finestre_scelte prima di applicare — le altre
--  cinque sono o gia' risolte o con scadenza futura. Stamattina avevo stimato
--  che questa correzione avrebbe risolto d'un colpo le OFF arretrate di tutte
--  le leghe e per questo l'avevo rimandata: era una sopravvalutazione, il
--  raggio d'azione e' una riga sola.
--
--  Definizione ripresa dal database e modificata nel solo punto necessario.
-- ============================================================

CREATE OR REPLACE FUNCTION private.avanza_finestre_scelte()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_finestra record;
  v_risolte integer := 0;
begin
  -- Passaggio di recupero: leghe la cui stagione corrente e' iniziata
  -- PRIMA che questa automazione esistesse (es. LegaBot, stagione 2 gia'
  -- in corso al momento di questa migrazione). inizializza_stagione fa lo
  -- stesso lavoro alla nascita di ogni stagione successiva; qui si
  -- recupera solo chi e' rimasto indietro, ed e' innocuo ripeterlo:
  -- svela_finestra_scelte non ritocca una finestra gia' svelata.
  for v_lega in
    select l.id as league_id, l.stagione_corrente, s.id as season_id, s.giornate_totali
    from public.leagues l
    join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente
    where l.stato = 'stagione' and l.fase_carriera = 'normale' and l.stagione_corrente >= 2
      and exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = l.id and sd.stagione = l.stagione_corrente
          and sd.finestra = 'on' and sd.stato = 'determinata'
      )
      and not exists (
        select 1 from public.finestre_scelte f
        where f.league_id = l.id and f.stagione = l.stagione_corrente and f.finestra = 'on'
      )
  loop
    begin
      v_giornata_mezza := v_lega.giornate_totali / 2;
      select f.data_sim into v_data_mezza
      from public.fixtures f
      where f.season_id = v_lega.season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
      limit 1;
      if v_data_mezza is not null then
        perform private.svela_finestra_scelte(
          v_lega.league_id, v_lega.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
        );
      end if;
    exception when others then
      raise warning 'mercato a scelte: recupero apertura ON-Season fallito per lega % stagione %: % (%)',
        v_lega.league_id, v_lega.stagione_corrente, sqlerrm, sqlstate;
    end;
  end loop;

  -- Preferenze PC su tutte le finestre ancora aperte, non solo quelle in
  -- scadenza: cosi' una squadra PC non resta "in attesa" per giorni.
  for v_finestra in
    select league_id, stagione, finestra from public.finestre_scelte where risolta_il is null
  loop
    begin
      perform private.preferenze_squadre_pc(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra);
    exception when others then
      raise warning 'mercato a scelte: preferenze PC fallite per lega % stagione % finestra %: % (%)',
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, sqlerrm, sqlstate;
    end;
  end loop;

  -- Una finestra non deve sopravvivere alla propria stagione: se la lega e'
  -- gia' passata a quella dopo, la sua scadenza originale non ha piu' senso.
  --
  -- Il 9 settembre 2026 questo blocco la RISOLVEVA all'istante. Sbagliato, e
  -- si e' visto subito: la stessa esecuzione apriva la finestra OFF di
  -- recupero con due giorni di respiro, e il giro successivo (5 minuti dopo)
  -- la ritrovava "di stagione arretrata" e la chiudeva. In LegaBot le sette
  -- squadre PC hanno preso il loro giocatore — le preferenze PC sono
  -- generate in automatico — e l'unica squadra umana ha perso la scelta con
  -- zero preferenze, senza aver mai avuto la possibilita' di comporre la
  -- lista.
  --
  -- Ora la scadenza viene solo AVVICINATA a 48 ore da adesso, e la
  -- risoluzione resta al percorso normale piu' sotto. Cosi' nessuno perde
  -- una scelta per un cambio di calendario, e il promemoria delle 24 ore
  -- (private.promemoria_scelte_draft) fa in tempo a suonare. La condizione
  -- "> now() + 48 ore" rende l'aggiornamento una tantum: appena avvicinata,
  -- la finestra non rientra piu' nel filtro.
  update public.finestre_scelte f
  set estrazione_il = now() + interval '48 hours'
  from public.leagues l
  where l.id = f.league_id
    and f.risolta_il is null
    and f.estrazione_il is not null
    and f.stagione < l.stagione_corrente
    and f.estrazione_il > now() + interval '48 hours';

  -- Anche le finestre 'off', non piu' solo le 'on'. Prima l'unico modo di
  -- risolvere una OFF-Season era il pulsante dell'admin
  -- (admin_forza_estrazione_scelte): scaduta la sua ora restava aperta per
  -- sempre. Difetto preesistente, emerso guardando questo ciclo il 10
  -- settembre 2026. L'apertura della OFF resta legata alla chiusura della
  -- ON della stessa stagione, come prima.
  -- Il draft a passi (private.avanza_draft_live, ogni minuto) chiama una
  -- scelta alla volta perche' la lega la veda in diretta. Questo ciclo gira
  -- ogni 5 minuti e risolverebbe tutto in un colpo, bruciando la diretta:
  -- quindi salta le finestre ON affidate al draft live finche' e' nei tempi.
  --
  -- Resta pero' la RETE DI SICUREZZA, ed e' il motivo per cui la condizione e'
  -- scritta cosi'. Se il draft live non partisse o si piantasse, dopo il tempo
  -- che gli serve piu' dieci passi di grazia questo ciclo riprende il comando e
  -- risolve ugualmente la finestra. Nessuno perde una scelta perche' una
  -- macchina nuova si e' rotta: al peggio il draft avviene in ritardo e tutto
  -- insieme, come prima di oggi. L'ancora e' coalesce(avviata_il,
  -- estrazione_il): se il draft live non e' mai partito si misura dall'ora di
  -- estrazione, altrimenti il termine non scadrebbe mai.
  for v_finestra in
    select f.league_id, f.stagione, f.finestra
    from public.finestre_scelte f
    where f.risolta_il is null
      and f.estrazione_il is not null and f.estrazione_il <= now()
      and not (
        f.finestra = 'on'
        and f.passo_secondi > 0
        and now() < coalesce(f.avviata_il, f.estrazione_il) + make_interval(secs =>
              f.passo_secondi * (10 + (
                select count(*) from public.scelte_draft sd
                where sd.league_id = f.league_id and sd.stagione = f.stagione
                  and sd.finestra = f.finestra
                  and sd.stato in ('determinata', 'usata', 'vuota')))::integer)
      )
    order by f.league_id, f.stagione, f.finestra
  loop
    begin
      -- v_finestra.finestra, non 'on' fisso. Era il difetto: il ciclo
      -- selezionava anche le finestre OFF scadute — il commento sopra lo dice
      -- da giorni — ma poi chiedeva sempre di risolvere la ON della stessa
      -- stagione. Quella era gia' risolta, risolvi_finestra_scelte usciva
      -- subito restituendo 0, e la OFF restava aperta per sempre.
      --
      -- Trovato il 13 settembre 2026 guardando perche' la OFF-Season 3 di
      -- LegaBot fosse ferma dal giorno prima con le preferenze gia' compilate:
      -- la schermata del mercato mostrava un countdown a 00:00:00 e le
      -- preferenze congelate, senza che l'estrazione arrivasse mai.
      perform private.risolvi_finestra_scelte(
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, true);
      v_risolte := v_risolte + 1;

      -- L'apertura della OFF segue la chiusura della ON della stessa stagione.
      -- Ha senso solo quando quella appena risolta era la ON: prima il caso
      -- "finestra = off" ci passava comunque, innocuo solo perche' la riga
      -- cercata era quella che si stava risolvendo.
      if v_finestra.finestra = 'on' and not exists (
        select 1 from public.finestre_scelte
        where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
      end if;
    exception when others then
      raise warning 'mercato a scelte: risoluzione ON-Season fallita per lega % stagione %: % (%)',
        v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
    end;
  end loop;
  return v_risolte;
end;
$function$
;
