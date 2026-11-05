-- Season 3, diario §5: prestiti a club reali (stemmi reali in public/loghi-club, da TheSportsDB).
-- * massimo 5 prestiti per squadra a stagione, ogni giocatore una sola volta a stagione;
-- * richiamabile quando si vuole, poi non riparte; a fine stagione rientrano tutti (prepara_offseason);
-- * in prestito: non si schiera, non si scambia, non si svincola; promessa di minuti sospesa e morale fermo;
-- * crescita come chi gioca il 60% dei minuti, con l'allenamento di un club medio (livello 5);
-- * allenamento e cambio ruolo li decide il club ospite (una specializzazione a caso, cambio ruolo al 20%);
-- * dopo il prestito devono restare almeno 18 giocatori disponibili e un portiere.
-- Funzioni ricostruite dalla definizione live.

create table public.club_prestito (
  id smallint generated always as identity primary key,
  nome text not null unique,
  logo text not null,
  paese text not null default ''
);
alter table public.club_prestito enable row level security;
create policy club_prestito_lettura on public.club_prestito for select using (true);
grant select on public.club_prestito to anon;
grant select, insert, update, delete on public.club_prestito to authenticated, service_role;

insert into public.club_prestito (nome, logo, paese) values
  ('Torino', '/loghi-club/torino.png', 'Italy'),
  ('Genoa', '/loghi-club/genoa.png', 'Italy'),
  ('Sassuolo', '/loghi-club/sassuolo.png', 'Italy'),
  ('Udinese', '/loghi-club/udinese.png', 'Italy'),
  ('Cagliari', '/loghi-club/cagliari.png', 'Italy'),
  ('Lecce', '/loghi-club/lecce.png', 'Italy'),
  ('Sampdoria', '/loghi-club/sampdoria.png', 'Italy'),
  ('Monza', '/loghi-club/monza.png', 'Italy'),
  ('Getafe', '/loghi-club/getafe.png', 'Spain'),
  ('Osasuna', '/loghi-club/osasuna.png', 'Spain'),
  ('Celta Vigo', '/loghi-club/celta.png', 'Spain'),
  ('Espanyol', '/loghi-club/espanyol.png', 'Spain'),
  ('Mallorca', '/loghi-club/mallorca.png', 'Spain'),
  ('Brentford', '/loghi-club/brentford.png', 'England'),
  ('Fulham', '/loghi-club/fulham.png', 'England'),
  ('Crystal Palace', '/loghi-club/crystal-palace.png', 'England'),
  ('Stoke City', '/loghi-club/stoke.png', 'England'),
  ('Watford', '/loghi-club/watford.png', 'England'),
  ('Nantes', '/loghi-club/nantes.png', 'France'),
  ('Lorient', '/loghi-club/lorient.png', 'France'),
  ('Toulouse', '/loghi-club/toulouse.png', 'France'),
  ('Mainz 05', '/loghi-club/mainz.png', 'Germany'),
  ('Augsburg', '/loghi-club/augsburg.png', 'Germany'),
  ('Friburgo', '/loghi-club/freiburg.png', 'Germany'),
  ('Werder Brema', '/loghi-club/werder.png', 'Germany'),
  ('Utrecht', '/loghi-club/utrecht.png', 'The Netherlands'),
  ('Twente', '/loghi-club/twente.png', 'The Netherlands'),
  ('Heerenveen', '/loghi-club/heerenveen.png', 'The Netherlands'),
  ('Braga', '/loghi-club/braga.png', 'Portugal'),
  ('Vitória Guimarães', '/loghi-club/guimaraes.png', 'Portugal'),
  ('Rio Ave', '/loghi-club/rio-ave.png', 'Portugal'),
  ('Genk', '/loghi-club/genk.png', 'Belgium'),
  ('Mechelen', '/loghi-club/mechelen.png', 'Belgium'),
  ('Norwich City', '/loghi-club/norwich.png', 'England'),
  ('Rayo Vallecano', '/loghi-club/rayo.png', 'Spain'),
  ('Auxerre', '/loghi-club/auxerre.png', 'France'),
  ('Gent', '/loghi-club/gent.png', 'Belgium');

create table public.prestiti (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  club_id smallint not null references public.club_prestito(id),
  stagione smallint not null,
  -- prima giornata saltata; giornata_fine = prima giornata di nuovo disponibile (null = fino a fine stagione)
  giornata_inizio smallint not null,
  giornata_fine smallint,
  esito text not null default 'in_corso' check (esito in ('in_corso', 'richiamato', 'rientrato')),
  iniziato_il timestamptz not null default now(),
  concluso_il timestamptz,
  unique (player_instance_id, stagione)
);
create index prestiti_team_stagione_idx on public.prestiti (team_id, stagione);
create index prestiti_league_idx on public.prestiti (league_id);
alter table public.prestiti enable row level security;
create policy prestiti_lettura on public.prestiti for select
  using (league_id = any ((select private.mie_leghe())::bigint[]));
grant select on public.prestiti to anon;
grant select, insert, update, delete on public.prestiti to authenticated, service_role;

alter table public.player_instances add column if not exists prestito_id bigint references public.prestiti(id) on delete set null;

-- Un giocatore in prestito non cambia squadra (scambi, svincoli, cessioni): prima va richiamato.
create or replace function private.trg_prestito_blocca_squadra()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if old.prestito_id is not null and new.team_id is distinct from old.team_id then
    raise exception using errcode = '55000', message = 'Il giocatore è in prestito: richiamalo prima.';
  end if;
  return new;
end;
$$;
create trigger player_instances_prestito_squadra before update of team_id on public.player_instances
  for each row execute function private.trg_prestito_blocca_squadra();

create or replace function private.trg_prestito_blocca_proposta()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if exists (select 1 from public.player_instances pi
             where pi.id = any(coalesce(new.giocatori_offerti, '{}'::bigint[]) || coalesce(new.giocatori_richiesti, '{}'::bigint[]))
               and pi.prestito_id is not null) then
    raise exception using errcode = '55000', message = 'Un giocatore della proposta è in prestito: va richiamato prima di scambiarlo.';
  end if;
  return new;
end;
$$;
create trigger trade_proposals_prestito before insert on public.trade_proposals
  for each row execute function private.trg_prestito_blocca_proposta();

-- In prestito allenamento e ruolo li decide il club ospite: il proprietario non ne avvia di nuovi.
create or replace function private.trg_prestito_blocca_allenamento()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.player_instance_id is not null
     and coalesce(current_setting('app.prestito_ospite', true), '') <> 'on'
     and exists (select 1 from public.player_instances pi where pi.id = new.player_instance_id and pi.prestito_id is not null) then
    raise exception using errcode = '55000', message = 'È in prestito: allenamento e ruolo li decide il club che lo ospita.';
  end if;
  return new;
end;
$$;
create trigger cambi_ruolo_prestito before insert on public.cambi_ruolo
  for each row execute function private.trg_prestito_blocca_allenamento();
create trigger specializzazioni_prestito before insert on public.specializzazioni_giocatore
  for each row execute function private.trg_prestito_blocca_allenamento();

