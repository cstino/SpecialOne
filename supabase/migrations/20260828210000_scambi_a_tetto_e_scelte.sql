-- ============================================================
--  ECONOMIA A TETTO SALARIALE — passo 5: scambi umani
--  docs/decisioni-economia.md §2, §3 ("Scambi")
--
--  "Il conguaglio economico non esiste piu'. Funziona come in NBA: si
--  scambiano giocatori e scelte." (utente, 28 agosto 2026)
--
--  Cosa sparisce, e perche' non basta togliere un parametro:
--
--  - conguaglio in contanti: sparisce dalla tabella, non solo dalle
--    funzioni. Non c'e' piu' niente da conguagliare.
--  - pro-rata dell'ingaggio residuo di stagione sui giocatori scambiati:
--    esisteva per ribilanciare CHI paga il resto della stagione per quel
--    giocatore. Sotto il tetto non si "paga" niente giorno per giorno
--    (il pagamento rateale sparisce col passo 5 stesso), quindi la domanda
--    non ha piu' senso: lo stipendio semplicemente segue il giocatore.
--  - rispondi_a_proposta_cassa_legacy: il nucleo su cui erano stratificati
--    due cancelli successivi (ingaggi_riservati, poi capienza). Riscritta
--    da zero invece di stratificare un terzo strato: la funzione gestiva
--    SOLO contanti, non c'era logica "core" da preservare.
--
--  Cosa si aggiunge: le scelte di draft come asset scambiabile
--  (docs/decisioni-draft-picks.md §3.2). Una scelta si scambia trasferendo
--  team_proprietario_id; non ha un ingaggio proprio, quindi il suo
--  trasferimento non tocca mai la capienza — solo i giocatori la toccano.
--
--  Scoping esplicito: le squadre PC. proposte_mercato_squadre_pc offriva
--  "compro con contanti" — un mercato non piu' esistente. Diventa un
--  generatore di scambi 1-per-1 (da' un giocatore in surplus, chiede il
--  bersaglio), usando la stessa valutazione (valore_mercato_pc) gia' in
--  uso. rispondi_a_proposta_pc rifiuta a priori qualunque proposta che
--  chieda una SUA scelta (non ha un modo di valutarle): puo' solo
--  ricevere scelte in omaggio, mai cederle. Non e' una strategia raffinata,
--  e' la scelta prudente finche' non si decide una valutazione delle
--  scelte per il PC (docs/decisioni-draft-picks.md §7, punto aperto).
-- ============================================================

-- ------------------------------------------------------------
--  Schema: via il conguaglio, dentro le scelte
-- ------------------------------------------------------------

alter table public.trade_proposals drop column if exists conguaglio;

alter table public.trade_proposals
  add column if not exists scelte_offerte   bigint[] not null default '{}',
  add column if not exists scelte_richieste bigint[] not null default '{}';

alter table public.trade_proposals drop constraint if exists trade_non_vuota;
alter table public.trade_proposals add constraint trade_non_vuota check (
  cardinality(giocatori_offerti) + cardinality(giocatori_richiesti)
  + cardinality(scelte_offerte) + cardinality(scelte_richieste) > 0
);

comment on column public.trade_proposals.scelte_offerte is
  'id di scelte_draft offerte dal proponente (da_team_id deve esserne proprietario al momento dell''offerta e dell''accettazione).';
comment on column public.trade_proposals.scelte_richieste is
  'id di scelte_draft richieste al destinatario (a_team_id deve esserne proprietario).';

-- ------------------------------------------------------------
--  Le funzioni cash-only che sparivano comunque con la colonna
-- ------------------------------------------------------------

drop function if exists public.rispondi_a_proposta_cassa_legacy(bigint, boolean);

-- ------------------------------------------------------------
--  Proporre uno scambio: giocatori e/o scelte, mai contanti
-- ------------------------------------------------------------

