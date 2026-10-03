-- ============================================================
--  MODULO SECONDARIO (season 2, 3 ottobre 2026)
--
--  Richiesta del committente: una squadra puo' preparare un secondo modulo.
--  A ogni partita simulata il secondario guadagna una partita di familiarita'
--  (la barra DISPOSIZIONE di formation_xp) anche se non e' stato schierato;
--  dopo FAM_PARTITE_PIENA (5) partite e' conosciuto come il principale. Si puo'
--  scambiare col principale senza perdere nulla (il contatore di ogni modulo
--  non cala mai), oppure eliminarlo e prepararne un altro. Un solo secondario.
--
--  Cosa NON fa: non tocca la barra INDICAZIONI (stile, ruoli, compiti, linea,
--  ampiezza, portiere): il secondario prepara il modulo, non le istruzioni.
--  Solo nelle leghe con tattiche_attive (il flag della season 2).
--
--  Si salva insieme alla formazione (il frontend chiama imposta_modulo_secondario
--  dopo salva_formazione). Visibile solo al proprietario della squadra: e' una
--  tattica (CLAUDE.md §6).
-- ============================================================
begin;

create table public.modulo_secondario (
  team_id      bigint primary key references public.teams(id) on delete cascade,
  league_id    bigint not null references public.leagues(id) on delete cascade,
  modulo       text not null,
  -- Sempre gli undici slot risolti (quelli standard se nessuno e' spostato): e'
  -- la stessa chiave di formation_xp (team, modulo, disposizione).
  disposizione text[] not null check (cardinality(disposizione) = 11),
  impostato_il timestamptz not null default now()
);

comment on table public.modulo_secondario is
  'Il modulo che la squadra sta preparando: accumula familiarita'' a ogni partita anche se non lo schiera. Uno per squadra, visibile solo al proprietario.';

alter table public.modulo_secondario enable row level security;

create policy modulo_secondario_proprio on public.modulo_secondario
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = modulo_secondario.team_id and t.user_id = (select auth.uid())
  ));

revoke all on public.modulo_secondario from anon, authenticated;
grant select on public.modulo_secondario to authenticated;


