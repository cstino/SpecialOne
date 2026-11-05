-- Battesimo dello stadio (richiesta del committente, 5/11/2026): al primo ingresso nella lega dopo l'arrivo dello
-- stadio, ogni allenatore sceglie il nome del suo stadio (puo' anche confermare quello di default). Vale anche in
-- off-season, a differenza del cambio da Club > Modifica squadra che resta solo a stagione in corso.
-- teams.nome_stadio_scelto: false finche' l'allenatore non ha confermato un nome.

alter table public.teams add column if not exists nome_stadio_scelto boolean not null default false;

create or replace function public.battezza_stadio(p_team_id bigint, p_nome text)
returns public.teams
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere per dare il nome allo stadio.';
  end if;

  select * into v_team from public.teams where id = p_team_id and user_id = v_user_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Puoi dare il nome soltanto al tuo stadio.';
  end if;
  if v_team.nome_stadio_scelto then
    raise exception using errcode = '22023', message = 'Il tuo stadio ha gia'' un nome: lo cambi da Club > Modifica squadra a stagione in corso.';
  end if;
  if not exists (select 1 from public.leagues l where l.id = v_team.league_id and l.stadio_attivo) then
    raise exception using errcode = '22023', message = 'In questa lega lo stadio non c''e'' ancora.';
  end if;

  p_nome := regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  if char_length(p_nome) < 3 then
    raise exception using errcode = '22023', message = 'Il nome dello stadio deve avere almeno 3 caratteri.';
  end if;
  if char_length(p_nome) > 25 then
    raise exception using errcode = '22023', message = 'Il nome dello stadio può avere al massimo 25 caratteri.';
  end if;

  update public.teams set nome_stadio = p_nome, nome_stadio_scelto = true
  where id = p_team_id
  returning * into v_team;
  return v_team;
end;
$function$;
revoke all on function public.battezza_stadio(bigint, text) from public, anon;
grant execute on function public.battezza_stadio(bigint, text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.aggiorna_profilo_squadra(p_team_id bigint, p_nome text, p_stemma_url text, p_sigla text DEFAULT NULL::text, p_nome_stadio text DEFAULT NULL::text)
 RETURNS teams
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_vincolo text;
  v_nome_stadio text;
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

  -- Nome dello stadio: null o vuoto = nessun cambio. Si cambia solo a stagione in corso con lo stadio acceso.
  v_nome_stadio := coalesce(nullif(trim(p_nome_stadio), ''), v_team.nome_stadio);
  if v_nome_stadio is distinct from v_team.nome_stadio then
    if not exists (select 1 from public.leagues l where l.id = v_team.league_id and l.stadio_attivo
                   and l.stato = 'stagione' and l.fase_carriera <> 'offseason') then
      raise exception using errcode = '22023', message = 'Il nome dello stadio si potrà cambiare quando inizia la nuova stagione.';
    end if;
    if char_length(v_nome_stadio) > 25 then
      raise exception using errcode = '22023', message = 'Il nome dello stadio può avere al massimo 25 caratteri.';
    end if;
  end if;

  begin
    update public.teams
    set nome = p_nome,
        stemma_url = p_stemma_url,
        sigla = coalesce(p_sigla, sigla),
        sigla_personalizzata = sigla_personalizzata or p_sigla is not null,
        nome_stadio = v_nome_stadio,
        nome_stadio_scelto = nome_stadio_scelto or v_nome_stadio is distinct from v_team.nome_stadio
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
$function$;
