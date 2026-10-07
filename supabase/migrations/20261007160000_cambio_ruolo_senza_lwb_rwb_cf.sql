-- LWB, RWB e CF non esistono piu' nel gioco (rimozione del 2 settembre 2026): la migrazione
-- 20260914100000 li aveva fatti rientrare come bersagli del cambio ruolo. Restano solo come punto
-- di partenza per chi li ha come ruolo primario, perche' da li' deve poter uscire.
create or replace function private.ruoli_target_cambio(p_posizioni_attuali text[])
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with vicini as (
    select case p_posizioni_attuali[1]
      when 'CB'  then array['LB', 'RB', 'CDM']
      when 'LB'  then array['CB', 'LM']
      when 'RB'  then array['CB', 'RM']
      when 'LWB' then array['LB', 'LM', 'LW']
      when 'RWB' then array['RB', 'RM', 'RW']
      when 'CDM' then array['CB', 'CM']
      when 'CM'  then array['CDM', 'CAM', 'LM', 'RM']
      when 'CAM' then array['CM', 'ST', 'LW', 'RW']
      when 'LM'  then array['LB', 'LW', 'CM']
      when 'RM'  then array['RB', 'RW', 'CM']
      when 'LW'  then array['LM', 'CAM', 'ST']
      when 'RW'  then array['RM', 'CAM', 'ST']
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
      and ruolo not in ('CF', 'LWB', 'RWB')  -- nessun modulo li schiera: non sono bersagli
      and ruolo <> 'GK'                    -- il cambio ruolo non porta in porta
    order by ruolo, fonte, ord
  ) distinti
$function$
;
