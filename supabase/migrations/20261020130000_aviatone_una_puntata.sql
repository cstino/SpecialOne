-- AviatOne: una sola puntata per volo (tolta la seconda puntata).
CREATE OR REPLACE FUNCTION public.casino_av_parti(p_league_id bigint, p_puntate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; f public.casino_av_voli;
  e jsonb; v_p int; v_a numeric; v_tot int := 0; v_lista jsonb := '[]'::jsonb;
begin
  perform private.av_attivo(p_league_id);
  v := private.casino_saldo(p_league_id, v_utente);
  select * into f from public.casino_av_voli where league_id = p_league_id and user_id = v_utente and not finito;
  if f.id is not null then
    f := private.av_aggiorna(f.id);
    if not f.finito then raise exception using errcode = '55000', message = 'L''aereo è ancora in volo.'; end if;
  end if;
  -- Una sola puntata (20/10/2026: tolta la seconda).
  if jsonb_typeof(p_puntate) <> 'array' or jsonb_array_length(p_puntate) <> 1 then
    raise exception using errcode = '22023', message = 'Una puntata per volo.';
  end if;
  for e in select x from jsonb_array_elements(p_puntate) x loop
    v_p := (e ->> 'puntata')::int;
    v_a := nullif(e ->> 'auto', '')::numeric;
    if v_p is null or v_p < 10 or v_p > 500 or v_p % 10 <> 0 then raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).'; end if;
    if v_a is not null and (v_a < 1.1 or v_a > 1000) then raise exception using errcode = '22023', message = 'Incasso automatico non valido (da 1,10× a 1000×).'; end if;
    v_tot := v_tot + v_p;
    v_lista := v_lista || jsonb_build_object('puntata', v_p, 'auto', round(v_a, 2), 'incassato', null);
  end loop;
  if v.crediti < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;

  update public.casino_saldi set crediti = crediti - v_tot, giri = giri + 1, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente returning * into v;
  insert into public.casino_av_voli (league_id, user_id, team_id, puntate, totale, crash)
  values (p_league_id, v_utente, v.team_id, v_lista, v_tot, private.av_crash()) returning * into f;
  return private.av_pubblico(f) || jsonb_build_object('crediti', v.crediti);
end $function$;
