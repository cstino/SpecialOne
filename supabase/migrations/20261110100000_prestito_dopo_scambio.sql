-- Prestiti: un giocatore richiamato e poi scambiato puo' ripartire in prestito dalla nuova squadra.
--
-- La regola era "un giocatore va in prestito una volta sola a stagione", legata al giocatore: chi lo riceveva in
-- uno scambio dopo un richiamo non poteva piu' mandarlo da nessuna parte (richiesta del committente, 10/11/2026).
-- Ora la regola e' per squadra: la stessa squadra non lo rimanda due volte nella stessa stagione, una squadra
-- nuova si'. Il tetto di 5 prestiti a stagione per squadra resta com'era.
-- La funzione e' ricostruita da quella in uso nel database: cambia solo il controllo "gia' stato in prestito".

alter table public.prestiti drop constraint prestiti_player_instance_id_stagione_key;
alter table public.prestiti add constraint prestiti_giocatore_stagione_squadra_key unique (player_instance_id, stagione, team_id);

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
  -- Una volta sola a stagione per squadra: chi lo richiama non lo rimanda, ma se viene scambiato la nuova squadra puo'.
  if exists (select 1 from public.prestiti p where p.player_instance_id = p_instance_id and p.stagione = v_lega.stagione_corrente
               and p.team_id = v_squadra.id) then
    raise exception using errcode = '55000', message = 'In questa stagione l''hai già mandato in prestito: ogni squadra può mandarci un giocatore una volta sola a stagione.';
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
