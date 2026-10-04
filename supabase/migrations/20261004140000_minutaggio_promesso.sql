-- ============================================================
--  MINUTAGGIO PROMESSO E RICHIESTA DI CESSIONE
--  docs/decisioni-minutaggio.md (deciso col committente il 4 ottobre 2026)
--
--  Il minutaggio fa parte del contratto: quattro gradini (titolare fisso,
--  turnover, sporadico, promessa futura) che il morale usa al posto della
--  quota attesa dall'overall, che si trattano al rinnovo insieme
--  all'ingaggio, e che il giocatore fa valere: un controllo ogni 5 giornate,
--  un richiamo, poi la richiesta di cessione (non rinnova piu').
--  Tutto vale solo nelle leghe con tattiche_attive.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Colonne
-- ------------------------------------------------------------
alter table public.player_instances
  add column if not exists minutaggio_promesso text
    check (minutaggio_promesso in ('titolare', 'turnover', 'sporadico', 'promessa')),
  add column if not exists arrivo_stagione smallint,
  add column if not exists richiamo_stagione smallint,
  add column if not exists richiamo_giornata smallint,
  add column if not exists richiesta_cessione_stagione smallint;

comment on column public.player_instances.minutaggio_promesso is
  'Gradino di minutaggio trattato al rinnovo (docs/decisioni-minutaggio.md). Vuoto = gradino automatico dalla gerarchia della rosa.';
comment on column public.player_instances.arrivo_stagione is
  'Stagione in cui e'' arrivato nella squadra attuale (con giornata_acquisizione dice da quando contare i suoi minuti). Vuoto = da prima.';
comment on column public.player_instances.richiesta_cessione_stagione is
  'Stagione in cui ha chiesto la cessione per minutaggio non rispettato: non rinnova piu'' il contratto.';

-- ------------------------------------------------------------
-- 2. Gradini
-- ------------------------------------------------------------
create or replace function private.quota_minutaggio(p_gradino text)
returns numeric
language sql
immutable parallel safe
set search_path = ''
as $$
  select case p_gradino
    when 'titolare' then 0.75
    when 'turnover' then 0.40
    when 'sporadico' then 0.05
    when 'promessa' then 0.05
    else 0.40
  end::numeric;
$$;

create or replace function private.reparto_minutaggio(p_posizione text)
returns text
language sql
immutable parallel safe
set search_path = ''
as $$
  select case
    when p_posizione = 'GK' then 'GK'
    when p_posizione in ('CB', 'LB', 'RB', 'LWB', 'RWB') then 'DEF'
    when p_posizione in ('CDM', 'CM', 'CAM', 'LM', 'RM') then 'MID'
    else 'ATT'
  end;
$$;

-- Gradino automatico: posizione nel proprio reparto, per overall, dentro la
-- rosa (portieri 1 titolare; difesa e centrocampo 4+2; attacco 2+2). Un under
-- 21 che non e' titolare fisso e' una promessa futura.
create or replace function private.gradino_automatico(p_instance_id bigint)
returns text
language sql
stable
set search_path = ''
as $$
  with me as (
    select pi.id, pi.team_id, pi.eta_corrente,
           private.reparto_minutaggio((coalesce(pi.posizioni_override, p.posizioni))[1]) as reparto
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.id = p_instance_id
  ), classifica as (
    select x.id,
           row_number() over (order by x.overall_corrente desc, x.id) as posto
    from public.player_instances x
    join public.players px on px.id = x.player_id
    join me on me.team_id = x.team_id
    where not x.ritirato
      and private.reparto_minutaggio((coalesce(x.posizioni_override, px.posizioni))[1]) = me.reparto
  ), base as (
    select me.eta_corrente,
           case
             when me.team_id is null then 'sporadico'
             when c.posto is null then 'sporadico'
             when me.reparto = 'GK' then case when c.posto = 1 then 'titolare' else 'sporadico' end
             when me.reparto = 'ATT' then case when c.posto <= 2 then 'titolare' when c.posto <= 4 then 'turnover' else 'sporadico' end
             else case when c.posto <= 4 then 'titolare' when c.posto <= 6 then 'turnover' else 'sporadico' end
           end as gradino
    from me
    left join classifica c on c.id = me.id
  )
  select case when gradino <> 'titolare' and eta_corrente < 21 then 'promessa' else gradino end
  from base;
$$;

create or replace function private.gradino_effettivo(p_instance_id bigint)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(pi.minutaggio_promesso, private.gradino_automatico(pi.id))
  from public.player_instances pi
  where pi.id = p_instance_id;
$$;

-- Un gradino puo' non essere alla sua altezza: null = accettabile, altrimenti
-- il motivo del rifiuto (docs/decisioni-minutaggio.md §2).
create or replace function private.gradino_rifiutato(p_gradino text, p_eta smallint, p_overall smallint, p_media_rosa numeric)
returns text
language sql
immutable parallel safe
set search_path = ''
as $$
  select case
    when p_gradino = 'promessa' and p_eta >= 21 then 'Ha già compiuto 21 anni: non è più una promessa.'
    when p_gradino = 'sporadico' and p_overall - coalesce(p_media_rosa, p_overall) >= 3 then 'È tra i migliori della rosa: non accetta di giocare così poco.'
    when p_gradino = 'turnover' and p_overall - coalesce(p_media_rosa, p_overall) >= 6 then 'È uno dei leader della squadra: vuole il posto da titolare.'
    else null
  end;
$$;

-- Promettere piu' minuti fa accettare meno soldi (docs/decisioni-minutaggio.md §2).
create or replace function private.richiesta_per_gradino(p_richiesta bigint, p_gradino text)
returns bigint
language sql
immutable parallel safe
set search_path = ''
as $$
  select greatest(500000::bigint, (round(p_richiesta * case p_gradino
    when 'titolare' then 0.92
    when 'sporadico' then 1.12
    when 'promessa' then 0.90
    else 1.00
  end / 100000) * 100000)::bigint);
$$;

revoke all on function private.quota_minutaggio(text), private.reparto_minutaggio(text),
  private.gradino_automatico(bigint), private.gradino_effettivo(bigint),
  private.gradino_rifiutato(text, smallint, smallint, numeric), private.richiesta_per_gradino(bigint, text)
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. Trasferimento: la promessa era della squadra di prima
-- ------------------------------------------------------------
create or replace function private.reset_rinnovo_al_trasferimento()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if old.team_id is not null
     and new.team_id is not null
     and old.team_id is distinct from new.team_id then
    new.rinnovo_tentativi := 0;
  end if;

  -- Minutaggio (docs/decisioni-minutaggio.md §3, §5): gradino, richiami e
  -- richiesta di cessione restano alla squadra che li ha vissuti.
  if old.team_id is distinct from new.team_id then
    new.minutaggio_promesso := null;
    new.richiamo_stagione := null;
    new.richiamo_giornata := null;
    new.richiesta_cessione_stagione := null;
    new.arrivo_stagione := case when new.team_id is null then null
      else (select l.stagione_corrente from public.leagues l where l.id = new.league_id) end;
  end if;

  return new;
end;
$function$;

-- ------------------------------------------------------------
-- 4. Morale: la quota attesa viene dal gradino
-- ------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public.applica_morale_checkpoint(bigint, smallint)'::regprocedure);
  v_a text;
begin
  v_a := E'        p.mentalita_vittorie,\n';
  if position(v_a in v_def) = 0 then raise exception 'morale: ancora mentalita_vittorie non trovata'; end if;
  v_def := replace(v_def, v_a, v_a || E'        pi.minutaggio_promesso,\n        l.tattiche_attive as tattiche,\n');

  v_a := '          - private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente))';
  if position(v_a in v_def) = 0 then raise exception 'morale: ancora quota_partite_attesa non trovata'; end if;
  v_def := replace(v_def, v_a,
    E'          - case when v_giocatore.tattiche\n'
    || E'              then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))\n'
    || E'              else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end');

  v_a := '      -- 2. Economia, pesata dal ramo';
  if position(v_a in v_def) = 0 then raise exception 'morale: ancora economia non trovata'; end if;
  v_def := replace(v_def, v_a,
    E'      -- Promessa trattata e non mantenuta: pesa il 50% in piu''\n'
    || E'      -- (docs/decisioni-minutaggio.md, punto 4).\n'
    || E'      if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_delta_min < 0 then\n'
    || E'        v_delta_min := greatest(-18, v_delta_min * 1.5);\n'
    || E'      end if;\n\n'
    || v_a);

  execute v_def;
end;
$$;

-- ------------------------------------------------------------
-- 5. Rinnovi: si tratta anche il gradino
-- ------------------------------------------------------------
create or replace function public.proposta_rinnovo(p_instance_id bigint)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_media numeric;
  v_gradini jsonb := '[]'::jsonb;
  v_g text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  if not exists (
    select 1 from public.teams
    where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnovera'' il contratto.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  if v_league.tattiche_attive then
    select avg(x.overall_corrente) into v_media
    from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
    foreach v_g in array array['titolare', 'turnover', 'sporadico', 'promessa'] loop
      v_gradini := v_gradini || jsonb_build_object(
        'chiave', v_g,
        'richiesta', private.richiesta_per_gradino(v_proposta.richiesta, v_g),
        'rifiuto', private.gradino_rifiutato(v_g, v_inst.eta_corrente, v_inst.overall_corrente, v_media)
      );
    end loop;
  end if;

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'ingaggio_attuale', v_inst.ingaggio,
    'scadenza_attuale', v_inst.contratto_scadenza,
    'stagione_corrente', v_league.stagione_corrente,
    'richiesta', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'nuova_scadenza', greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint),
    'tentativi_usati', v_inst.rinnovo_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_inst.rinnovo_tentativi >= 3,
    'gia_rinnovato', v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente,
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    ),
    -- Minutaggio (docs/decisioni-minutaggio.md): vuoto nelle leghe senza tattiche.
    'gradino_attuale', case when v_league.tattiche_attive then private.gradino_effettivo(v_inst.id) end,
    'gradino_trattato', v_inst.minutaggio_promesso is not null,
    'gradini', case when v_league.tattiche_attive then v_gradini end
  );
