-- ============================================================
--  FOTO IN PRESTITO PER I PROSPETTI VIVAIO
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  I prospetti UNDER sono generati (nome/nazionalita'/attributi
--  inventati, vedi 20260901070000): foto_url restava sempre null, in
--  RosaElenco/Under.tsx compare solo l'iniziale del nome puntata.
--
--  Soluzione scelta dall'utente: prendere in prestito la foto di un
--  giocatore REALE under 23 che pero' NON puo' comparire in questa
--  lega come carta vera, perche' il suo campionato non e' fra quelli
--  attivi (leagues.campionati_attivi, scelto alla creazione della
--  lega). Cosi' lo stesso volto non rischia mai di comparire due volte
--  nella stessa lega — una volta sul prospetto generato, una volta sul
--  giocatore vero — perche' quel giocatore vero in questa lega non
--  esiste proprio. E' un prestito della sola foto (storage path):
--  nome, nazionalita' e numeri restano quelli generati, il donatore
--  non viene toccato ne' referenziato altrove.
--
--  genera_prospetto_vivaio non conosceva la lega per cui stava
--  generando: serve per sapere quali campionati escludere dal prestito.
--  Firma diversa da prima: drop esplicito, altrimenti CREATE OR REPLACE
--  con un parametro in piu' crea un secondo overload invece di
--  sostituire (stesso errore gia' capitato con crea_lega in questa
--  sessione).
-- ============================================================

begin;

drop function if exists private.genera_prospetto_vivaio(text);

create function private.genera_prospetto_vivaio(p_macro_ruolo text, p_league_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_posizione text;
  v_overall smallint;
  v_potential smallint;
  v_nomi constant text[] := array['Liam','Noah','Mateo','Diego','Kai','Yusuf','Amir','Leon','Enzo','Theo',
    'Rayan','Elias','Adam','Milo','Nils','Ivo','Bruno','Mihail','Kofi','Chidi','Sami','Idris','Aron','Bram',
    'Jonas','Mats','Pablo','Rui','Tiago','Kwame'];
  v_cognomi constant text[] := array['Berg','Novak','Costa','Rossi','Diaby','Traore','Kovac','Larsen','Mendes',
    'Haddad','Silva','Krause','Petrov','Okafor','Sorensen','Almeida','Bakker','Lindqvist','Duarte','Ferreira',
    'Vukovic','Adeyemi','Marchetti','Hansen','Ribeiro','Sorland','Nakamura','Osei','Correia','Weiss'];
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
$$;

create or replace function private.estrai_under_lega(p_league_id bigint, p_giorno date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tornata integer;
  v_ruolo text;
  v_i integer;
  v_player_id bigint;
  v_creati integer := 0;
  v_liberato record;
begin
  select coalesce(max(a.tornata), 0) + 1 into v_tornata
  from public.under_auctions a
  where a.league_id = p_league_id and a.giorno = p_giorno;

  foreach v_ruolo in array array['GK','DEF','MID','ATT'] loop
    for v_i in 1..private.under_per_ruolo() loop
      v_player_id := private.genera_prospetto_vivaio(v_ruolo, p_league_id);
      insert into public.under_auctions (league_id, player_id, giorno, tornata)
      values (p_league_id, v_player_id, p_giorno, v_tornata);
      v_creati := v_creati + 1;
    end loop;
  end loop;

  for v_liberato in
    select player_id from private.rilasci_vivaio_in_coda where league_id = p_league_id
  loop
    insert into public.under_auctions (league_id, player_id, giorno, tornata)
    values (p_league_id, v_liberato.player_id, p_giorno, v_tornata)
    on conflict (league_id, giorno, player_id) do nothing;
    delete from private.rilasci_vivaio_in_coda
    where league_id = p_league_id and player_id = v_liberato.player_id;
    v_creati := v_creati + 1;
  end loop;

  return v_creati;
end;
$$;

commit;
