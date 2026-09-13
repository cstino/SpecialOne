-- ============================================================
--  UN TRAINING IN CORSO SEGUE IL GIOCATORE CHE VIENE SCAMBIATO
--
--  Segnalato il 13 settembre 2026: dopo uno scambio, un giocatore che stava
--  facendo un cambio di ruolo o una specializzazione restava bloccato.
--
--  PERCHE' SUCCEDEVA
--  Le righe di cambi_ruolo e specializzazioni_giocatore portano un team_id, che
--  al trasferimento restava quello della VECCHIA squadra. Da li' tre sintomi,
--  tutti dallo stesso difetto:
--
--    - il NUOVO proprietario non vedeva il training, perche' la pagina Squadra
--      filtra per team_id. Il giocatore sembrava libero. Ma avviare un training
--      gli veniva rifiutato con "ha gia' un cambio di ruolo in corso", perche'
--      quel controllo e' su player_instance_id e non sulla squadra: bloccato da
--      qualcosa che non poteva ne' vedere ne' annullare;
--    - il VECCHIO proprietario continuava a vedere (e poteva annullare) il
--      training di un giocatore che non aveva piu';
--    - alla scadenza la notifica "training completato" andava alla vecchia
--      squadra, perche' private.completa_cambi_ruolo e
--      private.completa_specializzazioni leggono team_id dalla riga.
--
--  Il training si completava comunque — quelle due funzioni scorrono per lega e
--  non per squadra — quindi nessun lavoro e' mai andato perso. Semplicemente
--  nessuno lo sapeva, e intanto il giocatore restava inutilizzabile.
--
--  LA REGOLA, decisa con l'utente: il training SEGUE il giocatore. Chi compra
--  se lo ritrova in corso, lo vede, riceve lui la notifica e puo' annullarlo
--  quando vuole (annulla_cambio_ruolo e annulla_specializzazione esistono gia'
--  e da ora funzionano per il proprietario giusto). E' anche la lettura piu'
--  realistica: un giocatore che si sta riqualificando continua a farlo.
--
--  Diverso il caso dello svincolo, dove una squadra nuova non c'e': li' la
--  riga viene cancellata, perche' un training senza nessuno che lo segua non
--  vuol dire niente. Se qualcuno lo riprende dal mercato, riparte da capo.
-- ============================================================

create or replace function private.training_segue_il_giocatore()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.team_id is null then
    -- Svincolato: nessuna squadra a cui affidare il training.
    delete from public.cambi_ruolo
    where player_instance_id = new.id and completato_il is null;
    delete from public.specializzazioni_giocatore
    where player_instance_id = new.id and completato_il is null;
  else
    update public.cambi_ruolo
    set team_id = new.team_id
    where player_instance_id = new.id and completato_il is null;
    update public.specializzazioni_giocatore
    set team_id = new.team_id
    where player_instance_id = new.id and completato_il is null;
  end if;
  return null;
end;
$$;

-- AFTER e non BEFORE come i trigger vicini: qui non si tocca NEW, si scrivono
-- altre tabelle in conseguenza di un trasferimento gia' avvenuto.
drop trigger if exists player_instances_training_segue on public.player_instances;
create trigger player_instances_training_segue
  after update of team_id on public.player_instances
  for each row
  when (old.team_id is distinct from new.team_id)
  execute function private.training_segue_il_giocatore();

-- ------------------------------------------------------------
--  Le righe gia' in limbo
--
--  Sette al momento di scrivere, tutte in Serie F e tutte specializzazioni,
--  nate dagli scambi fra Colpo del sole, FC Eddaiii e Coccialand. Scadono fra
--  la giornata 17 e la 25, quindi la correzione fa ancora in tempo a contare:
--  senza, la notifica sarebbe arrivata alla squadra sbagliata e fino ad allora
--  quei giocatori sarebbero rimasti inutilizzabili per chi li ha comprati.
-- ------------------------------------------------------------
update public.cambi_ruolo cr
set team_id = pi.team_id
from public.player_instances pi
where pi.id = cr.player_instance_id
  and cr.completato_il is null
  and pi.team_id is not null
  and pi.team_id is distinct from cr.team_id;

update public.specializzazioni_giocatore sg
set team_id = pi.team_id
from public.player_instances pi
where pi.id = sg.player_instance_id
  and sg.completato_il is null
  and pi.team_id is not null
  and pi.team_id is distinct from sg.team_id;

-- Training di giocatori ormai senza squadra: stessa regola del trigger.
delete from public.cambi_ruolo cr
using public.player_instances pi
where pi.id = cr.player_instance_id and cr.completato_il is null and pi.team_id is null;

delete from public.specializzazioni_giocatore sg
using public.player_instances pi
where pi.id = sg.player_instance_id and sg.completato_il is null and pi.team_id is null;