end;
$function$;

drop function if exists public.offri_rinnovo(bigint, bigint, smallint);

create or replace function public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint, p_minutaggio text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
  v_gradino text;
  v_media numeric;
  v_rifiuto text;
  v_richiesta bigint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata <> 1 then
    raise exception using errcode = '22023',
      message = 'I contratti durano una stagione: il rinnovo estende di un anno.';
  end if;
  if p_minutaggio is not null and p_minutaggio not in ('titolare', 'turnover', 'sporadico', 'promessa') then
    raise exception using errcode = '22023', message = 'Minutaggio non valido.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_league.tattiche_attive and v_inst.richiesta_cessione_stagione is not null then
    raise exception using errcode = '55000', message = 'Ha chiesto la cessione: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  -- Il gradino: quello offerto, o (senza sceglierlo) quello che ha gia'. Un
  -- gradino non alla sua altezza lo rifiuta senza consumare un tentativo.
  v_richiesta := v_proposta.richiesta;
  if v_league.tattiche_attive then
    v_gradino := coalesce(p_minutaggio, private.gradino_effettivo(v_inst.id));
    if p_minutaggio is not null then
      select avg(x.overall_corrente) into v_media
      from public.player_instances x where x.team_id = v_inst.team_id and not x.ritirato;
      v_rifiuto := private.gradino_rifiutato(p_minutaggio, v_inst.eta_corrente, v_inst.overall_corrente, v_media);
      if v_rifiuto is not null then
        return jsonb_build_object(
          'esito', 'gradino_rifiutato',
          'tentativi_usati', v_inst.rinnovo_tentativi,
          'tentativi_totali', 3,
          'messaggio', case p_minutaggio
            when 'promessa' then 'Mister, non sono più un ragazzino.'
            else 'Con tutto il rispetto, mister: non sono venuto qui per fare panchina.' end,
          'motivo', v_rifiuto
        );
      end if;
    end if;
    v_richiesta := private.richiesta_per_gradino(v_proposta.richiesta, v_gradino);
  end if;

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_richiesta * (1 - v_tolleranza);

  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente,
        -- Il gradino trattato diventa parte del contratto; senza sceglierlo
        -- resta com'era (anche automatico).
        minutaggio_promesso = case when v_league.tattiche_attive and p_minutaggio is not null
                                   then p_minutaggio else minutaggio_promesso end,
        richiamo_stagione = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_stagione end,
        richiamo_giornata = case when v_league.tattiche_attive and p_minutaggio is not null
                                 then null else richiamo_giornata end
    where id = v_inst.id;

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      0
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', 1,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'minutaggio', v_gradino,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

