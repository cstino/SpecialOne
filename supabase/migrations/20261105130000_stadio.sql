-- Season 3, diario §4: lo stadio, quarto ramo delle risorse.
-- * team_risorse.livello_stadio 0-10; massimo dei punti risorsa da 20 a 26 nelle leghe con lo stadio.
-- * Bonus casa: massimo +1,0 a livello 0, +0,2 a livello, +3,0 a livello 10 (livello 5 = come prima):
--   moltiplicatore = (1 + 0,2 x livello) / 2 x fattore pubblico.
-- * Biglietti: 50 crediti del casino' x livello per ogni partita in casa, pagati con i premi partita.
-- * teams.nome_stadio (massimo 20 caratteri; vuoto = nome di default scelto dall'app).
-- * leagues.stadio_attivo: lo stadio vale da quando parte la nuova stagione di ogni lega (in finalizza_offseason);
--   la Serie F lo accende subito perche' e' a fine stagione e puo' investire in off-season.
-- Funzioni ricostruite dalla definizione live.

alter table public.team_risorse add column if not exists livello_stadio smallint not null default 0;
alter table public.team_risorse drop constraint team_risorse_livelli_validi;
alter table public.team_risorse add constraint team_risorse_livelli_validi check (
  livello_vivaio between 0 and 10 and livello_training between 0 and 10
  and livello_medico between 0 and 10 and livello_stadio between 0 and 10);
alter table public.team_risorse drop constraint team_risorse_spesa_coperta;
alter table public.team_risorse add constraint team_risorse_spesa_coperta check (
  livello_vivaio + livello_training + livello_medico + livello_stadio <= punti_ricevuti);

alter table public.leagues add column if not exists stadio_attivo boolean not null default false;
update public.leagues set stadio_attivo = true where id = 63;

alter table public.teams add column if not exists nome_stadio text;
alter table public.teams add constraint teams_nome_stadio_lunghezza
  check (nome_stadio is null or char_length(nome_stadio) between 1 and 20);

alter table public.casino_premi_partita add column if not exists biglietti integer not null default 0;

create or replace function private.punti_abilita_massimi_lega(p_league_id bigint)
returns smallint
language sql
stable
set search_path to ''
as $$
  select (private.punti_abilita_massimi()
          + case when coalesce((select l.stadio_attivo from public.leagues l where l.id = p_league_id), false) then 6 else 0 end)::smallint
$$;
revoke all on function private.punti_abilita_massimi_lega(bigint) from public, anon, authenticated;


CREATE OR REPLACE FUNCTION private.effetti_ramo(p_ramo text, p_livello smallint)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_ramo
    when 'vivaio' then jsonb_build_object(
      'livello', p_livello,
      -- Si parte con uno slot e si arriva a cinque: +1 ai livelli 3, 5, 7 e 10.
      'slot', 1 + (p_livello >= 3)::int + (p_livello >= 5)::int
                + (p_livello >= 7)::int + (p_livello >= 10)::int,
      -- Ampiezza della forbice di potenziale mostrata sul giovane: 20 punti
      -- di incertezza a livello 0 (es. "68-88"), zero a 10 (valore esatto).
      'ampiezza_range', round(20.0 * (10 - p_livello) / 10.0)::int
    )
    when 'training' then jsonb_build_object(
      'livello', p_livello,
      -- Fronte dispari: sale ai livelli 1, 3, 5, 7, 9. Max 1.0 + 5*0.10 = 1.50.
      'moltiplicatore_crescita', round(1.0 + ((p_livello + 1) / 2) * 0.10, 2),
      -- Fronte pari: sale ai livelli 2, 4, 6, 8, 10. Max 5*8 = 40%.
      'riduzione_tempi_ruolo_pct', (p_livello / 2) * 8
    )
    when 'medico' then jsonb_build_object(
      'livello', p_livello,
      -- Fronte pari: sale ai livelli 2, 4, 6, 8, 10. Max 5*6 = 30%.
      'riduzione_infortuni_pct', (p_livello / 2) * 6,
      -- Fronte dispari: sale ai livelli 1, 3, 5, 7, 9. Max 5*8 = 40%.
      -- Stessa semantica di prima (attenua il calo non riassorbito dal
      -- recupero post-partita del motore, non tocca il consumo in gara).
      'riduzione_calo_residuo_pct', ((p_livello + 1) / 2) * 8,
      -- Guarigione (18 ottobre 2026, deciso con l'utente): a ogni giornata un infortunato ha questa probabilita'
      -- (in %) di rientrare UNA giornata prima. 3% per livello, fino al 30%.
      'recupero_infortuni_pct', p_livello * 3
    )
    when 'stadio' then jsonb_build_object(
      'livello', p_livello,
      -- Season 3 (diario §4): massimo del bonus casa del pubblico, +1,0 a livello 0 e +0,2 a livello.
      'bonus_casa_massimo', round(1.0 + 0.2 * p_livello, 1),
      -- Crediti del casino' per ogni partita in casa.
      'biglietti_partita', 50 * p_livello
    )
  end
$function$;

drop function public.tabella_risorse();
CREATE OR REPLACE FUNCTION public.tabella_risorse(p_league_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'punti_per_checkpoint', private.punti_per_checkpoint(),
    'punti_massimi', case when p_league_id is null then private.punti_abilita_massimi() else private.punti_abilita_massimi_lega(p_league_id) end,
    'livello_massimo', private.livello_ramo_massimo(),
    'rami', (
      select jsonb_object_agg(r.ramo, x.livelli)
      from (values ('vivaio'), ('training'), ('medico'), ('stadio')) as r(ramo)
      cross join lateral (
        select jsonb_agg(private.effetti_ramo(r.ramo, l.livello::smallint) order by l.livello) as livelli
        from generate_series(0, 10) as l(livello)
      ) x
    )
  )
$function$;
grant execute on function public.tabella_risorse(bigint) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.spendi_punto_abilita(p_team_id bigint, p_ramo text)
 RETURNS team_risorse
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_riga public.team_risorse;
  v_livello smallint;
  v_spesi smallint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire le risorse.';
  end if;
  if p_ramo not in ('vivaio', 'training', 'medico', 'stadio') then
    raise exception using errcode = '22023', message = 'Ramo non valido.';
  end if;
  if not (select private.e_mia_squadra(p_team_id)) then
    raise exception using errcode = '42501', message = 'Questa squadra non e'' tua.';
  end if;

  -- La riga esiste gia' per trigger, ma una squadra creata prima di questa
  -- migrazione (o da un percorso che aggira il trigger) non deve trovarsi
  -- bloccata: si crea al volo, sempre a zero.
  insert into public.team_risorse (team_id, league_id)
  select t.id, t.league_id from public.teams t where t.id = p_team_id
  on conflict (team_id) do nothing;

  select * into v_riga from public.team_risorse where team_id = p_team_id for update;

  if p_ramo = 'stadio' and not coalesce((select l.stadio_attivo from public.leagues l where l.id = v_riga.league_id), false) then
    raise exception using errcode = '22023', message = 'Lo stadio arriva con la prossima stagione.';
  end if;

  v_livello := case p_ramo
    when 'vivaio' then v_riga.livello_vivaio
    when 'training' then v_riga.livello_training
    when 'stadio' then v_riga.livello_stadio
    else v_riga.livello_medico
  end;
  if v_livello >= private.livello_ramo_massimo() then
    raise exception using errcode = '22023',
      message = 'Questo ramo e'' gia'' al massimo ('
        || private.livello_ramo_massimo() || '/' || private.livello_ramo_massimo() || ').';
  end if;

  v_spesi := v_riga.livello_vivaio + v_riga.livello_training + v_riga.livello_medico + v_riga.livello_stadio;
  if v_spesi >= v_riga.punti_ricevuti then
    raise exception using errcode = '22023',
      message = 'Non hai punti abilita'' disponibili: ne hai ricevuti '
        || v_riga.punti_ricevuti || ' e gia'' spesi ' || v_spesi || '.';
  end if;

  update public.team_risorse
  set livello_vivaio = livello_vivaio + (p_ramo = 'vivaio')::int,
      livello_training = livello_training + (p_ramo = 'training')::int,
      livello_medico = livello_medico + (p_ramo = 'medico')::int,
      livello_stadio = livello_stadio + (p_ramo = 'stadio')::int,
      aggiornata_il = now()
  where team_id = p_team_id
  returning * into v_riga;

  return v_riga;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assegna_punti_abilita(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_squadre integer := 0;
  v_team record;
begin
  select l.id, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'squadre_aggiornate', 0);
  end if;

  -- Stessa scansione di morale e progressione: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_punti_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_lega.season_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    insert into public.team_risorse (team_id, league_id)
    select t.id, t.league_id
    from public.teams t
    where t.league_id = p_league_id and t.attiva
    on conflict (team_id) do nothing;

    -- Notifica solo a chi riceve davvero i punti (esclude chi ha gia'
    -- raggiunto il tetto, e le squadre PC senza user_id: private.notifica
    -- e' gia' un no-op su user_id null, ma evitiamo il giro a vuoto).
    for v_team in
      update public.team_risorse r
      set punti_ricevuti = least(
            private.punti_abilita_massimi_lega(p_league_id),
            (r.punti_ricevuti + private.punti_per_checkpoint())::smallint
          ),
          aggiornata_il = now()
      from public.teams t
      where t.id = r.team_id
        and t.league_id = p_league_id
        and t.attiva
        and r.punti_ricevuti < private.punti_abilita_massimi_lega(p_league_id)
      returning t.id as team_id, t.user_id
    loop
      v_squadre := v_squadre + 1;
      if v_team.user_id is not null then
        perform private.notifica(
          v_team.user_id, p_league_id, 'sistema', 'Punti abilità disponibili',
          'Hai ricevuto ' || private.punti_per_checkpoint() || ' punti abilità da spendere nelle risorse del club.',
          jsonb_build_object('view', 'risorse')
        );
      end if;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'squadre_aggiornate', v_squadre);
end;
$function$;

CREATE OR REPLACE FUNCTION public.moltiplicatori_casa(p_league_id bigint)
 RETURNS TABLE(team_id bigint, moltiplicatore numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Season 3 (diario §4): lo stadio porta il massimo del bonus da +1,0 (livello 0) a +3,0 (livello 10).
  select t.id, private.moltiplicatore_pubblico(t.pubblico)
         * case when l.stadio_attivo then (1 + 0.2 * coalesce(r.livello_stadio, 0)) / 2.0 else 1 end
  from public.teams t
  join public.leagues l on l.id = t.league_id
  left join public.team_risorse r on r.team_id = t.id
  where t.league_id = p_league_id and l.conferenze_stampa
$function$;

drop function public.aggiorna_profilo_squadra(bigint, text, text, text);
CREATE OR REPLACE FUNCTION public.aggiorna_profilo_squadra(p_team_id bigint, p_nome text, p_stemma_url text, p_sigla text DEFAULT NULL::text, p_nome_stadio text DEFAULT NULL::text)
 RETURNS teams
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_vincolo text;
  v_nome_stadio text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per modificare la squadra.';
  end if;

  select * into v_team
  from public.teams
  where id = p_team_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Puoi modificare soltanto la tua squadra.';
  end if;

  p_nome := trim(p_nome);
  if length(p_nome) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non e'' valido.';
  end if;
  if not private.stemma_libero_in_lega(v_team.league_id, p_stemma_url, p_team_id) then
    raise exception using errcode = '23505', message = 'Questo stemma e'' gia'' usato nella lega.';
  end if;

  -- Sigla: null o uguale all'attuale = nessun cambio.
  p_sigla := nullif(upper(trim(coalesce(p_sigla, ''))), '');
  if p_sigla is not null and p_sigla is distinct from v_team.sigla then
    if p_sigla !~ '^[A-Z0-9]{3}$' then
      raise exception using errcode = '22023', message = 'La sigla deve avere esattamente 3 caratteri tra lettere e cifre.';
    end if;
  else
    p_sigla := null;
  end if;

  -- Nome dello stadio: null = nessun cambio, vuoto = torna al nome di default.
  v_nome_stadio := case when p_nome_stadio is null then v_team.nome_stadio else nullif(trim(p_nome_stadio), '') end;
  if char_length(v_nome_stadio) > 20 then
    raise exception using errcode = '22023', message = 'Il nome dello stadio può avere al massimo 20 caratteri.';
  end if;

  begin
    update public.teams
    set nome = p_nome,
        stemma_url = p_stemma_url,
        sigla = coalesce(p_sigla, sigla),
        sigla_personalizzata = sigla_personalizzata or p_sigla is not null,
        nome_stadio = v_nome_stadio
    where id = p_team_id
    returning * into v_team;
  exception when unique_violation then
    get stacked diagnostics v_vincolo = constraint_name;
    if v_vincolo = 'teams_sigla_unica_per_lega' then
      raise exception using errcode = '23505', message = 'Questa sigla e'' gia'' usata da un''altra squadra della lega.';
    end if;
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  return v_team;
end;
$function$;
revoke all on function public.aggiorna_profilo_squadra(bigint, text, text, text, text) from public;
grant execute on function public.aggiorna_profilo_squadra(bigint, text, text, text, text) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.casino_premi_partita(p_league_id bigint, p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_tot integer := 0; v_esito text; v_crediti integer; v_biglietti integer;
begin
  for r in
    select m.id as match_id, t.id as team_id,
           case when f.home_team_id = t.id then f.away_team_id else f.home_team_id end as avversario,
           case when f.home_team_id = t.id then m.gol_home else m.gol_away end as gf,
           case when f.home_team_id = t.id then m.gol_away else m.gol_home end as gs,
           case when f.home_team_id = t.id then m.rigori_home else m.rigori_away end as rf,
           case when f.home_team_id = t.id then m.rigori_away else m.rigori_home end as rs,
           -- Biglietti (Season 3, diario §4): 50 crediti x livello dello stadio per ogni partita in casa.
           case when f.home_team_id = t.id and f.campo_neutro is not true and l.stadio_attivo
                then 50 * coalesce(tr.livello_stadio, 0) else 0 end as biglietti
      from public.teams t
      join public.fixtures f on f.league_id = t.league_id and t.id in (f.home_team_id, f.away_team_id)
      join public.matches m on m.fixture_id = f.id
      join public.leagues l on l.id = t.league_id
      left join public.team_risorse tr on tr.team_id = t.id
     where t.league_id = p_league_id and t.user_id = p_user and t.attiva
       and m.id > 1513
       -- non prima delle 23:10 della sera in cui la partita e' stata simulata (le 6 ore di margine reggono una simulazione in ritardo oltre la mezzanotte)
       and now() >= ((((coalesce(m.simulata_il, 'epoch'::timestamptz) at time zone 'Europe/Rome') - interval '6 hours')::date)::timestamp + interval '23 hours 10 minutes') at time zone 'Europe/Rome'
       and not exists (select 1 from public.casino_premi_partita p where p.match_id = m.id and p.user_id = p_user)
       and (exists (select 1 from public.match_reveals mr where mr.match_id = m.id and mr.user_id = p_user)
            or m.simulata_il < now() - interval '24 hours')
  loop
    v_esito := case when r.gf > r.gs then 'vittoria' when r.gf < r.gs then 'sconfitta'
                    when r.rf is not null and r.rs is not null and r.rf <> r.rs then case when r.rf > r.rs then 'vittoria' else 'sconfitta' end
                    else 'pareggio' end;
    v_crediti := case v_esito when 'vittoria' then 300 when 'pareggio' then 150 else 100 end;
    v_biglietti := r.biglietti;
    insert into public.casino_premi_partita (match_id, user_id, league_id, team_id, esito, avversario_id, crediti, biglietti)
    values (r.match_id, p_user, p_league_id, r.team_id, v_esito, r.avversario, v_crediti, v_biglietti)
    on conflict do nothing;
    if found then v_tot := v_tot + v_crediti + v_biglietti; end if;
  end loop;
  if v_tot > 0 then
    update public.casino_saldi set crediti = crediti + v_tot, aggiornato_il = now() where league_id = p_league_id and user_id = p_user;
  end if;
  return v_tot;
end $function$;

CREATE OR REPLACE FUNCTION private.casino_premi_da_vedere(p_league_id bigint, p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('esito', p.esito, 'crediti', p.crediti, 'biglietti', p.biglietti, 'avversario_id', p.avversario_id) order by p.match_id), '[]'::jsonb)
    into v from public.casino_premi_partita p where p.league_id = p_league_id and p.user_id = p_user and not p.visto;
  update public.casino_premi_partita set visto = true where league_id = p_league_id and user_id = p_user and not visto;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION private.claude_spendi_punti()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_t record;
  v_r public.team_risorse;
  v_ramo text;
  v_n integer := 0;
  v_guardia integer;
begin
  for v_t in select t.id, t.league_id, t.user_id from public.teams t where t.gestita_da_claude and t.user_id is not null loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_t.user_id, 'role', 'authenticated')::text, true);
    v_guardia := 0;
    loop
      v_guardia := v_guardia + 1;
      exit when v_guardia > 20;
      select * into v_r from public.team_risorse where team_id = v_t.id;
      exit when not found or v_r.livello_vivaio + v_r.livello_training + v_r.livello_medico + v_r.livello_stadio >= v_r.punti_ricevuti;
      v_ramo := (select r from (values ('medico', v_r.livello_medico, 1), ('training', v_r.livello_training, 2), ('vivaio', v_r.livello_vivaio, 3)) x(r, lv, pr)
                  where lv < private.livello_ramo_massimo() order by lv, pr limit 1);
      exit when v_ramo is null;
      perform public.spendi_punto_abilita(v_t.id, v_ramo);
      insert into public.azioni_claude (league_id, team_id, tipo, dettaglio)
      values (v_t.league_id, v_t.id, 'risorse', jsonb_build_object('ramo', v_ramo, 'dopo', (select jsonb_build_object('vivaio', livello_vivaio, 'training', livello_training, 'medico', livello_medico) from public.team_risorse where team_id = v_t.id)));
      v_n := v_n + 1;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION private.finalizza_offseason(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_off public.offseasons;
  v_team record;
  v_candidate record;
  v_player record;
  v_rosa integer;
  v_ingaggi bigint;
  v_da_aggiungere integer;
  v_wage bigint;
  v_season bigint;
  v_aggiunti text[];
  v_rilasciati integer;
  v_attive integer;
  v_scelte_live integer;
  v_avvio_live timestamptz;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season non e'' attiva.';
  end if;

  select * into v_off
  from public.offseasons
  where league_id = p_league_id and stato = 'aperta'
  order by stagione_a desc limit 1
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Off-season aperta non trovata.';
  end if;
  if clock_timestamp() < v_off.scade_il then
    raise exception using errcode = '55000',
      message = 'L''off-season dura 24 ore e non puo'' essere chiusa prima della scadenza.';
  end if;

  if exists (
    select 1 from public.finestre_scelte
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off'
      and risolta_il is null
  ) then
    begin
      -- In diretta le notifiche delle scelte partono alla rivelazione.
      if v_league.conferenze_attive then perform set_config('private.silenzia_scelte', '1', true); end if;
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  perform set_config('private.silenzia_scelte', '', true);

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  -- Contratti scaduti e non rinnovati: i giocatori restano senza squadra E finiscono nella coda dei rilasci, cosi' alla
  -- prima estrazione dopo la riapertura del mercato compaiono tutti fra i free agent (non solo per sorteggio).
  with liberati as (
    update public.player_instances
    set team_id = null
    where league_id = p_league_id
      and team_id is not null
      and not ritirato
      and contratto_scadenza <= v_league.stagione_corrente
    returning player_id
  )
  insert into private.rilasci_in_coda (league_id, player_id)
  select p_league_id, l.player_id from liberati l
  on conflict (league_id, player_id) do nothing;

  for v_team in
    select * from public.teams
    where league_id = p_league_id and attiva
    order by id for update
  loop
    v_aggiunti := array[]::text[];
    v_rilasciati := 0;

    -- Se la rosa attuale non e' sostenibile sotto il tetto, si applica
    -- l'insolvenza del design: escono prima gli ingaggi piu' alti finche'
    -- restano finanziabili anche i posti mancanti al minimo di 21. Sotto
    -- il tetto questo non dovrebbe piu' accadere per una rosa costruita
    -- interamente dopo la migrazione (ogni acquisizione verifica gia' la
    -- capienza), ma resta il paracadute per le rose ereditate dal vecchio
    -- modello a cassa (v. private.capienza_residua).
    loop
      select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
      into v_rosa, v_ingaggi
      from public.player_instances
      where team_id = v_team.id and not ritirato;

      exit when v_ingaggi + greatest(21 - v_rosa, 0) * 500000 <= v_league.tetto_ingaggi;

      select pi.id into v_candidate
      from public.player_instances pi
      where pi.team_id = v_team.id and not pi.ritirato
      order by pi.ingaggio desc, pi.overall_corrente asc, pi.id
      limit 1;
      if not found then
        raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per completare la rosa di ' || v_team.nome || '.';
      end if;
      update public.player_instances set team_id = null where id = v_candidate.id;
      insert into private.rilasci_in_coda (league_id, player_id)
      select p_league_id, pi.player_id from public.player_instances pi where pi.id = v_candidate.id
      on conflict (league_id, player_id) do nothing;
      v_rilasciati := v_rilasciati + 1;
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;
    v_da_aggiungere := greatest(21 - v_rosa, 0);

    while v_da_aggiungere > 0 loop
      select p.id as player_id, p.nome,
             coalesce(fap.overall_corrente, p.overall) as overall, coalesce(fap.eta_corrente, p.eta) as eta,
             pi.id as instance_id,
             coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))::bigint as ingaggio
      into v_candidate
      from public.players p
      left join public.player_instances pi
        on pi.league_id = p_league_id and pi.player_id = p.id
      left join public.free_agent_progression fap
        on fap.league_id = p_league_id and fap.player_id = p.id
      where p.campionato = any(v_league.campionati_attivi)
        and (pi.id is null or (pi.team_id is null and not pi.ritirato))
        and not exists (select 1 from public.retired_players rp where rp.league_id = p_league_id and rp.player_id = p.id)
        and coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta)))
          <= v_league.tetto_ingaggi - v_ingaggi - ((v_da_aggiungere - 1) * 500000)
      order by coalesce(pi.ingaggio, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))) asc,
               coalesce(fap.overall_corrente, p.overall) asc, p.id
      limit 1;

      if not found then
        raise exception using errcode = '55000', message = 'Non ci sono svincolati sostenibili per completare la rosa di ' || v_team.nome || '.';
      end if;

      v_wage := greatest(500000, v_candidate.ingaggio);
      if v_candidate.instance_id is null then
        insert into public.player_instances(
          league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio,
          condizione, infortunato_fino_a, contratto_scadenza
        ) values (
          p_league_id, v_candidate.player_id, v_team.id, v_candidate.overall,
          v_candidate.eta, v_wage, 100, 0, v_off.stagione_a
        );
        delete from public.free_agent_progression
        where league_id = p_league_id and player_id = v_candidate.player_id;
      else
        update public.player_instances
        set team_id = v_team.id,
            ingaggio = v_wage,
            contratto_scadenza = v_off.stagione_a,
            condizione = 100,
            infortunato_fino_a = 0
        where id = v_candidate.instance_id and team_id is null;
      end if;

      v_ingaggi := v_ingaggi + v_wage;
      v_da_aggiungere := v_da_aggiungere - 1;
      v_aggiunti := array_append(v_aggiunti, v_candidate.nome);
    end loop;

    select count(*)::integer, coalesce(sum(ingaggio), 0)::bigint
    into v_rosa, v_ingaggi
    from public.player_instances
    where team_id = v_team.id and not ritirato;

    if v_rosa not between 21 and 30 then
      raise exception using errcode = '55000', message = 'La rosa di ' || v_team.nome || ' non rispetta il limite 21-30.';
    end if;
    if v_league.tetto_ingaggi < v_ingaggi then
      raise exception using errcode = '55000', message = 'Tetto ingaggi insufficiente per gli ingaggi di ' || v_team.nome || '.';
    end if;

    update public.draft_team_state
    set stato = 'concluso', aggiornato_il = clock_timestamp()
    where league_id = p_league_id and team_id = v_team.id and stato <> 'concluso';

    if cardinality(v_aggiunti) > 0 or v_rilasciati > 0 then
      perform private.notifica(
        v_team.user_id, p_league_id, 'sistema', 'Rosa completata automaticamente',
        case when cardinality(v_aggiunti) > 0
          then cardinality(v_aggiunti) || ' svincolati aggiunti per raggiungere il minimo di 21 giocatori.'
          else 'Rosa riequilibrata automaticamente per rispettare il tetto ingaggi.' end,
        jsonb_build_object('view', 'team', 'aggiunti', cardinality(v_aggiunti), 'rilasciati', v_rilasciati)
      );
    end if;
  end loop;

  -- Il rilascio automatico dei prospetti non promossi in tempo non e' piu'
  -- legato alla chiusura dell'off-season (deciso con l'utente il 4
  -- settembre 2026: comprare un giovane a ridosso della fine stagione non
  -- deve costringere a promuoverlo quasi subito). Ora e' un conto alla
  -- rovescia in giornate dal momento dell'acquisto, decrementato ogni
  -- giornata simulata da public.decrementa_vivaio_giornate — qui non
  -- resta piu' nulla da fare.

  -- ON-Season della nuova stagione: l'ordine dal monte ingaggi (minore -> maggiore),
  -- misurato ora che draft e rose sono completi.
  perform private.assegna_posizioni_on_per_monte_ingaggi(p_league_id, v_off.stagione_a);

  -- Le formazioni della stagione chiusa non devono sopravvivere nella nuova: lineups non ha la stagione,
  -- quindi una riga "giornata 2" di agosto verrebbe scambiata per quella della giornata 2 di questa
  -- stagione (simulazione, promemoria, pagina Formazione). Si archiviano e si tolgono: restano solo le
  -- formazioni preparate durante l'off-season (giornata 1 salvata dopo l'apertura dell'off-season).
  insert into private.lineups_archivio
  select l.*, v_off.stagione_da::smallint
  from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);
  delete from public.lineups l
  where l.league_id = p_league_id and (l.giornata >= 2 or l.salvata_il < v_off.creata_il);

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
      offseason_fine = null,
      stato = 'stagione',
      stadio_attivo = true
  where id = p_league_id;

  -- Season 3 (diario §2): ogni stagione riparte con morale dei giocatori e pubblico a meta'. Si fa qui, alla
  -- chiusura dell'off-season, perche' durante l'off-season il morale serve ancora ai rinnovi.
  update public.player_instances set morale = 50
  where league_id = p_league_id and not ritirato and morale <> 50;
  update public.teams set pubblico = 50
  where league_id = p_league_id and pubblico <> 50;

  for v_player in
    select pi.id, pi.eta_corrente, p.nome, t.user_id
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id and not pi.ritirato and not pi.ritiro_annunciato
      and pi.eta_corrente >= 34
      and random() < private.probabilita_ritiro(pi.eta_corrente)
  loop
    update public.player_instances set ritiro_annunciato = true where id = v_player.id;
    perform private.notifica(v_player.user_id, p_league_id, 'sistema',
      v_player.nome || ' annuncia il ritiro',
      'Giochera'' ancora questa stagione, poi lascera'' la carriera: non puo'' essere ceduto in trattativa.',
      jsonb_build_object('player_instance_id', v_player.id));
  end loop;

  -- Ritiro dei mai-scelti: legge l'eta' vera tracciata in
  -- free_agent_progression (non piu' un'eta' ipotetica ricalcolata),
  -- e ripulisce la riga tracciata quando il giocatore esce dal pool.
  insert into public.retired_players(league_id, player_id, stagione)
  select p_league_id, fap.player_id, v_off.stagione_a
  from public.free_agent_progression fap
  where fap.league_id = p_league_id
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = fap.player_id and pi.team_id is not null
    )
    and not exists (
      select 1 from public.retired_players rp
      where rp.league_id = p_league_id and rp.player_id = fap.player_id
    )
    and fap.eta_corrente >= 34
    and random() < private.probabilita_ritiro(fap.eta_corrente)
  on conflict do nothing;

  delete from public.free_agent_progression fap
  using public.retired_players rp
  where fap.league_id = p_league_id and rp.league_id = p_league_id and rp.player_id = fap.player_id;

  -- Con le conferenze la stagione non parte subito: prima il sorteggio East/West
  -- in diretta, e solo a sorteggio concluso nasce il calendario
  -- (private.completa_sorteggi_scaduti).
  if v_league.conferenze_attive then
    perform private.crea_sorteggio_conferenze(p_league_id, v_off.stagione_a);
    v_season := null;
    -- Draft dei giocatori in diretta (30 s a scelta) e, 3 minuti dopo l'ultima
    -- scelta, il sorteggio. Parte al minuto pieno successivo alla chiusura.
    select count(*)::integer into v_scelte_live
    from public.scelte_draft
    where league_id = p_league_id and stagione = v_off.stagione_da and finestra = 'off' and stato in ('usata', 'vuota');
    if v_scelte_live > 0 then
      v_avvio_live := date_trunc('minute', clock_timestamp()) + interval '1 minute';
      insert into public.scelte_live (league_id, stagione, finestra, avviato_il, totale)
      values (p_league_id, v_off.stagione_da, 'off', v_avvio_live, v_scelte_live)
      on conflict (league_id, stagione, finestra) do nothing;
      update public.sorteggi_conferenze
      set avviato_il = v_avvio_live + (v_scelte_live * 30 + 180) * interval '1 second'
      where league_id = p_league_id and stagione = v_off.stagione_a and completato_il is null;
    end if;
  else
    v_season := private.inizializza_stagione(p_league_id);
  end if;

  perform private.notifica(
    t.user_id, p_league_id, 'sistema',
    case when v_league.conferenze_attive then 'Draft e sorteggio in diretta' else 'La nuova stagione e'' iniziata' end,
    case when v_league.conferenze_attive then 'Entra ora: prima il draft dei giocatori, poi il sorteggio delle conferenze Eastern e Western.'
         else 'La prima giornata si giochera'' alle 23:00. Prepara la formazione.' end,
    jsonb_build_object('view', 'overview', 'season_id', v_season)
  )
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  return jsonb_build_object(
    'league_id', p_league_id,
    'season_id', v_season,
    'stagione', v_off.stagione_a,
    'prima_giornata', private.primo_calcio_dopo(v_off.scade_il)
  );
end;
$function$;
