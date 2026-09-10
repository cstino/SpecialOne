-- ============================================================
--  RIPARAZIONE DI UN DIFETTO INTRODOTTO DA ME IL 9 SETTEMBRE
--
--  Ieri, per evitare che una finestra draft sopravvivesse alla propria
--  stagione, avevo aggiunto ad avanza_finestre_scelte un blocco che le
--  RISOLVEVA all'istante. La stessa esecuzione pero' apriva anche la
--  finestra OFF di recupero, con due giorni di respiro perche' i
--  partecipanti componessero la lista — e il giro successivo, cinque
--  minuti dopo, quel blocco la ritrovava "di stagione arretrata" e la
--  chiudeva.
--
--  Danno reale, verificato sui dati: in LegaBot la OFF-Season 3 si e'
--  aperta il 9 settembre alle 13:03 e risolta alle 13:05. Le sette squadre
--  PC hanno preso il loro giocatore (le preferenze PC vengono generate in
--  automatico da preferenze_squadre_pc), mentre l'unica squadra umana —
--  Cocacolers — ha perso la scelta con zero preferenze, senza aver mai
--  avuto la possibilita' di comporre la lista. Esattamente il caso che il
--  promemoria di oggi voleva prevenire.
--
--  CORREZIONE 1. Una finestra arretrata non viene piu' risolta all'istante:
--  le si AVVICINA soltanto la scadenza a 48 ore da adesso, e la risoluzione
--  resta al percorso normale. Nessuno perde una scelta per un cambio di
--  calendario, e private.promemoria_scelte_draft fa in tempo a suonare il
--  suo avviso a 24 ore. La condizione "> now() + 48 ore" rende
--  l'aggiornamento una tantum.
--
--  CORREZIONE 2, difetto preesistente emerso guardando quel ciclo: la
--  risoluzione automatica filtrava "finestra = 'on'". Le OFF-Season non si
--  sono quindi MAI risolte da sole: l'unico modo era il pulsante dell'admin
--  (admin_forza_estrazione_scelte). Scaduta la loro ora restavano aperte a
--  tempo indeterminato. Ora il ciclo copre entrambe le finestre.
--  L'apertura della OFF resta legata alla chiusura della ON della stessa
--  stagione, come prima.
--
--  Il ripristino della scelta persa dai Cocacolers e' nel file successivo,
--  separato perche' tocca i dati di una lega e non va rigirato altrove.
-- ============================================================

begin;

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
  for v_finestra in
    select league_id, stagione, finestra
    from public.finestre_scelte
    where risolta_il is null
      and estrazione_il is not null and estrazione_il <= now()
    order by league_id, stagione, finestra
  loop
    begin
      perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'on', true);
      v_risolte := v_risolte + 1;
      if not exists (
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

commit;
