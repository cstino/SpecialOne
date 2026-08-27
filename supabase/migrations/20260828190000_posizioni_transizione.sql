-- ============================================================
--  POSIZIONI DI SCELTA: LA TRANSIZIONE UNA TANTUM
--  docs/decisioni-draft-picks.md §2.1
--
--  Non e' la regola a regime. A regime l'ordine lo determinano i due
--  tabelloni dei playoff (§2). Questa e' la compensazione per le squadre
--  che entrano a carriera gia' iniziata: partono indietro rispetto a chi
--  ha gia' giocato una stagione, e il risarcimento sono le prime scelte.
--
--  Fra le nuove, l'ordine premia chi ha speso MENO al draft: e' il modo
--  per non far scegliere per primo chi si e' gia' costruito la rosa piu'
--  cara. A parita' di spesa, sorteggio (deciso dall'utente il 28 agosto).
--
--  Le vecchie vengono dopo, in ordine inverso di classifica: la peggiore
--  delle vecchie sceglie subito dopo l'ultima delle nuove, la campione in
--  carica sceglie per ultima in assoluto.
--
--  Lo stesso ordine vale per ENTRAMBE le finestre della stagione, ON e
--  OFF (§2, ultimo capoverso).
-- ============================================================

-- ------------------------------------------------------------
--  Spesa netta al draft
--
--  Non la somma dei draft_pick: un draft annullato li rimborsa con una
--  riga 'annullamento_draft', e ignorarla farebbe risultare "spendaccione"
--  chi in realta' deve ancora draftare. E' successo davvero — Futuro
--  Nazionale in Real Fampionato risultava a 37,6 M€ con la rosa vuota,
--  perche' il suo draft e' stato annullato il 27 agosto per essere
--  rifatto.
--
--  Non uso il monte ingaggi attuale, che sarebbe piu' semplice ma
--  sbagliato: dopo il draft ci sono aste e scambi, e la classifica di
--  §2.1 deve premiare la parsimonia AL DRAFT, non la rosa di oggi.
--  FC Rocazz lo mostra bene: 38,9 M€ spesi al draft, 41,5 M€ di monte.
-- ------------------------------------------------------------

create or replace function private.spesa_draft(p_team_id bigint)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(-sum(importo), 0)::bigint
  from public.transactions
  where team_id = p_team_id
    and tipo in ('draft_pick', 'annullamento_draft')
$$;

comment on function private.spesa_draft(bigint) is
  'Quanto una squadra ha speso al draft, al netto degli annullamenti. Zero se non ha ancora draftato.';

revoke all on function private.spesa_draft(bigint) from public, anon;
grant execute on function private.spesa_draft(bigint) to authenticated, service_role;

-- ------------------------------------------------------------
--  Assegnazione
-- ------------------------------------------------------------

create or replace function private.assegna_posizioni_transizione(
  p_league_id bigint,
  p_stagione  smallint
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_senza_draft text;
  v_gia         integer;
  v_squadre     integer;
  v_assegnate   integer;
begin
  -- Non si rimescola un ordine gia' fissato: se qualcuno ha gia' composto
  -- la lista di preferenze sapendo di scegliere 3o, cambiargli la
  -- posizione sotto i piedi e' peggio che non assegnarla affatto.
  select count(*) into v_gia
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione and stato <> 'futura';
  if v_gia > 0 then
    raise exception using errcode = '55000',
      message = 'Le posizioni della stagione ' || p_stagione || ' sono gia'' state assegnate.';
  end if;

  select count(*) into v_squadre
  from public.scelte_draft
  where league_id = p_league_id and stagione = p_stagione and finestra = 'on';
  if v_squadre = 0 then
    raise exception using errcode = 'P0002',
      message = 'Nessuna scelta generata per la stagione ' || p_stagione || '.';
  end if;

  -- Una squadra entrata adesso e senza rosa non ha ancora draftato: la sua
  -- spesa varrebbe zero e si prenderebbe la prima scelta per un draft che
  -- non ha fatto.
  select string_agg(t.nome, ', ' order by t.nome) into v_senza_draft
  from public.teams t
  where t.league_id = p_league_id
    and t.entrata_stagione = p_stagione
    and t.attiva
    and not exists (select 1 from public.player_instances pi where pi.team_id = t.id);
  if v_senza_draft is not null then
    raise exception using errcode = '55000',
      message = 'Queste squadre non hanno ancora completato il draft: ' || v_senza_draft
                || '. Con la rosa vuota la spesa varrebbe zero e si prenderebbero le prime scelte.';
  end if;

  with ordine as (
    select
      t.id as team_id,
      row_number() over (
        order by
          -- prima le nuove
          (t.entrata_stagione is distinct from p_stagione),
          -- fra le nuove: chi ha speso meno al draft, poi sorteggio
          case when t.entrata_stagione = p_stagione then private.spesa_draft(t.id) end asc,
          -- fra le vecchie: ordine inverso di classifica
          case when t.entrata_stagione is distinct from p_stagione then st.posizione end desc,
          random()
      )::smallint as posizione
    from public.teams t
    left join public.seasons se
      on se.league_id = p_league_id and se.numero = (p_stagione - 1)::smallint
    left join public.standings st
      on st.season_id = se.id and st.team_id = t.id
    where t.league_id = p_league_id and t.attiva
  )
  update public.scelte_draft sd
  set posizione = o.posizione,
      stato     = 'determinata',
      aggiornata_il = now()
  from ordine o
  where sd.league_id = p_league_id
    and sd.stagione  = p_stagione
    and sd.team_origine_id = o.team_id;

  get diagnostics v_assegnate = row_count;
  return v_assegnate;
end;
$$;

comment on function private.assegna_posizioni_transizione(bigint, smallint) is
  'Ordine di scelta una tantum per le stagioni senza playoff a monte: prima le squadre entrate ora (spesa al draft crescente, parita'' a sorteggio), poi le altre in ordine inverso di classifica (docs/decisioni-draft-picks.md §2.1).';

revoke all on function private.assegna_posizioni_transizione(bigint, smallint) from public, anon, authenticated;
grant execute on function private.assegna_posizioni_transizione(bigint, smallint) to service_role;