drop function if exists public.proponi_scambio(bigint, bigint[], bigint[], bigint, text);

create or replace function public.proponi_scambio(
  p_a_team_id bigint,
  p_giocatori_offerti bigint[] default '{}'::bigint[],
  p_giocatori_richiesti bigint[] default '{}'::bigint[],
  p_scelte_offerte bigint[] default '{}'::bigint[],
  p_scelte_richieste bigint[] default '{}'::bigint[],
  p_messaggio text default null::text
) returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_dest public.teams;
  v_mia public.teams;
  v_lega public.leagues;
  v_g_off bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_g_ric bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_s_off bigint[] := coalesce(p_scelte_offerte, '{}');
  v_s_ric bigint[] := coalesce(p_scelte_richieste, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  if cardinality(v_g_off) + cardinality(v_g_ric) + cardinality(v_s_off) + cardinality(v_s_ric) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore o una scelta.';
  end if;

  if cardinality(array(select distinct unnest(v_g_off))) <> cardinality(v_g_off)
     or cardinality(array(select distinct unnest(v_g_ric))) <> cardinality(v_g_ric)
     or v_g_off && v_g_ric then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;
  if cardinality(array(select distinct unnest(v_s_off))) <> cardinality(v_s_off)
     or cardinality(array(select distinct unnest(v_s_ric))) <> cardinality(v_s_ric)
     or v_s_off && v_s_ric then
    raise exception using errcode = '22023', message = 'Una scelta compare due volte nella proposta.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_g_off) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_g_ric) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;
  if exists (select 1 from public.player_instances where id = any(v_g_off || v_g_ric) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;

  -- Una scelta si offre solo finche' non e' stata esercitata: 'usata' e
  -- 'vuota' sono gia' storia, non piu' un asset.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_off) and team_proprietario_id = v_mia.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo una scelta che non possiedi o gia'' esercitata.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_ric) and team_proprietario_id = v_dest.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo una scelta che quella squadra non possiede o gia'' esercitata.';
  end if;

  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id,
    giocatori_offerti, giocatori_richiesti, scelte_offerte, scelte_richieste,
    messaggio, scade_il
  ) values (
    v_lega.id, v_mia.id, v_dest.id,
    v_g_off, v_g_ric, v_s_off, v_s_ric,
    nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza
  ) returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 21:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  return v_proposta;
end;
$$;

revoke all on function public.proponi_scambio(bigint, bigint[], bigint[], bigint[], bigint[], text) from public, anon;
grant execute on function public.proponi_scambio(bigint, bigint[], bigint[], bigint[], bigint[], text) to authenticated;

-- ------------------------------------------------------------
--  Controproposta: chiude l'originale e ne apre una nuova invertita
-- ------------------------------------------------------------

drop function if exists public.controproponi(bigint, bigint[], bigint[], bigint, text);

create or replace function public.controproponi(
  p_proposta_id bigint,
  p_giocatori_offerti bigint[] default '{}'::bigint[],
  p_giocatori_richiesti bigint[] default '{}'::bigint[],
  p_scelte_offerte bigint[] default '{}'::bigint[],
  p_scelte_richieste bigint[] default '{}'::bigint[],
  p_messaggio text default null::text
) returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_originale public.trade_proposals;
  v_nuova public.trade_proposals;
begin
  select * into v_originale from public.trade_proposals where id = p_proposta_id for update;
  if not found then raise exception 'Proposta non trovata'; end if;
  if not private.e_mia_squadra(v_originale.a_team_id) then raise exception 'Non autorizzato'; end if;
  if v_originale.stato <> 'in_attesa' then raise exception 'La proposta non è più in attesa'; end if;
  if v_originale.scade_il <= now() then raise exception 'La proposta è scaduta'; end if;

  update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_originale.id;

  select * into v_nuova from public.proponi_scambio(
    v_originale.da_team_id,
    coalesce(p_giocatori_offerti, '{}'), coalesce(p_giocatori_richiesti, '{}'),
    coalesce(p_scelte_offerte, '{}'), coalesce(p_scelte_richieste, '{}'),
    p_messaggio
  );

  update public.trade_proposals set controproposta_di = v_originale.id
  where id = v_nuova.id
  returning * into v_nuova;
  return v_nuova;
