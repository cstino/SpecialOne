-- ============================================================
--  TRAINING, terzo fronte: specializzazione nel ruolo (stile FIFA).
--
--  Decisioni prese con l'utente il 2 settembre 2026:
--   - Non alza l'overall: modifica le STAT INDIVIDUALI vere che il motore
--     gia' legge per decidere chi segna/passa/si stanca (finishing,
--     short_passing, standing_tackle, dribbling, stamina) — vedi
--     supabase/functions/simula-giornata/index.ts:adaptPlayer. L'overall
--     resta quello che e', coerente con la crescita stagionale gia'
--     esistente che invece lo tocca.
--   - Stesso schema del cambio ruolo per il costo: il livello TRAINING
--     riduce le giornate di attesa (stesso riduzione_tempi_ruolo_pct gia'
--     usato da avvia_cambio_ruolo — e' la stessa "scuola calcio", non ha
--     senso un secondo indicatore per la stessa cosa).
--   - Una sola specializzazione attiva alla volta: riallenarsi la
--     sostituisce (si riparte sempre dagli attributi del catalogo + i
--     delta della nuova specializzazione, mai a cascata sulla vecchia).
--   - Ruoli coperti: DEF, MID, ATT con 3-4 archetipi ciascuno ispirati ai
--     playstyle di FIFA. NON il portiere: il motore legge un unico "gk"
--     aggregato (media dei 5 sotto-attributi FC26, mai scomposta), quindi
--     specializzazioni diverse per il portiere sarebbero un'illusione di
--     scelta con lo stesso identico effetto meccanico. Scelta autonoma,
--     segnalata qui: se in futuro il motore dovesse leggere i sotto-
--     attributi del portiere separatamente, si potra' aggiungere.
--
--  Struttura ricalcata 1:1 su 20260901090000_training_cambio_ruolo.sql
--  (stessa tabella di appoggio, stesso ciclo avvio/cron/completamento).
-- ============================================================

begin;

