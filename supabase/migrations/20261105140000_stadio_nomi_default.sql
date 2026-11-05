-- Stadio (Season 3, diario §4), seconda parte:
-- * nome dello stadio fino a 25 caratteri (era 20);
-- * mai vuoto: ogni squadra riceve un nome di default diverso dalle altre della sua lega, anche quelle nuove (trigger);
-- * il nome si cambia (Club > Modifica squadra) solo a stagione in corso con lo stadio acceso, cioe' dalla Season 3.

create or replace function private.nomi_stadio_default()
returns text[]
language sql
immutable
set search_path to ''
as $$
  select array[
    'Stadio Comunale', 'Arena Civica', 'Stadio dei Pini', 'Campo dei Tigli', 'Stadio del Porto',
    'Arena del Lago', 'Stadio delle Querce', 'Campo Sportivo', 'Stadio della Valle', 'Arena dei Colli',
    'Stadio del Mare', 'Stadio dei Cipressi', 'Arena del Fiume', 'Stadio del Litorale', 'Stadio dei Mulini',
    'Arena del Borgo', 'Stadio delle Mura', 'Campo degli Ulivi', 'Stadio del Faro', 'Arena dei Castagni',
    'Stadio della Rocca', 'Arena dei Gelsi', 'Stadio del Belvedere', 'Campo delle Rondini', 'Stadio dei Platani',
    'Arena della Pineta', 'Stadio del Ponte', 'Campo dei Girasoli', 'Stadio della Collina', 'Arena del Castello'
  ]::text[]
$$;
revoke all on function private.nomi_stadio_default() from public, anon, authenticated;

-- Il primo nome della lista non ancora usato nella lega (se sono finiti, si riparte dall'inizio).
create or replace function private.nome_stadio_libero(p_league_id bigint, p_escludi_team bigint default null)
returns text
language sql
stable
set search_path to ''
as $$
  select coalesce(
    (select n from unnest(private.nomi_stadio_default()) with ordinality as x(n, i)
      where not exists (select 1 from public.teams t
                        where t.league_id = p_league_id and t.nome_stadio = x.n
                          and (p_escludi_team is null or t.id <> p_escludi_team))
      order by i limit 1),
    (private.nomi_stadio_default())[1])
$$;
revoke all on function private.nome_stadio_libero(bigint, bigint) from public, anon, authenticated;

alter table public.teams drop constraint if exists teams_nome_stadio_lunghezza;

-- Nomi diversi dentro ogni lega, in ordine di id.
update public.teams t
set nome_stadio = (private.nomi_stadio_default())[((x.rn - 1) % cardinality(private.nomi_stadio_default())) + 1]
from (select id, row_number() over (partition by league_id order by id) as rn from public.teams) x
where x.id = t.id and t.nome_stadio is null;

create or replace function private.teams_nome_stadio_default()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.nome_stadio is null or trim(new.nome_stadio) = '' then
    new.nome_stadio := private.nome_stadio_libero(new.league_id);
  end if;
  return new;
end;
$$;
create trigger teams_nome_stadio before insert on public.teams
  for each row execute function private.teams_nome_stadio_default();

alter table public.teams alter column nome_stadio set not null;
alter table public.teams add constraint teams_nome_stadio_lunghezza
  check (char_length(nome_stadio) between 1 and 25);

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
        nome_stadio = v_nome_stadio
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