end;
$$;

revoke all on function public.controproponi(bigint, bigint[], bigint[], bigint[], bigint[], text) from public, anon;
grant execute on function public.controproponi(bigint, bigint[], bigint[], bigint[], bigint[], text) to authenticated;

-- ------------------------------------------------------------
--  Rumors pubblici: espone anche le scelte coinvolte
-- ------------------------------------------------------------

drop function if exists public.trattative_pubbliche(bigint);

create or replace function public.trattative_pubbliche(p_league_id bigint)
returns table (
  id bigint,
  da_team_id bigint,
  a_team_id bigint,
  giocatori_offerti bigint[],
  giocatori_richiesti bigint[],
  scelte_offerte bigint[],
  scelte_richieste bigint[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select tp.id, tp.da_team_id, tp.a_team_id,
         tp.giocatori_offerti, tp.giocatori_richiesti,
         tp.scelte_offerte, tp.scelte_richieste
  from public.trade_proposals tp
  where tp.league_id = p_league_id
    and tp.stato = 'in_attesa'
    and (select private.e_membro(p_league_id))
  order by tp.creata_il desc;
$$;

-- ------------------------------------------------------------
--  Accettare o rifiutare: nucleo riscritto, niente contanti
-- ------------------------------------------------------------

create or replace function public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
returns public.trade_proposals
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if not private.mercato_aperto_lega(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  -- Lock deterministico sulle due squadre: evita deadlock fra due
  -- accettazioni concorrenti che coinvolgono la stessa coppia.
  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  -- Stesso controllo per le scelte: puo' essere stata gia' esercitata, o
  -- rigirata altrove, nel tempo fra la proposta e questa risposta.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  -- Trasferimenti: prima i giocatori (i trigger su player_instances
  -- gestiscono liste e rinnovi in corso), poi le scelte.
  update public.player_instances set team_id = v_a.id  where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);

  -- Capienza: dopo aver spostato i giocatori, il monte di ciascuna
  -- squadra include gia' l'effetto dello scambio. Le scelte non vi
  -- contribuiscono: non hanno un ingaggio proprio finche' non si
  -- esercitano.
  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';
  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id in (v_da.id, v_a.id)
      and giornata >= v_prossima
      and (titolari && v_tutti or panchina && v_tutti or tribuna && v_tutti);
    get diagnostics v_form_tolte = row_count;
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  -- Registro: non piu' movimento di cassa, ma di spazio salariale. Zero
  -- e' un esito legittimo (scambio di picks pure, o pari valore) e non
  -- genera riga: importo <> 0 e' un vincolo della tabella.
  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, v_da.budget);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, v_a.budget);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));

  return v_p;
end;
$$;

revoke all on function public.rispondi_a_proposta(bigint, boolean) from public, anon, authenticated;
grant execute on function public.rispondi_a_proposta(bigint, boolean) to authenticated;

-- ------------------------------------------------------------
--  Squadre PC: da "compro con contanti" a scambio 1-per-1
--
--  Non e' una strategia raffinata. E' la versione minima che tiene il
--  mercato dei bot vivo senza contanti: cede un giocatore in surplus
--  (fuori dal ruolo appena cercato, cosi' non riapre subito lo stesso
--  buco) di valore comparabile al bersaglio.
-- ------------------------------------------------------------

