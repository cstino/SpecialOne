-- ============================================================
--  CONFERENCE EAST / WEST E SORTEGGIO IN DIRETTA (Serie F, 24 squadre)
--  Deciso con il committente il 5 ottobre 2026.
--
--  Una lega con conferenze (leagues.conferenze_attive) si divide a ogni
--  stagione in East e West con un SORTEGGIO IN DIRETTA: una squadra ogni 20
--  secondi, alternando East e West fino a 12 e 12. Si gioca la regular
--  season solo dentro la propria conferenza (22 giornate con 12 squadre e 2
--  gironi). I playoff a tre tabelloni (Champions, Europa League, Draft
--  Playoffs) sono il blocco successivo: qui NON si toccano.
--
--  Flusso alla chiusura dell'off-season (finalizza_offseason):
--    1. tutto come prima (contratti, rose, ritiri...) tranne il calendario;
--    2. la lega passa a fase_carriera = 'sorteggio' e nasce il sorteggio;
--    3. ogni minuto private.completa_sorteggi_scaduti guarda i sorteggi finiti
--       e per ciascuno rimette la lega in 'normale' e chiama
--       inizializza_stagione, che ora genera il calendario per conferenza.
--  Le leghe senza conferenze funzionano esattamente come prima.
--
--  SEGRETO DEL SORTEGGIO: l'ordine di estrazione e' deciso dal server
--  all'inizio, ma ogni estrazione e' leggibile (RLS) solo dal momento in cui
--  viene rivelata. Nessun partecipante puo' sapere in anticipo chi uscira'.
-- ============================================================

alter table public.leagues
  add column if not exists conferenze_attive boolean not null default false;
comment on column public.leagues.conferenze_attive is
  'Se vero la lega si divide ogni stagione in East e West con sorteggio in diretta; si gioca solo dentro la conferenza.';

-- Fino a 24 squadre (due conferenze da 12).
alter table public.leagues drop constraint if exists leagues_n_squadre_check;
alter table public.leagues add constraint leagues_n_squadre_check check (n_squadre >= 4 and n_squadre <= 24);

alter table public.leagues drop constraint if exists leagues_fase_carriera_check;
alter table public.leagues add constraint leagues_fase_carriera_check
  check (fase_carriera = any (array['normale', 'offseason', 'sorteggio', 'terminata']));

-- Giornate di regular season: con le conferenze si gioca solo contro le 11
-- avversarie della propria (n_squadre / 2 per conferenza).
alter table public.leagues alter column giornate_totali set expression as (
  case when conferenze_attive
    then (((n_squadre / 2) - 1) + (((n_squadre / 2))::integer % 2)) * n_gironi
    else ((n_squadre - 1) + ((n_squadre)::integer % 2)) * n_gironi
  end
);

alter table public.standings
  add column if not exists conferenza text check (conferenza in ('est', 'ovest'));
-- La posizione e' unica dentro la conferenza (non piu' in tutta la stagione).
drop index if exists public.standings_posizione_unique_idx;
create unique index standings_posizione_unique_idx
  on public.standings (season_id, (coalesce(conferenza, '')), posizione)
  where posizione is not null;

comment on column public.standings.conferenza is
  'Conferenza della stagione (sorteggiata a inizio stagione). Null nelle leghe senza conferenze. La posizione si calcola dentro la conferenza.';

create table if not exists public.sorteggi_conferenze (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  stagione smallint not null,
  avviato_il timestamptz not null default clock_timestamp(),
  passo_secondi smallint not null default 20 check (passo_secondi between 5 and 120),
  totale smallint not null check (totale >= 4),
  completato_il timestamptz,
  unique (league_id, stagione)
);

create table if not exists public.sorteggio_estrazioni (
  sorteggio_id bigint not null references public.sorteggi_conferenze(id) on delete cascade,
  ordine smallint not null check (ordine >= 1),
  team_id bigint not null references public.teams(id) on delete cascade,
  conferenza text not null check (conferenza in ('est', 'ovest')),
  primary key (sorteggio_id, ordine),
  unique (sorteggio_id, team_id)
);

-- Quante estrazioni sono gia' state rivelate (l'ordine k lo e' a avviato_il + k * passo).
create or replace function private.sorteggio_rivelate(p_sorteggio_id bigint)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select least(s.totale, greatest(0, floor(extract(epoch from (clock_timestamp() - s.avviato_il)) / s.passo_secondi)))::integer
  from public.sorteggi_conferenze s where s.id = p_sorteggio_id
