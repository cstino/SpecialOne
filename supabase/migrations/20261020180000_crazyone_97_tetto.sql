-- CrazyOne: pesi della top slot sui bonus corretti per il tetto di 2500× (Mischia 78->85, Caccia 91->94, CrazyOne 82->97).
CREATE OR REPLACE FUNCTION public.casino_ct_gira(p_league_id bigint, p_puntate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  -- Top slot: su quale casella si accende (per mille, il resto = nessuna) e con che moltiplicatore.
  -- 20/10/2026: ricalcolati per il 97% di ritorno su ogni casella (prima 83,90,50,34,86,69,82,73,433 = 94%),
  -- tenendo conto del tetto di 2500× sulle vincite dei bonus (calcolo esatto su 400.000 bonus simulati per tipo).
  c_top_pesi constant numeric[] := array[98,102,59,42,96,85,94,97, 327];
  v_puntate jsonb := '{}'::jsonb;
  v_k text; v_p int; v_tot int := 0;
  v_top text; v_molt int; v_sp int; v_esito text; v_m int;
  v_vinto bigint := 0; v_bonus jsonb; v_attesa boolean := false; v_b int;
  v_tavola int[]; v_slot int; v_lanci jsonb := '[]'::jsonb; v_x int; i int; v_mm int;
  v_ruota int[]; v_rot int[]; v_pos int[];
  v_risultato jsonb;
  g public.casino_ct_giri;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.casino_crazyone) then
    raise exception using errcode = '55000', message = 'CrazyOne non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  if exists (select 1 from public.casino_ct_giri where league_id = p_league_id and user_id = v_utente and in_attesa) then
    raise exception using errcode = '55000', message = 'Hai un bonus da giocare: finiscilo prima di girare di nuovo.';
  end if;

  -- Puntate: multipli di 10, al massimo 500 per casella e 2.000 in tutto.
  for v_k, v_p in select key, (value #>> '{}')::int from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    if not (v_k = any(c_caselle)) or v_p < 0 or v_p % 10 <> 0 or v_p > 500 then
      raise exception using errcode = '22023', message = 'Puntata non valida.';
    end if;
    if v_p > 0 then v_puntate := v_puntate || jsonb_build_object(v_k, v_p); v_tot := v_tot + v_p; end if;
  end loop;
  if v_tot = 0 then raise exception using errcode = '22023', message = 'Metti almeno una fiche.'; end if;
  if v_tot > 2000 then raise exception using errcode = '22023', message = 'Al massimo 2.000 crediti a giro.'; end if;
  if v.crediti < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;

  -- Top slot e ruota.
  v_x := private.ct_pesca(array[1,2,3,4,5,6,7,8,9], c_top_pesi);
  v_top := case when v_x <= 8 then c_caselle[v_x] end;
  v_molt := private.ct_pesca(array[2,3,5,10,15,25,50], array[35,25,18,12,5,3,2]);
  v_sp := floor(random() * 54)::int;
  v_esito := (private.ct_ruota())[v_sp + 1];
  v_m := case when v_top = v_esito then v_molt else 1 end;
  v_p := coalesce((v_puntate ->> v_esito)::int, 0);

  if v_esito in ('1', '2', '5', '10') then
    if v_p > 0 then v_vinto := v_p::bigint * v_esito::int * v_m + v_p; end if;
  elsif v_esito = 'cf' then
    v_x := private.ct_val_cf(); v_b := private.ct_val_cf();
    v_slot := case when random() < 0.5 then 0 else 1 end;   -- 0 rosso, 1 blu
    v_bonus := jsonb_build_object('rosso', v_x, 'blu', v_b, 'lato', case v_slot when 0 then 'rosso' else 'blu' end,
                                  'valore', case v_slot when 0 then v_x else v_b end);
    if v_p > 0 then v_vinto := v_p::bigint * least((v_bonus ->> 'valore')::int * v_m, 2500) + v_p; end if;
  elsif v_esito = 'pa' then
    -- Pachinko: 16 buche, 2 DOUBLE (raddoppiano tutta la tavola e si rilancia), al massimo 4 lanci.
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
    if v_p > 0 then v_vinto := v_p::bigint * least(v_b * v_m, 2500) + v_p; end if;
  elsif v_esito = 'ch' then
    v_bonus := jsonb_build_object('tavola', to_jsonb(array(select private.ct_val_ch() from generate_series(1, 108))));
    v_attesa := v_p > 0;
  else
    -- Crazy Time: 64 spicchi, 8 DOUBLE e 2 TRIPLE; rotazioni gia' estratte (la bandierina la sceglie il giocatore).
    v_ruota := array(select private.ct_val_ct() from generate_series(1, 64));
    v_pos := array(select x from generate_series(1, 64) x order by random() limit 10);
    for i in 1..8 loop v_ruota[v_pos[i]] := -2; end loop;
    v_ruota[v_pos[9]] := -3; v_ruota[v_pos[10]] := -3;
    v_rot := array(select floor(random() * 64)::int from generate_series(1, 6));
    v_bonus := jsonb_build_object('ruota', to_jsonb(v_ruota), 'rotazioni', to_jsonb(v_rot));
    v_attesa := v_p > 0;
  end if;

  update public.casino_saldi set crediti = crediti - v_tot + v_vinto, giri = giri + 1,
         max_vincita = greatest(max_vincita, v_vinto), totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente returning * into v;
  insert into public.casino_ct_giri (league_id, user_id, team_id, puntate, totale, top_casella, top_molt, spicchio, esito, bonus, in_attesa, vinto, concluso_il)
  values (p_league_id, v_utente, v.team_id, v_puntate, v_tot, v_top, v_molt, v_sp, v_esito, v_bonus, v_attesa, v_vinto,
          case when v_attesa then null else now() end)
  returning * into g;
  if not v_attesa and v_vinto > 0 then v := private.ct_chiudi(g.id, 0); end if;

  v_risultato := jsonb_build_object('id', g.id, 'spicchio', v_sp, 'esito', v_esito, 'top_casella', v_top, 'top_molt', v_molt,
    'puntate', v_puntate, 'totale', v_tot, 'vinto', v_vinto, 'crediti', v.crediti, 'max_vincita', v.max_vincita);
  if v_attesa then
    v_risultato := v_risultato || jsonb_build_object('attesa', private.ct_attesa_pubblica(g));
  elsif v_esito in ('cf', 'pa') then
    v_risultato := v_risultato || jsonb_build_object('bonus', v_bonus);
  end if;
  return v_risultato;
end $function$;
