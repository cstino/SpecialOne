
-- Premio di 'Calcio di rigore' in multipli della puntata: 5 tiri, il primo parato chiude.
create or replace function pg_temp.premio_rigori() returns numeric language plpgsql as $f$
declare pg numeric[] := array[0.78,0.68,0.58,0.48,0.38]; lad numeric[] := array[1,2,4,8,25,120]; k int := 0;
begin
  while k < 5 loop exit when random() >= pg[k+1]; k := k + 1; end loop;
  return lad[k+1];
end $f$;
-- Premio di 'Scegli lo stemma': 3 scudi su 9, somma dei valori, tetto 500.
create or replace function pg_temp.premio_stemma() returns numeric language plpgsql as $f$
declare v numeric[] := array[1,2,3,5,10,25,100,250]; w numeric[] := array[38,30,15,8,5,3,0.8,0.15]; tot numeric := 0; i int; r numeric; c numeric; j int; s numeric := 0;
begin
  select sum(x) into tot from unnest(w) x;
  for i in 1..3 loop
    r := random() * tot; c := 0;
    for j in 1..8 loop c := c + w[j]; if r < c then s := s + v[j]; exit; end if; end loop;
  end loop;
  return least(s, 500);
end $f$;
-- Simulazione pura di SlotOne (nessuna scrittura): copia fedele della logica di casino_gira.
-- Parametri: n giri PAGATI, pesi dei simboli (indice 1..n), scala. Restituisce puntato, vinto, giri totali, quanti bonus (simboli 11 e 12).
create or replace function pg_temp.sim_slot(p_n int, c_pesi int[], c_scala numeric) returns table(puntato numeric, vinto numeric, giri_tot bigint, scatter_coppe bigint, trig11 bigint, trig12 bigint)
language plpgsql as $f$
declare
  c_linee constant int[] := array[1,1,1,1,1, 0,0,0,0,0, 2,2,2,2,2, 0,1,2,1,0, 2,1,0,1,2, 0,0,1,2,2, 2,2,1,0,0, 1,0,0,0,1, 1,2,2,2,1, 0,1,1,1,0];
  g int[]; v_tot int; v_ns int := array_length(c_pesi,1); i int; v_r int; v_x int; v_cum int; v_k int;
  v_linea int; v_sim int; v_target int; v_n int; v_paga int; v_vl numeric; v_coppe int; v_b11 int; v_b12 int; v_sc numeric;
  v_gratis_res bigint; v_molt int; v_pag int := 0; tot_v numeric := 0; tot_p numeric := 0; tot_giri bigint := 0; t_coppe bigint := 0; t11 bigint := 0; t12 bigint := 0;
  v_cum_w int[]; v_bn numeric;
begin
  v_tot := (select sum(x) from unnest(c_pesi) x);
  v_cum_w := array(select sum(c_pesi[j]) over (order by j) from generate_series(1, v_ns) j);
  while v_pag < p_n loop
    v_pag := v_pag + 1; tot_p := tot_p + 1; v_gratis_res := 1;  -- 1 = il giro pagato; i gratis si aggiungono
    v_molt := 1;
    -- catena: il giro pagato e tutti i gratis che ne derivano
    loop
      exit when v_gratis_res = 0;
      v_gratis_res := v_gratis_res - 1; tot_giri := tot_giri + 1;
      g := array_fill(0, array[15]); v_coppe := 0; v_b11 := 0; v_b12 := 0;
      for v_k in 1..15 loop
        v_x := floor(random() * v_tot)::int;
        for v_r in 1..v_ns loop
          if v_x < v_cum_w[v_r] then g[v_k] := v_r - 1; exit; end if;
        end loop;
        if g[v_k] = 9 then v_coppe := v_coppe + 1; elsif g[v_k] = 11 then v_b11 := v_b11 + 1; elsif g[v_k] = 12 then v_b12 := v_b12 + 1; end if;
      end loop;
      v_vl := 0;
      for v_linea in 0..9 loop
        v_target := null; v_n := 0; v_paga := 0;
        for v_r in 0..4 loop
          v_sim := g[v_r * 3 + c_linee[v_linea * 5 + v_r + 1] + 1];
          if v_sim >= 9 then exit; end if;
          if v_target is null and v_sim <> 8 then v_target := v_sim; end if;
          if v_sim = 8 or v_sim = v_target then v_n := v_n + 1; else exit; end if;
        end loop;
        if v_target is null and v_n = 5 then v_paga := 400;
        elsif v_n >= 3 and v_target is not null then
          v_paga := case when v_target <= 2 then (array[9,29,110])[v_n - 2] when v_target <= 5 then (array[16,56,222])[v_n - 2] else (array[29,136,550])[v_n - 2] end;
        end if;
        if v_paga > 0 then v_vl := v_vl + round(v_paga * 1 / 10.0 * (case when v_molt = 2 then 2 else 1 end) * c_scala, 6); end if;
      end loop;
      v_sc := 0;
      if v_coppe >= 3 then
        v_sc := (case least(v_coppe, 5) when 3 then 2 when 4 then 5 else 20 end) * (case when v_molt = 2 then 2 else 1 end) * c_scala;
        v_gratis_res := v_gratis_res + (case least(v_coppe, 5) when 3 then 8 when 4 then 12 else 20 end);
        t_coppe := t_coppe + 1;
      end if;
      v_bn := 0;
      if v_b11 >= 3 then t11 := t11 + 1; v_bn := v_bn + pg_temp.premio_rigori(); end if;
      if v_b12 >= 3 then t12 := t12 + 1; v_bn := v_bn + pg_temp.premio_stemma(); end if;
      tot_v := tot_v + v_vl + v_sc + v_bn;
      v_molt := 2;   -- dopo il primo, i giri della catena sono gratis (x2)
    end loop;
  end loop;
  return query select tot_p, tot_v, tot_giri, t_coppe, t11, t12;
end $f$;

-- Esempio d'uso (versione con album): 4 milioni di giri pagati, circa 2 minuti.
-- Restituisce ritorno in %, giri totali per giro pagato e quanti giri scatenano ciascun minigioco.
select puntato, round(100 * vinto / puntato, 3) as rtp_pct, round(giri_tot / puntato, 4) as giri_per_pagato, trig11, trig12
from pg_temp.sim_slot(4000000, array[900,900,900,700,700,700,400,400,300,200,220,159,159], 1.0947);
