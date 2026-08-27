-- ============================================================
--  MERCATO A SCELTE: LISTE DI PREFERENZE E RISOLUZIONE
--  docs/decisioni-draft-picks.md §4
--
--  Il pezzo che mancava: le scelte esistevano (scelte_draft) e il pool
--  pure (scelte_pool), ma non c'era modo di esercitarle. Qui si aggiunge
--  la lista di preferenze e la risoluzione sequenziale.
--
--  Regole di §4, applicate alla lettera:
--   - chi ha la scelta N sottomette al massimo N preferenze, ordinate
--   - la risoluzione scorre dalla 1a alla Na
--   - a ogni squadra va la prima preferenza non ancora presa
--   - NESSUN ripiego automatico: chi esaurisce la lista resta a mani vuote
-- ============================================================

-- ------------------------------------------------------------
--  Le liste di preferenze
--
--  Segretezza: e' lo stesso requisito delle offerte a busta chiusa
--  (CLAUDE.md §6). Se le preferenze altrui fossero leggibili prima della
--  risoluzione, il gioco sarebbe rotto: chi sceglie per secondo saprebbe
--  esattamente cosa lasciare in lista. La RLS qui sotto le rende visibili
--  solo al proprietario della scelta.
-- ------------------------------------------------------------

create table if not exists public.scelte_preferenze (
  scelta_id  bigint   not null references public.scelte_draft (id) on delete cascade,
  ordine     smallint not null check (ordine >= 1),
  player_id  bigint   not null references public.players (id) on delete restrict,
  creata_il  timestamptz not null default now(),
  primary key (scelta_id, ordine),
  unique (scelta_id, player_id)
);

create index if not exists scelte_preferenze_scelta_idx
  on public.scelte_preferenze (scelta_id, ordine);

comment on table public.scelte_preferenze is
  'Lista ordinata di preferenze per una scelta di draft. Segreta come le offerte a busta chiusa: visibile solo a chi possiede la scelta (docs/decisioni-draft-picks.md §4).';

alter table public.scelte_preferenze enable row level security;

drop policy if exists scelte_preferenze_proprie on public.scelte_preferenze;
create policy scelte_preferenze_proprie on public.scelte_preferenze
  for select
  to authenticated
  using (exists (
    select 1
    from public.scelte_draft sd
    join public.teams t on t.id = sd.team_proprietario_id
    where sd.id = scelte_preferenze.scelta_id
      and t.user_id = (select auth.uid())
  ));

-- La scrittura passa solo dalla RPC: nessun privilegio diretto.
revoke all on table public.scelte_preferenze from public, anon, authenticated;
grant select on table public.scelte_preferenze to authenticated;
grant all on table public.scelte_preferenze to service_role;

-- ------------------------------------------------------------
--  Sottomissione della lista
--
--  Sostituisce integralmente la lista precedente: e' piu' semplice da
--  ragionare per chi gioca ("questa e' la mia lista") e rende l'operazione
--  idempotente.
--
--  Il limite di lunghezza e' la posizione della scelta, come da §4: chi
--  sceglie 1o puo' indicare un solo nome perche' lo prendera' comunque;
--  chi sceglie 14o ne indica fino a 14 se vuole essere sicuro di ottenere
--  qualcosa.
-- ------------------------------------------------------------