$$;
revoke all on function private.sorteggio_rivelate(bigint) from public, anon;
grant execute on function private.sorteggio_rivelate(bigint) to authenticated;

alter table public.sorteggi_conferenze enable row level security;
alter table public.sorteggio_estrazioni enable row level security;
revoke all on public.sorteggi_conferenze, public.sorteggio_estrazioni from anon, authenticated;
grant select on public.sorteggi_conferenze, public.sorteggio_estrazioni to authenticated;
grant all on public.sorteggi_conferenze, public.sorteggio_estrazioni to service_role;

create policy sorteggi_conferenze_lettura on public.sorteggi_conferenze
  for select to authenticated
  using ((select private.e_membro(league_id)));

create policy sorteggio_estrazioni_lettura on public.sorteggio_estrazioni
  for select to authenticated
  using (
    exists (
      select 1 from public.sorteggi_conferenze s
      where s.id = sorteggio_estrazioni.sorteggio_id
        and (select private.e_membro(s.league_id))
        and sorteggio_estrazioni.ordine <= private.sorteggio_rivelate(s.id)
    )
  );

-- Crea il sorteggio: ordine casuale, East ai posti dispari e West ai pari.
create or replace function private.crea_sorteggio_conferenze(p_league_id bigint, p_stagione smallint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
  v_id bigint;
begin
  select id into v_id from public.sorteggi_conferenze where league_id = p_league_id and stagione = p_stagione;
  if found then return v_id; end if;

  select count(*)::integer into v_n from public.teams where league_id = p_league_id and attiva;
  if v_n < 4 or v_n % 2 <> 0 then
    raise exception using errcode = '22023',
      message = 'Le conferenze richiedono un numero pari di squadre attive (almeno 4).';
  end if;

  insert into public.sorteggi_conferenze (league_id, stagione, totale)
  values (p_league_id, p_stagione, v_n)
  returning id into v_id;

  insert into public.sorteggio_estrazioni (sorteggio_id, ordine, team_id, conferenza)
  select v_id, x.rn::smallint, x.id, case when x.rn % 2 = 1 then 'est' else 'ovest' end
  from (
    select t.id, row_number() over (order by random()) as rn
    from public.teams t
    where t.league_id = p_league_id and t.attiva
  ) x;

  return v_id;
end;
$$;
revoke all on function private.crea_sorteggio_conferenze(bigint, smallint) from public, anon, authenticated;

-- Chiude i sorteggi finiti (ultimo nome rivelato + 20 secondi di margine).
-- Ogni sorteggio in un blocco suo: se la creazione del calendario fallisce, la
-- lega resta in 'sorteggio' e si riprova al giro dopo.
create or replace function private.completa_sorteggi_scaduti()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s record;
begin
  for v_s in
    select s.*
    from public.sorteggi_conferenze s
    join public.leagues l on l.id = s.league_id
    where s.completato_il is null
      and l.fase_carriera = 'sorteggio'
      and l.stagione_corrente = s.stagione
      and clock_timestamp() >= s.avviato_il + (s.totale * s.passo_secondi + 20) * interval '1 second'
    order by s.id
  loop
    begin
      update public.leagues set fase_carriera = 'normale' where id = v_s.league_id;
      perform private.inizializza_stagione(v_s.league_id);
      update public.sorteggi_conferenze set completato_il = clock_timestamp() where id = v_s.id;
      perform private.notifica(
        t.user_id, v_s.league_id, 'sistema', 'Le conferenze sono pronte',
        'La stagione e'' iniziata: la prima giornata si giochera'' alle 23:00. Prepara la formazione.',
        jsonb_build_object('view', 'overview')
      )
      from public.teams t
      where t.league_id = v_s.league_id and t.attiva;
    exception when others then
      raise warning 'sorteggio conferenze: lega % non completata: % (%)', v_s.league_id, sqlerrm, sqlstate;
    end;
  end loop;
end;
$$;
revoke all on function private.completa_sorteggi_scaduti() from public, anon, authenticated;

select cron.schedule('completa-sorteggi-conferenze', '* * * * *', $cron$select private.completa_sorteggi_scaduti();$cron$);

-- Stato del sorteggio piu' recente della lega, con l'ora del server (cosi' il
-- client sincronizza il proprio orologio e tutti vedono la stessa estrazione).
create or replace function public.sorteggio_conferenze_stato(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_s public.sorteggi_conferenze;
begin
  if not (select private.e_membro(p_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;
  select * into v_s from public.sorteggi_conferenze
  where league_id = p_league_id order by stagione desc limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'sorteggio_id', v_s.id,
    'stagione', v_s.stagione,
    'avviato_il', v_s.avviato_il,
    'passo_secondi', v_s.passo_secondi,
    'totale', v_s.totale,
    'rivelate', private.sorteggio_rivelate(v_s.id),
    'completato', v_s.completato_il is not null,
    'ora_server', clock_timestamp()
  );
end;
$$;
revoke all on function public.sorteggio_conferenze_stato(bigint) from public, anon;
grant execute on function public.sorteggio_conferenze_stato(bigint) to authenticated;

CREATE OR REPLACE FUNCTION private.inizializza_stagione(p_league_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_league public.leagues;
  v_season_id bigint;
  v_teams bigint[];
  v_rotation bigint[];
  v_next bigint[];
  v_team_count integer;
  v_slot_count integer;
  v_rounds integer;
  v_giornata integer;
  v_home bigint;
  v_away bigint;
  v_swap bigint;
  v_scadenza timestamptz;
  v_prima_giornata timestamptz;
  v_start date;
  v_campo_neutro boolean;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_gia_assegnate integer;
  v_gruppo text;
  v_conferenze boolean;
begin
  select * into v_league from public.leagues where id = p_league_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  v_conferenze := v_league.conferenze_attive;

  select id into v_season_id
  from public.seasons
  where league_id = p_league_id and numero = v_league.stagione_corrente;
  if found then return v_season_id; end if;

  if v_league.stato <> 'stagione' or v_league.fase_carriera <> 'normale' then
    raise exception using errcode = '55000', message = 'La lega non e'' pronta per iniziare la stagione.';
  end if;

  select coalesce(array_agg(t.id order by t.ordine_draft nulls last, t.id), array[]::bigint[]), count(*)::integer
  into v_teams, v_team_count
  from public.teams t
  where t.league_id = p_league_id and t.attiva;

  if v_team_count <> v_league.n_squadre then
    raise exception using errcode = '55000', message = 'Il numero di squadre attive non coincide con le impostazioni.';
  end if;

  select o.scade_il into v_scadenza
  from public.offseasons o
  where o.league_id = p_league_id and o.stagione_a = v_league.stagione_corrente
  order by o.id desc limit 1;

  -- Con le conferenze il calendario nasce a sorteggio concluso, non alla scadenza
  -- dell'off-season: la prima giornata si conta da adesso.
  v_prima_giornata := private.primo_calcio_dopo(case when v_conferenze then clock_timestamp() else coalesce(v_scadenza, clock_timestamp()) end);
  v_start := (v_prima_giornata at time zone 'Europe/Rome')::date;

  insert into public.seasons(league_id, numero, stato, data_inizio, data_fine, giornate_totali)
  values (p_league_id, v_league.stagione_corrente, 'in_corso', v_start,
          v_start + (v_league.giornate_totali - 1), v_league.giornate_totali)
  returning id into v_season_id;

  -- Il blocco "non svincolabile per 10 giornate dall'acquisto" confronta
  -- giornata_acquisizione con la prossima giornata in programma, ma
  -- giornata_acquisizione e' un numero di giornata SENZA stagione: a
  -- cavallo di due stagioni il confronto perde senso. Un acquisto alla
  -- giornata 19 della stagione scorsa, letto alla giornata 12 di questa,
  -- dava -7 giornate trascorse — messaggio assurdo ("mancano 17
  -- giornate") e blocco attivo fino alla 29ª di una stagione in cui il
  -- giocatore era in rosa dall'inizio. Un acquisto della stagione
  -- precedente non e' per definizione "recente": si azzera qui, alla
  -- nascita di ogni stagione, dove NULL significa gia' "mai bloccato"
  -- (draft, rose iniziali, off-season).
  update public.player_instances
  set giornata_acquisizione = null
  where league_id = p_league_id and giornata_acquisizione is not null;

  insert into public.standings(season_id, league_id, team_id, posizione, conferenza)
  select v_season_id, p_league_id, t.id,
         row_number() over(partition by c.conferenza order by t.nome, t.id)::smallint,
         c.conferenza
  from public.teams t
  left join (
    select x.team_id, x.conferenza
    from public.sorteggio_estrazioni x
    join public.sorteggi_conferenze s on s.id = x.sorteggio_id
    where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and v_conferenze
  ) c on c.team_id = t.id
  where t.league_id = p_league_id and t.attiva;

  -- Con le conferenze (East/West) si gioca solo dentro la propria: stesso
  -- metodo del cerchio, applicato a ciascun gruppo, sulle STESSE giornate.
  -- Senza conferenze c'e' un solo gruppo con tutte le squadre.
  foreach v_gruppo in array case when v_conferenze then array['est', 'ovest'] else array[''] end loop
    if v_conferenze then
      select coalesce(array_agg(x.team_id order by x.ordine), array[]::bigint[])
      into v_teams
      from public.sorteggio_estrazioni x
      join public.sorteggi_conferenze s on s.id = x.sorteggio_id
      where s.league_id = p_league_id and s.stagione = v_league.stagione_corrente and x.conferenza = v_gruppo;
      v_team_count := cardinality(v_teams);
    end if;
  v_slot_count := v_team_count + (v_team_count % 2);
  v_rounds := v_slot_count - 1;
  for v_leg in 1..v_league.n_gironi loop
    v_campo_neutro := (v_league.n_gironi % 2 = 1 and v_leg = v_league.n_gironi);
    v_rotation := v_teams;
    if v_team_count % 2 = 1 then
      v_rotation := array_append(v_rotation, null::bigint);
    end if;
    for v_round in 1..v_rounds loop
      v_giornata := (v_leg - 1) * v_rounds + v_round;
      for v_pair in 1..(v_slot_count / 2) loop
        v_home := v_rotation[v_pair];
        v_away := v_rotation[v_slot_count - v_pair + 1];
        if v_home is null or v_away is null then continue; end if;
        if mod(v_round, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        if mod(v_leg, 2) = 0 then
          v_swap := v_home; v_home := v_away; v_away := v_swap;
        end if;
        insert into public.fixtures(season_id, league_id, giornata, home_team_id, away_team_id, data_sim, campo_neutro)
        values (v_season_id, p_league_id, v_giornata, v_home, v_away,
                v_prima_giornata + ((v_giornata - 1) * interval '1 day'), v_campo_neutro);
      end loop;
      v_next := array[v_rotation[1], v_rotation[v_slot_count]];
      for v_index in 2..(v_slot_count - 1) loop
        v_next := array_append(v_next, v_rotation[v_index]);
      end loop;
      v_rotation := v_next;
    end loop;
  end loop;
  end loop;

  -- ------------------------------------------------------------
  --  Mercato a scelte: inventario, posizioni di transizione, apertura
  --  ON-Season. Tutto best-effort — non deve mai impedire alla stagione
  --  di iniziare (docs/decisioni-draft-picks.md §2.1, §3.1).
  -- ------------------------------------------------------------
  begin
    -- Bootstrap: solo alla primissima stagione di una lega nuova, che non
    -- ha ne' un draft precedente ne' un playoff precedente da cui
    -- ereditare le scelte 1..4. genera_scelte_draft parte da
    -- stagione_corrente+1 e non tocca mai la stagione 1: la si genera qui,
    -- una tantum, e si assegna subito ON-Season 1 dalla spesa del draft di
    -- creazione (nessun playoff esiste ancora). OFF-Season 1 resta
    -- 'futura' fino ai playoff di questa stessa stagione.
    if v_league.stagione_corrente = 1 then
      insert into public.scelte_draft (league_id, team_origine_id, team_proprietario_id, stagione, finestra)
      select p_league_id, t.id, t.id, 1, f.finestra
      from public.teams t
      cross join (values ('on'), ('off')) as f(finestra)
      where t.league_id = p_league_id and t.attiva
      on conflict (league_id, team_origine_id, stagione, finestra) do nothing;

      perform private.assegna_posizioni_transizione(p_league_id, 1::smallint, 'on');
    end if;

    perform private.genera_scelte_draft(p_league_id);

    if v_league.stagione_corrente = 2 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = 2 and stato <> 'futura';
      if v_gia_assegnate = 0 then
        perform private.assegna_posizioni_transizione(p_league_id, 2::smallint);
      end if;
    end if;

    if v_league.stagione_corrente >= 1 then
      select count(*) into v_gia_assegnate
      from public.scelte_draft
      where league_id = p_league_id and stagione = v_league.stagione_corrente
        and finestra = 'on' and stato = 'determinata';
      if v_gia_assegnate > 0 and not exists (
        select 1 from public.finestre_scelte
        where league_id = p_league_id and stagione = v_league.stagione_corrente and finestra = 'on'
      ) then
        v_giornata_mezza := v_league.giornate_totali / 2;
        select f.data_sim into v_data_mezza
        from public.fixtures f
        where f.season_id = v_season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
        limit 1;
        if v_data_mezza is not null then
          perform private.svela_finestra_scelte(
            p_league_id, v_league.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
          );
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'mercato a scelte: inizializzazione fallita per lega %: % (%)', p_league_id, sqlerrm, sqlstate;
  end;

  return v_season_id;
end;
$function$;

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
      perform private.risolvi_finestra_scelte(p_league_id, v_off.stagione_da, 'off', true);
    exception when others then
      raise warning 'mercato a scelte: risoluzione OFF-Season fallita per lega % stagione %: % (%)',
        p_league_id, v_off.stagione_da, sqlerrm, sqlstate;
    end;
  end if;

  select count(*)::integer into v_attive
  from public.teams where league_id = p_league_id and attiva;
  if v_attive < 4 then
    raise exception using errcode = '55000', message = 'Servono almeno 4 squadre attive per iniziare la stagione.';
  end if;

  update public.leagues set n_squadre = v_attive where id = p_league_id;

  update public.player_instances
  set team_id = null
  where league_id = p_league_id
    and team_id is not null
    and not ritirato
    and contratto_scadenza <= v_league.stagione_corrente;

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

  update public.offseasons
  set stato = 'conclusa', conclusa_il = clock_timestamp()
  where id = v_off.id;
  update public.leagues
  set stagione_corrente = v_off.stagione_a,
      fase_carriera = case when v_league.conferenze_attive then 'sorteggio' else 'normale' end,
      offseason_fine = null,
      stato = 'stagione'
  where id = p_league_id;

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
  else
    v_season := private.inizializza_stagione(p_league_id);
  end if;

  perform private.notifica(
    t.user_id, p_league_id, 'sistema',
    case when v_league.conferenze_attive then 'Sorteggio delle conferenze in diretta' else 'La nuova stagione e'' iniziata' end,
    case when v_league.conferenze_attive then 'Entra ora: si estrae chi va a East e chi a West, una squadra ogni 20 secondi.'
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

CREATE OR REPLACE FUNCTION public.registra_risultato_partita(p_fixture_id bigint, p_seed bigint, p_modulo_home text, p_modulo_away text, p_stile_home text, p_stile_away text, p_gol_home smallint, p_gol_away smallint, p_blocchi jsonb, p_stats_squadra jsonb, p_player_stats jsonb, p_titolari_home bigint[] DEFAULT '{}'::bigint[], p_titolari_away bigint[] DEFAULT '{}'::bigint[], p_gol_home_90 smallint DEFAULT NULL::smallint, p_gol_away_90 smallint DEFAULT NULL::smallint, p_rigori_home smallint DEFAULT NULL::smallint, p_rigori_away smallint DEFAULT NULL::smallint, p_rigori_serie jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_fixture public.fixtures;
  v_match public.matches;
  v_season public.seasons;
begin
  select * into v_fixture
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Fixture non trovata.';
  end if;

  select * into v_match
  from public.matches
  where fixture_id = p_fixture_id;

  if found then
    return jsonb_build_object(
      'match_id', v_match.id,
      'fixture_id', v_match.fixture_id,
      'gia_simulata', true,
      'gol_home', v_match.gol_home,
      'gol_away', v_match.gol_away
    );
  end if;

  select * into v_season
  from public.seasons
  where id = v_fixture.season_id
    and league_id = v_fixture.league_id;

  if not found or v_season.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'La stagione non e'' in corso.';
  end if;
  if v_fixture.stato not in ('programmata', 'in_corso') then
    raise exception using errcode = '55000', message = 'La fixture non puo'' essere simulata.';
  end if;
  if p_seed not between 1 and 4294967295 then
    raise exception using errcode = '22023', message = 'Seed non valido.';
  end if;
  if p_gol_home < 0 or p_gol_away < 0 then
    raise exception using errcode = '22023', message = 'Il risultato contiene gol negativi.';
  end if;
  if jsonb_typeof(p_blocchi) <> 'array'
     or jsonb_typeof(p_stats_squadra) <> 'object'
     or jsonb_typeof(p_player_stats) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload statistiche non valido.';
  end if;
  if not (p_modulo_home = any(private.moduli_validi()))
     or not (p_modulo_away = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_home = any(private.stili_validi()))
     or not (p_stile_away = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;

  if not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.home_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_home
      and l.stile_gioco = p_stile_home
  ) or not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.away_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_away
      and l.stile_gioco = p_stile_away
  ) then
    raise exception using errcode = '55000', message = 'Manca una formazione valida per questa partita.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_player_stats) as x(
      player_instance_id bigint,
      team_id bigint,
      minuti smallint,
      gol smallint,
      assist smallint,
      tiri smallint,
      tiri_porta smallint,
      passaggi_tentati smallint,
      passaggi_riusciti smallint,
      contrasti_vinti smallint,
      contrasti_persi smallint,
      dribbling smallint
    )
    left join public.player_instances pi
      on pi.id = x.player_instance_id
     and pi.league_id = v_fixture.league_id
     and pi.team_id = x.team_id
    where pi.id is null
       or x.team_id not in (v_fixture.home_team_id, v_fixture.away_team_id)
  ) then
    raise exception using errcode = '42501', message = 'Le statistiche contengono un giocatore fuori dalle squadre della partita.';
  end if;

  insert into public.matches (
    fixture_id,
    league_id,
    gol_home,
    gol_away,
    modulo_home,
    modulo_away,
    stile_home,
    stile_away,
    seed,
    blocchi,
    stats_squadra,
    titolari_home,
    titolari_away,
    gol_home_90,
    gol_away_90,
    rigori_home,
    rigori_away,
    rigori_serie
  ) values (
    p_fixture_id,
    v_fixture.league_id,
    p_gol_home,
    p_gol_away,
    p_modulo_home,
    p_modulo_away,
    p_stile_home,
    p_stile_away,
    p_seed,
    p_blocchi,
    p_stats_squadra,
    coalesce(p_titolari_home, '{}'::bigint[]),
    coalesce(p_titolari_away, '{}'::bigint[]),
    p_gol_home_90,
    p_gol_away_90,
    p_rigori_home,
    p_rigori_away,
    p_rigori_serie
  )
  returning * into v_match;

  insert into public.match_stats (
    match_id,
    league_id,
    team_id,
    player_instance_id,
    minuti,
    gol,
    assist,
    tiri,
    tiri_porta,
    passaggi_tentati,
    passaggi_riusciti,
    contrasti_vinti,
    contrasti_persi,
    dribbling
  )
  select
    v_match.id,
    v_fixture.league_id,
    x.team_id,
    x.player_instance_id,
    x.minuti,
    x.gol,
    x.assist,
    x.tiri,
    x.tiri_porta,
    x.passaggi_tentati,
    x.passaggi_riusciti,
    x.contrasti_vinti,
    x.contrasti_persi,
    x.dribbling
  from jsonb_to_recordset(p_player_stats) as x(
    player_instance_id bigint,
    team_id bigint,
    minuti smallint,
    gol smallint,
    assist smallint,
    tiri smallint,
    tiri_porta smallint,
    passaggi_tentati smallint,
    passaggi_riusciti smallint,
    contrasti_vinti smallint,
    contrasti_persi smallint,
    dribbling smallint
  );

  -- Le partite di playoff/playout non entrano in classifica (design §10.7):
  -- la stagione regolare e' gia' chiusa e la sua classifica e' congelata.
  if v_fixture.bracket_tie_id is null then
  update public.standings
  set
    vittorie = vittorie + case
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 1
      else 0 end,
    pareggi = pareggi + case when p_gol_home = p_gol_away then 1 else 0 end,
    sconfitte = sconfitte + case
      when team_id = v_fixture.home_team_id and p_gol_home < p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away < p_gol_home then 1
      else 0 end,
    punti = punti + case
      when p_gol_home = p_gol_away then 1
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 3
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 3
      else 0 end,
    gol_fatti = gol_fatti + case when team_id = v_fixture.home_team_id then p_gol_home else p_gol_away end,
    gol_subiti = gol_subiti + case when team_id = v_fixture.home_team_id then p_gol_away else p_gol_home end,
    aggiornata_il = now()
  where season_id = v_fixture.season_id
    and team_id in (v_fixture.home_team_id, v_fixture.away_team_id);
  end if;

  -- Le due barre di familiarita' (vedi 20260917010000). Lo schieramento e le
  -- indicazioni si leggono dalla formazione di giornata invece di arrivare per
  -- parametro: questa funzione ne ha gia' diciotto.
  perform private.avanza_familiarita(
    v_fixture.home_team_id, v_fixture.league_id, p_modulo_home, p_stile_home, v_fixture.giornata);
  perform private.avanza_familiarita(
    v_fixture.away_team_id, v_fixture.league_id, p_modulo_away, p_stile_away, v_fixture.giornata);

  insert into public.stile_xp (team_id, league_id, stile, partite_giocate)
  values
    (v_fixture.home_team_id, v_fixture.league_id, p_stile_home, 1),
    (v_fixture.away_team_id, v_fixture.league_id, p_stile_away, 1)
  on conflict (team_id, stile) do update set
    partite_giocate = public.stile_xp.partite_giocate + 1,
    aggiornata_il = now();

  update public.fixtures
  set stato = 'simulata'
  where id = p_fixture_id;

  -- La posizione e' ricalcolata dopo ogni risultato. Gli scontri diretti
  -- considerano soltanto le avversarie a pari punti nella classifica attuale.
  if v_fixture.bracket_tie_id is null then
  update public.standings
  set posizione = null
  where season_id = v_fixture.season_id;

  with h2h as (
    select
      st.team_id,
      coalesce(sum(case
        when f.home_team_id = st.team_id and m.gol_home > m.gol_away then 3
        when f.away_team_id = st.team_id and m.gol_away > m.gol_home then 3
        when m.gol_home = m.gol_away then 1
        else 0
      end), 0)::integer as punti_diretti
    from public.standings st
    left join public.fixtures f
      on f.season_id = st.season_id
     and (f.home_team_id = st.team_id or f.away_team_id = st.team_id)
    left join public.matches m on m.fixture_id = f.id
    left join public.standings opponent
      on opponent.season_id = st.season_id
     and opponent.team_id = case
       when f.home_team_id = st.team_id then f.away_team_id
       else f.home_team_id
     end
     and opponent.punti = st.punti
    where st.season_id = v_fixture.season_id
      and opponent.team_id is not null
    group by st.team_id
  ), ranking as (
    select
      st.team_id,
      row_number() over (
        partition by st.conferenza
        order by st.punti desc,
                 coalesce(h2h.punti_diretti, 0) desc,
                 st.differenza_reti desc,
                 st.gol_fatti desc,
                 st.team_id
      )::smallint as posizione
    from public.standings st
    left join h2h on h2h.team_id = st.team_id
    where st.season_id = v_fixture.season_id
  )
  update public.standings st
  set posizione = ranking.posizione
  from ranking
  where st.season_id = v_fixture.season_id
    and st.team_id = ranking.team_id;
  end if;

  -- Un accoppiamento si risolve appena entrambe le sue mani sono giocate:
  -- da li' nasce il turno successivo, e alla fine i premi del playout.
  if v_fixture.bracket_tie_id is not null then
    perform private.risolvi_tie(v_fixture.bracket_tie_id);
  end if;

  if not exists (
    select 1 from public.fixtures
    where season_id = v_fixture.season_id
      and stato = 'programmata'
  ) then
    -- Finita la stagione regolare non si chiude subito: se la lega ha almeno
    -- 8 squadre nascono playoff e playout, con le loro fixtures (design
    -- §10.7). La stagione finisce davvero solo quando anche quelle sono state
    -- giocate, e a quel punto qui non si crea piu' nulla.
    if not exists (select 1 from public.brackets where season_id = v_fixture.season_id) then
      perform private.crea_tabelloni(v_fixture.season_id);
    end if;

    if not exists (
      select 1 from public.fixtures
      where season_id = v_fixture.season_id
        and stato = 'programmata'
    ) then
      update public.seasons
      set stato = 'conclusa', data_fine = (now() at time zone 'Europe/Rome')::date
      where id = v_fixture.season_id;
      update public.leagues
      set stato = 'conclusa'
      where id = v_fixture.league_id;
    end if;
  end if;

  return jsonb_build_object(
    'match_id', v_match.id,
    'fixture_id', v_match.fixture_id,
    'gia_simulata', false,
    'gol_home', v_match.gol_home,
    'gol_away', v_match.gol_away
  );
end;
$function$;

notify pgrst, 'reload schema';
