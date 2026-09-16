-- ============================================================
--  UNA POSIZIONE CAMBIA DENTRO LA PROPRIA LINEA
--
--  La regola precedente diceva "sale o scende di una linea restando sulla
--  propria corsia", ed era sbagliata. Segnalata dall'utente con l'esempio
--  giusto: consentiva a una punta di scendere a CAM, e a quel punto un 4-4-2
--  non e' piu' un 4-4-2 ma un 4-4-1-1 — un modulo diverso, con una familiarita'
--  diversa e un nome che non corrisponde piu' a niente.
--
--  Il modulo lo sceglie l'utente; lo schema personalizzato lo dettaglia, non lo
--  sostituisce. Quindi una posizione puo' stringersi al centro, allargarsi,
--  alzarsi o abbassarsi, ma resta nella sua linea: in un 4-4-2 i due CM possono
--  diventare CDM perche' i centrocampisti restano quattro.
--
--  Le linee sono quelle di REPARTO in engine/config.js, cosi' "stessa linea"
--  vuol dire la stessa cosa nel motore, nell'interfaccia e qui.
--
--  Tavola generata da engine/config.js (SPOSTAMENTI_SLOT).
-- ============================================================

create or replace function private.spostamenti_slot(p_slot text)
returns text[] language sql immutable parallel safe set search_path = ''
as $FN$
  select case p_slot
    when 'CB' then array['CB','LB','RB']::text[]
    when 'LB' then array['LB','LWB','CB']::text[]
    when 'RB' then array['RB','RWB','CB']::text[]
    when 'LWB' then array['LWB','LB']::text[]
    when 'RWB' then array['RWB','RB']::text[]
    when 'CDM' then array['CDM','CM']::text[]
    when 'CM' then array['CM','CDM','CAM','LM','RM']::text[]
    when 'CAM' then array['CAM','CM']::text[]
    when 'LM' then array['LM','CM']::text[]
    when 'RM' then array['RM','CM']::text[]
    when 'LW' then array['LW','ST']::text[]
    when 'RW' then array['RW','ST']::text[]
    when 'ST' then array['ST','LW','RW']::text[]
    when 'GK' then array['GK']::text[]
    else array[p_slot]::text[]
  end
$FN$;
