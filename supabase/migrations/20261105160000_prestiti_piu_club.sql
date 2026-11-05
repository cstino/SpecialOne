-- Prestiti: 75 club reali in piu' (112 in tutto, una squadra ne usa al massimo 5 a stagione) e scelta del club
-- meno usato nella lega in questa stagione, cosi' i club non si ripetono. Funzione ricostruita dalla definizione live.

insert into public.club_prestito (nome, logo, paese) values
  ('Parma', '/loghi-club/parma.png', 'Italy'),
  ('Como', '/loghi-club/como.png', 'Italy'),
  ('Cremonese', '/loghi-club/cremonese.png', 'Italy'),
  ('Pisa', '/loghi-club/pisa.png', 'Italy'),
  ('Frosinone', '/loghi-club/frosinone.png', 'Italy'),
  ('Modena', '/loghi-club/modena.png', 'Italy'),
  ('Pescara', '/loghi-club/pescara.png', 'Italy'),
  ('Südtirol', '/loghi-club/sudtirol.png', 'Italy'),
  ('Mantova', '/loghi-club/mantova.png', 'Italy'),
  ('Elche', '/loghi-club/elche.png', 'Spain'),
  ('Girona', '/loghi-club/girona.png', 'Spain'),
  ('Levante', '/loghi-club/levante.png', 'Spain'),
  ('Real Oviedo', '/loghi-club/oviedo.png', 'Spain'),
  ('Valencia', '/loghi-club/valencia.png', 'Spain'),
  ('Siviglia', '/loghi-club/sevilla.png', 'Spain'),
  ('Bournemouth', '/loghi-club/bournemouth.png', 'England'),
  ('Burnley', '/loghi-club/burnley.png', 'England'),
  ('Everton', '/loghi-club/everton.png', 'England'),
  ('Sunderland', '/loghi-club/sunderland.png', 'England'),
  ('Middlesbrough', '/loghi-club/middlesbrough.png', 'England'),
  ('Hull City', '/loghi-club/hull.png', 'England'),
  ('Coventry City', '/loghi-club/coventry.png', 'England'),
  ('Blackburn Rovers', '/loghi-club/blackburn.png', 'England'),
  ('Swansea City', '/loghi-club/swansea.png', 'Wales'),
  ('Queens Park Rangers', '/loghi-club/qpr.png', 'England'),
  ('Millwall', '/loghi-club/millwall.png', 'England'),
  ('Bristol City', '/loghi-club/bristol-city.png', 'England'),
  ('Derby County', '/loghi-club/derby.png', 'England'),
  ('Sheffield Wednesday', '/loghi-club/sheffield-wed.png', 'England'),
  ('Southampton', '/loghi-club/southampton.png', 'England'),
  ('Birmingham City', '/loghi-club/birmingham.png', 'England'),
  ('Angers', '/loghi-club/angers.png', 'France'),
  ('Le Havre', '/loghi-club/le-havre.png', 'France'),
  ('Metz', '/loghi-club/metz.png', 'France'),
  ('Strasburgo', '/loghi-club/strasbourg.png', 'France'),
  ('Brest', '/loghi-club/brest.png', 'France'),
  ('Rennes', '/loghi-club/rennes.png', 'France'),
  ('Nizza', '/loghi-club/nice.png', 'France'),
  ('Heidenheim', '/loghi-club/heidenheim.png', 'Germany'),
  ('Colonia', '/loghi-club/koln.png', 'Germany'),
  ('St. Pauli', '/loghi-club/st-pauli.png', 'Germany'),
  ('Hoffenheim', '/loghi-club/hoffenheim.png', 'Germany'),
  ('Wolfsburg', '/loghi-club/wolfsburg.png', 'Germany'),
  ('Borussia Mönchengladbach', '/loghi-club/gladbach.png', 'Germany'),
  ('Groningen', '/loghi-club/groningen.png', 'The Netherlands'),
  ('NEC Nijmegen', '/loghi-club/nec.png', 'The Netherlands'),
  ('Sparta Rotterdam', '/loghi-club/sparta.png', 'The Netherlands'),
  ('Go Ahead Eagles', '/loghi-club/go-ahead.png', 'The Netherlands'),
  ('Fortuna Sittard', '/loghi-club/sittard.png', 'The Netherlands'),
  ('PEC Zwolle', '/loghi-club/zwolle.png', 'The Netherlands'),
  ('Heracles', '/loghi-club/heracles.png', 'The Netherlands'),
  ('Famalicão', '/loghi-club/famalicao.png', 'Portugal'),
  ('Gil Vicente', '/loghi-club/gil-vicente.png', 'Portugal'),
  ('Moreirense', '/loghi-club/moreirense.png', 'Portugal'),
  ('Estoril', '/loghi-club/estoril.png', 'Portugal'),
  ('Casa Pia', '/loghi-club/casa-pia.png', 'Portugal'),
  ('Arouca', '/loghi-club/arouca.png', 'Portugal'),
  ('Santa Clara', '/loghi-club/santa-clara.png', 'Portugal'),
  ('Westerlo', '/loghi-club/westerlo.png', 'Belgium'),
  ('Charleroi', '/loghi-club/charleroi.png', 'Belgium'),
  ('Standard Liegi', '/loghi-club/standard.png', 'Belgium'),
  ('Anversa', '/loghi-club/antwerp.png', 'Belgium'),
  ('Zulte Waregem', '/loghi-club/zulte.png', 'Belgium'),
  ('Hellas Verona', '/loghi-club/verona.png', 'Italy'),
  ('Alavés', '/loghi-club/alaves.png', 'Spain'),
  ('Brighton', '/loghi-club/brighton.png', 'England'),
  ('Leeds United', '/loghi-club/leeds.png', 'England'),
  ('West Ham', '/loghi-club/west-ham.png', 'England'),
  ('Ipswich Town', '/loghi-club/ipswich.png', 'England'),
  ('Leicester City', '/loghi-club/leicester.png', 'England'),
  ('West Bromwich Albion', '/loghi-club/west-brom.png', 'England'),
  ('Union Berlino', '/loghi-club/union-berlin.png', 'Germany'),
  ('Cercle Brugge', '/loghi-club/cercle.png', 'Belgium'),
  ('Wolverhampton', '/loghi-club/wolves.png', 'England'),
  ('Preston North End', '/loghi-club/preston.png', 'England')
