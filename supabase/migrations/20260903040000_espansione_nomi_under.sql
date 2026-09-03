-- ============================================================
--  ESPANSIONE LISTE NOMI/COGNOMI PROSPETTI VIVAIO.
--
--  Segnalato dall'utente: le liste erano ferme a 30x30 (900 combinazioni)
--  fin dalla prima versione di genera_prospetto_vivaio. Con 8 prospetti al
--  giorno per lega, per il paradosso del compleanno un doppione di nome
--  diventa probabile (>50%) gia' dopo ~35-40 estrazioni — nessun controllo
--  di unicita' esisteva ne' esiste ora, si e' scelto di allargare il
--  pool invece di aggiungere un retry-on-collision.
--
--  Da 30x30 a 70x70 (4.900 combinazioni, 5.4x): stesso stile
--  multiculturale gia' in uso (nomi/cognomi scandinavi, latini, slavi,
--  arabi, africani dell'ovest, giapponesi), solo piu' vario. Nessun'altra
--  riga della funzione cambia: corpo ri-fetchato dal vivo con
--  pg_get_functiondef, come sempre per non retipizzare a memoria.
-- ============================================================

CREATE OR REPLACE FUNCTION private.genera_prospetto_vivaio(p_macro_ruolo text, p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_posizione text;
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
    array[v_posizione], case when random() < 0.78 then 'destro' else 'sinistro' end,
    round(168 + random() * 26)::smallint,
    jsonb_build_object(
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
