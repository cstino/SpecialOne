-- ============================================================
--  L'ESTRAZIONE OFF-SEASON CADE ALLO SCADERE DELL'OFF-SEASON
--  docs/decisioni-draft-picks.md §3.1 bis
--
--  Precisato dall'utente il 28 agosto 2026: "il risultato del draft
--  dell'offseason si sa allo scadere stesso dell'offseason, le preferenze
--  un'ora prima". Quindi per la finestra 'off' l'istante di estrazione non
--  e' un valore a se': E' leagues.offseason_fine.
--
--  Due conseguenze che il modello precedente non reggeva.
--
--  1. Il pool OFF si svela a meta' stagione (subito dopo il draft
--     ON-Season), quando offseason_fine NON esiste ancora: viene fissata
--     solo quando l'off-season comincia. Quindi estrazione_il deve poter
--     essere ancora ignota al momento in cui la finestra si svela. E'
--     diventata nullable.
--
--     Con estrazione ignota le preferenze restano modificabili: non c'e'
--     nessuna estrazione imminente da proteggere, ed e' esattamente la
--     fase in cui l'utente vuole che si possa gia' ragionare sulla lista.
--
--  2. offseason_fine CAMBIA. E' gia' successo il 27 agosto su Real
--     Fampionato, spostata avanti per bloccare gli svincoli d'ufficio.
--     Copiare il valore una volta sola lo farebbe divergere in silenzio,
--     e il congelamento a -1h scatterebbe sull'orario sbagliato. Da qui il
--     trigger: la finestra 'off' segue la scadenza, sempre.
-- ============================================================

alter table public.finestre_scelte alter column estrazione_il drop not null;

comment on column public.finestre_scelte.estrazione_il is
  'Istante dell''estrazione; le preferenze si congelano un''ora prima. Per la finestra ''off'' e'' sempre allineata a leagues.offseason_fine dal trigger, e resta NULL finche'' quella scadenza non esiste.';

-- ------------------------------------------------------------
--  La finestra 'off' insegue offseason_fine
--
--  Quale finestra: quella della stagione a cui l'off-season PORTA, cioe'
--  stagione_corrente + 1 (docs §3.1, "l'off-season che porta alla
--  stagione X"). Con Real Fampionato in off-season a stagione_corrente 1,
--  la finestra interessata e' (stagione 2, 'off').
-- ------------------------------------------------------------

create or replace function private.sincronizza_estrazione_off()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.finestre_scelte f
  set estrazione_il = new.offseason_fine
  where f.league_id = new.id
    and f.finestra  = 'off'
    and f.stagione  = (new.stagione_corrente + 1)::smallint
    and f.risolta_il is null
    and f.estrazione_il is distinct from new.offseason_fine;
  return new;
end;
$$;

comment on function private.sincronizza_estrazione_off() is
  'Tiene la finestra ''off'' allineata a leagues.offseason_fine, che l''admin puo'' spostare.';

drop trigger if exists leagues_sincronizza_estrazione_off on public.leagues;
create trigger leagues_sincronizza_estrazione_off
after update of offseason_fine, stagione_corrente on public.leagues
for each row execute function private.sincronizza_estrazione_off();

-- ------------------------------------------------------------
--  Svelare: l'istante puo' essere ancora ignoto
-- ------------------------------------------------------------

create or replace function private.svela_finestra_scelte(
  p_league_id     bigint,
  p_stagione      smallint,
  p_finestra      text,
  p_estrazione_il timestamptz default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega        public.leagues;
  v_totali      integer;
  v_determinate integer;
  v_quando      timestamptz;
  v_estratti    integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: ' || p_finestra;
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  -- Per la 'off' l'istante non si passa: e' la scadenza dell'off-season,
  -- e finche' non esiste resta ignoto.
  if p_finestra = 'off' then
    v_quando := case when p_stagione = (v_lega.stagione_corrente + 1)::smallint
                     then v_lega.offseason_fine else null end;
  else
    v_quando := p_estrazione_il;
  end if;

  if v_quando is not null and v_quando <= now() then
    raise exception using errcode = '22023',
      message = 'L''estrazione va fissata nel futuro: le preferenze nascerebbero gia'' congelate.';
  end if;

  select count(*), count(*) filter (where stato = 'determinata')
    into v_totali, v_determinate
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  if v_totali = 0 then
    raise exception using errcode = 'P0002',
      message = 'Nessuna scelta esiste per questa finestra: vanno generate prima.';
  end if;

  if v_determinate = 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni di questa finestra non sono ancora state assegnate: '
                || 'senza ordine di scelta la finestra non puo'' essere svelata.';
  end if;

  insert into public.finestre_scelte (league_id, stagione, finestra, estrazione_il)
  values (p_league_id, p_stagione, p_finestra, v_quando)
  on conflict (league_id, stagione, finestra) do nothing;

  v_estratti := private.estrai_pool_scelte(p_league_id, p_stagione, p_finestra);
  return v_estratti;
end;
$$;

comment on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) is
  'Svela il pool di una finestra. Per la ''off'' l''istante di estrazione e'' offseason_fine e non si passa: puo'' essere ancora ignoto. Idempotente.';

revoke all on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) from public, anon, authenticated;
grant execute on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) to service_role;

