-- ============================================================
--  IL DRAFT ON-SEASON DIVENTA UN EVENTO IN DIRETTA
--
--  Prima: alla scadenza della finestra, private.risolvi_finestra_scelte
--  assegnava tutte le scelte in un'unica transazione. Chi apriva l'app un
--  minuto dopo trovava il draft già finito, senza aver visto niente.
--
--  Ora: una scelta ogni 60 secondi, in ordine di posizione, come al draft NBA.
--  La lega apre l'app e guarda le chiamate arrivare una dopo l'altra.
--
--  PERCHE' NON CI SONO SPOILER, ED E' GRATIS
--  Il requisito era che i giocatori non finiscano in rosa prima del proprio
--  turno. Lo schema lo garantisce già da solo, senza nessuna RLS nuova:
--
--    - scelte_preferenze e' leggibile SOLO dal proprietario della scelta
--      (policy scelte_preferenze_proprie): nessuno vede le liste altrui;
--    - scelte_draft e' leggibile da tutta la lega, ma una scelta non ancora
--      chiamata ha player_instance_id nullo e stato 'determinata'.
--
--  Quindi basta risolvere una scelta alla volta: il risultato esiste nel
--  database solo dall'istante in cui tocca a quella squadra. Non c'e' nessuna
--  tabella di "risultati nascosti" da proteggere, e questa e' la ragione per
--  cui la funzione si limita a scandire il tempo.
--
--  LE PREFERENZE ERANO GIA' A POSTO
--  Il requisito "da quando parte la prima scelta non si modifica piu' la
--  lista" e' già soddisfatto, e in forma più severa: public.salva_preferenze_scelta
--  congela le liste un'ora prima dell'estrazione. Quella funzione non viene
--  toccata — allentarla per farla combaciare col nuovo avvio sarebbe un passo
--  indietro.
--
--  COSA CAMBIA DAVVERO
--    1. finestre_scelte impara due cose: quando il draft e' partito e quanto
--       dura un passo.
--    2. La logica di UNA scelta viene estratta in private.risolvi_una_scelta.
--       risolvi_finestra_scelte continua a esistere identica nel
--       comportamento, ma ora delega: una sola copia della logica, cosi' il
--       draft in diretta e la risoluzione in blocco non possono divergere.
--    3. private.avanza_draft_live, al minuto, chiama la prossima scelta dovuta.
--    4. private.avanza_finestre_scelte (ogni 5 minuti) si fa da parte finche'
--       la diretta e' nei tempi, e riprende il comando se si pianta.
-- ============================================================

-- ------------------------------------------------------------
--  1. La finestra sa quando e' partita e con che ritmo
-- ------------------------------------------------------------
alter table public.finestre_scelte
  add column if not exists avviata_il    timestamptz,
  add column if not exists passo_secondi smallint not null default 60;

comment on column public.finestre_scelte.avviata_il is
  'Istante della prima chiamata del draft in diretta. Nullo = non ancora partito.';
comment on column public.finestre_scelte.passo_secondi is
  'Secondi fra una chiamata e la successiva. 0 disattiva la diretta e torna alla risoluzione in blocco.';

-- ------------------------------------------------------------
--  2. Una scelta sola
--
--  Corpo estratto tale e quale dal ciclo di risolvi_finestra_scelte: stessa
--  scansione delle preferenze, stessi controlli di rosa piena e di tetto
--  ingaggi, stessa gestione del caso "qualcuno se l'e' preso nel frattempo".
--  Non cambia una regola: cambia solo chi decide QUANDO chiamarla.
-- ------------------------------------------------------------
create or replace function private.risolvi_una_scelta(p_scelta_id bigint)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scelta     public.scelte_draft;
  v_pref       record;
  v_player_id  bigint;
  v_ingaggio   bigint;
  v_istanza    bigint;
  v_nome       text;
  v_righe      integer;
  v_prossima   integer;
  v_scadenza   smallint;
