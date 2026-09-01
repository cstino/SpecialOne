-- ============================================================
--  GESTIONE RISORSE: PUNTI ABILITA' E TRE RAMI
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Ogni squadra accumula punti abilita' e li spende su tre rami
--  (VIVAIO, TRAINING, REPARTO MEDICO), ciascuno da 0 a 10.
--
--    - 2 punti a ogni quarto di stagione (stesso ritmo della
--      progressione overall e del morale)
--    - massimo 20 punti in tutta la vita della lega: dopo, il
--      sistema smette di darne. 30 slot totali sui tre rami, quindi
--      NON si puo' arrivare a 10/10/10: bisogna scegliere.
--
--  Questa migrazione monta solo l'impianto: accumulo, spesa e
--  tabella degli effetti per livello. Gli effetti veri (mercato
--  UNDER, cambio ruolo, moltiplicatore di crescita, infortuni e
--  consumo di condizione) arrivano nei passi successivi e leggeranno
--  i livelli da qui.
--
--  Struttura ricalcata su season_morale_checkpoints e
--  applica_morale_checkpoint: stesso ritmo, registro e funzione
--  separati, cosi' si puo' correggere una meccanica senza toccare
--  le altre.
-- ============================================================

begin;

-- ------------------------------------------------------------
--  Costanti
-- ------------------------------------------------------------
create or replace function private.punti_per_checkpoint()
returns smallint language sql immutable set search_path = '' as $$ select 2::smallint $$;

create or replace function private.punti_abilita_massimi()
returns smallint language sql immutable set search_path = '' as $$ select 20::smallint $$;

create or replace function private.livello_ramo_massimo()
returns smallint language sql immutable set search_path = '' as $$ select 10::smallint $$;

