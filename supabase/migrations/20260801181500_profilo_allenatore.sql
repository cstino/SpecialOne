-- ============================================================
--  PROFILO ALLENATORE
--
--  Fino ad ora un partecipante era solo un `user_id` e un indirizzo email:
--  il nome dell'allenatore non esisteva da nessuna parte. Serve per mostrare
--  chi allena una squadra in classifica e nel profilo squadra.
--
--  Il profilo e' creato pigramente al primo salvataggio: nessun trigger su
--  `auth.users` e nessun backfill per gli utenti gia' registrati.
-- ============================================================

-- SECURITY DEFINER come gli altri helper: una policy su `profiles` che
-- interroga `teams` applicherebbe anche la RLS di `teams`. Vedi il commento
-- in 20260731120400_helper_rls.sql.
create or replace function private.condivide_lega(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teams altrui
    join public.teams mie
      on mie.league_id = altrui.league_id
    where altrui.user_id = p_user_id
      and mie.user_id = (select auth.uid())
  );
$$;

revoke all on function private.condivide_lega(uuid) from public, anon;
grant execute on function private.condivide_lega(uuid) to authenticated, service_role;

comment on function private.condivide_lega(uuid) is
  'Vero se l''utente indicato partecipa a una lega in comune con l''utente corrente.';

create table if not exists public.profiles (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  nome_allenatore text not null,
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now(),
  constraint profiles_nome_valido
    check (char_length(btrim(nome_allenatore)) between 2 and 30)
);

comment on table public.profiles is
  'Dati pubblici dell''allenatore, visibili a chi condivide una lega.';

alter table public.profiles enable row level security;

-- Il proprio profilo, piu' quello di chi gioca nelle stesse leghe. Nessun
-- accesso al profilo di un estraneo: non e' una rubrica globale.
create policy profiles_lettura on public.profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.condivide_lega(user_id))
  );

grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;
revoke all on table public.profiles from anon;

-- ============================================================
--  Scrittura validata: il browser non ha INSERT/UPDATE sulla tabella.
-- ============================================================

create or replace function public.aggiorna_nome_allenatore(p_nome text)
returns public.profiles
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_nome   text := btrim(coalesce(p_nome, ''));
  v_profilo public.profiles;
begin
  if v_utente is null then
    raise exception using
      errcode = '42501',
      message = 'Devi accedere per modificare il profilo.';
  end if;

  if char_length(v_nome) < 2 or char_length(v_nome) > 30 then
    raise exception using
      errcode = '22023',
      message = 'Il nome allenatore deve avere fra 2 e 30 caratteri.';
  end if;

  insert into public.profiles as p (user_id, nome_allenatore)
  values (v_utente, v_nome)
  on conflict (user_id) do update
    set nome_allenatore = excluded.nome_allenatore,
        aggiornato_il   = now()
  returning p.* into v_profilo;

  return v_profilo;
end;
$$;

revoke all on function public.aggiorna_nome_allenatore(text) from public, anon;
grant execute on function public.aggiorna_nome_allenatore(text) to authenticated;

comment on function public.aggiorna_nome_allenatore(text) is
  'Crea o aggiorna il nome dell''allenatore dell''utente corrente.';
