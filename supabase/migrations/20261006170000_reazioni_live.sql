-- Reazioni in diretta (draft ON/OFF-Season e sorteggio delle conference): chi guarda manda un messaggio
-- prefatto con emoji, che compare a tutti gli spettatori della stessa lega. Un messaggio ogni 5 secondi
-- per persona, controllato qui nel database (non solo nell'app). I messaggi sono un elenco fisso: nessun
-- testo libero. Le righe servono solo a far arrivare l'evento in tempo reale e si ripuliscono da sole.

create table if not exists public.reazioni_live (
  id        bigserial primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id   bigint not null,
  user_id   uuid   not null,
  contesto  text   not null check (contesto in ('draft', 'sorteggio', 'on')),
  codice    text   not null,
  creata_il timestamptz not null default clock_timestamp()
);
create index if not exists reazioni_live_lega_idx on public.reazioni_live (league_id, id desc);
create index if not exists reazioni_live_utente_idx on public.reazioni_live (user_id, creata_il desc);

alter table public.reazioni_live enable row level security;
drop policy if exists reazioni_live_membri on public.reazioni_live;
create policy reazioni_live_membri on public.reazioni_live for select to authenticated
  using ((select private.e_membro(league_id)));
revoke all on public.reazioni_live from public, anon;
grant select on public.reazioni_live to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reazioni_live') then
    alter publication supabase_realtime add table public.reazioni_live;
  end if;
end $$;

-- I codici validi stanno qui e in src/lib/reazioni.ts (da tenere allineati a mano).
create or replace function public.invia_reazione(p_league_id bigint, p_contesto text, p_codice text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_team bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per mandare una reazione.';
  end if;
  select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = v_user and t.attiva;
  if v_team is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;
  if p_contesto not in ('draft', 'sorteggio', 'on') then
    raise exception using errcode = '22023', message = 'Contesto non valido.';
  end if;
  if p_codice not in ('fuoco', 'wow', 'applauso', 'ridere', 'esplode', 'teschio', 'preghiera', 'festa', 'ahia', 'capra', 'perfetto', 'nooo') then
    raise exception using errcode = '22023', message = 'Reazione non valida.';
  end if;
  -- Cinque secondi fra una reazione e l'altra (qualche decimo di tolleranza per il ritardo di rete).
  if exists (
    select 1 from public.reazioni_live r
    where r.user_id = v_user and r.creata_il > clock_timestamp() - interval '4.6 seconds'
  ) then
    raise exception using errcode = '54000', message = 'Aspetta qualche secondo prima della prossima reazione.';
  end if;
  insert into public.reazioni_live (league_id, team_id, user_id, contesto, codice)
  values (p_league_id, v_team, v_user, p_contesto, p_codice);
  -- Pulizia: tolgo le vecchie ogni tanto (le reazioni contano solo mentre si guarda).
  if random() < 0.05 then
    delete from public.reazioni_live where creata_il < clock_timestamp() - interval '1 hour';
  end if;
end;
$$;
revoke all on function public.invia_reazione(bigint, text, text) from public, anon;
grant execute on function public.invia_reazione(bigint, text, text) to authenticated;
