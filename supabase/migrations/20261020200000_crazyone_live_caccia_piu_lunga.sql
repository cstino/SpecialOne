-- CrazyOne live: la fase finale della Caccia allo Stemma dura 7 s invece di 5 (il risultato restava a schermo solo ~2,6 s).
CREATE OR REPLACE FUNCTION private.ctl_giro(p_league_id bigint)
 RETURNS casino_ctl_giri
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  g public.casino_ctl_giri;
  v_ora timestamptz := clock_timestamp();
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  c_top_pesi constant numeric[] := array[98,102,59,42,96,85,94,97, 327];
  v_x int; v_b int; v_slot int; v_top text; v_molt int; v_sp int; v_esito text; v_bonus jsonb;
  v_tavola int[]; v_pos int[]; v_lanci jsonb := '[]'::jsonb; v_mm int; v_ruota int[]; v_rot int[]; i int; v_gmax int := 1;
  v_chiude timestamptz; v_esito_il timestamptz; v_scelta timestamptz; v_fine timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('crazyone:' || p_league_id));
  select * into g from public.casino_ctl_giri where league_id = p_league_id order by id desc limit 1;
  if g.id is not null and v_ora < g.fine_il then return g; end if;

  v_x := private.ct_pesca(array[1,2,3,4,5,6,7,8,9], c_top_pesi);
  v_top := case when v_x <= 8 then c_caselle[v_x] end;
  v_molt := private.ct_pesca(array[2,3,5,10,15,25,50], array[35,25,18,12,5,3,2]);
  v_sp := floor(random() * 54)::int;
  v_esito := (private.ct_ruota())[v_sp + 1];
  v_chiude := v_ora + interval '15 seconds';
  v_esito_il := v_chiude + interval '8.5 seconds';

  if v_esito in ('1', '2', '5', '10') then
    v_fine := v_esito_il + interval '4 seconds';
  elsif v_esito = 'cf' then
    v_x := private.ct_val_cf(); v_b := private.ct_val_cf();
    v_slot := case when random() < 0.5 then 0 else 1 end;
    v_bonus := jsonb_build_object('rosso', v_x, 'blu', v_b, 'lato', case v_slot when 0 then 'rosso' else 'blu' end, 'valore', case v_slot when 0 then v_x else v_b end);
    v_fine := v_esito_il + interval '10 seconds';
  elsif v_esito = 'pa' then
    v_tavola := array(select private.ct_val_pa() from generate_series(1, 16));
    v_pos := array(select x from generate_series(1, 16) x order by random() limit 2);
    v_tavola[v_pos[1]] := -2; v_tavola[v_pos[2]] := -2;
    v_mm := 1; v_b := null;
    for i in 1..4 loop
      v_slot := floor(random() * 16)::int;
      v_lanci := v_lanci || to_jsonb(v_slot);
      if v_tavola[v_slot + 1] = -2 then v_mm := v_mm * 2;
      else v_b := least(v_tavola[v_slot + 1] * v_mm, 1000); exit; end if;
    end loop;
    if v_b is null then v_b := least(100 * v_mm, 1000); end if;
    v_bonus := jsonb_build_object('tavola', to_jsonb(v_tavola), 'lanci', v_lanci, 'valore', v_b);
    v_fine := v_esito_il + make_interval(secs => 6 + jsonb_array_length(v_lanci) * 3.6);
  elsif v_esito = 'ch' then
    v_bonus := jsonb_build_object('tavola', to_jsonb(array(select private.ct_val_ch() from generate_series(1, 108))));
    v_scelta := v_esito_il + interval '16.5 seconds';
    v_fine := v_scelta + interval '7 seconds';   -- 20/10/2026: +2 s per lasciare a schermo il risultato
  else
    v_ruota := array(select private.ct_val_ct() from generate_series(1, 64));
    v_pos := array(select x from generate_series(1, 64) x order by random() limit 10);
    for i in 1..8 loop v_ruota[v_pos[i]] := -2; end loop;
    v_ruota[v_pos[9]] := -3; v_ruota[v_pos[10]] := -3;
    v_rot := array(select floor(random() * 64)::int from generate_series(1, 6));
    for i in 0..2 loop v_gmax := greatest(v_gmax, (private.ct_cammino_crazy(v_ruota, v_rot, i) ->> 'giri')::int); end loop;
    v_bonus := jsonb_build_object('ruota', to_jsonb(v_ruota), 'rotazioni', to_jsonb(v_rot), 'giri_max', v_gmax);
    v_scelta := v_esito_il + interval '12 seconds';
    v_fine := v_scelta + make_interval(secs => 1 + v_gmax * 9 + 4);
  end if;

  insert into public.casino_ctl_giri (league_id, apre_il, chiude_il, esito_il, scelta_fine_il, fine_il, top_casella, top_molt, spicchio, esito, bonus)
  values (p_league_id, v_ora, v_chiude, v_esito_il, v_scelta, v_fine, v_top, v_molt, v_sp, v_esito, v_bonus)
  returning * into g;
  return g;
end $function$;