begin
  select * into v_scelta from public.scelte_draft where id = p_scelta_id for update;
  if not found or v_scelta.stato <> 'determinata' then
    return false;
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_scelta.league_id and f.stato = 'programmata';

  -- Il contratto scade a fine della stagione della finestra. Se pero' la
  -- finestra viene risolta in ritardo, a stagione gia' voltata, quella
  -- scadenza sarebbe gia' passata: il giocatore entrerebbe in rosa con un
  -- contratto scaduto, fuori dal monte ingaggi e da rinnovare subito.
  -- Si prende quindi la piu' avanti fra le due.
  select greatest(v_scelta.stagione, l.stagione_corrente) into v_scadenza
  from public.leagues l where l.id = v_scelta.league_id;

  for v_pref in
    select pr.player_id, sp.ingaggio_teorico
    from public.scelte_preferenze pr
    join public.scelte_pool sp
      on sp.league_id = v_scelta.league_id and sp.stagione = v_scelta.stagione
     and sp.finestra = v_scelta.finestra and sp.player_id = pr.player_id
    where pr.scelta_id = v_scelta.id
    order by pr.ordine
  loop
    if exists (
      select 1 from public.player_instances pi
      where pi.league_id = v_scelta.league_id and pi.player_id = v_pref.player_id
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
    if private.capienza_residua(v_scelta.team_proprietario_id, v_scelta.stagione, null)
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
    return false;
  end if;

  select p.nome into v_nome from public.players p where p.id = v_player_id;

  insert into public.player_instances as pi
    (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
  select v_scelta.league_id, p.id, v_scelta.team_proprietario_id,
         coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta),
         v_ingaggio, v_scadenza, v_prossima
  from public.players p
  left join public.free_agent_progression fap
    on fap.league_id = v_scelta.league_id and fap.player_id = p.id
  where p.id = v_player_id
  on conflict (league_id, player_id) do update
    set team_id = excluded.team_id,
        ingaggio = excluded.ingaggio,
        contratto_scadenza = excluded.contratto_scadenza,
        giornata_acquisizione = excluded.giornata_acquisizione
    where pi.team_id is null
  returning pi.id into v_istanza;

  get diagnostics v_righe = row_count;
  if v_righe <> 1 then
    -- qualcuno se l'e' preso nel frattempo: questa scelta resta vuota,
    -- non fa fallire niente a valle.
    update public.scelte_draft set stato = 'vuota', aggiornata_il = now()
    where id = v_scelta.id;
    return false;
  end if;

  delete from public.free_agent_progression
  where league_id = v_scelta.league_id and player_id = v_player_id;

  update public.scelte_draft
  set stato = 'usata', player_instance_id = v_istanza, aggiornata_il = now()
  where id = v_scelta.id;

  insert into public.transactions
    (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  select v_scelta.league_id, v_scelta.team_proprietario_id, 'scelta_draft', -v_ingaggio,
         'Scelta ' || v_scelta.posizione || 'ª (' || v_scelta.finestra || '-Season '
           || v_scelta.stagione || '): ' || coalesce(v_nome, 'giocatore'),
         0;

  perform private.notifica(
    (select user_id from public.teams where id = v_scelta.team_proprietario_id),
    v_scelta.league_id, 'mercato_esito',
    'Scelta esercitata: ' || coalesce(v_nome, 'giocatore'),
    'Entra in rosa con un contratto di una stagione a '
      || private.in_milioni(v_ingaggio) || ' M€.',
    jsonb_build_object('scelta_id', v_scelta.id)
  );

  return true;
end;
$$;

revoke all on function private.risolvi_una_scelta(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  3. La risoluzione in blocco ora delega
--
--  Stessa firma, stessi controlli d'ingresso, stesso valore di ritorno.
--  Serve ancora: e' la rete di sicurezza del draft in diretta, la strada
--  della finestra OFF e quella del pulsante dell'admin.
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
  v_assegnate  integer := 0;
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
    select sd.id
    from public.scelte_draft sd
    where sd.league_id = p_league_id
      and sd.stagione  = p_stagione
      and sd.finestra  = p_finestra
      and sd.stato     = 'determinata'
    order by sd.posizione
  loop
    if private.risolvi_una_scelta(v_scelta.id) then
      v_assegnate := v_assegnate + 1;
    end if;
  end loop;

  update public.finestre_scelte set risolta_il = now()
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra;

  return v_assegnate;
end;
$$;

-- ------------------------------------------------------------
--  4. Il draft in diretta: una chiamata al minuto
--
--  Quando la prossima scelta e' dovuta: avviata_il + (chiamate_fatte x passo).
--  La prima quindi parte subito, nello stesso giro che avvia il draft.
--
--  Il conteggio si basa sullo STATO delle scelte, non su un contatore a parte:
--  se un giro salta, il successivo si accorge di essere in ritardo e recupera.
--  Ne risolve comunque UNA per volta, perche' il ritmo e' il punto dell'intera
--  funzione: meglio un draft che finisce un minuto tardi di sei chiamate che
--  arrivano insieme.
-- ------------------------------------------------------------
create or replace function private.avanza_draft_live()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_f          record;
  v_chiamate   integer;
  v_prossima   bigint;
  v_dovuta_il  timestamptz;
  v_fatte      integer := 0;
  v_membro     record;
begin
  for v_f in
    select f.*
    from public.finestre_scelte f
    where f.risolta_il is null
      and f.finestra = 'on'
      and f.passo_secondi > 0
      and f.estrazione_il is not null
      and f.estrazione_il <= now()
    order by f.league_id, f.stagione
    for update
  loop
    begin
      -- Avvio. date_trunc al minuto aggancia le chiamate al minuto tondo: il
      -- cron gira al minuto, quindi ogni scelta cade con pochi secondi di
      -- ritardo invece di accumulare la latenza di un giro.
      if v_f.avviata_il is null then
        v_f.avviata_il := date_trunc('minute', now());
        update public.finestre_scelte set avviata_il = v_f.avviata_il
        where league_id = v_f.league_id and stagione = v_f.stagione and finestra = v_f.finestra;

        -- La diretta non serve a niente se nessuno sa che e' iniziata.
        for v_membro in
          select t.user_id from public.teams t
          where t.league_id = v_f.league_id and t.user_id is not null and t.attiva
        loop
          perform private.notifica(
            v_membro.user_id, v_f.league_id, 'mercato_esito',
            'On-Season Draft: si parte',
            'Le chiamate arrivano una ogni minuto. Apri l''app per seguirle in diretta.',
            jsonb_build_object('draft_live', true, 'stagione', v_f.stagione)
          );
        end loop;
      end if;

      select count(*) into v_chiamate
      from public.scelte_draft sd
      where sd.league_id = v_f.league_id and sd.stagione = v_f.stagione
        and sd.finestra = v_f.finestra and sd.stato in ('usata', 'vuota');

      select sd.id into v_prossima
      from public.scelte_draft sd
      where sd.league_id = v_f.league_id and sd.stagione = v_f.stagione
        and sd.finestra = v_f.finestra and sd.stato = 'determinata'
      order by sd.posizione
      limit 1;

      if v_prossima is null then
        -- Finite le chiamate: si chiude la finestra e si apre la OFF, esattamente
        -- come faceva la risoluzione in blocco.
        update public.finestre_scelte set risolta_il = now()
        where league_id = v_f.league_id and stagione = v_f.stagione and finestra = v_f.finestra;

        if not exists (
          select 1 from public.finestre_scelte
          where league_id = v_f.league_id and stagione = v_f.stagione and finestra = 'off'
        ) then
          perform private.svela_finestra_scelte(v_f.league_id, v_f.stagione, 'off');
        end if;
        continue;
      end if;

      v_dovuta_il := v_f.avviata_il + make_interval(secs => (v_chiamate * v_f.passo_secondi)::integer);
      if now() < v_dovuta_il then
        continue;  -- il turno di questa squadra non e' ancora arrivato
      end if;

      perform private.risolvi_una_scelta(v_prossima);
      v_fatte := v_fatte + 1;

    exception when others then
      raise warning 'draft live: lega % stagione %: % (%)',
        v_f.league_id, v_f.stagione, sqlerrm, sqlstate;
    end;
  end loop;

  return v_fatte;
end;
$$;

revoke all on function private.avanza_draft_live() from public, anon, authenticated;

-- ------------------------------------------------------------
--  5. Il ciclo da 5 minuti si fa da parte, ma resta la rete
--
--  Definizione ripresa dal database e modificata nel solo ciclo finale: il
--  resto e' identico, commenti storici compresi.
--
--  NOTA su un difetto preesistente che NON tocco oggi: la chiamata qui sotto
--  passa 'on' fisso invece di v_finestra.finestra, quindi una finestra OFF
--  scaduta non viene mai risolta da questo ciclo malgrado il commento dica il
--  contrario. Correggerlo oggi farebbe risolvere d'un colpo le OFF arretrate di
--  tutte le leghe, poche ore prima di un draft vero: e' un task a se'.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.avanza_finestre_scelte()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_finestra record;
  v_risolte integer := 0;
begin
  -- Passaggio di recupero: leghe la cui stagione corrente e' iniziata
  -- PRIMA che questa automazione esistesse (es. LegaBot, stagione 2 gia'
  -- in corso al momento di questa migrazione). inizializza_stagione fa lo
  -- stesso lavoro alla nascita di ogni stagione successiva; qui si
  -- recupera solo chi e' rimasto indietro, ed e' innocuo ripeterlo:
  -- svela_finestra_scelte non ritocca una finestra gia' svelata.
  for v_lega in
    select l.id as league_id, l.stagione_corrente, s.id as season_id, s.giornate_totali
    from public.leagues l
    join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente
    where l.stato = 'stagione' and l.fase_carriera = 'normale' and l.stagione_corrente >= 2
      and exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = l.id and sd.stagione = l.stagione_corrente
          and sd.finestra = 'on' and sd.stato = 'determinata'
      )
      and not exists (
        select 1 from public.finestre_scelte f
        where f.league_id = l.id and f.stagione = l.stagione_corrente and f.finestra = 'on'
      )
  loop
    begin
      v_giornata_mezza := v_lega.giornate_totali / 2;
      select f.data_sim into v_data_mezza
      from public.fixtures f
      where f.season_id = v_lega.season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
      limit 1;
      if v_data_mezza is not null then
        perform private.svela_finestra_scelte(
          v_lega.league_id, v_lega.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
        );
      end if;
    exception when others then
      raise warning 'mercato a scelte: recupero apertura ON-Season fallito per lega % stagione %: % (%)',
        v_lega.league_id, v_lega.stagione_corrente, sqlerrm, sqlstate;
    end;
  end loop;

  -- Preferenze PC su tutte le finestre ancora aperte, non solo quelle in
  -- scadenza: cosi' una squadra PC non resta "in attesa" per giorni.
  for v_finestra in
    select league_id, stagione, finestra from public.finestre_scelte where risolta_il is null
  loop
    begin
      perform private.preferenze_squadre_pc(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra);
    exception when others then
      raise warning 'mercato a scelte: preferenze PC fallite per lega % stagione % finestra %: % (%)',
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, sqlerrm, sqlstate;
    end;
  end loop;

  -- Una finestra non deve sopravvivere alla propria stagione: se la lega e'
  -- gia' passata a quella dopo, la sua scadenza originale non ha piu' senso.
  --
  -- Il 9 settembre 2026 questo blocco la RISOLVEVA all'istante. Sbagliato, e
  -- si e' visto subito: la stessa esecuzione apriva la finestra OFF di
  -- recupero con due giorni di respiro, e il giro successivo (5 minuti dopo)
  -- la ritrovava "di stagione arretrata" e la chiudeva. In LegaBot le sette
  -- squadre PC hanno preso il loro giocatore — le preferenze PC sono
  -- generate in automatico — e l'unica squadra umana ha perso la scelta con
  -- zero preferenze, senza aver mai avuto la possibilita' di comporre la
  -- lista.
  --
  -- Ora la scadenza viene solo AVVICINATA a 48 ore da adesso, e la
  -- risoluzione resta al percorso normale piu' sotto. Cosi' nessuno perde
  -- una scelta per un cambio di calendario, e il promemoria delle 24 ore
  -- (private.promemoria_scelte_draft) fa in tempo a suonare. La condizione
  -- "> now() + 48 ore" rende l'aggiornamento una tantum: appena avvicinata,
  -- la finestra non rientra piu' nel filtro.
  update public.finestre_scelte f
  set estrazione_il = now() + interval '48 hours'
  from public.leagues l
  where l.id = f.league_id
    and f.risolta_il is null
    and f.estrazione_il is not null
    and f.stagione < l.stagione_corrente
    and f.estrazione_il > now() + interval '48 hours';

  -- Anche le finestre 'off', non piu' solo le 'on'. Prima l'unico modo di
  -- risolvere una OFF-Season era il pulsante dell'admin
  -- (admin_forza_estrazione_scelte): scaduta la sua ora restava aperta per
  -- sempre. Difetto preesistente, emerso guardando questo ciclo il 10
  -- settembre 2026. L'apertura della OFF resta legata alla chiusura della
  -- ON della stessa stagione, come prima.
  -- Il draft a passi (private.avanza_draft_live, ogni minuto) chiama una
  -- scelta alla volta perche' la lega la veda in diretta. Questo ciclo gira
  -- ogni 5 minuti e risolverebbe tutto in un colpo, bruciando la diretta:
  -- quindi salta le finestre ON affidate al draft live finche' e' nei tempi.
  --
  -- Resta pero' la RETE DI SICUREZZA, ed e' il motivo per cui la condizione e'
  -- scritta cosi'. Se il draft live non partisse o si piantasse, dopo il tempo
  -- che gli serve piu' dieci passi di grazia questo ciclo riprende il comando e
  -- risolve ugualmente la finestra. Nessuno perde una scelta perche' una
  -- macchina nuova si e' rotta: al peggio il draft avviene in ritardo e tutto
  -- insieme, come prima di oggi. L'ancora e' coalesce(avviata_il,
  -- estrazione_il): se il draft live non e' mai partito si misura dall'ora di
  -- estrazione, altrimenti il termine non scadrebbe mai.
  for v_finestra in
    select f.league_id, f.stagione, f.finestra
    from public.finestre_scelte f
    where f.risolta_il is null
      and f.estrazione_il is not null and f.estrazione_il <= now()
      and not (
        f.finestra = 'on'
        and f.passo_secondi > 0
        and now() < coalesce(f.avviata_il, f.estrazione_il) + make_interval(secs =>
              f.passo_secondi * (10 + (
                select count(*) from public.scelte_draft sd
                where sd.league_id = f.league_id and sd.stagione = f.stagione
                  and sd.finestra = f.finestra
                  and sd.stato in ('determinata', 'usata', 'vuota')))::integer)
      )
    order by f.league_id, f.stagione, f.finestra
  loop
    begin
      perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'on', true);
      v_risolte := v_risolte + 1;
      if not exists (
        select 1 from public.finestre_scelte
        where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
      end if;
    exception when others then
      raise warning 'mercato a scelte: risoluzione ON-Season fallita per lega % stagione %: % (%)',
        v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
    end;
  end loop;
  return v_risolte;
end;
$function$
;

-- ------------------------------------------------------------
--  6. Il job al minuto
--
--  Non si scrive come orario in cron: cron.timezone e' GMT e l'ora di Roma si
--  sposta con l'ora legale. Gira sempre, ed e' la funzione a decidere se c'e'
--  qualcosa da fare — lo stesso schema degli altri cinque job.
-- ------------------------------------------------------------
do $$
begin
  perform cron.unschedule('avanza-draft-live');
exception when others then
  null;  -- non era ancora schedulato
end $$;

select cron.schedule('avanza-draft-live', '* * * * *', 'select private.avanza_draft_live();');
