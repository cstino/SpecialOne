-- ============================================================
--  ECONOMIA A TETTO SALARIALE — passo 1: fondamenta
--  docs/decisioni-economia.md §1, §2
--
--  Questa migrazione e' ADDITIVA: non rimuove nulla e non cambia il
--  comportamento di nessuna funzione esistente. Introduce solo la colonna
--  del tetto e le primitive di capienza su cui si appoggeranno i passi
--  successivi (contratti annuali, percorsi di spesa, rimozione delle
--  entrate). Fino al passo 5 il vecchio modello a cassa continua a girare
--  in parallelo: le leghe gia' in corso non si accorgono di niente.
-- ============================================================

-- ------------------------------------------------------------
--  Il tetto
--
--  Sostituisce leagues.budget_iniziale come vincolo economico, ma non lo
--  rimuove ancora: budget_iniziale e' letto da 134 punti e va spento per
--  ultimo (passo 5). Qui viene solo copiato come valore di partenza, cosi'
--  una lega esistente parte da un tetto pari alla sua vecchia dotazione.
--
--  Pavimento: 25 slot al minimo contrattuale di 500.000 = 12,5 M€. Sotto
--  quella cifra una rosa regolamentare non e' componibile e il draft
--  andrebbe in deadlock (CLAUDE.md §7).
-- ------------------------------------------------------------

alter table public.leagues
  add column if not exists tetto_ingaggi bigint
  check (tetto_ingaggi between 12500000 and 500000000);

update public.leagues set tetto_ingaggi = budget_iniziale where tetto_ingaggi is null;

alter table public.leagues alter column tetto_ingaggi set not null;
alter table public.leagues alter column tetto_ingaggi set default 70000000;

comment on column public.leagues.tetto_ingaggi is
  'Tetto salariale: somma massima degli ingaggi attivi in una stagione. Uguale per tutte le squadre e immutabile tra stagioni (docs/decisioni-economia.md §1). Non e'' un portafoglio: non si consuma e non si accumula.';