on conflict (nome) do nothing;

CREATE OR REPLACE FUNCTION public.manda_in_prestito(p_instance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_pi public.player_instances;
  v_lega public.leagues;
  v_squadra public.teams;
  v_pos text[];
  v_gk boolean;
  v_restanti integer;
  v_portieri integer;
  v_club public.club_prestito;
  v_prestito public.prestiti;
  v_giornata smallint;
  v_spec text;
  v_ruolo text;
  v_ruolo_cambiato text := null;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire la rosa.';
  end if;
  select * into v_pi from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;
  select * into v_squadra from public.teams where id = v_pi.team_id;
  if not found or v_squadra.user_id is distinct from v_utente then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;
  select * into v_lega from public.leagues where id = v_pi.league_id;
  if v_lega.stato <> 'stagione' or v_lega.fase_carriera <> 'normale' or not exists (
       select 1 from public.seasons s where s.league_id = v_lega.id and s.numero = v_lega.stagione_corrente and s.stato = 'in_corso') then
    raise exception using errcode = '55000', message = 'I prestiti si fanno solo a stagione in corso.';
  end if;
  -- Le novita' della Season 3 si accendono insieme allo stadio (leagues.stadio_attivo).
  if not v_lega.stadio_attivo then
    raise exception using errcode = '55000', message = 'I prestiti arrivano con la prossima stagione.';
  end if;
  if v_pi.ritirato then
    raise exception using errcode = '55000', message = 'Questo giocatore si è ritirato.';
  end if;
  if v_pi.prestito_id is not null then
    raise exception using errcode = '55000', message = 'È già in prestito.';
  end if;
  if exists (select 1 from public.prestiti p where p.player_instance_id = p_instance_id and p.stagione = v_lega.stagione_corrente) then
    raise exception using errcode = '55000', message = 'In questa stagione è già stato in prestito: un giocatore ci va una volta sola a stagione.';
  end if;
  if (select count(*) from public.prestiti p where p.team_id = v_squadra.id and p.stagione = v_lega.stagione_corrente) >= 5 then
    raise exception using errcode = '55000', message = 'Hai già usato i 5 prestiti di questa stagione.';
  end if;

  select coalesce(v_pi.posizioni_override, p.posizioni) into v_pos from public.players p where p.id = v_pi.player_id;
  v_gk := 'GK' = any(v_pos);
  select count(*),
         count(*) filter (where 'GK' = any(coalesce(pi.posizioni_override, p.posizioni)))
    into v_restanti, v_portieri
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id and not pi.ritirato and pi.prestito_id is null and pi.id <> p_instance_id;
  if v_restanti < 18 then
    raise exception using errcode = '55000', message = 'Senza di lui ti resterebbero meno di 18 giocatori: non puoi mandarlo in prestito.';
  end if;
  if v_gk and v_portieri < 1 then
    raise exception using errcode = '55000', message = 'È il tuo unico portiere: non puoi mandarlo in prestito.';
  end if;

  -- Il club usato meno volte nella lega in questa stagione (a pari merito a caso): niente ripetizioni finche' ce ne sono di liberi.
  select c.* into v_club from public.club_prestito c
  order by (select count(*) from public.prestiti p
            where p.club_id = c.id and p.league_id = v_lega.id and p.stagione = v_lega.stagione_corrente), random()
  limit 1;
  v_giornata := private.prossima_giornata_lega(v_lega.id);

  insert into public.prestiti (league_id, team_id, player_instance_id, club_id, stagione, giornata_inizio)
  values (v_lega.id, v_squadra.id, p_instance_id, v_club.id, v_lega.stagione_corrente, v_giornata)
  returning * into v_prestito;
  update public.player_instances set prestito_id = v_prestito.id where id = p_instance_id;
  update public.teams set capitano = null where id = v_squadra.id and capitano = p_instance_id;
  perform private.togli_giocatori_dalle_formazioni(v_lega.id, array[v_squadra.id], array[p_instance_id], v_giornata);

  -- Il club ospite decide l'allenamento: si chiudono quelli del proprietario e se ne sceglie uno a caso;
  -- con probabilita' 20% cambia anche il ruolo (tempi normali).
  delete from public.cambi_ruolo where player_instance_id = p_instance_id and completato_il is null;
  delete from public.specializzazioni_giocatore where player_instance_id = p_instance_id and completato_il is null;
  perform set_config('app.prestito_ospite', 'on', true);
  select k into v_spec
  from jsonb_object_keys(private.specializzazioni_ruolo(v_pos[1])) k
  where k is distinct from coalesce(v_pi.specializzazione_attiva, 'bilanciato')
  order by random() limit 1;
  if v_spec is not null then
    begin
      perform public.avvia_specializzazione(p_instance_id, v_spec);
    exception when others then v_spec := null;
    end;
  end if;
  if random() < 0.20 then
    select r into v_ruolo from unnest(private.ruoli_target_cambio(v_pos)) r order by random() limit 1;
    if v_ruolo is not null then
      begin
        perform public.avvia_cambio_ruolo(p_instance_id, v_ruolo);
        v_ruolo_cambiato := v_ruolo;
      exception when others then v_ruolo_cambiato := null;
      end;
    end if;
  end if;
  perform set_config('app.prestito_ospite', '', true);

  return jsonb_build_object('prestito_id', v_prestito.id, 'club', v_club.nome, 'logo', v_club.logo,
                            'specializzazione', v_spec, 'ruolo', v_ruolo_cambiato, 'giornata', v_giornata);
end;
$function$;
