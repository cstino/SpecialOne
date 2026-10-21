-- Schedina BetOne: le doppie sono gratis (decisione del committente): il moltiplicatore dipende solo dagli errori.
CREATE OR REPLACE FUNCTION private.betone_moltiplicatore(p_partite integer, p_errori integer, p_doppie integer)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select round((case p_errori
      when 0 then 20 * power(1.6, greatest(0, p_partite - 6))
      when 1 then 4 * power(1.4, greatest(0, p_partite - 6))
      when 2 then 1.5 * power(1.2, greatest(0, p_partite - 6))
      when 3 then case when p_partite >= 8 then 1 else 0 end
      else 0 end), 2)   -- 21/10/2026: le doppie sono gratis, non dimezzano piu' il moltiplicatore (p_doppie resta per compatibilita')
$function$;
