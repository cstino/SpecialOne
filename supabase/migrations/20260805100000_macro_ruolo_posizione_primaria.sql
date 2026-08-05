-- ============================================================
--  FIX: private.macro_ruolo guardava se una QUALSIASI posizione del
--  giocatore ricadeva in un reparto (con priorita' fissa DEF > MID > ATT),
--  non la posizione PRIMARIA.
--
--  Segnalato dall'utente su un caso reale: T. Le Bris ha posizioni
--  ['LM','RM','LB'] (centrocampista di fascia, adattabile a terzino) ma
--  finiva sempre tra i difensori, perche' 'LB' e' presente da qualche
--  parte nell'array e il vecchio controllo (`&&`, overlap non ordinato)
--  non guardava quale delle tre fosse quella vera.
--
--  Nel dataset FC 26 l'ordine di `player_positions` NON e' arbitrario: la
--  prima voce e' sempre la posizione primaria di EA, le altre sono
--  alternative (tools/importazione/normalizza.py preserva l'ordine cosi'
--  com'e', non lo riordina mai). La funzione ora guarda solo
--  `p_posizioni[1]` invece di fare l'overlap su tutto l'array.
--
--  Stessa firma, stesso nome: la sostituzione vale per tutti i chiamanti
--  gia' esistenti senza toccarli (pesca_carta_ruolo per i pacchetti del
--  draft, estrazione svincolati stagionale/off-season/pool elite,
--  club_estratto in draft_picks). Le righe gia' scritte in draft_picks
--  restano com'erano (e' solo un campo di log, la posizione vera resta
--  in players.posizioni): il fix vale in avanti, non e' retroattivo.
-- ============================================================

create or replace function private.macro_ruolo(p_posizioni text[])
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_posizioni[1] = 'GK' then 'GK'
    when p_posizioni[1] in ('CB','LB','RB','LWB','RWB') then 'DEF'
    when p_posizioni[1] in ('CDM','CM','CAM','LM','RM') then 'MID'
    when p_posizioni[1] in ('ST','CF','LW','RW') then 'ATT'
    else 'MID'
  end;
$$;