create or replace function public.salva_preferenze_scelta(
  p_scelta_id  bigint,
  p_player_ids bigint[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente  uuid := (select auth.uid());
  v_scelta  public.scelte_draft;
  v_squadra public.teams;
  v_n       integer := coalesce(array_length(p_player_ids, 1), 0);
  v_validi  integer;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_scelta from public.scelte_draft where id = p_scelta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Scelta inesistente.';
  end if;

  select * into v_squadra from public.teams
  where id = v_scelta.team_proprietario_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questa scelta non è tua.';
  end if;

  if v_scelta.stato <> 'determinata' then
    raise exception using errcode = '55000', message = case v_scelta.stato
      when 'futura' then 'Questa scelta non ha ancora una posizione: se ne riparla quando la finestra si apre.'
      when 'usata'  then 'Questa scelta è già stata esercitata.'
      else 'Questa finestra è già stata risolta.' end;
  end if;

  if v_n > v_scelta.posizione then
    raise exception using errcode = '22023', message =
      'Puoi indicare al massimo ' || v_scelta.posizione || ' preferenze: scegli come '
      || v_scelta.posizione || 'ª e più di così non ti servirebbero.';
  end if;

  if v_n <> (select count(distinct x) from unnest(p_player_ids) as x) then
    raise exception using errcode = '22023', message = 'La lista contiene lo stesso giocatore più di una volta.';
  end if;

  -- Ogni preferenza deve stare nel pool di QUESTA finestra.
  select count(*) into v_validi
  from unnest(p_player_ids) as x
  where exists (
    select 1 from public.scelte_pool sp
    where sp.league_id = v_scelta.league_id
      and sp.stagione  = v_scelta.stagione
      and sp.finestra  = v_scelta.finestra
      and sp.player_id = x
  );
  if v_validi <> v_n then
    raise exception using errcode = '22023',
      message = 'Almeno un giocatore della lista non fa parte del pool di questa finestra.';
  end if;

  delete from public.scelte_preferenze where scelta_id = p_scelta_id;
  insert into public.scelte_preferenze (scelta_id, ordine, player_id)
  select p_scelta_id, i::smallint, p_player_ids[i]
  from generate_series(1, v_n) as i;

  return jsonb_build_object(
    'scelta_id', p_scelta_id,
    'posizione', v_scelta.posizione,
    'preferenze', v_n,
    'massimo', v_scelta.posizione
  );
end;
$$;

comment on function public.salva_preferenze_scelta(bigint, bigint[]) is
  'Sostituisce la lista di preferenze di una scelta. Al massimo tante preferenze quanto la posizione (docs/decisioni-draft-picks.md §4).';

revoke all on function public.salva_preferenze_scelta(bigint, bigint[]) from public, anon;
grant execute on function public.salva_preferenze_scelta(bigint, bigint[]) to authenticated;

-- ------------------------------------------------------------
--  Risoluzione della finestra
--
--  Scorre le scelte in ordine di posizione e assegna a ciascuna la prima
--  preferenza ancora libera. Il contratto e' quello di §6: ingaggio
--  teorico, una stagione, nessuna trattativa.
--
--  DUE CONDIZIONI CHE IL DOCUMENTO NON COPRE, risolte qui:
--
--  a) capienza sotto il tetto. decisioni-economia.md §1 non ammette
--     eccezioni: nessun ingaggio puo' sfondare il tetto, e una scelta non
--     e' un canale privilegiato. Una preferenza che non entra sotto il
--     tetto viene SALTATA e si passa alla successiva, invece di far
--     fallire l'intera scelta: saltare lascia comunque qualcosa alla
--     squadra, fallire non lascerebbe nulla.
--  b) posti in rosa. Stessa logica: se la rosa e' piena la scelta resta
--     vuota, come per le aste.
--
--  Se questo non e' il comportamento voluto, e' il punto da correggere.
--
--  La stagione del contratto e' quella della finestra (scelte_draft.stagione),
--  non private.stagione_contratto: la finestra sa a quale stagione si
--  riferisce, e non dipende da quando materialmente gira la risoluzione.
-- ------------------------------------------------------------

