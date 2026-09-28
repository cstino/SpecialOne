-- ============================================================
--  I GIOVANI DEL VIVAIO NASCONO CON I RUOLI SECONDARI
--
--  Segnalato dall'utente: i prospetti venivano generati sempre monoruolo.
--  Misurato: 434 su 434 con una sola posizione, contro il 65% di giocatori del
--  catalogo che ne hanno piu' d'una (media 2,04). La causa era una riga:
--  l'insert salvava array[v_posizione] e nessuno aveva mai scritto la parte
--  che aggiunge i secondari.
--
--  I secondari si prendono da un giocatore VERO con lo stesso ruolo principale,
--  cosi' la distribuzione e' quella reale per costruzione. Il CF si scarta.
--
--  Vale per i giovani generati da ora in poi. Definizione ripresa dal database
--  vivo: cambiano solo la scelta dei secondari e l'insert.
-- ============================================================

CREATE OR REPLACE FUNCTION private.genera_prospetto_vivaio(p_macro_ruolo text, p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_posizione text;
  v_posizioni text[];
  v_overall smallint;
  v_potential smallint;
  v_nomi constant text[] := array['Liam','Noah','Mateo','Diego','Kai','Yusuf','Amir','Leon','Enzo','Theo',
    'Rayan','Elias','Adam','Milo','Nils','Ivo','Bruno','Mihail','Kofi','Chidi','Sami','Idris','Aron','Bram',
    'Jonas','Mats','Pablo','Rui','Tiago','Kwame',
    'Lucas','Mathis','Hugo','Nico','Sven','Erik','Anders','Magnus','Rasmus','Oskar',
    'Felix','Julian','Lars','Timo','Marek','Tomas','Igor','Pavel','Dario','Marco',
    'Luca','Matteo','Alessio','Gabriel','Rafael','Joao','Andre','Nuno','Vasco','Karim',
    'Hassan','Tariq','Malik','Kwabena','Emeka','Sekou','Moussa','Ibrahim','Kenji','Ren'];
  v_cognomi constant text[] := array['Berg','Novak','Costa','Rossi','Diaby','Traore','Kovac','Larsen','Mendes',
    'Haddad','Silva','Krause','Petrov','Okafor','Sorensen','Almeida','Bakker','Lindqvist','Duarte','Ferreira',
    'Vukovic','Adeyemi','Marchetti','Hansen','Ribeiro','Sorland','Nakamura','Osei','Correia','Weiss',
    'Andersen','Nilsson','Eriksson','Johansson','Muller','Fischer','Schmidt','Wagner','Dubois','Lefevre',
    'Moreau','Girard','Fontana','Bianchi','Conti','Greco','Ferrari','Colombo','Barros','Pinto',
    'Neves','Cardoso','Fonseca','Amaral','Farouk','Mansour','Toure','Camara','Kone','Sylla',
    'Diallo','Coulibaly','Ouedraogo','Suzuki','Tanaka','Sato','Yamamoto','Watanabe','Kallio','Petit'];
  v_nazionalita text;
  v_nome text;
  v_rep text;
  v_stamina smallint;
  v_finishing smallint;
  v_passing smallint;
  v_tackle smallint;
  v_dribbling smallint;
  v_gk smallint;
  v_foto text;
  v_id bigint;
begin
  v_posizione := case p_macro_ruolo
    when 'GK' then 'GK'
    when 'DEF' then (array['CB','LB','RB'])[1 + floor(random() * 3)::int]
    when 'MID' then (array['CDM','CM','CAM'])[1 + floor(random() * 3)::int]
    else (array['LW','RW','ST'])[1 + floor(random() * 3)::int]
  end;
  -- RUOLI SECONDARI, presi da un giocatore vero con lo stesso ruolo principale.
  -- Prima il giovane nasceva con array[v_posizione] e basta: 434 prospetti su
  -- 434 senza un solo ruolo secondario, contro il 65% del catalogo (media 2,04
  -- posizioni). Pescare da un giocatore reale invece di inventare percentuali
  -- riproduce la distribuzione vera per ruolo: un CB prende i secondari tipici
  -- di un CB, e circa un terzo resta monoruolo come nella realta'.
  -- Il CF si scarta: nessun modulo lo schiera (20260914100000).
  select coalesce(array_agg(s.pos order by s.ord), '{}'::text[])
  into v_posizioni
  from (
    select p.posizioni from public.players p
    where not p.origine_vivaio and p.posizioni[1] = v_posizione
    order by random() limit 1
  ) modello
  cross join lateral unnest(modello.posizioni[2:]) with ordinality as s(pos, ord)
  where s.pos <> 'CF' and s.pos <> v_posizione;
  v_posizioni := array[v_posizione] || coalesce(v_posizioni, '{}'::text[]);

  v_rep := case when v_posizione = 'GK' then 'GK'
    when v_posizione in ('CB','LB','RB') then 'DEF'
    when v_posizione in ('CDM','CM','CAM') then 'MID'
    else 'ATT' end;

  v_overall := greatest(40, least(60, round(46 + (random() - 0.5) * 18)))::smallint;
  v_potential := case
    when random() < 0.55 then round(v_overall + 8 + random() * 14)
    when random() < 0.88 then round(74 + random() * 10)
    else round(85 + random() * 9)
  end;
  v_potential := greatest(v_overall + 5, least(94, v_potential))::smallint;

  select nazionalita into v_nazionalita
  from public.players where nazionalita is not null order by random() limit 1;

  v_nome := v_nomi[1 + floor(random() * array_length(v_nomi, 1))::int]
    || ' ' || v_cognomi[1 + floor(random() * array_length(v_cognomi, 1))::int];

  v_stamina := greatest(35, least(85, round(60 + (random() - 0.5) * 24)))::smallint;
  v_finishing := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then -6 else -20 end) + (random() - 0.5) * 14)))::smallint;
  v_passing := greatest(15, least(80, round(v_overall + (case v_rep when 'MID' then 4 when 'GK' then -22 else -3 end) + (random() - 0.5) * 14)))::smallint;
  v_tackle := greatest(15, least(80, round(v_overall + (case v_rep when 'DEF' then 5 when 'MID' then -3 else -22 end) + (random() - 0.5) * 14)))::smallint;
  v_dribbling := greatest(15, least(80, round(v_overall + (case v_rep when 'ATT' then 4 when 'MID' then 1 else -16 end) + (random() - 0.5) * 14)))::smallint;
  v_gk := case when v_rep = 'GK' then v_overall else 0 end;

  -- Foto in prestito: un U23 vero il cui campionato non e' fra quelli
  -- attivi di questa lega, quindi non puo' mai comparirci come carta
  -- vera. order by random() accetta un rarissimo doppione fra due
  -- prospetti generati: non e' un problema per una lega privata fra
  -- amici, lo sarebbe stato solo pescare dal pool dei campionati attivi.
  select foto_url into v_foto
  from public.players p
  join public.leagues l on l.id = p_league_id
  where p.eta <= 23 and p.foto_url is not null and not p.origine_vivaio
    and not (p.campionato = any(coalesce(l.campionati_attivi, array[]::text[])))
  order by random() limit 1;

  insert into public.players (
    fc_id, nome, nazionalita, club, campionato, foto_url, overall, potential, eta,
    posizioni, piede, altezza, attributi, is_icon, is_regen, origine_vivaio,
    disponibile_estrazione, elite_globale
  ) values (
    nextval('private.vivaio_fc_id_seq'), v_nome, v_nazionalita, 'Vivaio', 'Vivaio', v_foto,
    v_overall, v_potential, 15,
    v_posizioni, case when random() < 0.78 then 'destro' else 'sinistro' end,
    round(168 + random() * 26)::smallint,
    -- Profilo completo dal catalogo vero (private.attributi_vivaio), POI i sei
    -- storici che lo sovrascrivono. L'ordine conta: quei sei sono gli unici che
    -- il motore legge, sono calcolati qui sotto con le formule di sempre, e
    -- lasciarli vincere garantisce che le partite si giochino esattamente come
    -- prima di questa migrazione. Gli altri trentacinque servono a scheda,
    -- specializzazioni e profili tattici.
    private.attributi_vivaio(v_rep, v_overall) || jsonb_build_object(
      'stamina', v_stamina, 'finishing', v_finishing, 'short_passing', v_passing,
      'standing_tackle', v_tackle, 'dribbling', v_dribbling, 'gk', v_gk
    ),
    false, false, true,
    false, false
  )
  returning id into v_id;

  return v_id;
end;
$function$;
