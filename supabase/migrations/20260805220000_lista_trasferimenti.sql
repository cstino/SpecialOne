-- ============================================================
--  LISTA TRASFERIMENTI — "Mercato della lega"
--
--  Richiesta dell'utente, 5 agosto 2026: dalla scheda giocatore si può
--  mettere un proprio giocatore in lista, e nella pagina Mercato compare
--  una vetrina con tutti quelli messi in lista dalle squadre della lega.
--
--  È una vetrina, non un canale di trattativa nuovo: chi vede un giocatore
--  interessante usa proponi_scambio, che esiste già. Serve a dire "questo
--  lo cedo" senza doverlo scrivere in chat.
--
--  Nessuna policy nuova: player_instances_lettura permette già a ogni
--  membro della lega di leggere tutte le rose (è così che funziona la
--  pagina Squadra sugli avversari). Basta filtrare sul flag.
-- ============================================================

alter table public.player_instances
  add column sul_mercato boolean not null default false;

comment on column public.player_instances.sul_mercato is
  'Messo in lista trasferimenti dal proprietario: visibile a tutta la lega nella vetrina "Mercato della lega".';

-- Indice parziale: la vetrina cerca sempre e solo i pochi in lista, non ha
-- senso indicizzare anche tutti gli altri.
create index player_instances_sul_mercato_idx
  on public.player_instances (league_id)
  where sul_mercato;

-- ------------------------------------------------------------
--  Il flag non sopravvive a un cambio di squadra: un giocatore appena
--  acquistato (o svincolato) non deve risultare già in vetrina per il nuovo
--  proprietario, che quella scelta non l'ha mai fatta.
-- ------------------------------------------------------------

create or replace function private.azzera_lista_al_trasferimento()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.team_id is distinct from old.team_id then
    new.sul_mercato := false;
  end if;
  return new;
end;
$$;

create trigger player_instances_azzera_lista
  before update on public.player_instances
  for each row
  when (old.team_id is distinct from new.team_id)
  execute function private.azzera_lista_al_trasferimento();

-- ------------------------------------------------------------
--  Mettere / togliere dalla lista. Solo il proprietario.
-- ------------------------------------------------------------

create or replace function public.imposta_sul_mercato(
  p_instance_id bigint,
  p_valore boolean
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di gestire la lista trasferimenti.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  if not exists (
    select 1 from public.teams
    where id = v_inst.team_id and league_id = v_inst.league_id
      and user_id = v_user_id and attiva
  ) then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  if v_inst.ritirato then
    raise exception using errcode = '55000', message = 'Un giocatore ritirato non puo'' essere messo in lista.';
  end if;

  update public.player_instances set sul_mercato = p_valore where id = v_inst.id;

  return jsonb_build_object('player_instance_id', v_inst.id, 'sul_mercato', p_valore);
end;
$$;

revoke all on function public.imposta_sul_mercato(bigint, boolean) from public, anon;
grant execute on function public.imposta_sul_mercato(bigint, boolean) to authenticated;

comment on function public.imposta_sul_mercato(bigint, boolean) is
  'Mette o toglie un proprio giocatore dalla lista trasferimenti visibile a tutta la lega.';