create or replace function private.risolvi_finestra_scelte(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scelta     record;
  v_pref       record;
  v_assegnate  integer := 0;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra sconosciuta: ' || p_finestra;
  end if;

  for v_scelta in
    select sd.*
    from public.scelte_draft sd
    where sd.league_id = p_league_id
      and sd.stagione  = p_stagione
      and sd.finestra  = p_finestra
      and sd.stato     = 'determinata'
    order by sd.posizione
    for update
  loop
    v_player_id := null;

    -- prima preferenza ancora disponibile che la squadra puo' permettersi
    for v_pref in
      select pr.player_id, sp.ingaggio_teorico
      from public.scelte_preferenze pr
      join public.scelte_pool sp
        on sp.league_id = p_league_id and sp.stagione = p_stagione
       and sp.finestra = p_finestra and sp.player_id = pr.player_id
      where pr.scelta_id = v_scelta.id
      order by pr.ordine
    loop
      -- gia' preso da chi ha scelto prima, in questa finestra o altrove?
      if exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = v_pref.player_id
          and pi.team_id is not null
      ) then
        continue;
      end if;

      if (select count(*) from public.player_instances pi
          where pi.team_id = v_scelta.team_proprietario_id) >= private.rosa_massima() then
        exit;  -- rosa piena: nessuna preferenza potra' entrare
      end if;

      if private.capienza_residua(v_scelta.team_proprietario_id, p_stagione, null)
         < v_pref.ingaggio_teorico then
        continue;  -- non ci sta sotto il tetto: prova la prossima
      end if;

      v_player_id := v_pref.player_id;
      v_ingaggio  := v_pref.ingaggio_teorico;
      exit;
    end loop;

    if v_player_id is null then
      update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
      where id = v_scelta.id;
      continue;
    end if;

    select p.nome into v_nome from public.players p where p.id = v_player_id;

    insert into public.player_instances as pi
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza)
    select p_league_id, p.id, v_scelta.team_proprietario_id, p.overall, p.eta,
           v_ingaggio, p_stagione
    from public.players p where p.id = v_player_id
    on conflict (league_id, player_id) do update
      set team_id = excluded.team_id,
          ingaggio = excluded.ingaggio,
          contratto_scadenza = excluded.contratto_scadenza
      where pi.team_id is null
    returning pi.id into v_istanza;

    get diagnostics v_righe = row_count;
    if v_righe <> 1 then
      -- qualcuno se l'e' preso nel frattempo: questa scelta resta vuota,
      -- non fa fallire l'intera finestra.
      update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
      where id = v_scelta.id;
      continue;
    end if;

    update public.scelte_draft
    set stato = 'usata', player_instance_id = v_istanza, aggiornata_il = now()
    where id = v_scelta.id;

    insert into public.transactions
      (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    select p_league_id, v_scelta.team_proprietario_id, 'scelta_draft', -v_ingaggio,
           'Scelta ' || v_scelta.posizione || 'ª (' || p_finestra || '-Season '
             || p_stagione || '): ' || coalesce(v_nome, 'giocatore'),
           (select budget from public.teams where id = v_scelta.team_proprietario_id);

    perform private.notifica(
      (select user_id from public.teams where id = v_scelta.team_proprietario_id),
      -- 'mercato_esito' e non un tipo nuovo: notifications_tipo_check
      -- ammette solo sette valori, e allargare il vincolo per una riga
      -- costringerebbe a toccare anche il frontend che ci fa switch sopra.
      p_league_id, 'mercato_esito',
      'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
      'Entra in rosa con un contratto di una stagione a '
        || private.in_milioni(v_ingaggio) || ' M€.',
      jsonb_build_object('scelta_id', v_scelta.id)
    );

    v_assegnate := v_assegnate + 1;
  end loop;

  return v_assegnate;
end;
$$;

comment on function private.risolvi_finestra_scelte(bigint, smallint, text) is
  'Risolve una finestra del mercato a scelte: scorre le posizioni e assegna a ciascuna la prima preferenza ancora libera e sostenibile. Nessun ripiego automatico (docs/decisioni-draft-picks.md §4).';

revoke all on function private.risolvi_finestra_scelte(bigint, smallint, text) from public, anon, authenticated;
grant execute on function private.risolvi_finestra_scelte(bigint, smallint, text) to service_role;