-- Prima giornata ancora da giocare della stagione (come in avvia_cambio_ruolo).
create or replace function private.prossima_giornata_lega(p_league_id bigint)
returns smallint
language sql
stable
set search_path to ''
as $$
  select coalesce(min(f.giornata), (select l.giornate_totali + 1 from public.leagues l where l.id = p_league_id))::smallint
  from public.fixtures f
  join public.seasons s on s.id = f.season_id
  join public.leagues l on l.id = s.league_id and s.numero = l.stagione_corrente
  where f.league_id = p_league_id and f.stato = 'programmata'
$$;
revoke all on function private.prossima_giornata_lega(bigint) from public, anon, authenticated;

create or replace function public.manda_in_prestito(p_instance_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
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

  select * into v_club from public.club_prestito order by random() limit 1;
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
$$;
revoke all on function public.manda_in_prestito(bigint) from public;
grant execute on function public.manda_in_prestito(bigint) to authenticated, service_role;

create or replace function public.richiama_dal_prestito(p_instance_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_pi public.player_instances;
  v_giornata smallint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire la rosa.';
  end if;
  select * into v_pi from public.player_instances where id = p_instance_id for update;
  if not found or not exists (select 1 from public.teams t where t.id = v_pi.team_id and t.user_id = v_utente) then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;
  if v_pi.prestito_id is null then
    raise exception using errcode = '55000', message = 'Non è in prestito.';
  end if;
  v_giornata := private.prossima_giornata_lega(v_pi.league_id);
  update public.prestiti set esito = 'richiamato', giornata_fine = v_giornata, concluso_il = now()
  where id = v_pi.prestito_id;
  update public.player_instances set prestito_id = null where id = p_instance_id;
  return jsonb_build_object('giornata', v_giornata);
end;
$$;
revoke all on function public.richiama_dal_prestito(bigint) from public;
grant execute on function public.richiama_dal_prestito(bigint) to authenticated, service_role;

-- A fine stagione rientrano tutti (chiamata all'apertura dell'off-season, prima di rinnovi e invecchiamento).
create or replace function private.chiudi_prestiti_lega(p_league_id bigint)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare v_n integer;
begin
  update public.player_instances pi set prestito_id = null
  from public.prestiti p
  where p.id = pi.prestito_id and p.league_id = p_league_id;
  update public.prestiti set esito = 'rientrato', concluso_il = now()
  where league_id = p_league_id and esito = 'in_corso';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function private.chiudi_prestiti_lega(bigint) from public, anon, authenticated;


CREATE OR REPLACE FUNCTION private.minuti_stagione(p_instance_id bigint)
 RETURNS TABLE(partite integer, minuti numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with g as (
    select pi.id, pi.team_id, pi.league_id,
           coalesce(pi.giornata_acquisizione, 1) as inizio,
           l.stagione_corrente
    from public.player_instances pi
    join public.leagues l on l.id = pi.league_id
    where pi.id = p_instance_id
  ), f as (
    select fx.id as fixture_id
    from g
    join public.seasons s on s.league_id = g.league_id and s.numero = g.stagione_corrente
    join public.fixtures fx on fx.season_id = s.id and fx.stato = 'simulata'
      and fx.giornata >= g.inizio
      and (fx.home_team_id = g.team_id or fx.away_team_id = g.team_id)
    where not exists (select 1 from private.assenze_partita a
                      where a.fixture_id = fx.id and a.player_instance_id = g.id)
      -- Prestiti (Season 3): le giornate passate in prestito non contano.
      and not exists (select 1 from public.prestiti pr
                      where pr.player_instance_id = g.id and pr.stagione = g.stagione_corrente
                        and fx.giornata >= pr.giornata_inizio and (pr.giornata_fine is null or fx.giornata < pr.giornata_fine))
  )
  select (select count(*) from f)::integer,
         coalesce((select sum(ms.minuti) from public.match_stats ms
                   join public.matches m on m.id = ms.match_id
                   join f on f.fixture_id = m.fixture_id
                   join g on true
                   where ms.player_instance_id = g.id and ms.team_id = g.team_id), 0)::numeric;
$function$;

CREATE OR REPLACE FUNCTION private.morale_giornaliero(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_stagione_id bigint;
  v_quarto numeric;
  v_aggiornati integer := 0;
  v_fuori_ruolo integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_esatto numeric;
  v_nuovo smallint;
  v_raw_min numeric;
  v_raw_eco numeric;
  v_f_min numeric;
  v_f_eco numeric;
  v_f_vit numeric;
  v_f_con numeric;
  v_w_eco numeric;
  v_w_vit numeric;
  v_w_con numeric;
  v_p numeric;
  v_n numeric;
  v_pesi numeric;
  v_anni numeric;
  c_pavimento constant numeric := 40;  -- sotto questo morale i fattori negativi non spingono piu' in giu'
  c_quota constant numeric := 0.25;    -- quota della distanza recuperata a ogni giornata
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('morale_giornaliero', false, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;
  v_quarto := greatest(1, ceil(v_lega.giornate_totali::numeric / 4.0));

  -- Una sola volta per giornata, anche se la simulazione venisse rilanciata.
  insert into private.morale_giornaliero(season_id, giornata, league_id)
  values (v_stagione_id, p_giornata, p_league_id)
  on conflict (season_id, giornata) do nothing;
  if not found then
    return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', 0);
  end if;

  -- Il pubblico vive i risultati (Season 3, diario §6): in casa vittoria +4, pareggio -1, sconfitta -4;
  -- in trasferta la meta'. Nei derby (rivalita' oltre 90 o rivale dichiarato, come nelle conferenze stampa)
  -- l'effetto raddoppia, al posto del vecchio bonus in proporzione al grado.
  update public.teams t
     set pubblico = greatest(0, least(100, t.pubblico + x.delta))
    from (
      select q.team_id, sum(q.delta * case when q.derby then 2 else 1 end) as delta
      from (
        select f.home_team_id as team_id,
               case when m.gol_home > m.gol_away then 4 when m.gol_home < m.gol_away then -4 else -1 end as delta,
               private.e_derby(f.league_id, f.home_team_id, f.away_team_id) as derby
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
        union all
        select f.away_team_id,
               case when m.gol_away > m.gol_home then 2 when m.gol_away < m.gol_home then -2 else -0.5 end,
               private.e_derby(f.league_id, f.home_team_id, f.away_team_id)
          from public.fixtures f join public.matches m on m.fixture_id = f.id
         where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
      ) q
      group by q.team_id
    ) x
   where t.id = x.team_id;

  -- Le rivalita': negli scontri diretti fra squadre rivali chi vince guadagna un po' di morale
  -- e chi perde ne perde (fino a +-4 a rivalita' 100%, in proporzione al grado); il pubblico dei derby
  -- e' gia' raddoppiato sopra. Poi la rivalita' si raffredda di 1 punto a giornata. Una sola
  -- applicazione per giornata (la guardia e' sopra).
  with scontri as (
    select f.home_team_id, f.away_team_id, m.gol_home, m.gol_away, r.grado
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    join public.rivalita r on r.league_id = f.league_id
     and r.team_a = least(f.home_team_id, f.away_team_id) and r.team_b = greatest(f.home_team_id, f.away_team_id)
    where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata' and r.grado > 0
  ), esiti as (
    select case when gol_home > gol_away then home_team_id else away_team_id end as vincente,
           case when gol_home > gol_away then away_team_id else home_team_id end as perdente, grado
    from scontri where gol_home <> gol_away
  ), effetti as (
    select vincente as team_id, 4 * grado / 100.0 as morale from esiti
    union all
    select perdente, -4 * grado / 100.0 from esiti
  )
  update public.player_instances pi
     set morale = greatest(0, least(100,
           floor(pi.morale + e.morale) + case when random() < (pi.morale + e.morale) - floor(pi.morale + e.morale) then 1 else 0 end))::smallint
    from (select team_id, sum(morale) as morale from effetti group by team_id) e
   where pi.team_id = e.team_id and not pi.ritirato and pi.prestito_id is null;

  -- Scontri diretti ACCESI: la rivalita' nasce e cresce anche sul campo. Un'espulsione (rosso diretto o doppio
  -- giallo) vale +6; un gol decisivo dal 85' in poi (partita finita con un solo gol di scarto, segnato dalla
  -- vincente) vale +4; le due cose insieme +10. Vale per qualsiasi coppia di squadre, anche senza una rivalita' prima.
  perform private.sposta_rivalita(a.league_id, a.home_team_id, a.away_team_id,
            (case when a.rosso then 6 else 0 end) + (case when a.finale_decisivo then 4 else 0 end))
  from (
    select f.league_id, f.home_team_id, f.away_team_id,
           exists (select 1 from jsonb_array_elements(m.blocchi) e where e->>'tipo' = 'cartellino' and e->>'colore' in ('rosso_diretto', 'doppio_giallo')) as rosso,
           abs(m.gol_home - m.gol_away) = 1 and exists (
             select 1 from jsonb_array_elements(m.blocchi) e
              where e->>'tipo' = 'gol' and (e->>'minuto')::int >= 85
                and e->>'lato' = case when m.gol_home > m.gol_away then 'casa' else 'ospite' end) as finale_decisivo
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata' and f.campo_neutro is not true
  ) a
  where a.rosso or a.finale_decisivo;

  update public.rivalita r set grado = greatest((case when exists (select 1 from public.teams t where (t.id = r.team_a and t.rivale_id = r.team_b) or (t.id = r.team_b and t.rivale_id = r.team_a)) then 91 else 0 end), grado - 1), aggiornata_il = now()
   where r.league_id = p_league_id and r.grado > 0;

  -- Il capitano effettivo e la sua forza si calcolano UNA volta per squadra (prima erano ricalcolati tre volte per
  -- ogni giocatore: ~11 secondi in una lega da 16 squadre, oltre il limite di 8 s delle chiamate).
  for v_giocatore in
    with cap as materialized (
      select t2.id as team_id, c.cap_id,
             case when c.cap_id is null or not l2.tattiche_attive then 0 else private.qualita_capitano(c.cap_id) end as forza
        from public.teams t2
        join public.leagues l2 on l2.id = t2.league_id
        cross join lateral (select coalesce(t2.capitano, case when l2.conferenze_stampa then private.capitano_automatico(t2.id) end) as cap_id) c
       where t2.league_id = p_league_id and t2.attiva
    )
    select
      pi.id,
      pi.morale,
      pi.ingaggio,
      pi.overall_corrente,
      pi.eta_corrente,
      pi.team_id,
      pi.contratto_scadenza,
      private.stagione_contratto(pi.league_id) as stagione_contratto,
      -- Capitano effettivo: quello designato oppure, nelle leghe con il capitano a requisiti
      -- (conferenze_stampa), il piu' idoneo. Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
      -- un capitano, o se il capitano e' quello che si sta valutando: chi
      -- porta la fascia non consola se stesso.
      case when cap.cap_id is null or cap.cap_id = pi.id then 0 else cap.forza end as forza_capitano,
      p.mentalita_bandiera,
      p.mentalita_economia,
      p.mentalita_vittorie,
      pi.minutaggio_promesso,
      l.tattiche_attive as tattiche,
      -- media overall della propria rosa: e' il metro con cui il giocatore
      -- giudica quanto dovrebbe giocare
      (select avg(x.overall_corrente)
         from public.player_instances x
        where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
      -- quota di minuti effettivamente giocati sulle giornate disputate
      coalesce((select ms.minuti from private.minuti_stagione(pi.id) ms), 0) as minuti_giocati,
      coalesce((select ms.partite from private.minuti_stagione(pi.id) ms), 0) as giornate_disputate,
      coalesce((select st.posizione
                  from public.standings st
                 where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione,
        coalesce(private.squadre_nel_gruppo(v_stagione_id, pi.team_id), v_lega.n_squadre) as n_gruppo
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    join cap on cap.team_id = pi.team_id
    join public.leagues l on l.id = pi.league_id
    where pi.league_id = p_league_id and not pi.ritirato and pi.prestito_id is null
    order by pi.id
    for update of pi
  loop
    -- MODELLO A FATTORI (18 ottobre 2026, deciso con il committente). Ogni giornata si guarda quanto ogni fattore e'
    -- rispettato ADESSO, da -1 (molto contro) a +1 (molto a favore), pesato dal carattere del giocatore. Il morale sale
    -- in proporzione ai fattori a favore e scende SOLO in proporzione a quelli contro.

    -- 1. Minutaggio (peso 1 per tutti). Asimmetrico di proposito: giocare meno del previsto delude piu' di quanto
    --    giocare tanto gratifichi. Con meno di 3 partite giocabili non pesa (neutro).
    v_raw_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
      ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
        - case when v_giocatore.tattiche
            then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
            else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
      ) * 30
    )) end;
    -- Promessa trattata e non mantenuta: pesa il 50% in piu' (docs/decisioni-minutaggio.md, punto 4).
    if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_raw_min < 0 then
      v_raw_min := greatest(-18, v_raw_min * 1.5);
    end if;
    v_f_min := case when v_raw_min >= 0 then v_raw_min / 8.0 else greatest(-1, v_raw_min / 12.0) end;

    -- 2. Stipendio, peso = mentalita economia / 33.
    v_raw_eco := greatest(-10, least(6,
      ((v_giocatore.ingaggio::numeric
        / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20));
    v_f_eco := case when v_raw_eco >= 0 then v_raw_eco / 6.0 else v_raw_eco / 10.0 end;
    v_w_eco := v_giocatore.mentalita_economia / 33.0;

    -- 3. Vittorie: posizione nel proprio gruppo (conferenza), 1a = +1, ultima = -1. Peso = mentalita vittorie / 33.
    v_f_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_giocatore.n_gruppo - 1))) * 2;
    v_w_vit := v_giocatore.mentalita_vittorie / 33.0;

    -- 4. Contratto: in scadenza a fine stagione = insicurezza (-0,5), un anno ancora = neutro, due o piu' = sicurezza (+0,3).
    --    Peso = mentalita bandiera / 33 (a chi tiene alla maglia la stabilita' conta di piu').
    v_anni := coalesce(v_giocatore.contratto_scadenza, v_giocatore.stagione_contratto) - coalesce(v_giocatore.stagione_contratto, 0);
    v_f_con := case when v_anni <= 0 then -0.5 when v_anni = 1 then 0 else 0.3 end;
    v_w_con := v_giocatore.mentalita_bandiera / 33.0;

    -- I fattori negativi sono attenuati dalla bandiera e dal capitano (come prima): un bandiera 60 assorbe il 30%
    -- del malcontento; un trascinatore fino al 30%, un capitano scontento lo peggiora.
    v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);
    v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);
    if v_f_min < 0 then v_f_min := v_f_min * v_attenuazione * v_att_capitano; end if;
    if v_f_eco < 0 then v_f_eco := v_f_eco * v_attenuazione * v_att_capitano; end if;
    if v_f_vit < 0 then v_f_vit := v_f_vit * v_attenuazione * v_att_capitano; end if;
    if v_f_con < 0 then v_f_con := v_f_con * v_attenuazione * v_att_capitano; end if;

    -- Quanto i fattori a favore (P) e quelli contro (N) pesano, da 0 a 1, sul totale dei pesi. Il morale SALE verso 100
    -- in proporzione a P e SCENDE verso il pavimento in proporzione a N: senza nessun fattore negativo (N = 0) non
    -- scende mai, per quanto alto sia; senza fattori a favore (P = 0) non sale. Un giocatore perde morale solo se
    -- c'e' davvero qualcosa che glielo fa perdere.
    v_pesi := greatest(0.01, 1.0 + v_w_eco + v_w_vit + v_w_con);
    v_p := (greatest(0, v_f_min) + v_w_eco * greatest(0, v_f_eco) + v_w_vit * greatest(0, v_f_vit) + v_w_con * greatest(0, v_f_con)) / v_pesi;
    v_n := (greatest(0, -v_f_min) + v_w_eco * greatest(0, -v_f_eco) + v_w_vit * greatest(0, -v_f_vit) + v_w_con * greatest(0, -v_f_con)) / v_pesi;

    -- L'arrotondamento a sorte conserva la media (come prima).
    v_esatto := v_giocatore.morale
      + c_quota * (v_p * (100 - v_giocatore.morale) - v_n * greatest(0, v_giocatore.morale - c_pavimento));
    v_nuovo := greatest(0, least(100,
      floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;

    update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
    v_aggiornati := v_aggiornati + 1;
  end loop;

  -- FUORI RUOLO (24/10/2026): titolari schierati in un reparto non loro, scesi davvero in campo in questa giornata.
  -- Reparto vicino -8, reparto lontano -25, fino a un minimo di 10 (chi e' gia' sotto 10 non risale per questo).
  with partite as (
    select f.home_team_id as team_id, f.giornata, m.titolari_home as in_campo
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
    union all
    select f.away_team_id, f.giornata, m.titolari_away
      from public.fixtures f join public.matches m on m.fixture_id = f.id
     where f.season_id = v_stagione_id and f.giornata = p_giornata and f.stato = 'simulata'
  ), cali as (
    select x.id as player_id,
           private.calo_morale_fuori_ruolo(coalesce(pi.posizioni_override, p.posizioni),
                                           (coalesce(l.disposizione, private.disposizione_standard(l.modulo)))[x.k]) as calo
      from partite pa
      join public.lineups l on l.team_id = pa.team_id and l.giornata = pa.giornata and l.league_id = p_league_id
      cross join lateral unnest(l.titolari) with ordinality as x(id, k)
      join public.player_instances pi on pi.id = x.id
      join public.players p on p.id = pi.player_id
     where x.k between 2 and 11 and x.id = any(pa.in_campo)
  )
  update public.player_instances pi
     set morale = least(pi.morale, greatest(10, pi.morale - c.calo))::smallint
    from cali c
   where pi.id = c.player_id and c.calo > 0;
  get diagnostics v_fuori_ruolo = row_count;

  return jsonb_build_object('morale_giornaliero', true, 'giocatori_aggiornati', v_aggiornati, 'cali_fuori_ruolo', v_fuori_ruolo);
end;
$function$;

CREATE OR REPLACE FUNCTION public.applica_morale_checkpoint(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_aggiornati integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_nuovo smallint;
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;

  -- Leghe con il morale a ogni giornata (conferenze_stampa): niente quarti.
  if (select l.conferenze_stampa from public.leagues l where l.id = p_league_id) then
    return private.morale_giornaliero(p_league_id, p_giornata) || jsonb_build_object('checkpoint_applicato', null);
  end if;

  -- Stessa scansione della progressione overall: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_morale_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_stagione_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    for v_giocatore in
      select
        pi.id,
        pi.morale,
        pi.ingaggio,
        pi.overall_corrente,
        pi.eta_corrente,
        pi.team_id,
        -- Capitano effettivo: quello designato oppure, nelle leghe con il capitano a requisiti
        -- (conferenze_stampa), il piu' idoneo. Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
        -- un capitano, o se il capitano e' quello che si sta valutando: chi
        -- porta la fascia non consola se stesso.
        case when coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) is null or coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) = pi.id then 0
             when not l.tattiche_attive then 0
             else private.qualita_capitano(coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end)) end as forza_capitano,
        p.mentalita_bandiera,
        p.mentalita_economia,
        p.mentalita_vittorie,
        pi.minutaggio_promesso,
        l.tattiche_attive as tattiche,
        -- media overall della propria rosa: e' il metro con cui il giocatore
        -- giudica quanto dovrebbe giocare
        (select avg(x.overall_corrente)
           from public.player_instances x
          where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
        -- quota di minuti effettivamente giocati sulle giornate disputate
        coalesce((select ms.minuti from private.minuti_stagione(pi.id) ms), 0) as minuti_giocati,
        coalesce((select ms.partite from private.minuti_stagione(pi.id) ms), 0) as giornate_disputate,
        coalesce((select st.posizione
                    from public.standings st
                   where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione,
        coalesce(private.squadre_nel_gruppo(v_stagione_id, pi.team_id), v_lega.n_squadre) as n_gruppo
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      join public.leagues l on l.id = pi.league_id
      where pi.league_id = p_league_id and not pi.ritirato and pi.prestito_id is null
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      -- Dall'arrivo in squadra, solo stagione corrente, senza le partite da
      -- assente; con meno di 3 partite giocabili la voce non pesa.
      v_delta_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - case when v_giocatore.tattiche
              then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
              else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
        ) * 30
      )) end;

      -- Promessa trattata e non mantenuta: pesa il 50% in piu'
      -- (docs/decisioni-minutaggio.md, punto 4).
      if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_delta_min < 0 then
        v_delta_min := greatest(-18, v_delta_min * 1.5);
      end if;

      -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
      v_delta_eco := greatest(-10, least(6,
        ((v_giocatore.ingaggio::numeric
          / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
      )) * (v_giocatore.mentalita_economia / 33.0);

      -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
      v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_giocatore.n_gruppo - 1)))
        * 16 * (v_giocatore.mentalita_vittorie / 33.0);

      -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
      --    Un bandiera 60 assorbe il 30% del malcontento.
      v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

      -- 5. Il capitano. In Football Manager la fascia agisce sullo spogliatoio
      --    nel tempo, non sui novanta minuti: e' qui che deve pesare, non nel
      --    motore. Un trascinatore assorbe fino al 30% del malcontento dei
      --    compagni; un capitano scontento lo peggiora, perche' la qualita' va
      --    anche sotto zero. Si moltiplica con l'attenuazione da bandiera
      --    invece di sommarsi: sono due modi diversi di reggere lo stesso colpo,
      --    e sommandoli un bandiera capitano sarebbe diventato immune.
      v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);

      v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
      v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit))
                    * v_attenuazione * v_att_capitano;

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;

