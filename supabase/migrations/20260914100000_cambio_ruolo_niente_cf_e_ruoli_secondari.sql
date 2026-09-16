-- ============================================================
--  CAMBIO RUOLO: via il CF dai bersagli, dentro i ruoli secondari
--
--  Due segnalazioni del 14 settembre 2026, stessa schermata.
--
--  1. IL CF ERA UN VICOLO CIECO.
--     Un attaccante poteva allenarsi per diventare CF, ma NESSUN modulo del
--     gioco schiera un CF: gli slot esistenti sono GK CB LB RB LWB RWB CDM CM
--     CAM LM RM LW RW ST. Chi completava quel training si ritrovava un ruolo
--     primario impossibile da coprire, e da li' in poi giocava sempre fuori
--     ruolo — 0.91 invece di 1.00 in penalitaRuolo. Un allenamento che
--     peggiorava il giocatore.
--
--     Il CF sparisce quindi dai bersagli sia dello ST (sostituito da CAM, come
--     chiesto) sia del CAM (sostituito da ST). Resta invece il ramo che PARTE
--     dal CF: un giocatore nativamente CF esiste davvero nel catalogo — uno su
--     1154 tesserati — e quel ramo e' la sua unica via d'uscita.
--
--  2. I RUOLI SECONDARI NON ERANO RAGGIUNGIBILI.
--     La tabella guardava solo il ruolo primario e restituiva una lista fissa
--     di ruoli vicini. Un LM che ha RM fra i secondari non poteva promuoverlo,
--     perche' RM non e' nella lista dei vicini di LM.
--
--     Non e' un dettaglio estetico: penalitaRuolo da' 1.00 al ruolo primario e
--     0.98 a uno secondario. Promuovere un secondario che il giocatore sa gia'
--     fare e' un guadagno reale, ed e' anche il cambio di ruolo piu' sensato
--     che esista — si allena per specializzarsi in qualcosa che gia' conosce.
--
--     Ora i bersagli sono l'unione dei ruoli vicini e dei propri secondari. I
--     vicini restano in testa, i secondari seguono.
-- ============================================================

create or replace function private.ruoli_target_cambio(p_posizioni_attuali text[])
returns text[]
language sql
immutable
security invoker
set search_path = ''
as $$
  with vicini as (
    select case p_posizioni_attuali[1]
      when 'CB'  then array['LB', 'RB', 'CDM']
      when 'LB'  then array['CB', 'LWB', 'LM']
      when 'RB'  then array['CB', 'RWB', 'RM']
      when 'LWB' then array['LB', 'LM', 'LW']
      when 'RWB' then array['RB', 'RM', 'RW']
      when 'CDM' then array['CB', 'CM']
      when 'CM'  then array['CDM', 'CAM', 'LM', 'RM']
      when 'CAM' then array['CM', 'ST', 'LW', 'RW']
      when 'LM'  then array['LB', 'LWB', 'LW', 'CM']
      when 'RM'  then array['RB', 'RWB', 'RW', 'CM']
      when 'LW'  then array['LWB', 'LM', 'CAM', 'ST']
      when 'RW'  then array['RWB', 'RM', 'CAM', 'ST']
      when 'ST'  then array['CAM', 'LW', 'RW']
      -- Nessun modulo schiera un CF, quindi il CF non e' mai un bersaglio.
      -- Ma un giocatore nativamente CF esiste, e da qui deve poter uscire.
      when 'CF'  then array['CAM', 'ST']
      else array[]::text[]
    end as elenco
  ), candidati as (
    -- fonte 1 = ruoli vicini. "with ordinality" conserva l'ordine in cui sono
    -- scritti qui sopra, che va dal piu' vicino al piu' lontano: ordinarli
    -- alfabeticamente butterebbe via quell'informazione.
    select v.ruolo, 1 as fonte, v.ord
    from vicini, unnest(vicini.elenco) with ordinality as v(ruolo, ord)
    union all
    -- fonte 2 = i propri ruoli secondari, cioe' quelli che il giocatore sa
    -- gia' fare e che qui puo' promuovere a primario. Seguono i vicini.
    select s.ruolo, 2, s.ord
    from unnest(p_posizioni_attuali[2:coalesce(array_length(p_posizioni_attuali, 1), 1)])
      with ordinality as s(ruolo, ord)
  )
  -- distinct on e non un group by con min(): un ruolo che compare in
  -- entrambe le sorgenti deve tenere la posizione che ha nella PRIMA, non un
  -- minimo preso a cavallo delle due (che mescolava due ordinamenti diversi e
  -- rovesciava l'elenco del CF nativo).
  select coalesce(array_agg(ruolo order by fonte, ord), '{}'::text[])
  from (
    select distinct on (ruolo) ruolo, fonte, ord
    from candidati
    where ruolo is not null
      and ruolo <> p_posizioni_attuali[1]  -- non ha senso "cambiare" nel proprio
      and ruolo <> 'CF'                    -- nessun modulo lo schiera
      and ruolo <> 'GK'                    -- il cambio ruolo non porta in porta
    order by ruolo, fonte, ord
  ) distinti
$$;
