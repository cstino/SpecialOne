-- Pool degli eleggibili al draft delle scelte con 28 squadre (Serie F dalla Season 3, decisione del committente
-- 7/11/2026): 35 giocatori, 8 portieri + 9 difensori + 9 centrocampisti + 9 attaccanti. Con la formula di prima
-- sarebbero stati 34 (7 portieri). Sotto le 28 squadre non cambia niente (24 squadre: 6 + 8×3 = 30). Il pool della
-- finestra 'off' in corso e' gia' estratto (30) e resta com'e'.
create or replace function private.eleggibili_portieri(p_squadre integer)
 returns integer
 language sql
 immutable
 set search_path to ''
as $function$
  select case when p_squadre >= 28 then 8 else greatest(5, ceil(p_squadre / 4.0)::integer) end
$function$;