-- ------------------------------------------------------------
--  Stato per squadra
-- ------------------------------------------------------------
create table public.team_risorse (
  team_id bigint primary key references public.teams(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  -- Cumulativo di quanti punti la squadra ha ricevuto finora, non quanti
  -- gliene restano: i punti disponibili sono ricevuti - somma dei livelli.
  -- Tenerlo cosi' rende impossibile "perdere" punti per un bug di conteggio.
  punti_ricevuti smallint not null default 0,
  livello_vivaio smallint not null default 0,
  livello_training smallint not null default 0,
  livello_medico smallint not null default 0,
  aggiornata_il timestamptz not null default now(),
  constraint team_risorse_livelli_validi check (
    livello_vivaio between 0 and 10
    and livello_training between 0 and 10
    and livello_medico between 0 and 10
  ),
  -- Invariante forte, garantita dal database e non solo dalla RPC: non si
  -- puo' mai aver speso piu' di quanto ricevuto.
  constraint team_risorse_spesa_coperta check (
    livello_vivaio + livello_training + livello_medico <= punti_ricevuti
  )
);

comment on table public.team_risorse is
  'Punti abilita accumulati e livelli dei tre rami (vivaio/training/medico) per squadra. I punti arrivano a ogni quarto di stagione fino al tetto di private.punti_abilita_massimi().';

create index team_risorse_league_idx on public.team_risorse(league_id);

create table public.season_punti_checkpoints (
  season_id bigint not null references public.seasons(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  checkpoint smallint not null,
  giornata smallint not null,
  applicato_il timestamptz not null default now(),
  primary key (season_id, checkpoint)
);

comment on table public.season_punti_checkpoints is
  'Registro dei quarti di stagione in cui sono gia stati distribuiti i punti abilita: rende assegna_punti_abilita idempotente se il cron ritenta.';

-- ------------------------------------------------------------
--  Tabella degli effetti per livello.
--  Unica fonte di verita': la legge il backend quando applichera' gli
--  effetti e la legge l'interfaccia per mostrare cosa sblocca ogni
--  punto. Cambiare la curva significa cambiare solo questa funzione.
-- ------------------------------------------------------------
create or replace function private.effetti_ramo(p_ramo text, p_livello smallint)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_ramo
    when 'vivaio' then jsonb_build_object(
      'livello', p_livello,
      -- Si parte con uno slot e si arriva a cinque: +1 ai livelli 3, 5, 7 e 10.
      'slot', 1 + (p_livello >= 3)::int + (p_livello >= 5)::int
                + (p_livello >= 7)::int + (p_livello >= 10)::int,
      -- Ampiezza della forbice di potenziale mostrata sul giovane: 15 punti
      -- di incertezza a livello 0 (es. "71-86"), zero a 10 (valore esatto).
      'ampiezza_range', round(15.0 * (10 - p_livello) / 10.0)::int
    )
    when 'training' then jsonb_build_object(
      'livello', p_livello,
      -- Moltiplicatore sulla crescita gia' esistente della progressione
      -- trimestrale: +5% per livello, massimo +50%. Tenuto volutamente
      -- contenuto per non rompere l'equilibrio della progressione.
      'moltiplicatore_crescita', round(1.0 + p_livello * 0.05, 2),
      'riduzione_tempi_ruolo_pct', p_livello * 4
    )
    when 'medico' then jsonb_build_object(
      'livello', p_livello,
      'riduzione_infortuni_pct', p_livello * 3,
      'riduzione_consumo_pct', p_livello * 2
    )
  end
$$;

create or replace function public.tabella_risorse()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'punti_per_checkpoint', private.punti_per_checkpoint(),
    'punti_massimi', private.punti_abilita_massimi(),
    'livello_massimo', private.livello_ramo_massimo(),
    'rami', (
      select jsonb_object_agg(r.ramo, x.livelli)
      from (values ('vivaio'), ('training'), ('medico')) as r(ramo)
      cross join lateral (
        select jsonb_agg(private.effetti_ramo(r.ramo, l.livello::smallint) order by l.livello) as livelli
        from generate_series(0, 10) as l(livello)
      ) x
    )
  )
$$;

-- ------------------------------------------------------------
--  Distribuzione dei punti: un quarto di stagione alla volta.
-- ------------------------------------------------------------
create or replace function public.assegna_punti_abilita(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_squadre integer := 0;
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

    update public.team_risorse r
    set punti_ricevuti = least(
          private.punti_abilita_massimi(),
          (r.punti_ricevuti + private.punti_per_checkpoint())::smallint
        ),
        aggiornata_il = now()
    from public.teams t
    where t.id = r.team_id
      and t.league_id = p_league_id
      and t.attiva
      and r.punti_ricevuti < private.punti_abilita_massimi();
    get diagnostics v_squadre = row_count;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'squadre_aggiornate', v_squadre);
end;
$$;

-- ------------------------------------------------------------
--  Spesa di un punto. Irreversibile: una volta messo su un ramo il
--  punto resta li'. E' una scelta di design (stessa logica di un
--  albero abilita'), non un limite tecnico.
-- ------------------------------------------------------------
create or replace function public.spendi_punto_abilita(p_team_id bigint, p_ramo text)
returns public.team_risorse
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_riga public.team_risorse;
  v_livello smallint;
  v_spesi smallint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire le risorse.';
  end if;
  if p_ramo not in ('vivaio', 'training', 'medico') then
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

  v_livello := case p_ramo
    when 'vivaio' then v_riga.livello_vivaio
    when 'training' then v_riga.livello_training
    else v_riga.livello_medico
  end;
  if v_livello >= private.livello_ramo_massimo() then
    raise exception using errcode = '22023',
      message = 'Questo ramo e'' gia'' al massimo ('
        || private.livello_ramo_massimo() || '/' || private.livello_ramo_massimo() || ').';
  end if;

  v_spesi := v_riga.livello_vivaio + v_riga.livello_training + v_riga.livello_medico;
  if v_spesi >= v_riga.punti_ricevuti then
    raise exception using errcode = '22023',
      message = 'Non hai punti abilita'' disponibili: ne hai ricevuti '
        || v_riga.punti_ricevuti || ' e gia'' spesi ' || v_spesi || '.';
  end if;

  update public.team_risorse
  set livello_vivaio = livello_vivaio + (p_ramo = 'vivaio')::int,
      livello_training = livello_training + (p_ramo = 'training')::int,
      livello_medico = livello_medico + (p_ramo = 'medico')::int,
      aggiornata_il = now()
  where team_id = p_team_id
  returning * into v_riga;

  return v_riga;
end;
$$;

-- ------------------------------------------------------------
--  Ogni squadra nuova nasce con la sua riga risorse a zero.
-- ------------------------------------------------------------
create or replace function private.crea_risorse_squadra()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.team_risorse (team_id, league_id)
  values (new.id, new.league_id)
  on conflict (team_id) do nothing;
  return new;
end;
$$;

create trigger teams_risorse_iniziali
after insert on public.teams
for each row execute function private.crea_risorse_squadra();

-- Squadre gia' esistenti: partono tutte da zero punti, anche quelle in
-- leghe gia' avanzate. Assegnare punti retroattivi per i quarti di
-- stagione gia' passati premierebbe chi gioca da piu' tempo per una
-- meccanica che allora non esisteva.
insert into public.team_risorse (team_id, league_id)
select id, league_id from public.teams
on conflict (team_id) do nothing;

-- ------------------------------------------------------------
--  RLS: i livelli di una squadra sono pubblici dentro la lega (come
--  rosa e classifica), ma si scrivono solo passando dalla RPC.
-- ------------------------------------------------------------
alter table public.team_risorse enable row level security;
create policy team_risorse_lettura on public.team_risorse
  for select using ((select private.e_membro(league_id)));

alter table public.season_punti_checkpoints enable row level security;
create policy season_punti_checkpoints_lettura on public.season_punti_checkpoints
  for select using ((select private.e_membro(league_id)));

grant select on public.team_risorse to authenticated;
grant select on public.season_punti_checkpoints to authenticated;
grant execute on function public.tabella_risorse() to authenticated;
grant execute on function public.spendi_punto_abilita(bigint, text) to authenticated;

commit;
