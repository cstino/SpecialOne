-- ============================================================
--  I CRON GIRAVANO A MINUTI SFALSATI RISPETTO AGLI ORARI ANNUNCIATI.
--
--  Seconda delle tre cause dell'imprecisione segnalata dall'utente il
--  7 settembre 2026 (la prima, la deriva cumulativa del calendario, e'
--  chiusa in 20260907120000_orari_partite_senza_deriva.sql).
--
--  L'interfaccia dice "chiude alle 21:00" e "i nuovi svincolati escono
--  alle 23:30", ma le schedule erano su minuti arbitrari:
--
--    risoluzione-aste          '3 * * * *'          -> 21:03
--    risoluzione-aste-under    '2 * * * *'          -> 21:02
--    chiusura-mercato          '5 * * * *'          -> 21:05
--    estrazione-svincolati     '2,17,32,47 * * * *' -> 23:32
--    estrazione-under          '*/5 * * * *'        -> 23:30
--
--  Le offerte erano comunque gia' rifiutate dalle 21:00:00 in punto
--  (private.mercato_aperto_lega controlla l'orologio, non "il cron ha
--  girato"), quindi nessuno ha mai potuto offrire in ritardo: il
--  problema non era la correttezza ma il fatto che il countdown andava
--  a zero e gli esiti comparivano due-cinque minuti dopo.
--
--  Le schedule NON possono essere scritte come '0 21 * * *': cron.timezone
--  e' GMT, e l'offset di Roma cambia con l'ora legale. E' la trappola gia'
--  documentata in 20260901130000_fix_orario_cron_mercato_under.sql, dove
--  due job non partirono mai per mesi. Si resta quindi sullo schema
--  corretto — schedule frequente, controllo dell'ora di Roma dentro la
--  funzione — ma portando la schedule a ogni minuto, come fa gia'
--  simula-giornata-notturna: cosi' il primo giro utile cade sul secondo
--  :00 dell'orario giusto.
--
--  Perche' e' sicuro rieseguire ogni minuto:
--    - risolvi_aste / risolvi_aste_under lavorano solo sulle aste in
--      stato 'aperta' e le chiudono: al secondo giro non trovano nulla.
--    - scadi_proposte_giorno lavora solo sulle proposte 'in_attesa'
--      scadute e le marca 'scaduta': idem.
--    - estrai_under_lega ha gia' la sua guardia in testa (se esiste
--      un'asta under per quel giorno, esce subito).
--    - estrai_svincolati_lega NO: ricalcola max(tornata)+1 e creerebbe
--      una tornata nuova a ogni minuto. La guardia va aggiunta, ma NON
--      dentro estrai_svincolati_lega, che ha altri tre chiamanti
--      (apri_mercato_nuova_lega, admin_apri_mercato,
--      svincola_giocatore_cassa_legacy): bloccarla li' cambierebbe il
--      comportamento dell'admin che forza l'apertura del mercato.
--      Si aggiunge quindi nel solo punto d'ingresso del cron, e mirata
--      alla finestra notturna (creata_il >= le 23:30 di stasera) per non
--      confondere un'estrazione dell'admin fatta prima nella giornata.
-- ============================================================

begin;

-- ------------------------------------------------------------
--  Estrazione svincolati: idempotente sulla finestra notturna.
-- ------------------------------------------------------------
create or replace function private.estrai_svincolati()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oggi date;
  v_ora time;
  v_inizio_finestra timestamptz;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;

  -- Le 23:30 di stasera, ora di Roma: tutto cio' che e' stato estratto
  -- prima appartiene a un'apertura manuale dell'admin, non a questo giro.
  v_inizio_finestra := (v_oggi + time '23:30') at time zone 'Europe/Rome';

  for v_lega in select id from public.leagues where stato = 'stagione' and not mercato_bloccato loop
    -- Con la schedule a ogni minuto questa funzione rigira fino alle
    -- 23:45: senza questa guardia creerebbe una tornata nuova ogni volta.
    -- Le riesecuzioni servono da rete se il primo giro fallisce.
    if exists (
      select 1 from public.free_agent_auctions a
      where a.league_id = v_lega
        and a.giorno = v_oggi
        and a.origine = 'estrazione'
        and a.creata_il >= v_inizio_finestra
    ) then
      continue;
    end if;

    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$$;

-- ------------------------------------------------------------
--  Schedule a ogni minuto: il controllo vero sull'ora di Roma resta
--  dentro le funzioni, che e' l'unico modo corretto con cron.timezone
--  a GMT e l'ora legale di mezzo.
-- ------------------------------------------------------------
select cron.schedule('estrazione-svincolati',  '* * * * *', $cron$select private.estrai_svincolati();$cron$);
select cron.schedule('estrazione-under',       '* * * * *', $cron$select private.estrai_under();$cron$);
select cron.schedule('risoluzione-aste',       '* * * * *', $cron$select private.risolvi_aste();$cron$);
select cron.schedule('risoluzione-aste-under', '* * * * *', $cron$select private.risolvi_aste_under();$cron$);
select cron.schedule('chiusura-mercato',       '* * * * *', $cron$select private.chiudi_mercato_giornaliero();$cron$);

commit;
