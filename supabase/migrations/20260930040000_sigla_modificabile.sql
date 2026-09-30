-- ============================================================
--  SIGLA MODIFICABILE DAL PROPRIETARIO
--
--  Ogni utente puo' scegliere la sigla della propria squadra da "Modifica
--  squadra", purche' libera nella lega (vincolo teams_sigla_unica_per_lega).
--  Una sigla scelta a mano resta tale anche se poi la squadra cambia nome:
--  sigla_personalizzata impedisce al trigger di ricalcolarla.
-- ============================================================

alter table public.teams add column if not exists sigla_personalizzata boolean not null default false;

create or replace function private.imposta_sigla_squadra()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.sigla is null
     or (new.nome is distinct from old.nome
         and not new.sigla_personalizzata
         and new.sigla is not distinct from old.sigla) then
    new.sigla := private.genera_sigla(new.league_id, new.nome, new.id);
  end if;
  return new;
end;
$$;

drop function if exists public.aggiorna_profilo_squadra(bigint, text, text);

create or replace function public.aggiorna_profilo_squadra(p_team_id bigint, p_nome text, p_stemma_url text, p_sigla text default null)
returns public.teams
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_vincolo text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per modificare la squadra.';
  end if;

  select * into v_team
  from public.teams
  where id = p_team_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Puoi modificare soltanto la tua squadra.';
  end if;

  p_nome := trim(p_nome);
  if length(p_nome) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non e'' valido.';
  end if;
  if not private.stemma_libero_in_lega(v_team.league_id, p_stemma_url, p_team_id) then
    raise exception using errcode = '23505', message = 'Questo stemma e'' gia'' usato nella lega.';
  end if;

  -- Sigla: null o uguale all'attuale = nessun cambio.
  p_sigla := nullif(upper(trim(coalesce(p_sigla, ''))), '');
  if p_sigla is not null and p_sigla is distinct from v_team.sigla then
    if p_sigla !~ '^[A-Z0-9]{3}$' then
      raise exception using errcode = '22023', message = 'La sigla deve avere esattamente 3 caratteri tra lettere e cifre.';
    end if;
  else
    p_sigla := null;
  end if;

  begin
    update public.teams
    set nome = p_nome,
        stemma_url = p_stemma_url,
        sigla = coalesce(p_sigla, sigla),
        sigla_personalizzata = sigla_personalizzata or p_sigla is not null
    where id = p_team_id
    returning * into v_team;
  exception when unique_violation then
    get stacked diagnostics v_vincolo = constraint_name;
    if v_vincolo = 'teams_sigla_unica_per_lega' then
      raise exception using errcode = '23505', message = 'Questa sigla e'' gia'' usata da un''altra squadra della lega.';
    end if;
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  return v_team;
end;
$$;

revoke all on function public.aggiorna_profilo_squadra(bigint, text, text, text) from public, anon;
grant execute on function public.aggiorna_profilo_squadra(bigint, text, text, text) to authenticated;
