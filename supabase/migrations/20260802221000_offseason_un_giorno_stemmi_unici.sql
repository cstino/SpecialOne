-- Off-season: durata reale 1 giorno e stemmi non duplicabili nella stessa lega.

create or replace function private.forza_offseason_un_giorno()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.scade_il := ((now() at time zone 'Europe/Rome') + interval '1 day') at time zone 'Europe/Rome';
  return new;
end;
$$;

drop trigger if exists offseasons_durata_un_giorno on public.offseasons;
create trigger offseasons_durata_un_giorno
  before insert on public.offseasons
  for each row execute function private.forza_offseason_un_giorno();

revoke all on function private.forza_offseason_un_giorno() from public, anon, authenticated;

update public.offseasons
set scade_il = least(scade_il, ((now() at time zone 'Europe/Rome') + interval '1 day') at time zone 'Europe/Rome')
where stato = 'aperta';

update public.leagues l
set offseason_fine = o.scade_il
from public.offseasons o
where o.league_id = l.id
  and o.stato = 'aperta'
  and l.fase_carriera = 'offseason';

create or replace function private.stemma_libero_in_lega(
  p_league_id bigint,
  p_stemma_url text,
  p_team_id bigint default null
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select 1
    from public.teams t
    where t.league_id = p_league_id
      and t.attiva
      and t.stemma_url = p_stemma_url
      and (p_team_id is null or t.id <> p_team_id)
  );
$$;

revoke all on function private.stemma_libero_in_lega(bigint, text, bigint) from public, anon, authenticated;
grant execute on function private.stemma_libero_in_lega(bigint, text, bigint) to service_role;

create or replace function public.anteprima_invito(p_codice text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_partecipanti integer;
  v_stemmi text[];
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;

  p_codice := upper(trim(p_codice));
  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;

  select * into v_league
  from public.leagues
  where codice_invito = p_codice;

  if not found then
    raise exception using errcode = 'P0002', message = 'Codice invito non trovato.';
  end if;
  if not (v_league.stato = 'setup' or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (
    select 1 from public.teams
    where league_id = v_league.id and user_id = v_user_id
  ) then
    raise exception using errcode = '23505', message = 'Hai gia'' una squadra in questa lega.';
  end if;

  select count(*)::integer, coalesce(array_agg(stemma_url order by id), array[]::text[])
  into v_partecipanti, v_stemmi
  from public.teams
  where league_id = v_league.id and attiva;

  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha gia'' raggiunto il numero massimo di squadre.';
  end if;

  return jsonb_build_object(
    'league_id', v_league.id,
    'nome_lega', v_league.nome,
    'fase_carriera', v_league.fase_carriera,
    'posti_disponibili', v_league.n_squadre - v_partecipanti,
    'stemmi_usati', v_stemmi
  );
end;
$$;

revoke all on function public.anteprima_invito(text) from public, anon, authenticated;
grant execute on function public.anteprima_invito(text) to authenticated;

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
  v_ordine integer;
  v_offseason public.offseasons;
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
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non e'' valido.';
  end if;

  select * into v_league from public.leagues where codice_invito = p_codice for update;
  if not found then raise exception using errcode = 'P0002', message = 'Codice invito non trovato.'; end if;
  if not (v_league.stato = 'setup' or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (select 1 from public.teams where league_id = v_league.id and user_id = v_user_id) then
    raise exception using errcode = '23505', message = 'Hai gia'' una squadra in questa lega.';
  end if;
  if not private.stemma_libero_in_lega(v_league.id, p_stemma_url, null) then
    raise exception using errcode = '23505', message = 'Questo stemma e'' gia'' usato nella lega.';
  end if;

  select count(*) into v_partecipanti from public.teams where league_id = v_league.id and attiva;
  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha gia'' raggiunto il numero massimo di squadre.';
  end if;
  select coalesce(max(ordine_draft), -1) + 1 into v_ordine
  from public.teams where league_id = v_league.id;

  begin
    insert into public.teams(
      league_id, user_id, nome, stemma_url, budget, reroll_rimasti,
      ordine_draft, attiva, entrata_stagione
    ) values (
      v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
      v_league.budget_iniziale, v_league.reroll_draft, v_ordine, true,
      case when v_league.fase_carriera = 'offseason' then v_league.stagione_corrente + 1 else 1 end
    ) returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
          case when v_league.fase_carriera = 'offseason'
            then 'Dotazione squadra entrante stagione ' || (v_league.stagione_corrente + 1)
            else 'Dotazione iniziale della lega' end,
          v_league.budget_iniziale);

  if v_league.fase_carriera = 'offseason' then
    select * into v_offseason from public.offseasons
    where league_id = v_league.id and stato = 'aperta' order by stagione_a desc limit 1;
    if not found or now() >= v_offseason.scade_il then
      raise exception using errcode = '55000', message = 'La finestra d''ingresso e'' terminata.';
    end if;
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
    insert into public.draft_state(league_id, pick_numero, stato)
    values (v_league.id,
      coalesce((select max(dp.pick_numero) + 1 from public.draft_picks dp where dp.league_id = v_league.id), 0),
      'in_corso')
    on conflict (league_id) do update set stato = 'in_corso', aggiornato_il = now();
    perform private.notifica(v_league.admin_id, v_league.id, 'sistema', 'Nuova squadra iscritta',
      v_team.nome || ' e'' entrata e puo'' iniziare il draft.', jsonb_build_object('team_id', v_team.id));
  end if;

  return jsonb_build_object('league_id', v_league.id, 'team_id', v_team.id,
    'codice_invito', v_league.codice_invito, 'offseason', v_league.fase_carriera = 'offseason');
end;
$$;

revoke all on function public.entra_in_lega(text, text, text) from public, anon, authenticated;
grant execute on function public.entra_in_lega(text, text, text) to authenticated;

create or replace function public.aggiorna_profilo_squadra(
  p_team_id bigint,
  p_nome text,
  p_stemma_url text
)
returns public.teams
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
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

  begin
    update public.teams
    set nome = p_nome,
        stemma_url = p_stemma_url
    where id = p_team_id
    returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  return v_team;
end;
$$;

revoke all on function public.aggiorna_profilo_squadra(bigint, text, text) from public, anon, authenticated;
grant execute on function public.aggiorna_profilo_squadra(bigint, text, text) to authenticated;