revoke all on function public.offri_rinnovo(bigint, bigint, smallint, text) from public, anon;
grant execute on function public.offri_rinnovo(bigint, bigint, smallint, text) to authenticated;

-- Il gradino di ogni giocatore di una rosa, per la scheda: lo vede tutta la
-- lega (come in FM lo status in rosa non e' un segreto) e cosi' la richiesta
-- di cessione; il richiamo, che e' un messaggio al mister, solo il proprietario.
create or replace function public.gradini_squadra(p_team_id bigint)
returns table(player_instance_id bigint, gradino text, trattato boolean, richiamo boolean, cessione boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select pi.id,
         private.gradino_effettivo(pi.id),
         pi.minutaggio_promesso is not null,
         t.user_id = (select auth.uid()) and pi.richiamo_stagione = l.stagione_corrente,
         pi.richiesta_cessione_stagione is not null
  from public.player_instances pi
  join public.teams t on t.id = pi.team_id
  join public.leagues l on l.id = pi.league_id
  where pi.team_id = p_team_id and not pi.ritirato and l.tattiche_attive
    and (select private.e_membro(pi.league_id));
$$;

revoke all on function public.gradini_squadra(bigint) from public, anon;
grant execute on function public.gradini_squadra(bigint) to authenticated;

-- ------------------------------------------------------------
-- 6. I controlli: richiamo, poi richiesta di cessione
-- ------------------------------------------------------------
create table if not exists private.minutaggio_controlli (
  season_id  bigint not null references public.seasons(id) on delete cascade,
  giornata   smallint not null,
  fatto_il   timestamptz not null default now(),
  primary key (season_id, giornata)
);

comment on table private.minutaggio_controlli is
  'Controlli del minutaggio promesso gia'' fatti (docs/decisioni-minutaggio.md §5): uno ogni 5 giornate dalla 8.';

create or replace function private.controlla_minutaggio(p_league_id bigint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_ultima smallint;
  v_controllo smallint;
  v_g record;
  v_inizio smallint;
  v_partite integer;
  v_minuti numeric;
  v_reale numeric;
  v_attesa numeric;
  v_messaggi integer := 0;
  v_nome_gradino text;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione' and l.tattiche_attive;
  if not found then return 0; end if;

  -- Ultima giornata di stagione regolare gia' giocata.
  select max(f.giornata) into v_ultima
  from public.fixtures f
  where f.season_id = v_lega.season_id and f.stato = 'simulata' and f.giornata <= v_lega.giornate_totali;
  if v_ultima is null or v_ultima < 8 then return 0; end if;

  -- Il controllo piu' recente raggiunto: 8, 13, 18, 23, 28...
  v_controllo := (8 + ((v_ultima - 8) / 5) * 5)::smallint;
  insert into private.minutaggio_controlli (season_id, giornata)
  values (v_lega.season_id, v_controllo)
  on conflict do nothing;
  if not found then return 0; end if;

  for v_g in
    select pi.id, pi.team_id, pi.arrivo_stagione, pi.giornata_acquisizione, pi.richiamo_stagione,
           pi.minutaggio_promesso, t.user_id, p.nome
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id
      and not pi.ritirato and not pi.ritiro_annunciato
      and pi.richiesta_cessione_stagione is null
      -- Solo le promesse trattate al rinnovo: il gradino automatico e' una
      -- stima della gerarchia, non una promessa (docs/decisioni-minutaggio.md §5).
      and pi.minutaggio_promesso is not null
      and coalesce(pi.infortunato_fino_a, 0) <= v_ultima
      and t.user_id is not null and not coalesce(t.controllata_da_pc, false)
    order by pi.id
    for update of pi
  loop
    v_inizio := case when v_g.arrivo_stagione = v_lega.stagione_corrente
                     then coalesce(v_g.giornata_acquisizione, 1) else 1 end;

    select count(*) into v_partite
    from public.fixtures f
    where f.season_id = v_lega.season_id and f.stato = 'simulata'
      and f.giornata between v_inizio and v_ultima
      and (f.home_team_id = v_g.team_id or f.away_team_id = v_g.team_id);
    if v_partite < 5 then continue; end if;

    select coalesce(sum(ms.minuti), 0) into v_minuti
    from public.match_stats ms
    join public.matches m on m.id = ms.match_id
    join public.fixtures f on f.id = m.fixture_id
    where ms.player_instance_id = v_g.id and ms.team_id = v_g.team_id
      and f.season_id = v_lega.season_id and f.giornata between v_inizio and v_ultima;

    v_reale := v_minuti / (90.0 * v_partite);
    v_attesa := private.quota_minutaggio(private.gradino_effettivo(v_g.id));
    v_nome_gradino := case private.gradino_effettivo(v_g.id)
      when 'titolare' then 'titolare fisso' when 'turnover' then 'turnover'
      when 'sporadico' then 'sporadico' else 'promessa futura' end;

    if v_reale < 0.6 * v_attesa and v_attesa - v_reale >= 0.10 then
      if v_g.richiamo_stagione = v_lega.stagione_corrente then
        update public.player_instances
        set richiesta_cessione_stagione = v_lega.stagione_corrente
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' chiede la cessione', 80),
          'Mister, la mia situazione non è cambiata: chiedo la cessione. Non rinnoverò il contratto.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'cessione_minutaggio'));
      else
        update public.player_instances
        set richiamo_stagione = v_lega.stagione_corrente, richiamo_giornata = v_controllo
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' chiede più spazio', 80),
          'Mister, mi era stato promesso il ruolo di ' || v_nome_gradino || ' e al momento non lo sto avendo. '
            || 'Le chiedo di migliorare la mia situazione, altrimenti sarò costretto a chiedere la cessione.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'richiamo_minutaggio'));
      end if;
      v_messaggi := v_messaggi + 1;
    elsif v_g.richiamo_stagione = v_lega.stagione_corrente then
      -- La situazione e' rientrata: il richiamo si cancella.
      update public.player_instances
      set richiamo_stagione = null, richiamo_giornata = null
      where id = v_g.id;
    end if;
  end loop;

  return v_messaggi;
end;
$$;

create or replace function private.controlla_minutaggio_tutte()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  for v_id in select id from public.leagues where tattiche_attive and stato = 'stagione' loop
    perform private.controlla_minutaggio(v_id);
  end loop;
end;
$$;

revoke all on function private.controlla_minutaggio(bigint), private.controlla_minutaggio_tutte()
  from public, anon, authenticated;

-- Le stagioni gia' in corso partono pulite: i controlli gia' "passati"
-- risultano fatti, cosi' nessuno riceve un richiamo per settimane in cui il
-- minutaggio non esisteva. Conta dal prossimo controllo.
insert into private.minutaggio_controlli (season_id, giornata)
select s.id, g::smallint
from public.seasons s
join public.leagues l on l.id = s.league_id and l.stagione_corrente = s.numero
cross join lateral generate_series(8, 60, 5) as g
where s.stato = 'in_corso'
  and g <= coalesce((select max(f.giornata) from public.fixtures f
                     where f.season_id = s.id and f.stato = 'simulata' and f.giornata <= l.giornate_totali), 0)
on conflict do nothing;

select cron.schedule(
  'controlla-minutaggio', '*/10 * * * *',
  $$select private.controlla_minutaggio_tutte();$$
);

commit;