create or replace function private.proposte_mercato_squadre_pc(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pc public.teams;
  v_bersaglio record;
  v_dai record;
  v_ruolo text;
  v_scadenza timestamptz;
  v_preferisce_pc boolean;
  v_stagione smallint;
  v_delta_pc bigint;
  v_inserite integer := 0;
begin
  v_stagione := private.stagione_contratto(p_league_id);

  for v_pc in
    select t.* from public.teams t
    where t.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.da_team_id = t.id and tp.stato = 'in_attesa'
      )
    order by random()
  loop
    if random() > 0.34 then continue; end if;

    select ruoli.ruolo into v_ruolo
    from (values ('GK'), ('DEF'), ('MID'), ('ATT')) as ruoli(ruolo)
    left join (
      select private.macro_ruolo(p.posizioni) as ruolo,
             count(*) as quanti,
             avg(pi.overall_corrente) as media
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      where pi.team_id = v_pc.id
      group by private.macro_ruolo(p.posizioni)
    ) rosa using (ruolo)
    order by coalesce(rosa.quanti, 0), coalesce(rosa.media, 0), random()
    limit 1;

    v_preferisce_pc := random() < 0.60;
    select pi.id, pi.team_id, pi.ingaggio, pi.overall_corrente, t.controllata_da_pc
      into v_bersaglio
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id
    where pi.league_id = p_league_id
      and t.id <> v_pc.id and t.attiva
      and not pi.ritiro_annunciato
      and private.macro_ruolo(p.posizioni) = coalesce(v_ruolo, 'MID')
      and (select count(*) from public.player_instances x where x.team_id = t.id) > private.rosa_minima()
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.stato = 'in_attesa'
          and pi.id = any(tp.giocatori_richiesti)
      )
    order by (t.controllata_da_pc = v_preferisce_pc) desc,
             abs(pi.overall_corrente - 74 + floor(random() * 9)::integer), random()
    limit 1;
    if not found then continue; end if;

    -- Cosa cedere in cambio: un giocatore fuori dal ruolo appena cercato
    -- (altrimenti si riapre subito lo stesso buco), di ingaggio simile al
    -- bersaglio — proxy di valore comparabile senza dover stimare
    -- l'overall di entrambi.
    select pi.id, pi.ingaggio into v_dai
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.team_id = v_pc.id
      and not pi.ritiro_annunciato
      and private.macro_ruolo(p.posizioni) <> coalesce(v_ruolo, 'MID')
      and not exists (
        select 1 from public.trade_proposals tp
        where tp.league_id = p_league_id and tp.stato = 'in_attesa'
          and pi.id = any(tp.giocatori_offerti)
      )
    order by abs(pi.ingaggio - v_bersaglio.ingaggio), random()
    limit 1;
    if not found then continue; end if;

    v_delta_pc := v_bersaglio.ingaggio - v_dai.ingaggio;
    if v_delta_pc > 0 and private.capienza_residua(v_pc.id, v_stagione) < v_delta_pc then continue; end if;

    v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
    if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

    insert into public.trade_proposals(
      league_id, da_team_id, a_team_id, giocatori_offerti, giocatori_richiesti, messaggio, scade_il
    ) values (
      p_league_id, v_pc.id, v_bersaglio.team_id, array[v_dai.id], array[v_bersaglio.id],
      'Proposta di scambio del direttore sportivo.', v_scadenza
    );

    if not v_bersaglio.controllata_da_pc then
      perform private.notifica(
        (select user_id from public.teams where id = v_bersaglio.team_id),
        p_league_id, 'mercato_proposta', 'Offerta di scambio da ' || v_pc.nome,
        'Il club propone uno scambio per un tuo giocatore.', jsonb_build_object('team_id', v_pc.id)
      );
    end if;
    v_inserite := v_inserite + 1;
  end loop;
  return v_inserite;
end;
$$;

revoke all on function private.proposte_mercato_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function private.proposte_mercato_squadre_pc(bigint) to service_role;

