-- ============================================================
--  MODULI PERSONALIZZATI
--
--  Richiesta del committente (29 settembre 2026): uno schema modificato si
--  salva con un nome e poi compare nel menu dei moduli della Formazione.
--  Decisioni prese con lui:
--    - si salva TUTTO: posizioni, ruoli, compiti e dove si attacca. Un modulo
--      personalizzato e' un'idea di gioco completa, pronta da richiamare;
--    - al massimo 3 per squadra: al quarto se ne sovrascrive uno o se ne
--      elimina uno;
--    - ognuno vede solo i suoi. Sono le tattiche di una squadra: un avversario
--      che le leggesse saprebbe come giochera' (CLAUDE.md §6, requisito di
--      sicurezza principale).
--
--  Il modulo salvato e' solo un modello: richiamarlo riempie lo Schema
--  Tattico, e quello che conta per la partita resta la formazione salvata
--  (public.lineups), con i controlli di salva_formazione. Per questo qui non
--  serve l'interruttore tattiche_attive.
--
--  La familiarita' non ha bisogno di niente: formation_xp e' gia' indicizzata
--  sullo schieramento, quindi tornare a un modulo salvato ritrova il suo
--  contatore come tornare al vecchio 4-4-2.
-- ============================================================

create table public.moduli_personalizzati (
  id            bigint generated always as identity primary key,
  league_id     bigint not null references public.leagues(id) on delete cascade,
  team_id       bigint not null references public.teams(id) on delete cascade,
  nome          text not null check (char_length(btrim(nome)) between 1 and 30),
  -- Il modulo di partenza: e' la chiave della familiarita' e decide quali
  -- spostamenti sono leciti.
  modulo        text not null,
  -- Sempre gli undici slot, anche se nessuno e' spostato: cosi' richiamarlo
  -- non dipende da come il frontend rappresenta "nessuno spostamento".
  disposizione  text[] not null check (cardinality(disposizione) = 11),
  ruoli         text[] check (ruoli is null or cardinality(ruoli) = 11),
  compiti       text[] check (compiti is null or cardinality(compiti) = 11),
  focus_corsia  text check (focus_corsia is null or focus_corsia in ('SX','CEN','DX')),
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

create unique index moduli_personalizzati_nome_unico
  on public.moduli_personalizzati (team_id, lower(btrim(nome)));
create index moduli_personalizzati_squadra
  on public.moduli_personalizzati (team_id);

comment on table public.moduli_personalizzati is
  'Schemi tattici salvati con un nome (max 3 per squadra). Visibili solo al proprietario della squadra.';

alter table public.moduli_personalizzati enable row level security;

-- Lettura: solo le righe della propria squadra. Scrittura: solo dalle due
-- funzioni qui sotto, che applicano i controlli.
create policy moduli_personalizzati_propri on public.moduli_personalizzati
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = moduli_personalizzati.team_id and t.user_id = (select auth.uid())
  ));

revoke all on public.moduli_personalizzati from anon, authenticated;
grant select on public.moduli_personalizzati to authenticated;


-- ------------------------------------------------------------
--  Salva (o sovrascrive) un modulo personalizzato
--
--  p_sostituisci: l'id di un modulo della stessa squadra da sovrascrivere.
--  NULL = nuovo modulo, rifiutato se la squadra ne ha gia' 3.
-- ------------------------------------------------------------
create or replace function public.salva_modulo_personalizzato(
  p_league_id    bigint,
  p_nome         text,
  p_modulo       text,
  p_disposizione text[],
  p_ruoli        text[] default null,
  p_compiti      text[] default null,
  p_focus_corsia text default null,
  p_sostituisci  bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team_id bigint;
  v_std     text[];
  v_nome    text := btrim(coalesce(p_nome, ''));
  v_id      bigint;
  v_i       integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare un modulo.';
  end if;

  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  if char_length(v_nome) not between 1 and 30 then
    raise exception using errcode = '22023', message = 'Il nome deve avere da 1 a 30 caratteri.';
  end if;

  -- Stessi controlli di salva_formazione: da qui non puo' uscire uno schema
  -- che poi la formazione rifiuterebbe.
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  v_std := private.disposizione_standard(p_modulo);
  if v_std is null then
    raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
  end if;
  if p_disposizione is null or cardinality(p_disposizione) <> 11 then
    raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
  end if;
  for v_i in 1..11 loop
    if not (p_disposizione[v_i] = any(private.spostamenti_slot(v_std[v_i]))) then
      raise exception using errcode = '22023',
        message = format('La posizione %s non puo'' diventare %s.', v_std[v_i], p_disposizione[v_i]);
    end if;
  end loop;

  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(p_disposizione[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], p_disposizione[v_i]);
      end if;
    end loop;
  end if;

  if p_compiti is not null then
    if cardinality(p_compiti) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 compiti, uno per posizione.';
    end if;
    if exists (select 1 from unnest(p_compiti) c where c is not null and c not in ('difesa','equilibrio','attacco')) then
      raise exception using errcode = '22023', message = 'Compito non valido.';
    end if;
  end if;

  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;

  if exists (
    select 1 from public.moduli_personalizzati m
    where m.team_id = v_team_id and lower(btrim(m.nome)) = lower(v_nome)
      and m.id is distinct from p_sostituisci
  ) then
    raise exception using errcode = '23505', message = 'Hai già un modulo con questo nome.';
  end if;

  if p_sostituisci is not null then
    update public.moduli_personalizzati m
    set nome = v_nome, modulo = p_modulo, disposizione = p_disposizione, ruoli = p_ruoli,
        compiti = p_compiti, focus_corsia = p_focus_corsia, aggiornato_il = now()
    where m.id = p_sostituisci and m.team_id = v_team_id
    returning m.id into v_id;
    if v_id is null then
      raise exception using errcode = 'P0002', message = 'Il modulo da sovrascrivere non esiste.';
    end if;
    return v_id;
  end if;

  -- Il tetto si controlla sotto lock della squadra: due salvataggi insieme
  -- dallo stesso account non devono arrivare a 4.
  perform 1 from public.teams t where t.id = v_team_id for update;
  if (select count(*) from public.moduli_personalizzati m where m.team_id = v_team_id) >= 3 then
    raise exception using errcode = '23514',
      message = 'Hai già 3 moduli personalizzati: sovrascrivine uno o eliminane uno.';
  end if;

  insert into public.moduli_personalizzati
    (league_id, team_id, nome, modulo, disposizione, ruoli, compiti, focus_corsia)
  values
    (p_league_id, v_team_id, v_nome, p_modulo, p_disposizione, p_ruoli, p_compiti, p_focus_corsia)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.salva_modulo_personalizzato(bigint, text, text, text[], text[], text[], text, bigint) from public, anon;
grant execute on function public.salva_modulo_personalizzato(bigint, text, text, text[], text[], text[], text, bigint) to authenticated;


-- ------------------------------------------------------------
--  Elimina un modulo personalizzato della propria squadra
-- ------------------------------------------------------------
create or replace function public.elimina_modulo_personalizzato(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di eliminare un modulo.';
  end if;
  delete from public.moduli_personalizzati m
  using public.teams t
  where m.id = p_id and t.id = m.team_id and t.user_id = (select auth.uid());
  if not found then
    raise exception using errcode = 'P0002', message = 'Modulo non trovato.';
  end if;
end;
$$;

revoke all on function public.elimina_modulo_personalizzato(bigint) from public, anon;
grant execute on function public.elimina_modulo_personalizzato(bigint) to authenticated;
