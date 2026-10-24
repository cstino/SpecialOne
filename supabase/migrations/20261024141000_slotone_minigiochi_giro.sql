-- SlotOne: il giro estrae anche i simboli dei minigiochi (11 = pallone, 12 = stemma d'oro), crea il bonus quando ne escono
-- almeno 3, e non si puo' girare con un minigioco ancora da finire. Pesi dei rulli in scala x10 con i due simboli nuovi e
-- scala dei pagamenti ricalcolata per restare al 97% (vedi 20261024140000). casino_gira e casino_stato sono riscritte dalla
-- definizione viva.

CREATE OR REPLACE FUNCTION public.casino_gira(p_league_id bigint, p_puntata integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  -- simboli 0-7 stemmi, 8 jolly, 9 coppa, 10 bustina (solo dove l'album e' attivo), 11 pallone (rigori), 12 stemma d'oro (scegli lo stemma). Pesi in centesimi.
  c_pesi_album constant int[] := array[900,900,900,700,700,700,400,400,300,200,220,159,159];
  c_pesi_base constant int[] := array[900,900,900,700,700,700,400,400,300,200,0,153,153];
  c_pesi int[];
  v_album boolean;
  c_scala numeric;   -- 20/10/2026: porta il ritorno dal 94% al 97% senza toccare la tabella dei pesi
  v_bustine int := 0;
  v_rigori int := 0;
  v_stemmi int := 0;
  v_bonus jsonb := '[]'::jsonb;
  v_bid bigint;
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
  -- Un minigioco scaduto si chiude da solo (mosse a caso); uno ancora aperto va finito prima di girare.
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  if exists (select 1 from public.casino_slot_bonus b where b.league_id = p_league_id and b.user_id = v_utente and b.stato = 'aperto') then
    raise exception using errcode = '55000', message = 'Hai un minigioco da finire: completalo prima di girare.';
  end if;
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
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
  c_scala := case when v_album then 1.0947 else 1.0537 end;
  v_tot := (select sum(x) from unnest(c_pesi) x);

  -- Estrazione: ogni casella pescata secondo i pesi (lo fa il server).
  g := array_fill(0, array[15]);
  for v_k in 1..15 loop
    v_x := floor(random() * v_tot)::int; v_cum := 0;
    for v_r in 1..13 loop
      v_cum := v_cum + c_pesi[v_r];
      if v_x < v_cum then g[v_k] := v_r - 1; exit; end if;
    end loop;
    if g[v_k] = 9 then v_coppe := v_coppe + 1; end if;
    if g[v_k] = 10 then v_bustine := v_bustine + 1; end if;
    if g[v_k] = 11 then v_rigori := v_rigori + 1; end if;
    if g[v_k] = 12 then v_stemmi := v_stemmi + 1; end if;
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

  -- Minigiochi: 3 o piu' palloni = calcio di rigore, 3 o piu' stemmi d'oro = scegli lo stemma. Il premio si paga a fine minigioco.
  if v_rigori >= 3 then
    v_bid := private.casino_bonus_crea(p_league_id, v_utente, v.team_id, v_giro_id, 'rigori', v_puntata);
    v_bonus := v_bonus || jsonb_build_object('id', v_bid, 'tipo', 'rigori');
  end if;
  if v_stemmi >= 3 then
    v_bid := private.casino_bonus_crea(p_league_id, v_utente, v.team_id, v_giro_id, 'stemma', v_puntata);
    v_bonus := v_bonus || jsonb_build_object('id', v_bid, 'tipo', 'stemma');
  end if;

  -- Il colpo grosso (almeno 100 volte la puntata) finisce su SocialOne.
  if v_vinto >= 100 * v_puntata then
    select nome into v_nome_team from public.teams where id = v.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (p_league_id, 'casino:' || v_giro_id, 'lega', 'BetOne Casinò', v.team_id,
            '🎰 COLPO GROSSO al casinò! ' || v_nome_team || ' vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti con un solo giro 🤑', now())
    on conflict do nothing;
  end if;

  return jsonb_build_object('griglia', to_jsonb(g), 'vincite', v_vinte, 'coppe', v_coppe, 'scatter', v_scatter, 'vinto', v_vinto,
    'gratis', v_gratis, 'molt', v_molt, 'puntata', v_puntata, 'nuovi_gratis', v_nuovi_gratis, 'bustine', v_bustine, 'bustine_vinte', v_bustine_vinte, 'bustine_gratis', v.bustine_gratis, 'bonus', v_bonus,
    'crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'max_vincita', v.max_vincita);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
  v_speso bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  perform private.casino_bustine_speso(p_league_id);
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = v_utente;
  select coalesce(sum(m.speso), 0) into v_speso from private.casino_movimenti(p_league_id) m where m.team_id = v.team_id;
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'bonus_aperto', (select jsonb_build_object('id', b.id, 'tipo', b.tipo) from public.casino_slot_bonus b where b.league_id = p_league_id and b.user_id = v_utente and b.stato = 'aperto' order by b.id limit 1),
    'bustina_spesi', greatest(0, v_speso - v.speso_base - 500 * v.bustine_speso),
    'bustine_oggi', case when v.bustine_giorno = (now() at time zone 'Europe/Rome')::date then v.bustine_oggi else 0 end,
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'blackjack', (select l.casino_blackjack from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours 10 minutes') at time zone 'Europe/Rome'));
end $function$;