-- ------------------------------------------------------------
--  Imposta (o elimina, con p_modulo null) il modulo secondario
-- ------------------------------------------------------------
create or replace function public.imposta_modulo_secondario(
  p_league_id    bigint,
  p_modulo       text default null,
  p_disposizione text[] default null
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
  v_i       integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per preparare un modulo.';
  end if;

  select t.id into v_team_id
  from public.teams t
  where t.league_id = p_league_id and t.user_id = v_user_id;
  if v_team_id is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  select coalesce(l.tattiche_attive, false) into v_attive from public.leagues l where l.id = p_league_id;
  if not v_attive then
    raise exception using errcode = '55000', message = 'Il modulo secondario non e'' ancora attivo in questa lega.';
  end if;

  if p_modulo is null then
    delete from public.modulo_secondario where team_id = v_team_id;
    return;
  end if;

  -- Stessi controlli di salva_formazione e dei moduli personalizzati.
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

  insert into public.modulo_secondario (team_id, league_id, modulo, disposizione)
  values (v_team_id, p_league_id, p_modulo, p_disposizione)
  on conflict (team_id) do update
    set modulo = excluded.modulo, disposizione = excluded.disposizione, impostato_il = now();
end;
$$;

revoke all on function public.imposta_modulo_secondario(bigint, text, text[]) from public, anon;
grant execute on function public.imposta_modulo_secondario(bigint, text, text[]) to authenticated;


-- ------------------------------------------------------------
--  Una riga di formation_xp per (squadra, modulo, schieramento): se non c'e',
--  si crea con la quota ereditata dallo schieramento piu' simile. Stessa regola
--  di private.avanza_familiarita (che la tiene inline).
-- ------------------------------------------------------------
create or replace function private.assicura_riga_xp(
  p_team_id bigint, p_league_id bigint, p_modulo text, p_disp text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_semina smallint;
begin
  if exists (
    select 1 from public.formation_xp
    where team_id = p_team_id and modulo = p_modulo and disposizione = p_disp
  ) then
    return;
  end if;
  select coalesce(max(round(
           least(1.0, fx.partite_giocate::numeric / private.fam_partite_piena())
           * private.resa_familiarita(1 - private.similarita_disposizione(fx.disposizione, p_disp))
           * private.fam_partite_piena()
         )), 0)
  into v_semina
  from public.formation_xp fx
  where fx.team_id = p_team_id;

  insert into public.formation_xp (team_id, league_id, modulo, disposizione, partite_giocate)
  values (p_team_id, p_league_id, p_modulo, p_disp, greatest(0, coalesce(v_semina, 0)))
  on conflict (team_id, modulo, disposizione) do nothing;
end;
$$;


-- ------------------------------------------------------------
--  A ogni partita simulata: il secondario guadagna una partita se non e' lo
--  schieramento appena giocato.
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
  v_sec public.modulo_secondario;
begin
  select * into v_sec from public.modulo_secondario where team_id = p_team_id;
  if not found then
    return;
  end if;
  -- Solo con le tattiche accese (se il flag si spegne, si ferma).
  if not coalesce((select l.tattiche_attive from public.leagues l where l.id = p_league_id), false) then
    return;
  end if;
  -- Lo schieramento giocato avanza gia' da solo: niente doppio conteggio.
  if v_sec.modulo = p_modulo_giocato and v_sec.disposizione = p_disp_giocata then
    return;
  end if;

  perform private.assicura_riga_xp(p_team_id, p_league_id, v_sec.modulo, v_sec.disposizione);
  update public.formation_xp
  set partite_giocate = partite_giocate + 1, aggiornata_il = now()
  where team_id = p_team_id and modulo = v_sec.modulo and disposizione = v_sec.disposizione;
end;
$$;

CREATE OR REPLACE FUNCTION private.avanza_familiarita(p_team_id bigint, p_league_id bigint, p_modulo text, p_stile text, p_giornata smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_disp      text[];
  v_ruoli     text[];
  v_compiti   text[];
  v_semina    smallint;
  v_prec      public.indicazioni_xp;
  v_distanza  numeric;
  v_diversi   integer;
  v_focus     text;
  v_linea     text;
  v_ampiezza  text;
  v_portiere  text;
begin
  select coalesce(l.disposizione, private.disposizione_standard(p_modulo)), l.ruoli, l.compiti, l.focus_corsia,
         l.linea_difensiva, l.ampiezza, l.ruolo_portiere
  into v_disp, v_ruoli, v_compiti, v_focus, v_linea, v_ampiezza, v_portiere
  from public.lineups l
  where l.team_id = p_team_id and l.giornata = p_giornata;

  if v_disp is null then
    v_disp := private.disposizione_standard(p_modulo);
  end if;
  if v_disp is null then
    return; -- modulo sconosciuto: non si inventa una barra
  end if;

  -- ----- barra DISPOSIZIONE -----
  -- Se questo schieramento non e' mai stato giocato, eredita dal piu' simile.
  if not exists (
    select 1 from public.formation_xp
    where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp
  ) then
    -- Si eredita dalla QUOTA, non dal conteggio grezzo. Il contatore cresce
    -- senza limite — una squadra puo' avere 21 partite col suo 4-4-2 — e
    -- moltiplicare quello per 0,71 darebbe ancora 15, cioe' una barra piena:
    -- l'eredita' non morderebbe mai per chi gioca da tempo lo stesso modulo,
    -- che e' esattamente chi dovrebbe sentirla.
    select coalesce(max(round(
             least(1.0, fx.partite_giocate::numeric / private.fam_partite_piena())
             * private.resa_familiarita(1 - private.similarita_disposizione(fx.disposizione, v_disp))
             * private.fam_partite_piena()
           )), 0)
    into v_semina
    from public.formation_xp fx
    where fx.team_id = p_team_id;

    insert into public.formation_xp (team_id, league_id, modulo, disposizione, partite_giocate)
    values (p_team_id, p_league_id, p_modulo, v_disp, greatest(0, coalesce(v_semina, 0)))
    on conflict (team_id, modulo, disposizione) do nothing;
  end if;

  update public.formation_xp
  set partite_giocate = partite_giocate + 1, aggiornata_il = now()
  where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp;

  -- Modulo secondario (season 2): anche lui accumula una partita, anche se non
  -- e' stato schierato. Prima delle indicazioni: la barra indicazioni ha un
  -- return anticipato alla prima riga e non deve saltarlo.
  perform private.avanza_secondario(p_team_id, p_league_id, p_modulo, v_disp);

  -- ----- barra INDICAZIONI -----
  select * into v_prec from public.indicazioni_xp where team_id = p_team_id;

  if not found then
    -- Prima riga per questa squadra. NON parte da zero: la barra indicazioni
    -- assorbe quello che prima era la familiarita' con lo STILE, e azzerarla
    -- qui vorrebbe dire che alla prima giornata dopo questa migrazione ogni
    -- squadra della lega perde meta' della sua familiarita' senza aver
    -- cambiato niente.
    insert into public.indicazioni_xp (team_id, league_id, partite_giocate, stile, ruoli, compiti, focus_corsia, linea_difensiva, ampiezza, ruolo_portiere)
    values (
      p_team_id, p_league_id,
      least(private.fam_partite_piena(),
            coalesce((select sx.partite_giocate from public.stile_xp sx
                      where sx.team_id = p_team_id and sx.stile = p_stile), 0))::smallint + 1,
      p_stile, v_ruoli, v_compiti, v_focus, v_linea, v_ampiezza, v_portiere);
    return;
  end if;

  -- Distanza su 23 elementi: lo stile, gli undici ruoli, gli undici compiti.
  -- Un elemento assente da entrambe le parti non e' un cambiamento.
  v_diversi := (case when coalesce(v_prec.stile, '') <> coalesce(p_stile, '') then 1 else 0 end)
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.ruoli[i], '') <> coalesce(v_ruoli[i], ''))
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.compiti[i], '') <> coalesce(v_compiti[i], ''))
    -- Ventiquattresimo elemento: dove si attacca. E' un'indicazione come le
    -- altre, quindi cambiarla costa familiarita' come cambiare un compito.
    + (case when coalesce(v_prec.focus_corsia, '') <> coalesce(v_focus, '') then 1 else 0 end)
    -- Dal 29 settembre 2026 anche linea, ampiezza e portiere (registro,
    -- punto 30): ventisette elementi.
    + (case when coalesce(v_prec.linea_difensiva, '') <> coalesce(v_linea, '') then 1 else 0 end)
    + (case when coalesce(v_prec.ampiezza, '') <> coalesce(v_ampiezza, '') then 1 else 0 end)
    + (case when coalesce(v_prec.ruolo_portiere, '') <> coalesce(v_portiere, '') then 1 else 0 end);
  v_distanza := v_diversi::numeric / 27;

  -- Stessa cura dell'eredita': si arretra la quota, non il conteggio grezzo.
  update public.indicazioni_xp
  set partite_giocate = least(32767, greatest(0,
        round(least(1.0, partite_giocate::numeric / private.fam_partite_piena())
              * private.resa_familiarita(v_distanza)
              * private.fam_partite_piena())::smallint + 1)),
      stile = p_stile, ruoli = v_ruoli, compiti = v_compiti, focus_corsia = v_focus,
      linea_difensiva = v_linea, ampiezza = v_ampiezza, ruolo_portiere = v_portiere, aggiornata_il = now()
  where team_id = p_team_id;
end;
$function$
;

commit;