-- ------------------------------------------------------------
--  Come posizioni_override, ma per le stat: vive per-istanza, mai sul
--  catalogo condiviso players.attributi (altre leghe non devono vederlo).
--  Contiene solo le chiavi che divergono dal catalogo (valori assoluti,
--  gia' clampati a 99); assente o null = usa il valore del catalogo.
-- ------------------------------------------------------------
alter table public.player_instances
  add column attributi_override jsonb;
comment on column public.player_instances.attributi_override is
  'Valori assoluti che sostituiscono le chiavi corrispondenti di players.attributi per questa istanza (Gestione risorse, specializzazione TRAINING). Scritto solo da private.completa_specializzazioni(), sempre ricalcolato da zero (mai a cascata su un override precedente).';

alter table public.player_instances
  add column specializzazione_attiva text;
comment on column public.player_instances.specializzazione_attiva is
  'Chiave della specializzazione attualmente in vigore (vedi private.specializzazioni_ruolo), null se nessuna. Solo informativo/UI: gli effetti veri sono in attributi_override.';

create table public.specializzazioni_giocatore (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  specializzazione_precedente text,
  specializzazione_target text not null,
  avviato_giornata integer not null,
  completa_giornata integer not null,
  completato_il timestamptz,
  creato_il timestamptz not null default now()
);
comment on table public.specializzazioni_giocatore is
  'Allenamenti di specializzazione in corso o conclusi (TRAINING, riduzione_tempi_ruolo_pct). avviato/completa_giornata sono numeri di giornata di campionato, non date.';
create unique index specializzazioni_un_solo_in_corso on public.specializzazioni_giocatore (player_instance_id) where completato_il is null;
create index specializzazioni_team_idx on public.specializzazioni_giocatore(team_id);
create index specializzazioni_league_aperti_idx on public.specializzazioni_giocatore(league_id) where completato_il is null;

alter table public.specializzazioni_giocatore enable row level security;
create policy specializzazioni_giocatore_lettura on public.specializzazioni_giocatore
  for select using ((select private.e_membro(league_id)));
grant select on public.specializzazioni_giocatore to authenticated;

-- ------------------------------------------------------------
--  Catalogo delle specializzazioni per macro-ruolo. Pura funzione SQL,
--  come private.effetti_ramo: e' dato di gioco statico, non ha bisogno di
--  una tabella. +7 all'attributo primario, +4 al secondario (clampati a
--  99 al momento dell'applicazione, non qui). GK esclusa di proposito.
-- ------------------------------------------------------------
create or replace function private.specializzazioni_ruolo(p_macro_ruolo text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_macro_ruolo
    when 'DEF' then jsonb_build_object(
      'marcatore', jsonb_build_object('etichetta', 'Marcatore',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'terzino_offensivo', jsonb_build_object('etichetta', 'Terzino offensivo',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'libero_costruttore', jsonb_build_object('etichetta', 'Libero costruttore',
        'deltas', jsonb_build_object('short_passing', 7, 'standing_tackle', 4))
    )
    when 'MID' then jsonb_build_object(
      'regista', jsonb_build_object('etichetta', 'Regista',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'box_to_box', jsonb_build_object('etichetta', 'Box-to-box',
        'deltas', jsonb_build_object('stamina', 7, 'standing_tackle', 4)),
      'recupera_palloni', jsonb_build_object('etichetta', 'Recupera palloni',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'mezzala_inserimento', jsonb_build_object('etichetta', 'Mezz''ala d''inserimento',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    when 'ATT' then jsonb_build_object(
      'rapace_area', jsonb_build_object('etichetta', 'Rapace d''area',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4)),
      'ala_rapida', jsonb_build_object('etichetta', 'Ala rapida',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'falso_nueve', jsonb_build_object('etichetta', 'Falso nueve',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4))
    )
    else '{}'::jsonb
  end
$$;

-- Wrapper pubblico: il frontend deve poter mostrare le opzioni (con le
-- etichette e cosa migliorano) prima di avviare l'allenamento, senza
-- duplicare il catalogo lato client.
create or replace function public.specializzazioni_disponibili(p_instance_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.specializzazioni_ruolo(private.macro_ruolo(coalesce(pi.posizioni_override, p.posizioni)))
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;
$$;
grant execute on function public.specializzazioni_disponibili(bigint) to authenticated;

-- ------------------------------------------------------------
--  Avvio dell'allenamento di specializzazione.
-- ------------------------------------------------------------
create or replace function public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
returns public.specializzazioni_giocatore
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_macro text;
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
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

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_macro := private.macro_ruolo(v_posizioni_attuali);
  v_catalogo := private.specializzazioni_ruolo(v_macro);
  if v_macro = 'GK' or v_catalogo is null or not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = case when v_macro = 'GK'
        then 'Il portiere non ha specializzazioni: il motore riassume le sue qualità in un unico valore.'
        else 'Specializzazione non valida per questo ruolo.' end;
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  -- Base 10 giornate, senza lo sconto-versatilita' del cambio ruolo (qui
  -- non si impara un ruolo nuovo, solo un'inclinazione dentro il proprio):
  -- stessa curva TRAINING del cambio ruolo, minimo 3 giornate.
  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$$;
grant execute on function public.avvia_specializzazione(bigint, text) to authenticated;

-- ------------------------------------------------------------
--  Annullamento: stesso costo/beneficio di annulla_cambio_ruolo.
-- ------------------------------------------------------------
create or replace function public.annulla_specializzazione(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;
  delete from public.specializzazioni_giocatore s
  using public.teams t
  where s.id = p_id and s.team_id = t.id and t.user_id = v_utente and s.completato_il is null;
end;
$$;
grant execute on function public.annulla_specializzazione(bigint) to authenticated;

-- ------------------------------------------------------------
--  Completamento: job periodico, stesso schema di completa_cambi_ruolo.
--  Ricalcola SEMPRE da zero (catalogo + delta della nuova specializzazione):
--  mai a cascata su un override precedente, altrimenti riallenarsi piu'
--  volte accumulerebbe bonus invece di sostituirli.
-- ------------------------------------------------------------
create or replace function private.completa_specializzazioni()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_riga record;
  v_deltas jsonb;
  v_chiave text;
  v_base_attributi jsonb;
  v_override jsonb;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_riga in
      select s.*, pi.posizioni_override, p.posizioni as posizioni_catalogo, p.attributi as attributi_catalogo
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_deltas := private.specializzazioni_ruolo(private.macro_ruolo(coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo)))
        -> v_riga.specializzazione_target -> 'deltas';
      v_base_attributi := v_riga.attributi_catalogo;
      v_override := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(coalesce(v_deltas, '{}'::jsonb)) loop
        v_override := v_override || jsonb_build_object(
          v_chiave, least(99, coalesce((v_base_attributi->>v_chiave)::int, 0) + (v_deltas->>v_chiave)::int)
        );
      end loop;

      update public.player_instances
      set attributi_override = v_override, specializzazione_attiva = v_riga.specializzazione_target
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        'Un giocatore ha completato l''allenamento: ora è specializzato come ' || v_riga.specializzazione_target || '.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;

revoke all on function private.completa_specializzazioni() from public, anon, authenticated;
grant execute on function private.completa_specializzazioni() to service_role;

select cron.schedule(
  'completa-specializzazioni',
  '*/15 * * * *',
  $cron$select private.completa_specializzazioni();$cron$
);

commit;