-- ------------------------------------------------------------
--  Congelamento solo quando c'e' qualcosa da congelare
-- ------------------------------------------------------------

create or replace function private.preferenze_congelate(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select f.estrazione_il is not null
     and now() >= f.estrazione_il - interval '1 hour'
  from public.finestre_scelte f
  where f.league_id = p_league_id and f.stagione = p_stagione and f.finestra = p_finestra
$$;

comment on function private.preferenze_congelate(bigint, smallint, text) is
  'Vero nell''ultima ora prima dell''estrazione. Falso finche'' l''istante e'' ignoto: non c''e'' nulla da proteggere.';

revoke all on function private.preferenze_congelate(bigint, smallint, text) from public, anon;
grant execute on function private.preferenze_congelate(bigint, smallint, text) to authenticated, service_role;

-- ------------------------------------------------------------
--  I due chiamanti, resi espliciti sul caso "istante ignoto"
--
--  Con estrazione_il nullable entrambi si comportavano per accidente
--  invece che per intenzione, e in un caso l'accidente era un bug:
--
--  - salva_preferenze_scelta: `now() >= null - interval` vale NULL, che in
--    un IF si comporta come falso, quindi le preferenze restavano
--    modificabili. Comportamento giusto, ma ottenuto per caso. Ora e'
--    scritto.
--
--  - risolvi_finestra_scelte: `now() < null` vale NULL, quindi il
--    controllo NON scattava e la finestra veniva risolta anche senza un
--    istante di estrazione fissato. Questo era un bug: si sarebbe potuta
--    chiudere una finestra 'off' mentre l'off-season non era nemmeno
--    cominciata.
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
  v_quando  timestamptz;
  v_trovata boolean;
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
      when 'futura' then 'Questa scelta non ha ancora una posizione: se ne riparla quando la finestra si svela.'
      when 'usata'  then 'Questa scelta è già stata esercitata.'
      else 'Questa finestra è già stata risolta.' end;
  end if;

  select true, estrazione_il into v_trovata, v_quando
  from public.finestre_scelte
  where league_id = v_scelta.league_id and stagione = v_scelta.stagione and finestra = v_scelta.finestra;
  if not coalesce(v_trovata, false) then
    raise exception using errcode = '55000',
      message = 'Il pool di questa finestra non è ancora stato svelato.';
  end if;

  -- Istante ancora ignoto (tipico della finestra 'off' svelata a metà
  -- stagione): nessuna estrazione imminente, si può modificare liberamente.
  if v_quando is not null and now() >= v_quando - interval '1 hour' then
    raise exception using errcode = '55000',
      message = 'Le preferenze si congelano un''ora prima dell''estrazione: la lista non è più modificabile.';
  end if;

  if v_n > v_scelta.posizione then
    raise exception using errcode = '22023', message =
      'Puoi indicare al massimo ' || v_scelta.posizione || ' preferenze: scegli come '
      || v_scelta.posizione || 'ª e più di così non ti servirebbero.';
  end if;

  if v_n <> (select count(distinct x) from unnest(p_player_ids) as x) then
    raise exception using errcode = '22023', message = 'La lista contiene lo stesso giocatore più di una volta.';
  end if;

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
    'massimo', v_scelta.posizione,
    'estrazione_il', v_quando,
    'modificabile_fino_a', case when v_quando is null then null
                                else v_quando - interval '1 hour' end
  );
