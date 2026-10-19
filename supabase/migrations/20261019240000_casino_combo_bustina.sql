-- ============================================================
--  CASINO': COMBO BUSTINA (19/10/2026, deciso con il committente). Nuovo simbolo "bustina" (indice 10), conta ovunque
--  come la coppa: 3 = 1 bustina gratis per l'album, 4 = 2, 5+ = 3. Esce solo dove l'album e' attivo, circa 1 giro su 70;
--  li' gli stemmi pagano ~18% in piu' per compensare (ritorno medio invariato). Le bustine vinte stanno in
--  casino_saldi.bustine_gratis e si aprono dall'album senza crediti (album_compra_bustina(lega, p_gratis => true)).
--  Funzioni riscritte dalla definizione viva.
-- ============================================================
begin;
alter table public.casino_saldi add column bustine_gratis integer not null default 0 check (bustine_gratis >= 0);
drop function public.album_compra_bustina(bigint);
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
                       case when v_target <= 2 then (array[9,31,118])[v_n - 2]
                            when v_target <= 5 then (array[17,61,236])[v_n - 2]
                            else (array[31,148,590])[v_n - 2] end
                     else
                       case when v_target <= 2 then (array[8,26,100])[v_n - 2]
                            when v_target <= 5 then (array[14,52,200])[v_n - 2]
                            else (array[26,125,500])[v_n - 2] end end;
    end if;
    if v_paga > 0 then
      v_vinto_linee := v_vinto_linee + v_paga;
      v_vinte := v_vinte || jsonb_build_object('linea', v_linea, 'simbolo', v_target, 'n', v_n, 'vinto', round(v_paga * v_puntata / 10.0 * v_molt));
    end if;
  end loop;

  -- Coppe ovunque: 3 = 2x la puntata e 8 giri gratis, 4 = 5x e 12, 5+ = 20x e 20 (vincite doppie nei giri gratis).
  if v_coppe >= 3 then
    v_scatter := (case least(v_coppe, 5) when 3 then 2 when 4 then 5 else 20 end) * v_puntata * v_molt;
    v_nuovi_gratis := case least(v_coppe, 5) when 3 then 8 when 4 then 12 else 20 end;
  end if;
  v_vinto := round(v_vinto_linee * v_puntata / 10.0 * v_molt + v_scatter);
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

CREATE OR REPLACE FUNCTION public.album_compra_bustina(p_league_id bigint, p_gratis boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_saldo public.casino_saldi;
  v_stag smallint;
  v_k int;
  v_r numeric;
  v_tipo text;
  v_fig public.album_figurine;
  v_ultra boolean;
  v_nuova boolean;
  v_out jsonb := '[]'::jsonb;
  c_prezzo constant int := 250;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.album_attivo(p_league_id) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  -- Bustina gratis (vinta al casino'): non costa crediti.
  if p_gratis then
    if v_saldo.bustine_gratis < 1 then raise exception using errcode = '22023', message = 'Non hai bustine gratis.'; end if;
  elsif v_saldo.crediti < c_prezzo then raise exception using errcode = '22023', message = 'Crediti insufficienti: una bustina costa 250 crediti.'; end if;
  v_stag := private.album_sincronizza(p_league_id);
  update public.casino_saldi set
    crediti = crediti - (case when p_gratis then 0 else c_prezzo end),
    bustine_gratis = bustine_gratis - (case when p_gratis then 1 else 0 end), aggiornato_il = now()
  where league_id = p_league_id and user_id = v_utente;

  for v_k in 1..3 loop
    v_r := random();
    v_ultra := v_r < 0.02;
    v_tipo := case when v_ultra then 'ultra' when v_r < 0.12 then 'stemma' else 'giocatore' end;
    if v_tipo = 'stemma' then
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
    elsif v_tipo = 'giocatore' then
      -- I piu' forti escono piu' di rado: peso = 100 - overall (minimo 5). Estrazione pesata con chiave esponenziale.
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
      order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
    else
      -- Ultrarara: un giocatore (stesso peso) oppure, nelle leghe a conferenze, una delle due conference (circa 1 ultra su 10).
      if exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
      end if;
    end if;
    if v_fig.id is null then continue; end if;
    -- Le figurine delle conference esistono solo ultrarare.
    if v_fig.tipo = 'conferenza' then v_ultra := true; end if;
    select not exists (select 1 from public.album_possesso where user_id = v_utente and figurina_id = v_fig.id and (case when v_ultra then ultra else normali end) > 0) into v_nuova;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, ultra)
    values (p_league_id, v_utente, v_fig.id, case when v_ultra then 0 else 1 end, case when v_ultra then 1 else 0 end)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + case when v_ultra then 0 else 1 end,
      ultra = public.album_possesso.ultra + case when v_ultra then 1 else 0 end;
    v_out := v_out || jsonb_build_object('figurina_id', v_fig.id, 'tipo', v_fig.tipo, 'team_id', v_fig.team_id, 'player_id', v_fig.player_id,
      'conferenza', v_fig.conferenza, 'ultra', v_ultra, 'nuova', v_nuova);
    v_fig := null;
  end loop;

  insert into public.album_bustine (league_id, user_id, contenuto) values (p_league_id, v_utente, v_out);
  return jsonb_build_object('figurine', v_out, 'premi', private.album_controlla_premi(p_league_id, v_utente, v_stag),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente),
    'bustine_gratis', (select bustine_gratis from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
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
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'prossima_ricarica', ((v.settimana + 1)::timestamp at time zone 'Europe/Rome'));
end $function$;
revoke all on function public.album_compra_bustina(bigint, boolean) from public, anon;
grant execute on function public.album_compra_bustina(bigint, boolean) to authenticated;
commit;
