-- ============================================================
--  Piano di sviluppo subito attivo (season 2, 3 ottobre 2026).
--
--  Segnalato dal committente: col modello dei piani di sviluppo (il piano
--  sceglie DOVE va la crescita che il giocatore fa comunque, non regala punti)
--  il tempo di attesa non ha piu' senso. Ora, nelle leghe con le tattiche
--  accese (il flag della season 2: leagues.tattiche_attive), avvia_specializzazione
--  applica il piano subito. Le altre leghe tengono l'attesa fino al lancio.
--  Il cambio ruolo resta con la sua attesa (cambia il ruolo primario).
--
--  Funzione ricostruita dal testo vivo del database (non a memoria).
--  I piani gia' in corso nelle leghe con il flag si completano ora.
-- ============================================================
begin;

CREATE OR REPLACE FUNCTION public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
 RETURNS specializzazioni_giocatore
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
  v_maturato jsonb;
  v_congelati jsonb;
  v_chiave text;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if coalesce(v_istanza.specializzazione_attiva, 'bilanciato') = p_specializzazione then
    raise exception using errcode = '55000', message = 'Questo giocatore segue già questo piano di sviluppo.';
  end if;

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;
  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' cambiando ruolo: non puo'' anche allenare una specializzazione insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni_attuali[1]);
  if not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = 'Specializzazione non valida per questo ruolo.';
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  -- Season 2 (3 ottobre 2026): il piano sceglie DOVE va la crescita che il
  -- giocatore fa comunque, quindi non c'e' niente da attendere: vale subito.
  -- Solo nelle leghe con le tattiche accese (il flag della season 2); le altre
  -- tengono l'attesa di prima fino al lancio. Stessa contabilita' di
  -- private.completa_specializzazioni: quello che il piano uscente ha gia'
  -- spostato resta al giocatore. La riga resta nello storico, gia' completata.
  if coalesce(v_lega.tattiche_attive, false) then
    v_maturato := private.scostamenti_piano(
      v_istanza.specializzazione_attiva, private.macro_ruolo(v_posizioni_attuali),
      case when v_istanza.piano_overall_rif is null then 0 else v_istanza.overall_corrente - v_istanza.piano_overall_rif end);
    v_congelati := coalesce(v_istanza.piano_scostamenti, '{}'::jsonb);
    for v_chiave in select jsonb_object_keys(v_maturato) loop
      v_congelati := v_congelati || jsonb_build_object(v_chiave,
        round(coalesce((v_congelati->>v_chiave)::numeric, 0) + (v_maturato->>v_chiave)::numeric, 3));
    end loop;

    update public.player_instances
    set piano_scostamenti = v_congelati,
        specializzazione_attiva = p_specializzazione,
        piano_overall_rif = overall_corrente
    where id = p_instance_id;

    insert into public.specializzazioni_giocatore (
      league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
      avviato_giornata, completa_giornata, completato_il
    ) values (
      v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
      v_prossima, v_prossima, now()
    ) returning * into v_allenamento;
    return v_allenamento;
  end if;

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$function$
;

-- Piani gia' in corso nelle leghe con il flag: si chiudono adesso, con la
-- stessa funzione che li chiude di solito (notifica compresa). Tutti, anche
-- quelli rimasti aperti da una stagione precedente (partiti a giornate come 28
-- o 32 e da completare a 36 o 41: con la numerazione ripartita da 1 non
-- sarebbero mai arrivati a completarsi).
update public.specializzazioni_giocatore s
set completa_giornata = 0
from public.leagues l
where s.league_id = l.id and l.tattiche_attive and s.completato_il is null;
select private.completa_specializzazioni();

commit;
