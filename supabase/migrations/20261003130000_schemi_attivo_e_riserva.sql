-- ============================================================
--  SCHEMI: ATTIVO E RISERVA (season 2, 3 ottobre 2026)
--
--  Rifà il "modulo secondario" (migrazione 20261003120000, applicata solo da
--  poche ore e mai usata: la tabella è vuota) come chiede il committente, in
--  stile EA FC: ogni squadra ha DUE schemi tattici, con un nome.
--    - lo schema ATTIVO è quello che gioca: coincide con la formazione salvata
--      (public.lineups); qui si tiene solo il suo nome (default "Schema 1");
--    - lo schema RISERVA è uno schema tattico completo (modulo, schieramento,
--      ruoli, compiti, dove si attacca, stile, linea, ampiezza, portiere) che
--      la squadra prepara: il suo modulo accumula una partita di familiarità a
--      ogni partita anche se non lo schiera, e dopo 5 è conosciuto come il
--      principale. Si può scambiare con l'attivo senza perdite (i contatori non
--      calano) oppure eliminarlo e prepararne un altro.
--
--  La familiarità resta quella del MODULO (barra disposizione): la barra
--  indicazioni (stile, ruoli, compiti, ...) non avanza da sola, come deciso.
--  Solo nelle leghe con tattiche_attive. Visibile solo al proprietario.
-- ============================================================
begin;

drop function if exists public.imposta_modulo_secondario(bigint, text, text[]);
drop table public.modulo_secondario;

create table public.schemi_squadra (
  team_id      bigint primary key references public.teams(id) on delete cascade,
  league_id    bigint not null references public.leagues(id) on delete cascade,
  nome_attivo  text not null default 'Schema 1' check (char_length(btrim(nome_attivo)) between 1 and 24),
  -- La riserva: tutto o niente.
  riserva_nome         text check (riserva_nome is null or char_length(btrim(riserva_nome)) between 1 and 24),
  riserva_modulo       text,
  riserva_disposizione text[] check (riserva_disposizione is null or cardinality(riserva_disposizione) = 11),
  riserva_ruoli        text[] check (riserva_ruoli is null or cardinality(riserva_ruoli) = 11),
  riserva_compiti      text[] check (riserva_compiti is null or cardinality(riserva_compiti) = 11),
  riserva_focus_corsia text check (riserva_focus_corsia is null or riserva_focus_corsia in ('SX','CEN','DX')),
  riserva_stile        text,
  riserva_linea        text check (riserva_linea is null or riserva_linea in ('alta','bassa')),
  riserva_ampiezza     text check (riserva_ampiezza is null or riserva_ampiezza in ('larga','stretta')),
  riserva_portiere     text check (riserva_portiere is null or riserva_portiere = 'libero'),
  aggiornato_il timestamptz not null default now(),
  check ((riserva_nome is null) = (riserva_modulo is null) and (riserva_modulo is null) = (riserva_disposizione is null))
);

comment on table public.schemi_squadra is
  'Schema attivo (solo il nome) e schema riserva (completo) di una squadra: la riserva accumula familiarita'' del modulo a ogni partita. Visibile solo al proprietario.';

alter table public.schemi_squadra enable row level security;

create policy schemi_squadra_propri on public.schemi_squadra
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = schemi_squadra.team_id and t.user_id = (select auth.uid())
  ));

revoke all on public.schemi_squadra from anon, authenticated;
grant select on public.schemi_squadra to authenticated;


