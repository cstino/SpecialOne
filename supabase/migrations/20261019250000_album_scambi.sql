-- ============================================================
--  SCAMBI DI FIGURINE (19/10/2026, deciso con il committente). Si scambiano solo i DOPPIONI (la copia attaccata
--  nell'album non si cede), normali o ultrarari; almeno una figurina per parte, niente crediti. La proposta vale 24 ore;
--  si accetta, si rifiuta, si ritira o si risponde con una controproposta. All'accettazione si ricontrolla che i doppioni
--  ci siano ancora. Le figurine ricevute possono completare una pagina (premio da 200 crediti). Solo dove l'album e' attivo.
-- ============================================================
begin;

create table public.album_scambi (
  id          bigint generated always as identity primary key,
  league_id   bigint not null references public.leagues(id) on delete cascade,
  da_user     uuid not null references auth.users(id) on delete cascade,
  a_user      uuid not null references auth.users(id) on delete cascade,
  da_team_id  bigint not null references public.teams(id) on delete cascade,
  a_team_id   bigint not null references public.teams(id) on delete cascade,
  offerte     jsonb not null,   -- [{"figurina_id": 1, "ultra": false}, ...]
  richieste   jsonb not null,
  stato       text not null default 'in_attesa' check (stato in ('in_attesa', 'accettato', 'rifiutato', 'ritirato', 'scaduto')),
  controproposta_di bigint references public.album_scambi(id) on delete set null,
  creato_il   timestamptz not null default now(),
  scade_il    timestamptz not null default now() + interval '24 hours',
  risolto_il  timestamptz
);
create index album_scambi_utenti_idx on public.album_scambi (league_id, a_user, stato);
alter table public.album_scambi enable row level security;
create policy album_scambi_miei on public.album_scambi for select to authenticated using ((select auth.uid()) in (da_user, a_user));
grant select on public.album_scambi to authenticated;
grant all on public.album_scambi to service_role;

-- I doppioni di una squadra della lega (le copie in piu', per versione): li vede chi gioca nella lega, per proporre scambi.
create or replace function public.album_doppioni(p_league_id bigint, p_team_id bigint)
returns table (figurina_id bigint, ultra boolean, copie integer)
language sql stable security definer set search_path = '' as $f$
  select ap.figurina_id, false, ap.normali - 1 from public.album_possesso ap
   join public.teams t on t.user_id = ap.user_id and t.league_id = p_league_id and t.id = p_team_id
   where ap.league_id = p_league_id and ap.normali > 1 and (select private.e_membro(p_league_id))
  union all
  select ap.figurina_id, true, ap.ultra - 1 from public.album_possesso ap
   join public.teams t on t.user_id = ap.user_id and t.league_id = p_league_id and t.id = p_team_id
   where ap.league_id = p_league_id and ap.ultra > 1 and (select private.e_membro(p_league_id))
$f$;

-- Controlla che un utente abbia i doppioni elencati (ogni voce = una copia in piu' di quella versione).
create or replace function private.album_ha_doppioni(p_league_id bigint, p_user uuid, p_voci jsonb)
returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce(bool_and(
    coalesce((select case when v.ultra then ap.ultra else ap.normali end from public.album_possesso ap
               where ap.user_id = p_user and ap.figurina_id = v.figurina_id and ap.league_id = p_league_id), 0) - 1 >= v.n), false)
  from (select (x->>'figurina_id')::bigint as figurina_id, coalesce((x->>'ultra')::boolean, false) as ultra, count(*) as n
          from jsonb_array_elements(p_voci) x group by 1, 2) v
$f$;

create or replace function private.album_sposta(p_league_id bigint, p_da uuid, p_a uuid, p_voci jsonb)
returns void language plpgsql security definer set search_path = '' as $f$
declare v record;
begin
  for v in select (x->>'figurina_id')::bigint as figurina_id, coalesce((x->>'ultra')::boolean, false) as ultra from jsonb_array_elements(p_voci) x loop
    update public.album_possesso set normali = normali - (case when v.ultra then 0 else 1 end), ultra = ultra - (case when v.ultra then 1 else 0 end)
     where user_id = p_da and figurina_id = v.figurina_id;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, ultra)
    values (p_league_id, p_a, v.figurina_id, case when v.ultra then 0 else 1 end, case when v.ultra then 1 else 0 end)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + case when v.ultra then 0 else 1 end,
      ultra = public.album_possesso.ultra + case when v.ultra then 1 else 0 end;
  end loop;
end $f$;

create or replace function public.album_proponi_scambio(p_league_id bigint, p_a_team_id bigint, p_offerte jsonb, p_richieste jsonb, p_controproposta_di bigint default null)
returns public.album_scambi language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_mia public.teams;
  v_dest public.teams;
  v_s public.album_scambi;
  v_orig public.album_scambi;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.album_attivo(p_league_id) then raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.'; end if;
  select * into v_mia from public.teams where league_id = p_league_id and user_id = v_utente and attiva;
  select * into v_dest from public.teams where id = p_a_team_id and league_id = p_league_id and attiva;
  if v_mia.id is null or v_dest.id is null or v_dest.user_id is null or v_dest.controllata_da_pc then
    raise exception using errcode = '22023', message = 'Squadra non valida per uno scambio di figurine.';
  end if;
  if v_mia.id = v_dest.id then raise exception using errcode = '22023', message = 'Non puoi scambiare con te stesso.'; end if;
  if jsonb_typeof(p_offerte) <> 'array' or jsonb_typeof(p_richieste) <> 'array' or jsonb_array_length(p_offerte) = 0 or jsonb_array_length(p_richieste) = 0 then
    raise exception using errcode = '22023', message = 'Serve almeno una figurina per parte: niente regali.';
  end if;
  if jsonb_array_length(p_offerte) > 15 or jsonb_array_length(p_richieste) > 15 then
    raise exception using errcode = '22023', message = 'Al massimo 15 figurine per parte.';
  end if;
  if not private.album_ha_doppioni(p_league_id, v_utente, p_offerte) then
    raise exception using errcode = '22023', message = 'Puoi offrire solo i tuoi doppioni.';
  end if;
  if not private.album_ha_doppioni(p_league_id, v_dest.user_id, p_richieste) then
    raise exception using errcode = '22023', message = 'Puoi chiedere solo i doppioni dell''altra squadra.';
  end if;
  if p_controproposta_di is not null then
    select * into v_orig from public.album_scambi where id = p_controproposta_di for update;
    if v_orig.id is null or v_orig.a_user <> v_utente or v_orig.stato <> 'in_attesa' then
      raise exception using errcode = '22023', message = 'Controproposta non valida.';
    end if;
    update public.album_scambi set stato = 'rifiutato', risolto_il = now() where id = v_orig.id;
  end if;
  insert into public.album_scambi (league_id, da_user, a_user, da_team_id, a_team_id, offerte, richieste, controproposta_di)
  values (p_league_id, v_utente, v_dest.user_id, v_mia.id, v_dest.id, p_offerte, p_richieste, p_controproposta_di)
  returning * into v_s;
  perform private.notifica(v_dest.user_id, p_league_id, 'sistema', 'Scambio di figurine',
    v_mia.nome || ' ti propone uno scambio di figurine: hai 24 ore per rispondere.', jsonb_build_object('view', 'album', 'album_scambio_id', v_s.id));
  return v_s;
end $f$;

create or replace function public.album_rispondi_scambio(p_id bigint, p_accetta boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_s public.album_scambi;
  v_stag smallint;
  v_nome text;
begin
  select * into v_s from public.album_scambi where id = p_id for update;
  if v_s.id is null or v_s.a_user <> v_utente then raise exception using errcode = '42501', message = 'Proposta non trovata.'; end if;
  if v_s.stato <> 'in_attesa' then raise exception using errcode = '55000', message = 'Questa proposta è già chiusa.'; end if;
  if now() >= v_s.scade_il then
    update public.album_scambi set stato = 'scaduto', risolto_il = now() where id = p_id;
    raise exception using errcode = '55000', message = 'La proposta è scaduta.';
  end if;
  select nome into v_nome from public.teams where id = v_s.a_team_id;
  if not coalesce(p_accetta, false) then
    update public.album_scambi set stato = 'rifiutato', risolto_il = now() where id = p_id;
    perform private.notifica(v_s.da_user, v_s.league_id, 'sistema', 'Scambio di figurine', v_nome || ' ha rifiutato il tuo scambio di figurine.', jsonb_build_object('view', 'album'));
    return jsonb_build_object('stato', 'rifiutato');
  end if;
  if not private.album_ha_doppioni(v_s.league_id, v_s.da_user, v_s.offerte) or not private.album_ha_doppioni(v_s.league_id, v_s.a_user, v_s.richieste) then
    raise exception using errcode = '55000', message = 'Uno dei doppioni non c''è più (forse è stato riciclato o scambiato): la proposta non è più valida.';
  end if;
  perform private.album_sposta(v_s.league_id, v_s.da_user, v_s.a_user, v_s.offerte);
  perform private.album_sposta(v_s.league_id, v_s.a_user, v_s.da_user, v_s.richieste);
  update public.album_scambi set stato = 'accettato', risolto_il = now() where id = p_id;
  select stagione_corrente into v_stag from public.leagues where id = v_s.league_id;
  perform private.album_controlla_premi(v_s.league_id, v_s.da_user, v_stag);
  perform private.album_controlla_premi(v_s.league_id, v_s.a_user, v_stag);
  perform private.notifica(v_s.da_user, v_s.league_id, 'sistema', 'Scambio di figurine', v_nome || ' ha accettato il tuo scambio di figurine!', jsonb_build_object('view', 'album'));
  return jsonb_build_object('stato', 'accettato');
end $f$;

create or replace function public.album_ritira_scambio(p_id bigint)
returns void language plpgsql security definer set search_path = '' as $f$
begin
  update public.album_scambi set stato = 'ritirato', risolto_il = now()
   where id = p_id and da_user = (select auth.uid()) and stato = 'in_attesa';
  if not found then raise exception using errcode = '55000', message = 'Proposta non trovata o già chiusa.'; end if;
end $f$;

revoke all on function public.album_doppioni(bigint, bigint), public.album_proponi_scambio(bigint, bigint, jsonb, jsonb, bigint),
  public.album_rispondi_scambio(bigint, boolean), public.album_ritira_scambio(bigint) from public, anon;
grant execute on function public.album_doppioni(bigint, bigint), public.album_proponi_scambio(bigint, bigint, jsonb, jsonb, bigint),
  public.album_rispondi_scambio(bigint, boolean), public.album_ritira_scambio(bigint) to authenticated;

commit;
