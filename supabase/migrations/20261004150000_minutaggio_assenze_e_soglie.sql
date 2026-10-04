-- ============================================================
--  MINUTAGGIO: gli assenti non contano, soglie piu' alte
--  docs/decisioni-minutaggio.md §6 (deciso col committente, 4 ottobre 2026)
--
--  1. Un giocatore infortunato o squalificato non puo' giocare: quella partita
--     non conta ne' nei minuti attesi ne' nella percentuale. Prima i controlli
--     contavano tutte le partite della squadra, e il controllo "non infortunato
--     al momento" confrontava un numero di giornate rimaste con un numero di
--     giornata (sempre vero, quindi non escludeva nessuno).
--     Lo storico non esisteva: ora un trigger sulle partite registra chi era
--     indisponibile al momento di ogni partita (prima che la simulazione
--     aggiorni infortuni e squalifiche, che avviene dopo il salvataggio delle
--     partite). Le partite gia' giocate prima di questa migrazione non hanno
--     storico e contano come "disponibile".
--  2. Soglia minima del titolare 55% (era 45%) e del turnover 30% (era 24%);
--     la quota promessa, usata dal morale, resta 75% e 40%.
-- ============================================================

begin;

create table if not exists private.assenze_partita (
  fixture_id         bigint not null references public.fixtures(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  motivo             text not null check (motivo in ('infortunio', 'squalifica')),
  primary key (fixture_id, player_instance_id)
);

comment on table private.assenze_partita is
  'Giocatori indisponibili (infortunati o squalificati) al momento di ogni partita: non contano nel minutaggio (docs/decisioni-minutaggio.md).';

create or replace function private.registra_assenze_partita()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.assenze_partita (fixture_id, player_instance_id, motivo)
  select new.fixture_id, pi.id,
         case when coalesce(pi.infortunato_fino_a, 0) > 0 then 'infortunio' else 'squalifica' end
  from public.fixtures f
  join public.player_instances pi on pi.team_id in (f.home_team_id, f.away_team_id)
  where f.id = new.fixture_id
    and not pi.ritirato
    and (coalesce(pi.infortunato_fino_a, 0) > 0 or coalesce(pi.squalificato_fino_a, 0) > 0)
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function private.registra_assenze_partita() from public, anon, authenticated;

drop trigger if exists matches_registra_assenze on public.matches;
create trigger matches_registra_assenze
  after insert on public.matches
  for each row execute function private.registra_assenze_partita();

-- Soglia minima: sotto questa quota di minuti (sulle partite giocabili) la
-- promessa non e' rispettata. In giallo fra la soglia e il 70% della soglia,
-- in rosso (richiamo) sotto.
create or replace function private.soglia_minutaggio(p_gradino text)
returns numeric
language sql
immutable parallel safe
set search_path = ''
as $$
  select case p_gradino
    when 'titolare' then 0.55
    when 'turnover' then 0.30
    when 'sporadico' then 0.03
    when 'promessa' then 0.03
    else 0.30
  end::numeric;
$$;

revoke all on function private.soglia_minutaggio(text) from public, anon, authenticated;

-- Minuti e partite della stagione regolare corrente dal suo arrivo in squadra,
-- ESCLUSE le partite in cui era infortunato o squalificato.
create or replace function private.minuti_stagione(p_instance_id bigint)
returns table(partite integer, minuti numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with g as (
    select pi.id, pi.team_id, pi.league_id,
           case when pi.arrivo_stagione = l.stagione_corrente then coalesce(pi.giornata_acquisizione, 1) else 1 end as inizio,
           l.giornate_totali, l.stagione_corrente
    from public.player_instances pi
    join public.leagues l on l.id = pi.league_id
    where pi.id = p_instance_id
  ), f as (
    select fx.id as fixture_id
    from g
    join public.seasons s on s.league_id = g.league_id and s.numero = g.stagione_corrente
    join public.fixtures fx on fx.season_id = s.id and fx.stato = 'simulata'
      and fx.giornata between g.inizio and g.giornate_totali
      and (fx.home_team_id = g.team_id or fx.away_team_id = g.team_id)
    where not exists (select 1 from private.assenze_partita a
                      where a.fixture_id = fx.id and a.player_instance_id = g.id)
  )
  select (select count(*) from f)::integer,
         coalesce((select sum(ms.minuti) from public.match_stats ms
                   join public.matches m on m.id = ms.match_id
                   join f on f.fixture_id = m.fixture_id
                   join g on true
                   where ms.player_instance_id = g.id and ms.team_id = g.team_id), 0)::numeric;
$$;

-- I controlli: stessa misura della percentuale che si vede in rosa.
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
    select pi.id, pi.team_id, pi.richiamo_stagione, t.user_id, p.nome
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id
      and not pi.ritirato and not pi.ritiro_annunciato
      and pi.richiesta_cessione_stagione is null
      -- Solo le promesse trattate o assegnate alla firma: il gradino
      -- automatico e' una stima, non una promessa.
      and pi.minutaggio_promesso is not null
      and t.user_id is not null and not coalesce(t.controllata_da_pc, false)
    order by pi.id
    for update of pi
  loop
    select ms.partite, ms.minuti into v_partite, v_minuti from private.minuti_stagione(v_g.id) ms;
    -- Con meno di 5 partite giocabili non c'e' abbastanza campione.
    if v_partite < 5 then continue; end if;

    v_gradino := private.gradino_effettivo(v_g.id);
    v_reale := v_minuti / (90.0 * v_partite);
    v_attesa := private.quota_minutaggio(v_gradino);
    v_soglia := private.soglia_minutaggio(v_gradino);
    v_nome_gradino := case v_gradino
      when 'titolare' then 'titolare fisso' when 'turnover' then 'turnover'
      when 'sporadico' then 'sporadico' else 'promessa futura' end;

    -- Molto al di sotto: meno del 70% della soglia minima e almeno 10 punti
    -- sotto la quota. E' il rosso dei minuti in rosa.
    if v_reale < 0.7 * v_soglia and v_attesa - v_reale >= 0.10 then
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
      update public.player_instances
      set richiamo_stagione = null, richiamo_giornata = null
      where id = v_g.id;
    end if;
  end loop;

  return v_messaggi;
end;
$$;

revoke all on function private.controlla_minutaggio(bigint) from public, anon, authenticated;

commit;
