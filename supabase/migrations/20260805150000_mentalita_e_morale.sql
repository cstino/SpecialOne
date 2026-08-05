-- ============================================================
--  MENTALITÀ E MORALE (design §11)
--
--  Richiesta dell'utente, 5 agosto 2026. Due meccaniche legate:
--
--  MENTALITÀ — tratto permanente del giocatore, tre rami che si dividono
--  100 punti (bandiera / economia / vittorie): dice COSA VIENE PRIMA per
--  quel giocatore, non quanto vale. Il dataset FC 26 non contiene nulla di
--  simile (le colonne mentality_* non sono importate e comunque misurano
--  altro), quindi va generata. Scelta dell'utente: deterministica dall'id,
--  cosi' lo stesso giocatore ha la stessa personalita' in ogni lega e per
--  sempre, e i partecipanti possono costruirsi un'intuizione stabile.
--
--  Implementata come COLONNE GENERATE, non come colonne riempite da un
--  UPDATE: cosi' non esiste il caso "giocatore importato dopo senza
--  mentalita'" (e' successo davvero con i 576 del pool elite globale del 4
--  agosto) e non puo' mai andare fuori sincrono. Serve una funzione
--  IMMUTABLE, quindi aritmetica pura: hashtext() e' solo STABLE.
--
--  Nota sulla generazione: i tre rami usano tre moltiplicatori DIVERSI.
--  Un primo tentativo usava lo stesso moltiplicatore con un offset per
--  ramo e produceva rami correlati (r2 = r1 + costante): misurato sui
--  5.992 giocatori dava "bandiera" dominante solo 1.123 volte contro le
--  ~2.434 delle altre due. Con moltiplicatori distinti: 1.908 / 1.996 /
--  1.897, cioe' un terzo ciascuno.
--
--  MORALE — stato che evolve, per istanza di giocatore (0-100, parte da
--  70). Ricalcolato a ogni quarto di stagione, come la progressione
--  overall. Componenti:
--    · minutaggio  — gioca quanto ritiene di dover giocare? (vale per tutti)
--    · economia    — e' pagato quanto vale? (pesato dal ramo economia)
--    · vittorie    — la squadra vince? (pesato dal ramo vittorie)
--    · bandiera    — NON e' un contributo a se': attenua le insoddisfazioni.
--                    Chi e' bandiera si lamenta meno di soldi e risultati,
--                    che e' esattamente la definizione data dall'utente
--                    ("soldi e vittorie vengono dopo").
--
--  Il morale NON tocca il rendimento in campo (decisione dell'utente):
--  engine/ resta intatto e non serve il protocollo di CLAUDE.md §4. Serve
--  ai rinnovi e alle richieste economiche.
-- ============================================================

-- ------------------------------------------------------------
--  MENTALITÀ
-- ------------------------------------------------------------

create or replace function private.mentalita_ramo(p_id bigint, p_ramo integer)
returns smallint
language sql
immutable
parallel safe
set search_path = ''
as $$
  with grezzi as (
    select
      15 + (((p_id * 2654435761) % 4294967296) / 4096) % 56 as r1,
      15 + (((p_id * 2246822519) % 4294967296) / 4096) % 56 as r2,
      15 + (((p_id * 3266489917) % 4294967296) / 4096) % 56 as r3
  ), quote as (
    select
      round(100.0 * r1 / (r1 + r2 + r3)) as bandiera,
      round(100.0 * r2 / (r1 + r2 + r3)) as economia
    from grezzi
  )
  select (case p_ramo
    when 1 then bandiera
    when 2 then economia
    else 100 - bandiera - economia
  end)::smallint
  from quote;
$$;

revoke all on function private.mentalita_ramo(bigint, integer) from public, anon;
grant execute on function private.mentalita_ramo(bigint, integer) to authenticated, service_role;

alter table public.players
  add column mentalita_bandiera smallint generated always as (private.mentalita_ramo(id, 1)) stored,
  add column mentalita_economia smallint generated always as (private.mentalita_ramo(id, 2)) stored,
  add column mentalita_vittorie smallint generated always as (private.mentalita_ramo(id, 3)) stored;

comment on column public.players.mentalita_bandiera is
  'Mentalità §11: attaccamento alla maglia. I tre rami sommano sempre 100. Generata dall''id, identica in ogni lega.';

-- ------------------------------------------------------------
--  MORALE
-- ------------------------------------------------------------

alter table public.player_instances
  add column morale smallint not null default 70 check (morale between 0 and 100);

comment on column public.player_instances.morale is
  'Morale §11, 0-100. Ricalcolato a ogni quarto di stagione da applica_morale_checkpoint.';

-- Quanto un giocatore ritiene di dover giocare, dalla sua posizione
-- rispetto all'overall medio della propria rosa (design §11.2).
create or replace function private.quota_partite_attesa(p_ovr smallint, p_media numeric)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_ovr - p_media >= 6  then 0.90
    when p_ovr - p_media >= 3  then 0.75
    when p_ovr - p_media >= -1 then 0.55
    when p_ovr - p_media >= -4 then 0.30
    else 0.10
  end::numeric;
$$;

revoke all on function private.quota_partite_attesa(smallint, numeric) from public, anon;
grant execute on function private.quota_partite_attesa(smallint, numeric) to authenticated, service_role;

-- Registro dei checkpoint di morale: separato da season_progression_checkpoints
-- perche' e' un meccanismo distinto, e tenerli separati permette di
-- correggerne uno senza toccare l'altro.
create table public.season_morale_checkpoints (
  season_id   bigint not null,
  league_id   bigint not null,
  checkpoint  smallint not null check (checkpoint between 1 and 4),
  giornata    smallint not null check (giornata >= 1),
  applicato_il timestamptz not null default now(),
  primary key (season_id, checkpoint)
);

alter table public.season_morale_checkpoints enable row level security;

create policy season_morale_checkpoints_lettura on public.season_morale_checkpoints
  for select to authenticated
  using ((select private.e_membro(league_id)));

grant select on public.season_morale_checkpoints to authenticated;
grant select, insert, update, delete on public.season_morale_checkpoints to service_role;

-- ------------------------------------------------------------
--  Ricalcolo del morale a un quarto di stagione
-- ------------------------------------------------------------

create or replace function public.applica_morale_checkpoint(
  p_league_id bigint,
  p_giornata smallint
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
        p.mentalita_bandiera,
        p.mentalita_economia,
        p.mentalita_vittorie,
        -- media overall della propria rosa: e' il metro con cui il giocatore
        -- giudica quanto dovrebbe giocare
        (select avg(x.overall_corrente)
           from public.player_instances x
          where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
        -- quota di minuti effettivamente giocati sulle giornate disputate
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate,
        coalesce((select st.posizione
                    from public.standings st
                   where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      v_delta_min := greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente))
        ) * 30
      ));

      -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
      v_delta_eco := greatest(-10, least(6,
        ((v_giocatore.ingaggio::numeric
          / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
      )) * (v_giocatore.mentalita_economia / 33.0);

      -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
      v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_lega.n_squadre - 1)))
        * 16 * (v_giocatore.mentalita_vittorie / 33.0);

      -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
      --    Un bandiera 60 assorbe il 30% del malcontento.
      v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

      v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
      v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit)) * v_attenuazione;

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;
$$;

revoke all on function public.applica_morale_checkpoint(bigint, smallint) from public, anon, authenticated;
grant execute on function public.applica_morale_checkpoint(bigint, smallint) to service_role;

comment on function public.applica_morale_checkpoint(bigint, smallint) is
  'Ricalcola il morale della lega al quarto di stagione raggiunto (design §11.3). Idempotente per (stagione, checkpoint).';
