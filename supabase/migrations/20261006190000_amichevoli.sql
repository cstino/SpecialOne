-- Amichevoli (solo in off-season): una squadra ne invita un'altra, l'altra accetta, la partita si simula con le
-- formazioni salvate e il referto resta in questa tabella. NIENTE di quello che succede in campo viene scritto
-- sui giocatori: nessuna statistica, infortunio, cartellino, stanchezza, familiarita' o morale. Serve solo a provare le tattiche.
-- Le giocate sono visibili a tutta la lega; inviti e partite non ancora giocate solo ai due interessati.
-- Solo fra squadre di persone (niente squadre PC), senza limiti di numero.

alter table public.notifications drop constraint if exists notifications_tipo_check;
alter table public.notifications add constraint notifications_tipo_check
  check (tipo = any (array['giornata_simulata','formazione_mancante','infortunio','squalifica','mercato_proposta',
                           'mercato_esito','mercato_asta','sistema','scambio_ufficiale','amichevole']));

create table if not exists public.amichevoli (
  id          bigserial primary key,
  league_id   bigint not null references public.leagues(id) on delete cascade,
  da_team_id  bigint not null,
  a_team_id   bigint not null,
  stato       text not null default 'in_attesa' check (stato in ('in_attesa', 'accettata', 'rifiutata', 'giocata')),
  creata_il   timestamptz not null default now(),
  risolta_il  timestamptz,
  giocata_il  timestamptz,
  gol_da      smallint,
  gol_a       smallint,
  risultato   jsonb,
  foreign key (da_team_id, league_id) references public.teams (id, league_id) on delete cascade,
  foreign key (a_team_id, league_id) references public.teams (id, league_id) on delete cascade,
  check (da_team_id <> a_team_id)
);
create index if not exists amichevoli_lega_idx on public.amichevoli (league_id, id desc);

alter table public.amichevoli enable row level security;
drop policy if exists amichevoli_lettura on public.amichevoli;
create policy amichevoli_lettura on public.amichevoli for select to authenticated using (
  (select private.e_membro(league_id))
  and (
    stato = 'giocata'
    or exists (select 1 from public.teams t where t.user_id = (select auth.uid()) and t.id in (da_team_id, a_team_id))
  )
);
revoke all on public.amichevoli from public, anon;
grant select on public.amichevoli to authenticated;

-- Invita un'altra squadra (di una persona) a un'amichevole.
create or replace function public.invia_amichevole(p_league_id bigint, p_a_team_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_da public.teams;
  v_a public.teams;
  v_lega public.leagues;
  v_id bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per invitare una squadra.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'Le amichevoli si giocano solo durante l''off-season.';
  end if;
  select * into v_da from public.teams where league_id = p_league_id and user_id = v_user and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;
  select * into v_a from public.teams where id = p_a_team_id and league_id = p_league_id and attiva;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra non trovata.';
  end if;
  if v_a.id = v_da.id then
    raise exception using errcode = '22023', message = 'Non puoi sfidare te stesso.';
  end if;
  if v_a.controllata_da_pc or v_a.user_id is null then
    raise exception using errcode = '22023', message = 'Le amichevoli si giocano solo contro squadre di persone.';
  end if;
  if exists (
    select 1 from public.amichevoli x
    where x.league_id = p_league_id and x.stato in ('in_attesa', 'accettata')
      and ((x.da_team_id = v_da.id and x.a_team_id = v_a.id) or (x.da_team_id = v_a.id and x.a_team_id = v_da.id))
  ) then
    raise exception using errcode = '23505', message = 'C''e'' gia'' un''amichevole in corso con questa squadra.';
  end if;
  insert into public.amichevoli (league_id, da_team_id, a_team_id) values (p_league_id, v_da.id, v_a.id) returning id into v_id;
  perform private.notifica(v_a.user_id, p_league_id, 'amichevole', 'Invito a un''amichevole',
    v_da.nome || ' ti sfida a un''amichevole. Non conta per classifica e statistiche.',
    jsonb_build_object('view', 'amichevoli', 'amichevole_id', v_id));
  return v_id;
end;
$$;
revoke all on function public.invia_amichevole(bigint, bigint) from public, anon;
grant execute on function public.invia_amichevole(bigint, bigint) to authenticated;

-- Accetta o rifiuta un invito (solo la squadra invitata). L'accettazione NON simula: lo fa la funzione di
-- simulazione, chiamata subito dopo dall'app (o ritentata da uno dei due se fallisce).
create or replace function public.rispondi_amichevole(p_id bigint, p_accetta boolean)
returns public.amichevoli
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_am public.amichevoli;
  v_da public.teams;
  v_a public.teams;
  v_lega public.leagues;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere.';
  end if;
  select * into v_am from public.amichevoli where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Invito non trovato.';
  end if;
  select * into v_a from public.teams where id = v_am.a_team_id;
  select * into v_da from public.teams where id = v_am.da_team_id;
  if v_a.user_id is distinct from v_user then
    raise exception using errcode = '42501', message = 'Solo la squadra invitata puo'' rispondere.';
  end if;
  if v_am.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'L''invito non e'' piu'' in attesa.';
  end if;
  select * into v_lega from public.leagues where id = v_am.league_id;
  if v_lega.fase_carriera <> 'offseason' then
    raise exception using errcode = '55000', message = 'L''off-season e'' finita: niente piu'' amichevoli.';
  end if;
  update public.amichevoli set stato = case when p_accetta then 'accettata' else 'rifiutata' end, risolta_il = now()
    where id = p_id returning * into v_am;
  perform private.notifica(v_da.user_id, v_am.league_id, 'amichevole',
    case when p_accetta then 'Amichevole accettata' else 'Amichevole rifiutata' end,
    v_a.nome || case when p_accetta then ' ha accettato: la partita si sta giocando.' else ' ha rifiutato l''invito.' end,
    jsonb_build_object('view', 'amichevoli', 'amichevole_id', v_am.id));
  return v_am;
end;
$$;
revoke all on function public.rispondi_amichevole(bigint, boolean) from public, anon;
grant execute on function public.rispondi_amichevole(bigint, boolean) to authenticated;

-- Salva il referto: lo chiama SOLO la funzione di simulazione (chiave di servizio). Nessun'altra scrittura.
create or replace function public.registra_amichevole(p_id bigint, p_gol_da smallint, p_gol_a smallint, p_risultato jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_am public.amichevoli;
  v_da public.teams;
  v_a public.teams;
begin
  select * into v_am from public.amichevoli where id = p_id for update;
  if not found or v_am.stato <> 'accettata' then
    return;
  end if;
  update public.amichevoli
  set stato = 'giocata', giocata_il = now(), gol_da = p_gol_da, gol_a = p_gol_a, risultato = p_risultato
  where id = p_id;
  select * into v_da from public.teams where id = v_am.da_team_id;
  select * into v_a from public.teams where id = v_am.a_team_id;
  perform private.notifica(u.uid, v_am.league_id, 'amichevole', 'Amichevole giocata',
    v_da.nome || ' ' || p_gol_da || ' - ' || p_gol_a || ' ' || v_a.nome || '. Non conta per classifica e statistiche.',
    jsonb_build_object('view', 'amichevoli', 'amichevole_id', p_id))
  from (values (v_da.user_id), (v_a.user_id)) as u(uid);
end;
$$;
revoke all on function public.registra_amichevole(bigint, smallint, smallint, jsonb) from public, anon, authenticated;
grant execute on function public.registra_amichevole(bigint, smallint, smallint, jsonb) to service_role;
