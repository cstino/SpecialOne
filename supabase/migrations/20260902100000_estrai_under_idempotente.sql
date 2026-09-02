-- ============================================================
--  ESTRAZIONE UNDER DUPLICATA: 24 PROSPETTI INVECE DI 8.
--
--  Segnalato dall'utente su Serie F: 3 "tornate" da 8 nello stesso giorno
--  invece di una sola. Causa: 20260901130000_fix_orario_cron_mercato_under.sql
--  aveva messo il cron ogni 5 minuti ('*/5 * * * *') per intercettare la
--  finestra 23:30-23:45 di private.estrai_under() a prescindere dall'ora
--  legale — ma quella finestra e' larga 15 minuti, quindi CI CADONO DENTRO
--  3 tick del cron (23:30, 23:35, 23:40), e private.estrai_under_lega()
--  non aveva nessun controllo "ho gia' estratto oggi per questa lega":
--  ogni tick creava una tornata nuova da zero.
--
--  estrai_svincolati() ha la stessa finestra di tempo ma non lo stesso
--  problema per puro caso di allineamento (il suo cron e' ogni 15 minuti,
--  '2,17,32,47 * * * *': un solo tick ricade nella finestra). E' un
--  allineamento fragile, non una vera protezione — qui si sceglie la
--  protezione vera invece di ricalcolare un altro orario magico.
--
--  Fix: private.estrai_under_lega ora controlla se esiste gia' ALMENO UNA
--  riga per (league_id, giorno) prima di procedere, e si ferma se si —
--  indipendente da quante volte il cron la richiama nella finestra.
--
--  Nessun dato da correggere a ritroso: le aste doppie gia' create per
--  Serie F (2 settembre) hanno gia' ricevuto offerte vere da giocatori
--  veri (tornata 1 e 3) — cancellarle butterebbe via un'azione reale.
--  Restano semplicemente piu' prospetti del solito per quel giorno,
--  innocuo, e si risolvono normalmente stasera.
-- ============================================================

create or replace function private.estrai_under_lega(p_league_id bigint, p_giorno date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tornata integer;
  v_ruolo text;
  v_i integer;
  v_player_id bigint;
  v_creati integer := 0;
  v_liberato record;
begin
  if exists (select 1 from public.under_auctions where league_id = p_league_id and giorno = p_giorno) then
    return 0;
  end if;

  v_tornata := 1;

  foreach v_ruolo in array array['GK','DEF','MID','ATT'] loop
    for v_i in 1..private.under_per_ruolo() loop
      v_player_id := private.genera_prospetto_vivaio(v_ruolo, p_league_id);
      insert into public.under_auctions (league_id, player_id, giorno, tornata)
      values (p_league_id, v_player_id, p_giorno, v_tornata);
      v_creati := v_creati + 1;
    end loop;
  end loop;

  for v_liberato in
    select player_id from private.rilasci_vivaio_in_coda where league_id = p_league_id
  loop
    insert into public.under_auctions (league_id, player_id, giorno, tornata)
    values (p_league_id, v_liberato.player_id, p_giorno, v_tornata)
    on conflict (league_id, giorno, player_id) do nothing;
    delete from private.rilasci_vivaio_in_coda
    where league_id = p_league_id and player_id = v_liberato.player_id;
    v_creati := v_creati + 1;
  end loop;

  return v_creati;
end;
$$;
