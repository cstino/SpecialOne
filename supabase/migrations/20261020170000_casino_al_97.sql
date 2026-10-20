-- BetOne Casino': tutti i giochi portati al 97% di ritorno medio (come l'Aviator vero), prima 94%.
-- AviatOne: costante del crash 0,946 -> 0,976. CrazyOne: pesi della top slot. SlotOne: vincite x1,033 (album) / x1,024.
CREATE OR REPLACE FUNCTION private.av_crash()
 RETURNS numeric
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select least(greatest(floor(0.976 / (1 - random()) * 100) / 100, 1), 1000)::numeric(8,2)
$function$;

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
  -- 20/10/2026: ricalcolati per il 97% di ritorno su ogni casella (prima 83,90,50,34,86,69,82,73,433 = 94%).
  c_top_pesi constant numeric[] := array[98,102,59,42,96,78,91,82, 352];
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

CREATE OR REPLACE FUNCTION public.casino_gira(p_league_id bigint, p_puntata integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  -- simboli 0-7 stemmi, 8 jolly, 9 coppa, 10 bustina (solo dove l'album e' attivo). Pesi in decimi.
  c_pesi_album constant int[] := array[90,90,90,70,70,70,40,40,30,20,22];
  c_pesi_base constant int[] := array[90,90,90,70,70,70,40,40,30,20,0];
  c_pesi int[];
  v_album boolean;
  c_scala numeric;   -- 20/10/2026: porta il ritorno dal 94% al 97% senza toccare la tabella dei pesi
  v_bustine int := 0;
  v_bustine_vinte int := 0;
  c_linee constant int[] := array[
    1,1,1,1,1, 0,0,0,0,0, 2,2,2,2,2, 0,1,2,1,0, 2,1,0,1,2,
    0,0,1,2,2, 2,2,1,0,0, 1,0,0,0,1, 1,2,2,2,1, 0,1,1,1,0];
  v_gratis boolean;
  v_puntata integer;
  v_molt integer;
  g int[];            -- griglia 5 rulli x 3 righe, indice (rullo*3 + riga) + 1
  v_r int; v_k int; v_x int; v_cum int; v_tot int;
  v_linea int; v_sim int; v_target int; v_n int; v_paga int; v_vinto_linee numeric := 0;
  v_vinte jsonb := '[]'::jsonb;
  v_coppe int := 0; v_nuovi_gratis int := 0; v_scatter numeric := 0;
  v_vinto bigint;
  v_giro_id bigint;
  v_nome_team text;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  v_gratis := v.giri_gratis > 0;
  if v_gratis then
    v_puntata := v.puntata_gratis; v_molt := 2;
  else
    if p_puntata not in (10, 20, 50, 100) then raise exception using errcode = '22023', message = 'Puntata non valida.'; end if;
    if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
    v_puntata := p_puntata; v_molt := 1;
  end if;

  -- Dove c'e' l'album esce anche la bustina (circa 1 giro su 70) e gli stemmi pagano un po' di piu' per compensare:
  -- il ritorno medio resta lo stesso.
  v_album := private.album_attivo(p_league_id);
  c_pesi := case when v_album then c_pesi_album else c_pesi_base end;
  c_scala := case when v_album then 1.033 else 1.024 end;
  v_tot := (select sum(x) from unnest(c_pesi) x);

  -- Estrazione: ogni casella pescata secondo i pesi (lo fa il server).
  g := array_fill(0, array[15]);
  for v_k in 1..15 loop
    v_x := floor(random() * v_tot)::int; v_cum := 0;
    for v_r in 1..11 loop
      v_cum := v_cum + c_pesi[v_r];
      if v_x < v_cum then g[v_k] := v_r - 1; exit; end if;
    end loop;
    if g[v_k] = 9 then v_coppe := v_coppe + 1; end if;
    if g[v_k] = 10 then v_bustine := v_bustine + 1; end if;
  end loop;

  -- Linee: da sinistra, simboli uguali (il jolly sostituisce gli stemmi, non la coppa). 5 jolly = jackpot.
  for v_linea in 0..9 loop
    v_target := null; v_n := 0; v_paga := 0;
    for v_r in 0..4 loop
      v_sim := g[v_r * 3 + c_linee[v_linea * 5 + v_r + 1] + 1];
      if v_sim >= 9 then exit; end if;
      if v_target is null and v_sim <> 8 then v_target := v_sim; end if;
      if v_sim = 8 or v_sim = v_target then v_n := v_n + 1; else exit; end if;
    end loop;
    if v_target is null and v_n = 5 then v_paga := 400; v_target := 8;
    elsif v_n >= 3 and v_target is not null then
      v_paga := case when v_album then
                       case when v_target <= 2 then (array[9,29,110])[v_n - 2]
                            when v_target <= 5 then (array[16,56,222])[v_n - 2]
                            else (array[29,136,550])[v_n - 2] end
                     else
                       case when v_target <= 2 then (array[8,26,100])[v_n - 2]
                            when v_target <= 5 then (array[14,52,200])[v_n - 2]
                            else (array[26,125,500])[v_n - 2] end end;
    end if;
    if v_paga > 0 then
      v_vinto_linee := v_vinto_linee + round(v_paga * v_puntata / 10.0 * v_molt * c_scala);
      v_vinte := v_vinte || jsonb_build_object('linea', v_linea, 'simbolo', v_target, 'n', v_n, 'vinto', round(v_paga * v_puntata / 10.0 * v_molt * c_scala));
    end if;
  end loop;

  -- Coppe ovunque: 3 = 2x la puntata e 8 giri gratis, 4 = 5x e 12, 5+ = 20x e 20 (vincite doppie nei giri gratis).
  if v_coppe >= 3 then
    v_scatter := round((case least(v_coppe, 5) when 3 then 2 when 4 then 5 else 20 end) * v_puntata * v_molt * c_scala);
    v_nuovi_gratis := case least(v_coppe, 5) when 3 then 8 when 4 then 12 else 20 end;
  end if;
  v_vinto := v_vinto_linee + v_scatter;   -- v_vinto_linee e' gia' in crediti
  -- Bustine ovunque: 3 = 1 bustina gratis per l'album, 4 = 2, 5 o piu' = 3.
  if v_bustine >= 3 then v_bustine_vinte := least(v_bustine, 5) - 2; end if;

  update public.casino_saldi set
    crediti = crediti - (case when v_gratis then 0 else v_puntata end) + v_vinto,
    giri_gratis = greatest(0, giri_gratis - (case when v_gratis then 1 else 0 end)) + v_nuovi_gratis,
    puntata_gratis = case when v_nuovi_gratis > 0 then v_puntata when giri_gratis - (case when v_gratis then 1 else 0 end) <= 0 then null else puntata_gratis end,
    bustine_gratis = bustine_gratis + v_bustine_vinte,
    giri = giri + 1, max_vincita = greatest(max_vincita, v_vinto), totale_vinto = totale_vinto + v_vinto, aggiornato_il = now()
  where league_id = p_league_id and user_id = v_utente
  returning * into v;

  insert into public.casino_giri (league_id, user_id, team_id, puntata, gratis, vinto, griglia)
  values (p_league_id, v_utente, v.team_id, v_puntata, v_gratis, v_vinto, to_jsonb(g)) returning id into v_giro_id;

  -- Il colpo grosso (almeno 100 volte la puntata) finisce su SocialOne.
  if v_vinto >= 100 * v_puntata then
    select nome into v_nome_team from public.teams where id = v.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (p_league_id, 'casino:' || v_giro_id, 'lega', 'BetOne Casinò', v.team_id,
            '🎰 COLPO GROSSO al casinò! ' || v_nome_team || ' vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti con un solo giro 🤑', now())
    on conflict do nothing;
  end if;

  return jsonb_build_object('griglia', to_jsonb(g), 'vincite', v_vinte, 'coppe', v_coppe, 'scatter', v_scatter, 'vinto', v_vinto,
    'gratis', v_gratis, 'molt', v_molt, 'puntata', v_puntata, 'nuovi_gratis', v_nuovi_gratis, 'bustine', v_bustine, 'bustine_vinte', v_bustine_vinte, 'bustine_gratis', v.bustine_gratis,
    'crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'max_vincita', v.max_vincita);
end $function$;