-- ------------------------------------------------------------
--  Monte ingaggi di una squadra in una data stagione
--
--  Un contratto e' attivo nella stagione S finche' contratto_scadenza >= S.
--  E' la stessa convenzione gia' usata da monte_ingaggi_prossima_stagione
--  (che filtra contratto_scadenza > stagione_corrente, cioe' >= corrente+1),
--  qui generalizzata a una stagione qualsiasi.
--
--  I ritirati non contano: lasciano la rosa e liberano lo spazio.
-- ------------------------------------------------------------

create or replace function private.monte_ingaggi(
  p_team_id  bigint,
  p_stagione smallint
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(ingaggio), 0)::bigint
  from public.player_instances
  where team_id = p_team_id
    and not ritirato
    and contratto_scadenza >= p_stagione
$$;

comment on function private.monte_ingaggi(bigint, smallint) is
  'Somma degli ingaggi attivi nella stagione indicata. Un contratto e'' attivo finche'' contratto_scadenza >= stagione.';

-- ------------------------------------------------------------
--  Ingaggi gia' promessi dalle offerte d'asta ancora aperte
--
--  Analogo di private.budget_impegnato, ma in spazio salariale invece che
--  in contanti: un'offerta a busta chiusa non muove denaro, pero' se vince
--  occupa il tetto. Va contata prima, altrimenti si puo' offrire su cinque
--  aste con la capienza per una sola.
--
--  p_escludi: l'asta di cui si sta modificando la propria offerta, per non
--  contare due volte l'offerta che si sta sostituendo. Stessa convenzione
--  di budget_impegnato.
-- ------------------------------------------------------------

create or replace function private.ingaggi_impegnati_aste(
  p_team_id bigint,
  p_escludi bigint default null
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(b.ingaggio_offerto), 0)::bigint
  from public.free_agent_bids b
  join public.free_agent_auctions a on a.id = b.auction_id
  where b.team_id = p_team_id
    and a.stato = 'aperta'
    and (p_escludi is null or b.auction_id <> p_escludi)
$$;

comment on function private.ingaggi_impegnati_aste(bigint, bigint) is
  'Somma degli ingaggi offerti sulle aste ancora aperte. Occupano capienza anche se non hanno ancora vinto.';

-- ------------------------------------------------------------
--  Capienza residua sotto il tetto
--
--  E' la quantita' che il gioco mostra e su cui decide: quanto ingaggio
--  ancora si puo' assumere per la stagione indicata.
-- ------------------------------------------------------------

create or replace function private.capienza_residua(
  p_team_id  bigint,
  p_stagione smallint,
  p_escludi  bigint default null
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select l.tetto_ingaggi
         - private.monte_ingaggi(p_team_id, p_stagione)
         - private.ingaggi_impegnati_aste(p_team_id, p_escludi)
  from public.teams t
  join public.leagues l on l.id = t.league_id
  where t.id = p_team_id
$$;

comment on function private.capienza_residua(bigint, smallint, bigint) is
  'Tetto meno gli ingaggi attivi nella stagione meno le offerte d''asta aperte. Puo'' essere negativo su rose ereditate dal vecchio modello a cassa.';

-- ------------------------------------------------------------
--  Il controllo che sostituisce verifica_sostenibilita
--
--  La differenza sostanziale rispetto al vecchio tetto di sostenibilita':
--  quello stimava (entrate future nel caso peggiore, monte della prossima
--  stagione), questo NON stima nulla. Tetto e ingaggi sono entrambi noti,
--  quindi la risposta e' esatta.
--
--  Come verifica_sostenibilita, lascia sempre passare chi ALLEGGERISCE:
--  una rosa ereditata dal modello a cassa puo' essere sopra il tetto, e
--  deve poter rientrare invece di restare incastrata.
-- ------------------------------------------------------------

create or replace function private.verifica_capienza(
  p_team_id   bigint,
  p_ingaggio  bigint,
  p_stagione  smallint,
  p_escludi   bigint default null
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_residua bigint;
begin
  if p_ingaggio <= 0 then
    return;
  end if;

  v_residua := private.capienza_residua(p_team_id, p_stagione, p_escludi);

  if v_residua < p_ingaggio then
    raise exception using errcode = '22023', message =
      'Fuori dal tetto ingaggi: servono ' || private.in_milioni(p_ingaggio)
      || ' M€ di spazio salariale per la stagione ' || p_stagione
      || ', ma ne restano ' || private.in_milioni(greatest(v_residua, 0)) || ' M€.';
  end if;
end;
$$;

comment on function private.verifica_capienza(bigint, bigint, smallint, bigint) is
  'Rifiuta un impegno che sfonderebbe il tetto nella stagione indicata. Esatto, non prudenziale: non stima entrate future perche'' non ne esistono.';

-- ------------------------------------------------------------
--  Privilegi
--
--  Il browser deve poter leggere la capienza per comporre un'offerta o un
--  rinnovo, esattamente come oggi legge budget_impegnato. Il resto resta
--  chiuso: verifica_capienza la chiamano solo le RPC.
-- ------------------------------------------------------------

revoke all on function private.monte_ingaggi(bigint, smallint)                  from public, anon, authenticated;
revoke all on function private.ingaggi_impegnati_aste(bigint, bigint)           from public, anon, authenticated;
revoke all on function private.capienza_residua(bigint, smallint, bigint)       from public, anon, authenticated;
revoke all on function private.verifica_capienza(bigint, bigint, smallint, bigint) from public, anon, authenticated;

grant execute on function private.monte_ingaggi(bigint, smallint)            to authenticated, service_role;
grant execute on function private.ingaggi_impegnati_aste(bigint, bigint)     to authenticated, service_role;
grant execute on function private.capienza_residua(bigint, smallint, bigint) to authenticated, service_role;
grant execute on function private.verifica_capienza(bigint, bigint, smallint, bigint) to service_role;