end;
$$;

comment on function public.salva_preferenze_scelta(bigint, bigint[]) is
  'Sostituisce la lista di preferenze di una scelta. Modificabile fino a un''ora prima dell''estrazione; se l''istante non e'' ancora noto, sempre (docs/decisioni-draft-picks.md §3.1 bis).';

revoke all on function public.salva_preferenze_scelta(bigint, bigint[]) from public, anon;
grant execute on function public.salva_preferenze_scelta(bigint, bigint[]) to authenticated;

-- ------------------------------------------------------------

create or replace function private.risolvi_finestra_scelte(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text,
  p_forza     boolean default false
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_finestra   public.finestre_scelte;
  v_scelta     record;
  v_pref       record;
  v_assegnate  integer := 0;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
begin
  select * into v_finestra from public.finestre_scelte
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra
  for update;
  if not found then
    raise exception using errcode = '55000',
      message = 'Questa finestra non e'' mai stata svelata: non c''e'' nulla da risolvere.';
  end if;
  if v_finestra.risolta_il is not null then
    return 0;
  end if;

  -- Istante ignoto: la finestra non e' ancora arrivata a scadenza perche'
  -- una scadenza non ce l'ha. Vale anche con p_forza: forzare l'orario di
  -- un'estrazione che non e' stata fissata non significa niente.
  if v_finestra.estrazione_il is null then
    raise exception using errcode = '55000',
      message = 'L''istante di estrazione di questa finestra non e'' ancora fissato'
                || case when p_finestra = 'off'
                        then ': dipende dalla scadenza dell''off-season, che non e'' ancora stata impostata.'
                        else '.' end;
  end if;

  if not p_forza and now() < v_finestra.estrazione_il then
    raise exception using errcode = '55000',
      message = 'L''estrazione di questa finestra e'' fissata per il '
                || to_char(v_finestra.estrazione_il at time zone 'Europe/Rome', 'DD/MM/YYYY HH24:MI')
                || ': risolvere adesso taglierebbe fuori chi sta ancora componendo la lista.';
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

    for v_pref in
      select pr.player_id, sp.ingaggio_teorico
      from public.scelte_preferenze pr
      join public.scelte_pool sp
        on sp.league_id = p_league_id and sp.stagione = p_stagione
       and sp.finestra = p_finestra and sp.player_id = pr.player_id
      where pr.scelta_id = v_scelta.id
      order by pr.ordine
    loop
      if exists (
        select 1 from public.player_instances pi
        where pi.league_id = p_league_id and pi.player_id = v_pref.player_id
          and pi.team_id is not null
      ) then
        continue;
      end if;

      if (select count(*) from public.player_instances pi
          where pi.team_id = v_scelta.team_proprietario_id) >= private.rosa_massima() then
        exit;
      end if;

      -- Confermato dall'utente il 28 agosto: un ingaggio che non entra
      -- sotto il tetto non puo' entrare in rosa. Si salta e si passa alla
      -- preferenza successiva.
      if private.capienza_residua(v_scelta.team_proprietario_id, p_stagione, null)
         < v_pref.ingaggio_teorico then
        continue;
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
      p_league_id, 'mercato_esito',
      'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
      'Entra in rosa con un contratto di una stagione a '
        || private.in_milioni(v_ingaggio) || ' M€.',
      jsonb_build_object('scelta_id', v_scelta.id)
    );

    v_assegnate := v_assegnate + 1;
  end loop;

  update public.finestre_scelte set risolta_il = now()
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  return v_assegnate;
end;
$$;

comment on function private.risolvi_finestra_scelte(bigint, smallint, text, boolean) is
  'Risolve una finestra svelata, non prima dell''istante di estrazione e mai se quell''istante non e'' fissato. p_forza salta solo il controllo sull''orario. Nessun ripiego automatico (docs/decisioni-draft-picks.md §4).';

revoke all on function private.risolvi_finestra_scelte(bigint, smallint, text, boolean) from public, anon, authenticated;
grant execute on function private.risolvi_finestra_scelte(bigint, smallint, text, boolean) to service_role;