$function$;

CREATE OR REPLACE FUNCTION private.controlla_minutaggio(p_league_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_ultima smallint;
  v_controllo smallint;
  v_g record;
  v_partite integer;
  v_minuti numeric;
  v_reale numeric;
  v_attesa numeric;
  v_soglia numeric;
  v_messaggi integer := 0;
  v_nome_gradino text;
  v_gradino text;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione' and l.tattiche_attive;
  if not found then return 0; end if;

  select max(f.giornata) into v_ultima
  from public.fixtures f
  where f.season_id = v_lega.season_id and f.stato = 'simulata' and f.giornata <= v_lega.giornate_totali;
  if v_ultima is null or v_ultima < 8 then return 0; end if;

  v_controllo := (8 + ((v_ultima - 8) / 5) * 5)::smallint;
  insert into private.minutaggio_controlli (season_id, giornata)
  values (v_lega.season_id, v_controllo)
  on conflict do nothing;
  if not found then return 0; end if;

  for v_g in
    select pi.id, pi.team_id, pi.richiamo_stagione, pi.morale, t.user_id, p.nome
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id
      and not pi.ritirato and not pi.ritiro_annunciato
      and pi.richiesta_cessione_stagione is null
      and pi.prestito_id is null
      and t.user_id is not null and not coalesce(t.controllata_da_pc, false)
    order by pi.id
    for update of pi
  loop
    select ms.partite, ms.minuti into v_partite, v_minuti from private.minuti_stagione(v_g.id) ms;
    -- Con meno di 5 partite giocabili non c'e' abbastanza campione.
    if v_partite < 5 then continue; end if;

    -- Dall'8 ottobre 2026 il giocatore scrive quando il MORALE scende sotto 30 (non piu' solo per i minuti):
    -- il morale contiene gia' minutaggio, ingaggio e classifica. Al controllo dopo, se e' ancora sotto, chiede
    -- la cessione; se e' risalito, il richiamo si cancella.
    if v_g.morale < 30 then
      if v_g.richiamo_stagione = v_lega.stagione_corrente then
        update public.player_instances
        set richiesta_cessione_stagione = v_lega.stagione_corrente
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' chiede la cessione', 80),
          'Mister, la mia situazione non è cambiata: chiedo la cessione. Non rinnoverò il contratto.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'cessione_morale'));
      else
        update public.player_instances
        set richiamo_stagione = v_lega.stagione_corrente, richiamo_giornata = v_controllo
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' non è soddisfatto', 80),
          'Salve mister, volevo dirle che non sono soddisfatto del mio impiego e credo di meritare di meglio. '
            || 'Le chiedo di prendere provvedimenti, altrimenti sarò costretto a richiedere la cessione.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'richiamo_morale'));
      end if;
      v_messaggi := v_messaggi + 1;
    elsif v_g.richiamo_stagione = v_lega.stagione_corrente then
      update public.player_instances
      set richiamo_stagione = null, richiamo_giornata = null
      where id = v_g.id;
    end if;
  end loop;

  return v_messaggi;
