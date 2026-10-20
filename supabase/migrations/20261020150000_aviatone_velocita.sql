-- AviatOne: moltiplicatore piu' veloce, vicino a quello dell'Aviator vero (m = e^(0,13·t): 2× a ~5 s, 10× a ~18 s, 100× a ~35 s).
CREATE OR REPLACE FUNCTION private.av_molt(p_secondi numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select least(floor(exp(0.13 * greatest(p_secondi, 0)) * 100) / 100, 1000)::numeric(8,2)
$function$

;
CREATE OR REPLACE FUNCTION private.av_giro(p_league_id bigint)
 RETURNS casino_av_giri
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g public.casino_av_giri; v_ora timestamptz := clock_timestamp(); v_crash numeric;
begin
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));
  select * into g from public.casino_av_giri where league_id = p_league_id order by id desc limit 1;
  if g.id is null or v_ora > g.finisce_il + interval '3 seconds' then
    v_crash := private.av_crash();
    insert into public.casino_av_giri (league_id, apre_il, parte_il, crash, finisce_il)
    values (p_league_id, v_ora, v_ora + interval '7 seconds', v_crash,
            v_ora + interval '7 seconds' + make_interval(secs => ln(v_crash) / 0.13))
    returning * into g;
  end if;
  return g;
end $function$

;