-- ------------------------------------------------------------
--  Salva i nomi e lo schema riserva. p_modulo null = nessuna riserva
--  (elimina quella che c'era). Stessi controlli di salva_formazione e dei
--  moduli personalizzati: da qui non esce niente che la formazione rifiuterebbe.
-- ------------------------------------------------------------
create or replace function public.salva_schemi(
  p_league_id    bigint,
  p_nome_attivo  text,
  p_riserva_nome text default null,
  p_modulo       text default null,
  p_disposizione text[] default null,
  p_ruoli        text[] default null,
  p_compiti      text[] default null,
  p_focus_corsia text default null,
  p_stile        text default null,
  p_linea        text default null,
  p_ampiezza     text default null,
  p_portiere     text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team_id bigint;
  v_std     text[];
  v_attive  boolean;
  v_nome_a  text := btrim(coalesce(p_nome_attivo, ''));
  v_nome_r  text := btrim(coalesce(p_riserva_nome, ''));
  v_i       integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per salvare gli schemi.';
  end if;

  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  select coalesce(l.tattiche_attive, false) into v_attive from public.leagues l where l.id = p_league_id;
  if not v_attive then
    raise exception using errcode = '55000', message = 'Gli schemi a due slot non sono ancora attivi in questa lega.';
  end if;

  if char_length(v_nome_a) not between 1 and 24 then
    raise exception using errcode = '22023', message = 'Il nome dello schema deve avere da 1 a 24 caratteri.';
  end if;

  if p_modulo is null then
    insert into public.schemi_squadra (team_id, league_id, nome_attivo)
    values (v_team_id, p_league_id, v_nome_a)
    on conflict (team_id) do update set
      nome_attivo = excluded.nome_attivo,
      riserva_nome = null, riserva_modulo = null, riserva_disposizione = null, riserva_ruoli = null,
      riserva_compiti = null, riserva_focus_corsia = null, riserva_stile = null, riserva_linea = null,
      riserva_ampiezza = null, riserva_portiere = null, aggiornato_il = now();
    return;
  end if;

  if char_length(v_nome_r) not between 1 and 24 then
    raise exception using errcode = '22023', message = 'Il nome dello schema riserva deve avere da 1 a 24 caratteri.';
  end if;
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
  if p_stile is not null and not (p_stile = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  if p_linea is not null and p_linea not in ('alta','bassa') then
    raise exception using errcode = '22023', message = 'Linea difensiva non valida.';
  end if;
  if p_ampiezza is not null and p_ampiezza not in ('larga','stretta') then
    raise exception using errcode = '22023', message = 'Ampiezza non valida.';
  end if;
  if p_portiere is not null and p_portiere <> 'libero' then
    raise exception using errcode = '22023', message = 'Ruolo del portiere non valido.';
  end if;

  insert into public.schemi_squadra (
    team_id, league_id, nome_attivo, riserva_nome, riserva_modulo, riserva_disposizione, riserva_ruoli,
    riserva_compiti, riserva_focus_corsia, riserva_stile, riserva_linea, riserva_ampiezza, riserva_portiere)
  values (
    v_team_id, p_league_id, v_nome_a, v_nome_r, p_modulo, p_disposizione, p_ruoli,
    p_compiti, p_focus_corsia, p_stile, p_linea, p_ampiezza, p_portiere)
  on conflict (team_id) do update set
    nome_attivo = excluded.nome_attivo, riserva_nome = excluded.riserva_nome, riserva_modulo = excluded.riserva_modulo,
    riserva_disposizione = excluded.riserva_disposizione, riserva_ruoli = excluded.riserva_ruoli,
    riserva_compiti = excluded.riserva_compiti, riserva_focus_corsia = excluded.riserva_focus_corsia,
    riserva_stile = excluded.riserva_stile, riserva_linea = excluded.riserva_linea,
    riserva_ampiezza = excluded.riserva_ampiezza, riserva_portiere = excluded.riserva_portiere,
    aggiornato_il = now();
end;
$$;

revoke all on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text) from public, anon;
grant execute on function public.salva_schemi(bigint, text, text, text, text[], text[], text[], text, text, text, text, text) to authenticated;


-- ------------------------------------------------------------
--  A ogni partita simulata: la riserva guadagna una partita se il suo
--  schieramento non e' quello appena giocato (stessa logica di prima, letta
--  dalla nuova tabella).
-- ------------------------------------------------------------
create or replace function private.avanza_secondario(
  p_team_id bigint, p_league_id bigint, p_modulo_giocato text, p_disp_giocata text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_modulo text;
  v_disp   text[];
begin
  select s.riserva_modulo, s.riserva_disposizione into v_modulo, v_disp
  from public.schemi_squadra s where s.team_id = p_team_id;
  if v_modulo is null then
    return;
  end if;
  -- Solo con le tattiche accese (se il flag si spegne, si ferma).
  if not coalesce((select l.tattiche_attive from public.leagues l where l.id = p_league_id), false) then
    return;
  end if;
  -- Lo schieramento giocato avanza gia' da solo: niente doppio conteggio.
  if v_modulo = p_modulo_giocato and v_disp = p_disp_giocata then
    return;
  end if;

  perform private.assicura_riga_xp(p_team_id, p_league_id, v_modulo, v_disp);
  update public.formation_xp
  set partite_giocate = partite_giocate + 1, aggiornata_il = now()
  where team_id = p_team_id and modulo = v_modulo and disposizione = v_disp;
end;
$$;

commit;
