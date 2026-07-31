-- ============================================================
--  ONBOARDING LEGA  (design §3.1 e §3.2)
--
--  Le scritture passano da RPC SECURITY DEFINER: il browser non riceve
--  privilegi diretti su leagues, teams o transactions.
-- ============================================================

create unique index teams_nome_case_insensitive_unique_idx
  on public.teams (league_id, lower(nome));

create or replace function private.stemma_valido(
  p_stemma_url text,
  p_user_id uuid
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_stemma_url = any (array[
      'preset:scudo',
      'preset:diagonale',
      'preset:torre',
      'preset:stella',
      'preset:quartieri',
      'preset:corona'
    ]::text[])
    or p_stemma_url ~ (
      '^' || p_user_id::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$'
    );
$$;

create or replace function private.genera_codice_invito()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_codice text := '';
  i integer;
begin
  v_bytes := extensions.gen_random_bytes(6);
  for i in 0..5 loop
    v_codice := v_codice || substr(
      v_alfabeto,
      (get_byte(v_bytes, i) % length(v_alfabeto)) + 1,
      1
    );
  end loop;
  return v_codice;
end;
$$;

create or replace function public.crea_lega(
  p_nome_lega text,
  p_nome_squadra text,
  p_stemma_url text,
  p_n_squadre smallint,
  p_n_gironi smallint,
  p_budget_iniziale bigint,
  p_reroll_draft smallint,
  p_slot_rosa smallint,
  p_portieri_minimi smallint,
  p_campionati_attivi text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa not between 20 and 30
    or p_portieri_minimi not between 2 and 4 then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if p_portieri_minimi > p_slot_rosa then
    raise exception using errcode = '22023', message = 'I portieri minimi superano gli slot rosa.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_reroll_draft, p_slot_rosa, p_portieri_minimi,
        p_campionati_attivi
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, budget, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
    v_league.budget_iniziale, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

create or replace function public.entra_in_lega(
  p_codice text,
  p_nome_squadra text,
  p_stemma_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_partecipanti integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;

  p_codice := upper(trim(p_codice));
  p_nome_squadra := trim(p_nome_squadra);

  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  select * into v_league
  from public.leagues
  where codice_invito = p_codice
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Codice invito non trovato.';
  end if;
  if v_league.stato <> 'setup' then
    raise exception using errcode = '55000', message = 'Questa lega non accetta più partecipanti.';
  end if;
  if exists (
    select 1 from public.teams
    where league_id = v_league.id and user_id = v_user_id
  ) then
    raise exception using errcode = '23505', message = 'Hai già una squadra in questa lega.';
  end if;

  select count(*) into v_partecipanti
  from public.teams
  where league_id = v_league.id;

  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha già raggiunto il numero massimo di squadre.';
  end if;

  begin
    insert into public.teams (
      league_id, user_id, nome, stemma_url, budget, reroll_rimasti
    ) values (
      v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
      v_league.budget_iniziale, v_league.reroll_draft
    ) returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra è già usato nella lega.';
  end;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

revoke all on function private.stemma_valido(text, uuid) from public, anon, authenticated;
revoke all on function private.genera_codice_invito() from public, anon, authenticated;
grant execute on function private.stemma_valido(text, uuid) to service_role;
grant execute on function private.genera_codice_invito() to service_role;

revoke all on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) from public, anon;
revoke all on function public.entra_in_lega(text, text, text) from public, anon;
grant execute on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) to authenticated;
grant execute on function public.entra_in_lega(text, text, text) to authenticated;

-- ------------------------------------------------------------
--  Stemmi squadra
-- ------------------------------------------------------------

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'team-crests', 'team-crests', false, 524288, array['image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy team_crests_upload_proprio
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'team-crests'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and lower(storage.extension(name)) = 'webp'
);

create policy team_crests_lettura
on storage.objects
for select
to authenticated
using (
  bucket_id = 'team-crests'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.teams t
      where t.stemma_url = name
        and (select private.e_membro(t.league_id))
    )
  )
);

create policy team_crests_elimina_proprio
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'team-crests'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

comment on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) is
  'Crea lega e squadra admin in un''unica transazione; design §3.1 e §3.2.';
comment on function public.entra_in_lega(text, text, text) is
  'Ingresso serializzato tramite codice invito; impedisce overbooking e bypass RLS.';
