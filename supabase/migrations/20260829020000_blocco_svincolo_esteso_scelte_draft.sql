-- ============================================================
--  BLOCCO SVINCOLO ESTESO ALLE SCELTE DEL MERCATO DRAFT
--  Deciso il 29 agosto 2026, in conversazione con l'utente, come
--  seguito di 20260829010000_blocco_svincolo_acquisti_recenti.sql.
--
--  Quella migrazione copriva solo asta svincolati e scambi. L'utente
--  ha confermato che vale anche per i giocatori presi tramite il
--  mercato a scelte (ON-Season/OFF-Season, la voce "Draft" del menu,
--  private.risolvi_finestra_scelte): non svincolabili prima di 10
--  giornate, scambiabili senza restrizioni nel frattempo.
--
--  Non tocca il draft iniziale di lega (Draft.tsx, la costruzione
--  della rosa da 25 quando una squadra entra): avviene a stato
--  'draft', prima che la stagione cominci, e svincola_giocatore e'
--  gia' bloccato fuori da stato 'stagione' — non c'e' un canale di
--  abuso da chiudere li'.
-- ============================================================

create or replace function private.risolvi_finestra_scelte(p_league_id bigint, p_stagione smallint, p_finestra text, p_forza boolean default false)
returns integer
language plpgsql
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
  v_prossima   integer;
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

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = p_league_id and f.stato = 'programmata';

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
      (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
    select p_league_id, p.id, v_scelta.team_proprietario_id, p.overall, p.eta,
           v_ingaggio, p_stagione, v_prossima
    from public.players p where p.id = v_player_id
    on conflict (league_id, player_id) do update
      set team_id = excluded.team_id,
          ingaggio = excluded.ingaggio,
          contratto_scadenza = excluded.contratto_scadenza,
          giornata_acquisizione = excluded.giornata_acquisizione
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
