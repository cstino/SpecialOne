-- ============================================================
--  GLI ORARI DELLE PARTITE SLITTAVANO DI UN MINUTO AL GIORNO.
--
--  Segnalato dall'utente il 7 settembre 2026: "tutte le cose che si
--  basano su orari non sono precise, spesso le aperture/chiusure
--  variano di minuti".
--
--  Non era pg_cron: lo storico di cron.job_run_details mostra ogni
--  esecuzione partita esattamente al secondo :00. Era
--  private.pianifica_prossima_giornata, che ripianificava la giornata
--  successiva cosi':
--
--    set data_sim = max(matches.simulata_il) + interval '24 hours'
--
--  cioe' ancorandola al momento in cui la simulazione era REALMENTE
--  avvenuta. Ma quel momento e' gia' in ritardo sul programmato: il cron
--  controlla ogni minuto (schedule '* * * * *'), quindi parte fino a 60
--  secondi dopo data_sim, piu' la durata della simulazione. Il ritardo di
--  ogni sera diventava la base della sera dopo:
--
--    programmata(n+1) = eseguita(n) + 24h = programmata(n) + 24h + ritardo
--
--  Una deriva cumulativa, non un jitter casuale. Misurata sulla lega 63
--  (Serie F): giornata 1 programmata alle 23:00:00, giornata 9 arrivata a
--  23:07:02 in appena 8 giornate (~53 s ciascuna). Con 176 giornate
--  ancora da giocare sarebbero state oltre 2 ore e mezza di slittamento a
--  fine stagione. E siccome private.mercato_aperto_lega deriva le sue
--  finestre dagli orari delle partite (ultima + 30 min, prossima - 2 h),
--  slittava a cascata anche l'apertura/chiusura del mercato.
--
--  Il commento originale sopra quella riga diceva "senza dipendere dal
--  minuto in cui parte cron": era esattamente il contrario.
--
--  Fix: ancorare la giornata successiva all'orario PROGRAMMATO di quella
--  appena conclusa, non a quello eseguito. Il ritardo di stasera non si
--  somma piu' a domani, e l'errore non si accumula.
--
--  In piu', l'aritmetica passa per l'ora locale invece che per un
--  "+ 24 hours" secco: cosi' la partita resta alle 23:00 di Roma anche
--  attraverso il cambio dell'ora legale, invece di spostarsi di un'ora
--  (CLAUDE.md sezione 2: il fuso e' un requisito, e la trappola nota e'
--  proprio il cambio dell'ora legale).
--
--  Resta il comportamento dinamico voluto dal disegno originale per i
--  fermi veri: se il gioco e' rimasto bloccato piu' di un giorno, le
--  giornate non si accavallano tutte insieme: si sposta avanti di 24 ore
--  finche' l'orario non torna nel futuro, mantenendo l'ora di parete.
-- ============================================================

begin;

create or replace function private.pianifica_prossima_giornata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_programmata_conclusa timestamptz;
  v_prossima_giornata smallint;
  v_prossima timestamptz;
begin
  if new.stato <> 'simulata' or old.stato = 'simulata' then
    return new;
  end if;

  -- Si aspetta l'ultima partita della giornata: fino ad allora non si deve
  -- spostare il turno successivo.
  if exists (
    select 1 from public.fixtures f
    where f.league_id = new.league_id
      and f.giornata = new.giornata
      and f.stato <> 'simulata'
  ) then
    return new;
  end if;

  -- L'ANCORA E' L'ORARIO PROGRAMMATO, non matches.simulata_il: e' questa
  -- la riga che prima faceva derivare tutto il calendario.
  select max(f.data_sim) into v_programmata_conclusa
  from public.fixtures f
  where f.league_id = new.league_id and f.giornata = new.giornata;

  select min(f.giornata) into v_prossima_giornata
  from public.fixtures f
  where f.league_id = new.league_id
    and f.giornata > new.giornata
    and f.stato = 'programmata';

  if v_programmata_conclusa is null or v_prossima_giornata is null then
    return new;
  end if;

  -- +1 giorno calcolato in ora locale: attraverso il cambio dell'ora
  -- legale l'intervallo reale e' di 23 o 25 ore, ma l'orario di parete
  -- resta lo stesso — che e' quello che i partecipanti si aspettano.
  v_prossima := ((v_programmata_conclusa at time zone 'Europe/Rome') + interval '1 day')
                at time zone 'Europe/Rome';

  -- Solo per i fermi lunghi (piu' di un giorno di stop): evita che le
  -- giornate arretrate partano tutte in fila a un minuto di distanza.
  -- Nel caso normale la condizione e' gia' falsa al primo giro, perche'
  -- abbiamo appena simulato a ridosso di v_programmata_conclusa.
  while v_prossima <= now() loop
    v_prossima := ((v_prossima at time zone 'Europe/Rome') + interval '1 day')
                  at time zone 'Europe/Rome';
  end loop;

  update public.fixtures
  set data_sim = v_prossima
  where league_id = new.league_id
    and giornata = v_prossima_giornata
    and stato = 'programmata';

  return new;
end;
$$;

-- ------------------------------------------------------------
--  Ripristino della deriva gia' accumulata.
--
--  Solo la giornata immediatamente successiva risulta sporca: il trigger
--  riscriveva una giornata alla volta, quindi il resto del calendario e'
--  ancora agli orari originali della generazione (verificato: lega 63
--  giornata 9 a 23:07:02, giornate 10+ tutte a 23:00:00).
--
--  L'orario giusto si ricava dalla giornata 1 della stessa lega, che
--  nessuno ha mai riscritto. Si aggiorna solo se la deriva e' inferiore a
--  un'ora, per non toccare le leghe il cui calendario e' stato spostato
--  di proposito (la 62 e' in playoff con orari da test manuali).
-- ------------------------------------------------------------
with orario_giusto as (
  select f.league_id,
         (select (min(f1.data_sim) at time zone 'Europe/Rome')::time
          from public.fixtures f1
          where f1.league_id = f.league_id and f1.giornata = 1) as ora_originale,
         min(f.giornata) as prossima_giornata
  from public.fixtures f
  join public.leagues l on l.id = f.league_id
  where f.stato = 'programmata' and l.stato = 'stagione'
  group by f.league_id
)
update public.fixtures f
set data_sim = ((f.data_sim at time zone 'Europe/Rome')::date + o.ora_originale)
               at time zone 'Europe/Rome'
from orario_giusto o
where f.league_id = o.league_id
  and f.giornata = o.prossima_giornata
  and f.stato = 'programmata'
  and o.ora_originale is not null
  and (f.data_sim at time zone 'Europe/Rome')::time <> o.ora_originale
  and abs(extract(epoch from (
        (f.data_sim at time zone 'Europe/Rome')::time - o.ora_originale
      ))) < 3600;

commit;