-- ------------------------------------------------------------
--  Squadre PC: decisione su proposte in entrata, senza contanti
--
--  Rifiuta subito se gli si chiede una scelta: non ha un modo di
--  valutarle (docs/decisioni-draft-picks.md §7, punto aperto), quindi non
--  ne cede mai. Puo' pero' accettare scelte offerte in omaggio, che non
--  contano nella soglia di valutazione: sono un bonus, mai un onere.
-- ------------------------------------------------------------

create or replace function private.rispondi_a_proposta_pc(p_proposta_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_p public.trade_proposals;
  v_lega public.leagues;
  v_da public.teams;
  v_a public.teams;
  v_valore_offerto bigint;
  v_valore_richiesto bigint;
  v_rosa_da integer;
  v_rosa_a integer;
  v_stagione smallint;
  v_ing_verso_a bigint;
  v_ing_verso_da bigint;
  v_delta_a bigint;
  v_delta_da bigint;
begin
  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found or v_p.stato <> 'in_attesa' then return; end if;
  select * into v_lega from public.leagues where id = v_p.league_id;
  select * into v_da from public.teams where id = v_p.da_team_id for update;
  select * into v_a from public.teams where id = v_p.a_team_id and controllata_da_pc for update;
  if not found then return; end if;

  if cardinality(v_p.scelte_richieste) > 0 then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      v_a.nome || ' non tratta le proprie scelte di draft.', jsonb_build_object('proposta_id', v_p.id));
    return;
  end if;

  if (select count(*) from public.player_instances where id = any(v_p.giocatori_offerti) and team_id = v_da.id) <> cardinality(v_p.giocatori_offerti)
     or (select count(*) from public.player_instances where id = any(v_p.giocatori_richiesti) and team_id = v_a.id) <> cardinality(v_p.giocatori_richiesti)
     or (select count(*) from public.scelte_draft where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura','determinata')) <> cardinality(v_p.scelte_offerte)
  then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_offerto from public.player_instances pi where pi.id = any(v_p.giocatori_offerti);
  select coalesce(sum(private.valore_mercato_pc(pi.overall_corrente, pi.ingaggio)), 0)::bigint
    into v_valore_richiesto from public.player_instances pi where pi.id = any(v_p.giocatori_richiesti);

  if v_valore_offerto < round(v_valore_richiesto * (0.94 + random() * 0.12)) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      v_a.nome || ' ha rifiutato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
    return;
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a := v_rosa_a - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da not between private.rosa_minima() and private.rosa_massima()
     or v_rosa_a not between private.rosa_minima() and private.rosa_massima() then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  v_stagione := private.stagione_contratto(v_p.league_id);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_a from public.player_instances where id = any(v_p.giocatori_offerti);
  select coalesce(sum(ingaggio), 0) into v_ing_verso_da from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_a := v_ing_verso_a - v_ing_verso_da;
  v_delta_da := v_ing_verso_da - v_ing_verso_a;

  if v_delta_a > 0 and private.capienza_residua(v_a.id, v_stagione) < v_delta_a then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;
  if v_da.controllata_da_pc and v_delta_da > 0 and private.capienza_residua(v_da.id, v_stagione) < v_delta_da then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now() where id = v_p.id;
    return;
  end if;

  update public.player_instances set team_id = v_a.id where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id, aggiornata_il = now() where id = any(v_p.scelte_offerte);
  delete from public.lineups where league_id = v_p.league_id and team_id in (v_da.id, v_a.id);

  if v_delta_da <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, v_da.budget);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_p.league_id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, v_a.budget);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now() where id = v_p.id;
  perform private.notifica(v_da.user_id, v_p.league_id, 'mercato_esito', 'Proposta accettata',
    v_a.nome || ' ha accettato la tua proposta.', jsonb_build_object('proposta_id', v_p.id));
end;
$$;

revoke all on function private.rispondi_a_proposta_pc(bigint) from public, anon, authenticated;
grant execute on function private.rispondi_a_proposta_pc(bigint) to service_role;
