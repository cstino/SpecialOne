-- ============================================================
--  FINESTRE: SVELATE IN ANTICIPO, PREFERENZE CONGELATE A -1h
--  docs/decisioni-draft-picks.md §3.1 bis
--
--  Correzione di un mio fraintendimento. Avevo modellato l'apertura come
--  un evento vicino alla risoluzione: si estrae il pool, si compilano le
--  liste, si risolve. L'utente intende l'opposto — il pool si svela appena
--  si chiude lo stadio precedente (inizio stagione per ON-Season, fine del
--  draft ON-Season per OFF-Season) e le preferenze restano aperte per
--  tutto il tempo intermedio, che puo' essere di settimane.
--
--  Conseguenza pratica: una finestra ha DUE istanti, non uno. Quello in
--  cui si svela e quello in cui si estrae. Il secondo dev'essere noto in
--  anticipo, perche' serve a calcolare il congelamento a -1h e a mostrare
--  un conto alla rovescia in interfaccia. Non si puo' ricavare al momento
--  in cui gira il cron.
-- ============================================================

-- ------------------------------------------------------------
--  Registro delle finestre
--
--  Una riga per (lega, stagione, finestra). Nasce quando la finestra si
--  svela e porta con se' l'istante dell'estrazione.
--
--  Perche' una tabella e non due colonne su scelte_pool: scelte_pool ha
--  una riga per giocatore (40), e ripetere gli stessi due timestamp su
--  quaranta righe e' un invito a farli divergere.
-- ------------------------------------------------------------

create table if not exists public.finestre_scelte (
  league_id      bigint      not null references public.leagues (id) on delete cascade,
  stagione       smallint    not null check (stagione >= 1),
  finestra       text        not null check (finestra in ('on', 'off')),
  svelata_il     timestamptz not null default now(),
  estrazione_il  timestamptz not null,
  risolta_il     timestamptz,
  primary key (league_id, stagione, finestra)
);

comment on table public.finestre_scelte is
  'Una finestra del mercato a scelte. svelata_il: quando il pool e'' diventato visibile. estrazione_il: quando si risolve, noto in anticipo perche'' serve al congelamento a -1h (docs/decisioni-draft-picks.md §3.1 bis).';

comment on column public.finestre_scelte.estrazione_il is
  'Istante dell''estrazione. Le preferenze si congelano un''ora prima.';

alter table public.finestre_scelte enable row level security;

drop policy if exists finestre_scelte_lettura on public.finestre_scelte;
create policy finestre_scelte_lettura on public.finestre_scelte
  for select
  to authenticated
  using ((select private.e_membro(league_id)));

revoke all on table public.finestre_scelte from public, anon, authenticated;
grant select on table public.finestre_scelte to authenticated;
grant all on table public.finestre_scelte to service_role;

-- ------------------------------------------------------------
--  Quando si congela
--
--  Una funzione sola, cosi' la soglia sta in un posto solo invece che
--  duplicata fra il controllo lato scrittura e il conto alla rovescia
--  lato lettura.
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
  select now() >= f.estrazione_il - interval '1 hour'
  from public.finestre_scelte f
  where f.league_id = p_league_id and f.stagione = p_stagione and f.finestra = p_finestra
$$;

comment on function private.preferenze_congelate(bigint, smallint, text) is
  'Vero nell''ultima ora prima dell''estrazione: da li'' in poi le liste non si toccano piu''.';

revoke all on function private.preferenze_congelate(bigint, smallint, text) from public, anon;
grant execute on function private.preferenze_congelate(bigint, smallint, text) to authenticated, service_role;

-- ------------------------------------------------------------
--  Svelare una finestra
--
--  Sostituisce apri_finestra_scelte: stesso controllo sulle posizioni, ma
--  ora registra anche i due istanti. Il vecchio nome era fuorviante —
--  "aprire" suggeriva l'inizio di una fase breve, mentre qui si tratta di
--  rendere visibile il pool molto prima.
--
--  Idempotente come l'estrazione che incapsula: richiamarla non ri-estrae
--  il pool e non sposta l'istante gia' fissato.
-- ------------------------------------------------------------

create or replace function private.svela_finestra_scelte(
  p_league_id     bigint,
  p_stagione      smallint,
  p_finestra      text,
  p_estrazione_il timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_totali      integer;
  v_determinate integer;
  v_estratti    integer;
begin
  if p_finestra not in ('on', 'off') then
    raise exception using errcode = '22023', message = 'Finestra non valida: ' || p_finestra;
  end if;

  if p_estrazione_il <= now() then
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
  values (p_league_id, p_stagione, p_finestra, p_estrazione_il)
  on conflict (league_id, stagione, finestra) do nothing;

  v_estratti := private.estrai_pool_scelte(p_league_id, p_stagione, p_finestra);
  return v_estratti;
end;
$$;

comment on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) is
  'Svela il pool di una finestra e ne fissa l''istante di estrazione. Rifiuta se le posizioni non sono assegnate. Idempotente.';

revoke all on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) from public, anon, authenticated;
grant execute on function private.svela_finestra_scelte(bigint, smallint, text, timestamptz) to service_role;

drop function if exists private.apri_finestra_scelte(bigint, smallint, text);

-- ------------------------------------------------------------
--  Il congelamento, lato scrittura
--
--  Unica differenza rispetto a 20260828140000: il controllo sull'ultima
--  ora. Resta tutto il resto — proprieta', stato, lunghezza massima pari
--  alla posizione, nessun duplicato, tutti dentro il pool.
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

  select estrazione_il into v_quando from public.finestre_scelte
  where league_id = v_scelta.league_id and stagione = v_scelta.stagione and finestra = v_scelta.finestra;
  if not found then
    raise exception using errcode = '55000',
      message = 'Il pool di questa finestra non è ancora stato svelato.';
  end if;
  if now() >= v_quando - interval '1 hour' then
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
    'modificabile_fino_a', v_quando - interval '1 hour'
  );
end;
$$;

comment on function public.salva_preferenze_scelta(bigint, bigint[]) is
  'Sostituisce la lista di preferenze di una scelta. Modificabile fino a un''ora prima dell''estrazione (docs/decisioni-draft-picks.md §3.1 bis).';

revoke all on function public.salva_preferenze_scelta(bigint, bigint[]) from public, anon;
grant execute on function public.salva_preferenze_scelta(bigint, bigint[]) to authenticated;

-- ------------------------------------------------------------
--  La risoluzione registra la chiusura
--
--  Il guardrail non guarda piu' il pool ma il registro, che e' la fonte
--  di verita' sull'esistenza della finestra, e rifiuta di risolvere prima
--  dell'istante fissato: risolvere in anticipo taglierebbe fuori chi sta
--  ancora ragionando sulla lista.
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
  'Risolve una finestra svelata, non prima dell''istante di estrazione. p_forza salta solo il controllo sull''orario, mai gli altri. Nessun ripiego automatico (docs/decisioni-draft-picks.md §4).';

revoke all on function private.risolvi_finestra_scelte(bigint, smallint, text, boolean) from public, anon, authenticated;
grant execute on function private.risolvi_finestra_scelte(bigint, smallint, text, boolean) to service_role;

drop function if exists private.risolvi_finestra_scelte(bigint, smallint, text);
