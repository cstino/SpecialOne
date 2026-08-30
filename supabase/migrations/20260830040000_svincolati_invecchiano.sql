begin;

-- ============================================================
--  GLI SVINCOLATI INVECCHIANO ED EVOLVONO ANCHE FUORI ROSA
--
--  Deciso il 30 agosto 2026, in conversazione con l'utente. Prima d'ora
--  un giocatore mai preso da nessuna squadra restava congelato ai valori
--  di importazione (public.players.overall/eta sono statici, nessun job
--  li tocca) e uno svincolato dopo essere stato in rosa smetteva di
--  evolvere nel momento stesso in cui restava senza squadra (la
--  progressione e l'invecchiamento leggevano solo player_instances con
--  team_id di una squadra attiva).
--
--  Decisione (per lega, non un orologio globale): ogni lega tiene un
--  proprio binario temporale anche per chi non e' mai stato scelto,
--  esattamente come gia' fa per chi e' stato scelto e poi svincolato
--  (player_instances.team_id nullo = "svincolato" fin dal commento
--  originale di 20260731120500_rose.sql). Per i "mai scelti" serve pero'
--  un posto dove tracciare l'evoluzione, perche' public.players e'
--  condiviso da tutte le leghe e non puo' diventare il registro di una
--  sola: nasce quindi public.free_agent_progression, popolata una volta
--  per lega con gli stessi giocatori idonei al pool di quella lega, e
--  aggiornata dagli stessi due meccanismi che gia' esistono per chi e'
--  in rosa (progressione trimestrale, invecchiamento di fine stagione),
--  solo estesi per includerla.
--
--  Chi e' gia' stato scelto (anche se poi svincolato) NON entra in
--  questa tabella: la sua evoluzione resta dove e' sempre stata, dentro
--  la sua riga di player_instances — che pero' andava anch'essa
--  sbloccata dal vincolo "squadra attiva", altrimenti uno svincolato
--  reale avrebbe continuato a restare congelato esattamente come un
--  giocatore mai scelto.
--
--  Il ritiro (chi esce definitivamente dal pool oltre i 34 anni) resta
--  fuori da questo cambiamento: gia' funziona per i mai-scelti in
--  private.finalizza_offseason usando (p.eta + stagione_a - 1) come eta'
--  ipotetica, e non lo si tocca qui.
-- ============================================================

-- ------------------------------------------------------------
--  1. Tabella: overall/eta correnti di chi non ha ancora un'istanza in
--     questa lega (mai scelto). Chi ha gia' un'istanza (scelto e magari
--     poi svincolato) evolve dentro player_instances, non qui: le due
--     tabelle non si sovrappongono mai per lo stesso (league_id, player_id).
-- ------------------------------------------------------------

create table public.free_agent_progression (
  league_id        bigint not null references public.leagues (id) on delete cascade,
  player_id        bigint not null references public.players (id) on delete cascade,
  overall_corrente smallint not null check (overall_corrente between 40 and 99),
  eta_corrente     smallint not null check (eta_corrente between 15 and 45),
  aggiornato_il    timestamptz not null default now(),
  primary key (league_id, player_id)
);

create index free_agent_progression_league_idx on public.free_agent_progression (league_id);

comment on table public.free_agent_progression is
  'Overall/eta correnti dei giocatori mai scelti in questa lega (nessuna riga in player_instances). Popolata una volta alla creazione della lega, aggiornata dagli stessi cicli di progressione/invecchiamento di chi e'' in rosa.';

alter table public.free_agent_progression enable row level security;

create policy free_agent_progression_lettura on public.free_agent_progression
  for select to authenticated
  using ((select private.e_membro(league_id)));

grant select on public.free_agent_progression to authenticated;
grant select, insert, update, delete on public.free_agent_progression to service_role;

-- ------------------------------------------------------------
--  2. Popolamento: tutti i giocatori idonei al pool di questa lega
--     (stesso filtro campionato/elite usato ovunque nel mercato) che non
--     hanno ancora nessuna istanza. Idempotente (on conflict do nothing):
--     si puo' richiamare in sicurezza sia alla creazione sia per un
--     backfill una tantum sulle leghe esistenti.
-- ------------------------------------------------------------

create or replace function private.popola_pool_svincolati(p_league_id bigint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_creati integer;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  insert into public.free_agent_progression (league_id, player_id, overall_corrente, eta_corrente)
  select p_league_id, p.id, p.overall, p.eta
  from public.players p
  where (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
  on conflict (league_id, player_id) do nothing;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$$;

revoke all on function private.popola_pool_svincolati(bigint) from public, anon, authenticated;
grant execute on function private.popola_pool_svincolati(bigint) to service_role;

-- Backfill una tantum sulle leghe gia' esistenti.
do $$
declare
  v_lega record;
begin
  for v_lega in select id from public.leagues loop
    perform private.popola_pool_svincolati(v_lega.id);
  end loop;
end;
$$;

-- ------------------------------------------------------------
--  3. crea_lega: popola il pool per ogni lega nuova, stesso momento in
--     cui nasce la lega (dopo che campionati_attivi e' gia' stato
--     scritto, quindi il filtro di popola_pool_svincolati lo trova).
-- ------------------------------------------------------------

create or replace function public.crea_lega(p_nome_lega text, p_nome_squadra text, p_stemma_url text, p_n_squadre smallint, p_n_gironi smallint, p_budget_iniziale bigint, p_budget_draft bigint, p_reroll_draft smallint, p_slot_rosa smallint, p_portieri_minimi smallint, p_campionati_attivi text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;
  if (select auth.email()) is distinct from 'cr.96bc@gmail.com' then
    raise exception using errcode = '42501', message = 'Solo l''amministratore del progetto può creare nuove leghe.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);
  p_portieri_minimi := 0;

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_budget_draft not between 20000000 and 200000000
    or p_budget_draft > p_budget_iniziale
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa <> 24 then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, budget_draft, tetto_ingaggi, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi, stato
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_budget_draft, p_budget_iniziale, p_reroll_draft, 24, p_portieri_minimi,
        p_campionati_attivi, 'draft'
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.draft_state (league_id) values (v_league.id);
  insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);

  perform private.popola_pool_svincolati(v_league.id);

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

commit;