end;
$function$;

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text, p_linea text DEFAULT NULL::text, p_ampiezza text DEFAULT NULL::text, p_portiere text DEFAULT NULL::text, p_velocita text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_i integer;
  v_std text[];
  v_schema text[];
  v_league public.leagues;
  v_team public.teams;
  v_all bigint[];
  v_convocati bigint[];
  v_rosa_count integer;
  v_unique_count integer;
  v_gk_disp integer;
  v_mov_disp integer;
  v_primo_gk boolean;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare la formazione.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La stagione non e'' ancora iniziata.';
  end if;
  -- Playoff e playout vivono a giornate OLTRE la stagione regolare (con 16
  -- squadre: regolare fino alla 30, playoff 31 e 32), quindi il confronto
  -- con giornate_totali da solo rendeva impossibile schierare la formazione
  -- proprio nelle partite decisive. Si accetta anche una giornata piu' alta,
  -- purche' esista davvero come turno di questa stagione.
  if p_giornata < 1 or (
    p_giornata > v_league.giornate_totali
    and not exists (
      select 1
      from public.fixtures f
      join public.seasons s on s.id = f.season_id
      where s.league_id = p_league_id
        and s.numero = v_league.stagione_corrente
        and f.giornata = p_giornata
    )
  ) then
    raise exception using errcode = '22023', message = 'Giornata non valida per questa lega.';
  end if;
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_gioco = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  -- Schema personalizzato: gli undici slot davvero schierati. NULL = lo
  -- schieramento standard del modulo, cioe' il comportamento di sempre.
  -- Ogni posizione puo' solo salire o scendere di una linea sulla propria
  -- corsia (private.spostamenti_slot), quindi da qui non puo' uscire uno
  -- schieramento che il motore non sa valutare.
  -- A interruttore spento lo schema personalizzato non si scrive nemmeno.
  -- Non e' pignoleria: la familiarita' e' indicizzata SULLO SCHIERAMENTO
  -- (formation_xp.disposizione), quindi salvare una variante che il motore
  -- ignora creerebbe un contatore per una forma mai davvero giocata, e la
  -- barra racconterebbe una storia falsa. Chi salva senza saperlo non riceve
  -- un errore: gli si ignorano i tre campi, come se non li avesse mandati.
  if not (select l.tattiche_attive from public.leagues l where l.id = p_league_id) then
    p_disposizione := null;
    p_ruoli := null;
    p_compiti := null;
    p_focus_corsia := null;
    p_linea := null;
    p_ampiezza := null;
    p_velocita := null;
    p_portiere := null;
  end if;

  -- Dove si attacca. NULL = da nessuna parte in particolare, ed e' una scelta
  -- come le altre: concentrare su una corsia paga se l'avversario la' e'
  -- scoperto e costa se e' il suo lato forte (engine/corsie.js).
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX','FASCE') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;

  -- Indicazioni di squadra (registro tattico, punto 30). NULL = l'opzione
  -- predefinita: linea media, ampiezza normale, portiere normale.
  if p_linea is not null and p_linea not in ('alta','bassa') then
    raise exception using errcode = '22023', message = 'Linea difensiva non valida.';
  end if;
  if p_ampiezza is not null and p_ampiezza not in ('larga','stretta') then
    raise exception using errcode = '22023', message = 'Ampiezza non valida.';
  end if;
  if p_velocita is not null and p_velocita not in ('ragionata','veloce') then
    raise exception using errcode = '22023', message = 'Velocita'' di manovra non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  if p_disposizione is not null then
    if cardinality(p_disposizione) <> 11 then
      raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
    end if;
    v_std := private.disposizione_standard(p_modulo);
    if v_std is null then
      raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
    end if;
    for v_i in 1..11 loop
      if not (p_disposizione[v_i] = any(private.spostamenti_slot(v_std[v_i]))) then
        raise exception using errcode = '22023',
          message = format('La posizione %s non puo'' diventare %s.', v_std[v_i], p_disposizione[v_i]);
      end if;
    end loop;
  if not private.disposizione_simmetrica(p_disposizione) then
    raise exception using errcode = '22023',
      message = 'Schema non valido: un terzino, un esterno di centrocampo o un''ala non possono esistere solo a destra o solo a sinistra.';
  end if;
  end if;

  v_schema := coalesce(p_disposizione, private.disposizione_standard(p_modulo));

  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(v_schema[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], v_schema[v_i]);
      end if;
    end loop;
  end if;

  if p_compiti is not null then
    if cardinality(p_compiti) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 compiti, uno per posizione.';
    end if;
    if exists (select 1 from unnest(p_compiti) c where c is not null and c not in ('difesa','equilibrio','attacco')) then
      raise exception using errcode = '22023', message = 'Compito non valido.';
    end if;
  end if;

  if coalesce(cardinality(p_titolari), 0) <> 11 then
    raise exception using errcode = '22023', message = 'Servono esattamente 11 titolari.';
  end if;
  if coalesce(cardinality(p_panchina), 0) > 9 then
    raise exception using errcode = '22023', message = 'La panchina puo'' contenere al massimo 9 giocatori.';
  end if;
  if p_titolari[1] is null then
    raise exception using errcode = '22023', message = 'Il primo slot deve contenere il portiere, anche se di movimento.';
  end if;
  if array_position(p_titolari, null) is not null
     or array_position(p_panchina, null) is not null
     or array_position(p_tribuna, null) is not null then
    raise exception using errcode = '22023', message = 'La formazione contiene uno slot vuoto non valido.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  -- Prestiti (Season 3): chi e' in prestito non si schiera; dalla tribuna si toglie da solo.
  if exists (select 1 from public.player_instances pi
             where pi.id = any(p_titolari || coalesce(p_panchina, '{}'::bigint[])) and pi.prestito_id is not null) then
    raise exception using errcode = '22023', message = 'Un giocatore della formazione è in prestito.';
  end if;
  p_tribuna := array(select x from unnest(coalesce(p_tribuna, '{}'::bigint[])) with ordinality as t(x, o)
                     where not exists (select 1 from public.player_instances pi where pi.id = x and pi.prestito_id is not null)
                     order by o);
  v_all := p_titolari || coalesce(p_panchina, '{}'::bigint[]) || coalesce(p_tribuna, '{}'::bigint[]);
  v_unique_count := (select count(distinct id)::integer from unnest(v_all) as u(id));
  if v_unique_count <> cardinality(v_all) then
    raise exception using errcode = '22023', message = 'Lo stesso giocatore compare piu'' volte nella formazione.';
  end if;

  select count(*) into v_rosa_count
  from public.player_instances
  where league_id = p_league_id and team_id = v_team.id and id = any(v_all);
  if v_rosa_count <> cardinality(v_all) then
    raise exception using errcode = '42501', message = 'La formazione contiene un giocatore fuori dalla tua rosa.';
  end if;

  v_convocati := p_titolari || coalesce(p_panchina, '{}'::bigint[]);
  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and team_id = v_team.id
      and id = any(v_convocati) and infortunato_fino_a > 0
  ) then
    raise exception using errcode = '22023', message = 'Un giocatore infortunato non puo'' essere titolare o andare in panchina. Spostalo in tribuna.';
  end if;

  -- Portiere vero in porta, niente portieri fra i dieci di movimento (eccezioni: nessun portiere disponibile,
  -- o meno di 10 giocatori di movimento disponibili).
  select count(*) filter (where 'GK' = any(coalesce(pi.posizioni_override, p.posizioni))),
         count(*) filter (where not ('GK' = any(coalesce(pi.posizioni_override, p.posizioni))))
    into v_gk_disp, v_mov_disp
    from public.player_instances pi join public.players p on p.id = pi.player_id
   where pi.league_id = p_league_id and pi.team_id = v_team.id and not coalesce(pi.ritirato, false)
     and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0;
  select 'GK' = any(coalesce(pi.posizioni_override, p.posizioni)) into v_primo_gk
    from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = p_titolari[1];
  if not coalesce(v_primo_gk, false) and v_gk_disp > 0 then
    raise exception using errcode = '22023', message = 'In porta deve giocare un portiere: ne hai disponibili in rosa.';
  end if;
  if v_mov_disp >= 10 and exists (
    select 1 from unnest(p_titolari[2:11]) as u(id)
      join public.player_instances pi on pi.id = u.id join public.players p on p.id = pi.player_id
     where 'GK' = any(coalesce(pi.posizioni_override, p.posizioni))
  ) then
    raise exception using errcode = '22023', message = 'Un portiere non puo'' giocare fuori dai pali: mettilo in porta, in panchina o in tribuna.';
  end if;

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il,
    disposizione, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, velocita_manovra, ruolo_portiere
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now(),
    p_disposizione, p_ruoli, p_compiti, p_focus_corsia, p_linea, p_ampiezza, p_velocita, p_portiere
  )
  on conflict (team_id, giornata) do update set
    modulo = excluded.modulo,
    titolari = excluded.titolari,
    panchina = excluded.panchina,
    tribuna = excluded.tribuna,
    stile_gioco = excluded.stile_gioco,
    automatica = false,
    salvata_il = now(),
    disposizione = excluded.disposizione,
    ruoli = excluded.ruoli,
    compiti = excluded.compiti,
    focus_corsia = excluded.focus_corsia,
    linea_difensiva = excluded.linea_difensiva,
    ampiezza = excluded.ampiezza,
    velocita_manovra = excluded.velocita_manovra,
    ruolo_portiere = excluded.ruolo_portiere;

  -- Chi batte piazzati e rigori: assegnato in automatico, e ricontrollato a
  -- ogni salvataggio. Un incarico sopravvive solo se quel giocatore e' ancora
  -- fra i titolari; altrimenti passa al migliore disponibile. Chi vuole lo
  -- cambia dopo, dalla stessa pagina.
  perform private.sistema_incaricati(v_team.id, p_giornata);

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', v_team.id,
    'giornata', p_giornata,
    'modulo', p_modulo,
    'stile_gioco', p_stile_gioco,
    'disposizione', p_disposizione,
    'ruoli', p_ruoli,
    'compiti', p_compiti,
    'focus_corsia', p_focus_corsia,
    'linea_difensiva', p_linea,
    'ampiezza', p_ampiezza,
    'velocita_manovra', p_velocita,
    'ruolo_portiere', p_portiere,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.applica_progressione_trimestrale(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_stagione_id bigint;
  v_player record;
  v_delta numeric;
  v_moltiplicatore numeric;
  v_valore numeric;
  v_ovr smallint;
  v_residuo numeric;
  v_giocatori_aggiornati integer := 0;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    raise exception using errcode = '55000', message = 'Non esiste una stagione in corso per la progressione overall.';
  end if;
  if p_giornata < 1 then
    raise exception using errcode = '22023', message = 'Giornata non valida per la progressione overall.';
  end if;
  v_stagione_id := v_lega.season_id;

  -- 10 settembre 2026, richiesta dell'utente: da qui non si aggiorna piu'
  -- una volta a quarto di stagione ma una volta per ogni giornata REALE
  -- (giornate_totali quote invece di 4), cosi' il badge di crescita nella
  -- rosa si muove sera dopo sera invece che a scatti ogni ~7-8 giornate.
  -- La formula annuale e le fasce d'eta' restano identiche: cambia solo il
  -- denominatore, da 4.0 a giornate_totali, e la cadenza con cui viene
  -- consumata. La tabella dei checkpoint resta la stessa
  -- (season_progression_checkpoints): la chiave "checkpoint" prima era il
  -- numero del quarto (1-4), ora e' il numero della giornata. Nessuna
  -- collisione possibile con i quarti gia' registrati per le stagioni in
  -- corso: la UNIQUE e' per (season_id, checkpoint), e una giornata gia'
  -- passata (dove viveva un vecchio "1", "2", "3" o "4") non torna mai
  -- indietro. Le prime giornate di ogni stagione gia' avviata hanno quindi
  -- ricevuto la crescita del vecchio schema in un'unica soluzione grossa
  -- (al raggiungimento del quarto), quelle successive la ricevono a fette
  -- quotidiane: e' una cucitura visibile una tantum nel passaggio, non un
  -- bug — la stagione non riparte e non raddoppia nulla.
  --
  -- Le giornate di playoff/playout stanno OLTRE la stagione regolare: la
  -- crescita annua e' distribuita per intero sulle giornate_totali della
  -- stagione regolare, quindi oltre quel punto non c'e' piu' nulla da
  -- applicare (senza questo controllo, il cron notturno che chiama questa
  -- funzione anche in playoff avrebbe provato a scrivere un checkpoint per
  -- giornate che non esistono nel monte crescita della stagione).
  -- 27/10/2026: niente piu' stop oltre giornate_totali. Nei playoff ogni giornata applica la stessa quota giornaliera
  -- (il denominatore resta giornate_totali): i giocatori si allenano anche nei playoff, al solito ritmo.

  insert into public.season_progression_checkpoints(league_id, season_id, checkpoint, giornata)
  values (p_league_id, v_stagione_id, p_giornata, p_giornata)
  on conflict (season_id, checkpoint) do nothing;
  if not found then
    -- Questa giornata ha gia' ricevuto la sua crescita: il cron puo'
    -- rientrare piu' volte sullo stesso invio (ritentativi), qui si ferma
    -- senza rifare nulla.
    return jsonb_build_object('checkpoint_applicati', array[]::smallint[], 'giocatori_aggiornati', 0);
  end if;

  -- Chi ha (o ha avuto) una squadra: player_instances. NESSUN join sulla
    -- squadra attiva (deciso il 30 agosto 2026): uno svincolato reale
    -- (team_id nullo) evolve esattamente come chi gioca, solo al ritmo
    -- minimo perche' minuti_giocati resta 0. Uno svincolato non ha un
    -- moltiplicatore_training (nessuna squadra): coalesce a 1.
    for v_player in
      select
        pi.id, pi.overall_corrente, pi.eta_corrente, pi.progressione_residuo, p.potential, p.origine_vivaio,
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        -- Prestiti (Season 3): le giornate passate in prestito non contano nel minutaggio.
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id)
                        and not exists (select 1 from public.prestiti pr
                                        where pr.player_instance_id = pi.id and pr.stagione = v_lega.stagione_corrente
                                          and f.giornata >= pr.giornata_inizio
                                          and (pr.giornata_fine is null or f.giornata < pr.giornata_fine)))) as giornate_disputate,
        case when pi.prestito_id is not null
          then (private.effetti_ramo('training', 5::smallint)->>'moltiplicatore_crescita')::numeric
          else coalesce((
            select (private.effetti_ramo('training', tr.livello_training)->>'moltiplicatore_crescita')::numeric
            from public.team_risorse tr
            where tr.team_id = pi.team_id
          ), 1) end as moltiplicatore_training,
        pi.prestito_id
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- Pavimento standard: 0.8x a zero minuti, 1.4x a minutaggio pieno.
      v_moltiplicatore := 0.8 + 0.6 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));

      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / v_lega.giornate_totali::numeric;
        if v_player.origine_vivaio and v_player.eta_corrente < 17 then
          -- Appena usciti dall'academy: ritmo fisso, ne' premiato ne'
          -- penalizzato dal minutaggio, finche' non compiono 17 anni. A
          -- quindici anni non si gioca, e misurare un ragazzino sui minuti
          -- sarebbe solo un modo elaborato di punirlo.
          --
          -- 1.3 e NON 1.0, che era il valore precedente. Con 1.0 il biennio
          -- 15-16 anni era una zona morta: si cresceva meno che nel vivaio E
          -- meno di un diciassettenne che gioca. Misurato su Pablo Hansen
          -- (Serie F, 15 anni, margine 34): 0,340 punti al giorno da promosso
          -- contro 0,595 che avrebbe avuto restando in cantera — il 57%.
          -- Promuovere un prodigio era un declassamento della crescita, il che
          -- e' esattamente il contrario di quello che deve essere.
          --
          -- 1.3 chiude quasi tutto il divario col vivaio senza superarlo: il
          -- vivaio resta il posto dove si cresce piu' in fretta finche' il
          -- margine e' grande, ed e' giusto cosi'. Vedi la nota in fondo alla
          -- migrazione per i numeri.
          v_moltiplicatore := 1.3;
        else
          -- <=22 anni ma non piu' "appena usciti dal vivaio" (o mai stati
          -- in vivaio): pavimento 0.85, non 0.8 — il minutaggio conta
          -- ancora davvero, solo un po' meno spietato per chi e' in
          -- panchina dietro un titolare fisso.
          v_moltiplicatore := 0.85 + 0.55 * least(1.0, v_player.minuti_giocati / (90.0 * v_player.giornate_disputate));
        end if;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / v_lega.giornate_totali::numeric;
      else
        v_delta := -(1.5 + random() * 2.5) / v_lega.giornate_totali::numeric;
      end if;

      -- In prestito gioca come chi ha il 60% dei minuti (i prodigi appena usciti dal vivaio tengono il loro ritmo).
      if v_player.prestito_id is not null and not (v_player.origine_vivaio and v_player.eta_corrente < 17) then
        v_moltiplicatore := case when v_player.eta_corrente <= 22 then 0.85 + 0.55 * 0.6 else 0.8 + 0.6 * 0.6 end;
      end if;

      v_delta := v_delta * v_moltiplicatore;

      -- TRAINING allena, non fa invecchiare piu' in fretta: il bonus vale
      -- solo sulla crescita vera, mai sul declino.
      if v_delta > 0 then
        v_delta := v_delta * v_player.moltiplicatore_training;
      end if;

      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.player_instances
      set overall_corrente = v_ovr, progressione_residuo = v_residuo
      where id = v_player.id;
      v_giocatori_aggiornati := v_giocatori_aggiornati + 1;
    end loop;

    -- Chi non e' mai stato scelto in questa lega: free_agent_progression.
    -- Stessa formula per fascia d'eta' e stesso residuo frazionario di
    -- player_instances (senza, un delta minuscolo arrotondava a zero ogni
    -- trimestre e andava perso). Moltiplicatore fisso al minimo (0.8): non
    -- hanno mai la possibilita' di giocare un minuto, quindi restano
    -- sempre alla velocita' piu' bassa della curva, mai a zero. Nessun
    -- bonus TRAINING: non hanno una squadra.
    for v_player in
      select fap.league_id, fap.player_id, fap.overall_corrente, fap.eta_corrente,
             fap.progressione_residuo, p.potential
      from public.free_agent_progression fap
      join public.players p on p.id = fap.player_id
      where fap.league_id = p_league_id
      for update of fap
    loop
      if v_player.eta_corrente <= 22 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.15 + random() * 0.30) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 26 then
        v_delta := (greatest(v_player.potential, v_player.overall_corrente) - v_player.overall_corrente) * (0.05 + random() * 0.20) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 31 then
        v_delta := (-1 + random() * 2) / v_lega.giornate_totali::numeric;
      elsif v_player.eta_corrente <= 35 then
        v_delta := -(0.5 + random() * 2) / v_lega.giornate_totali::numeric;
      else
        v_delta := -(1.5 + random() * 2.5) / v_lega.giornate_totali::numeric;
      end if;

      v_delta := v_delta * 0.8;
      v_valore := v_player.overall_corrente + v_player.progressione_residuo + v_delta;
      v_ovr := greatest(40, least(greatest(v_player.potential, v_player.overall_corrente), round(v_valore)))::smallint;
      v_residuo := case when v_ovr = 40 or v_ovr = greatest(v_player.potential, v_player.overall_corrente)
        then 0 else v_valore - v_ovr end;

      update public.free_agent_progression
      set overall_corrente = v_ovr, progressione_residuo = v_residuo, aggiornato_il = now()
      where league_id = v_player.league_id and player_id = v_player.player_id;
    end loop;

  return jsonb_build_object(
    'checkpoint_applicati', array[p_giornata],
    'giocatori_aggiornati', v_giocatori_aggiornati
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.prepara_offseason(p_league_id bigint, p_squadre_rimosse bigint[] DEFAULT '{}'::bigint[], p_posti_nuovi smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lega public.leagues;
  v_offseason public.offseasons;
  v_attive integer;
  v_rimosse integer;
  v_target integer;
  v_player record;
  v_ritirati integer := 0;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per aprire l''off-season.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user then
    raise exception using errcode = '42501', message = 'Solo l''admin può aprire l''off-season.';
  end if;
  if v_lega.stato <> 'conclusa' or v_lega.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'L''off-season è disponibile soltanto dopo una stagione conclusa.';
  end if;
  if clock_timestamp() < private.sblocco_offseason(p_league_id) then
    raise exception using errcode = '55000', message = format(
      'L''off-season si apre 24 ore dopo l''ultima giornata: da %s, così tutti possono rivedere i risultati.',
      to_char(private.sblocco_offseason(p_league_id) at time zone 'Europe/Rome', 'DD/MM "alle" HH24:MI'));
  end if;
  if coalesce(p_posti_nuovi, 0) not between 0 and 16 then
    raise exception using errcode = '22023', message = 'Numero di nuovi posti non valido.';
  end if;
  if cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[])) <>
     (select count(distinct id) from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)) then
    raise exception using errcode = '22023', message = 'La lista delle squadre rimosse contiene duplicati.';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_squadre_rimosse, '{}'::bigint[])) x(id)
    left join public.teams t on t.id = x.id and t.league_id = p_league_id and t.attiva
    where t.id is null
  ) then
    raise exception using errcode = '22023', message = 'Una squadra da rimuovere non appartiene alla lega o è già inattiva.';
  end if;
  if exists (
    select 1 from public.teams
    where id = any(coalesce(p_squadre_rimosse, '{}'::bigint[])) and user_id = v_lega.admin_id
  ) then
    raise exception using errcode = '22023', message = 'L''admin non può rimuovere la propria squadra.';
  end if;

  select count(*) into v_attive from public.teams where league_id = p_league_id and attiva;
  v_rimosse := cardinality(coalesce(p_squadre_rimosse, '{}'::bigint[]));
  v_target := v_attive - v_rimosse + coalesce(p_posti_nuovi, 0);
  if v_target not between 4 and 24 then
    raise exception using errcode = '22023', message = 'La prossima stagione deve avere da 4 a 24 squadre.';
  end if;

  -- Prestiti (Season 3): a fine stagione rientrano tutti, prima di rinnovi e invecchiamento.
  perform private.chiudi_prestiti_lega(p_league_id);

  insert into public.offseasons (league_id, stagione_da, stagione_a, scade_il, posti_nuovi)
  values (p_league_id, v_lega.stagione_corrente, v_lega.stagione_corrente + 1,
          ((now() at time zone 'Europe/Rome') + make_interval(hours => v_lega.durata_offseason_ore)) at time zone 'Europe/Rome',
          coalesce(p_posti_nuovi, 0))
  returning * into v_offseason;

  if v_rimosse > 0 then
    update public.trade_proposals
    set stato = 'scaduta', risolta_il = now()
    where league_id = p_league_id and stato = 'in_attesa'
      and (da_team_id = any(p_squadre_rimosse) or a_team_id = any(p_squadre_rimosse));

    update public.player_instances
    set team_id = null
    where league_id = p_league_id and team_id = any(p_squadre_rimosse);

    delete from public.scelte_draft
    where league_id = p_league_id
      and team_origine_id = any(p_squadre_rimosse)
      and stato = 'futura';

    update public.teams
    set attiva = false, uscita_stagione = v_lega.stagione_corrente
    where league_id = p_league_id and id = any(p_squadre_rimosse);
  end if;

  for v_player in
    select pi.id, pi.player_id, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and pi.ritiro_annunciato and not pi.ritirato
  loop
    update public.player_instances
    set team_id = null, ritirato = true, ritiro_annunciato = false
    where id = v_player.id;
    insert into public.retired_players(league_id, player_id, stagione)
    values (p_league_id, v_player.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
    v_ritirati := v_ritirati + 1;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' si ritira',
      'Il ritiro annunciato a inizio stagione e'' ora effettivo: la carriera termina qui.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Invecchiamento di fine stagione: il join sulla squadra attiva e'
  -- stato tolto (deciso il 30 agosto 2026), cosi' uno svincolato reale
  -- invecchia esattamente come chi e' in rosa.
  for v_player in
    select pi.id, pi.eta_corrente, pi.infortunato_fino_a
    from public.player_instances pi
    where pi.league_id = p_league_id and not pi.ritirato
    order by pi.id
    for update of pi
  loop
    update public.player_instances
    set eta_corrente = least(45, v_player.eta_corrente + 1),
        condizione = 100,
        -- La pausa fra due stagioni vale 6 giornate di recupero, non una
        -- guarigione completa (deciso con l'utente l'11 settembre 2026).
        -- Prima qui si azzerava: chi si rompeva per 10 giornate all'ultima
        -- di playoff ripartiva sano, e un infortunio grave di fine stagione
        -- non costava niente. Ora se ne porta dietro 4.
        infortunato_fino_a = greatest(0, v_player.infortunato_fino_a - 6),
        -- Fedina pulita a ogni nuova stagione, come all'inizio dei playoff:
        -- ne' il conto delle ammonizioni ne' una squalifica gia' maturata
        -- attraversano il confine fra due stagioni.
        ammonizioni_stagione = 0,
        squalificato_fino_a = 0,
        progressione_residuo = 0
    where id = v_player.id;
  end loop;

  -- Stesso invecchiamento per chi non e' mai stato scelto in questa lega,
  -- residuo azzerato come per player_instances.
  update public.free_agent_progression
  set eta_corrente = least(45, eta_corrente + 1), progressione_residuo = 0, aggiornato_il = now()
  where league_id = p_league_id;

  update public.leagues
  set n_squadre = v_target,
      stato = 'stagione',
      fase_carriera = 'offseason',
      offseason_fine = v_offseason.scade_il
  where id = p_league_id;

  return jsonb_build_object(
    'league_id', p_league_id,
    'offseason_id', v_offseason.id,
    'stagione_a', v_offseason.stagione_a,
    'scade_il', v_offseason.scade_il,
    'squadre_attese', v_target,
    'posti_nuovi', p_posti_nuovi,
    'ritirati', v_ritirati
  );
end;
$function$;
