-- Moduli 4-5-1 e 4-4-1-1 (richiesta del committente, 8/11/2026): due esterni, due mezzali e un mediano
-- davanti alla difesa; all'occorrenza il mediano sale a trequartista e il modulo diventa 4-4-1-1. Stessi indici
-- di slot (il 7 e' CDM nel primo e CAM nel secondo), come 4-3-3 e le sue varianti: passando dall'uno all'altro i
-- titolari restano al loro posto. Stessi slot di engine/config.js (MODULI).

CREATE OR REPLACE FUNCTION private.moduli_validi()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select array[
    '4-3-3','4-3-3 offensivo','4-3-3 difensivo',
    '4-4-2','4-2-3-1','3-5-2','3-4-3','5-3-2','4-2-4',
    '4-5-1','4-4-1-1'
  ]::text[];
$function$

;
CREATE OR REPLACE FUNCTION private.disposizione_standard(p_modulo text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select case p_modulo
    when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']::text[]
    when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']::text[]
    when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']::text[]
    when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']::text[]
    when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']::text[]
    when '3-5-2' then array['GK','CB','CB','CB','LM','CM','CDM','CM','RM','ST','ST']::text[]
    when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']::text[]
    when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']::text[]
    when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']::text[]
    when '4-5-1' then array['GK','LB','CB','CB','RB','LM','CM','CDM','CM','RM','ST']::text[]
    when '4-4-1-1' then array['GK','LB','CB','CB','RB','LM','CM','CAM','CM','RM','ST']::text[]
    else null::text[]
  end
$function$

;
