-- ============================================================
--  ALBUM DELLE FIGURINE (19/10/2026, deciso con il committente). Dentro BetOne, solo leghe con le novita'.
--  - Un album per stagione: una pagina per squadra (stemma + giocatori della rosa al momento della stampa); chi arriva
--    dopo (scambio, asta, vivaio) entra come figurina AGGIORNAMENTO nella pagina della nuova squadra.
--  - Bustina da 100 crediti (saldo del casino'), 3 figurine: giocatore 88%, stemma 10%, ultrarara 2%. Fra i giocatori i
--    piu' forti escono piu' di rado. Ultrarara = versione olografica di un giocatore; in Serie F anche le due figurine
--    delle conference (Eastern e Western), solo ultrarare.
--  - Doppioni riciclabili: 10 crediti (normale), 50 (ultrarara). Pagina squadra completa: 200 crediti e distintivo.
--    Album completo: distintivo e post su SocialOne.
--  - Schedine: 20 crediti per pronostico giusto, 300 di bonus per la WIN.
--  Estrazioni sul server. Niente effetti sul gioco vero.
-- ============================================================
begin;

create table public.album_figurine (
  id          bigint generated always as identity primary key,
  league_id   bigint not null references public.leagues(id) on delete cascade,
  stagione    smallint not null,
  tipo        text not null check (tipo in ('stemma', 'giocatore', 'conferenza')),
  team_id     bigint references public.teams(id) on delete cascade,
  player_id   bigint references public.players(id) on delete cascade,
  conferenza  text check (conferenza in ('est', 'ovest')),
  overall     smallint,
  aggiornamento boolean not null default false,
  creata_il   timestamptz not null default now()
);
create unique index album_figurine_unica on public.album_figurine (league_id, stagione, tipo, coalesce(team_id, 0), coalesce(player_id, 0), coalesce(conferenza, ''));
create index album_figurine_lega_idx on public.album_figurine (league_id, stagione);

create table public.album_possesso (
  league_id   bigint not null references public.leagues(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  figurina_id bigint not null references public.album_figurine(id) on delete cascade,
  normali     integer not null default 0 check (normali >= 0),
  ultra       integer not null default 0 check (ultra >= 0),
  primary key (user_id, figurina_id)
);
create index album_possesso_lega_idx on public.album_possesso (league_id, user_id);

create table public.album_premi (
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  stagione  smallint not null,
  chiave    text not null,        -- 'pagina:<team_id>' oppure 'album'
  creato_il timestamptz not null default now(),
  primary key (league_id, user_id, stagione, chiave)
);

create table public.album_bustine (
  id        bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  contenuto jsonb not null,
  creata_il timestamptz not null default now()
);

alter table public.album_figurine enable row level security;
alter table public.album_possesso enable row level security;
alter table public.album_premi enable row level security;
alter table public.album_bustine enable row level security;
create policy album_figurine_lega on public.album_figurine for select to authenticated using ((select private.e_membro(league_id)));
create policy album_possesso_miei on public.album_possesso for select to authenticated using (user_id = (select auth.uid()));
create policy album_premi_lega on public.album_premi for select to authenticated using ((select private.e_membro(league_id)));
create policy album_bustine_mie on public.album_bustine for select to authenticated using (user_id = (select auth.uid()));
grant select on public.album_figurine, public.album_possesso, public.album_premi, public.album_bustine to authenticated;
grant all on public.album_figurine, public.album_possesso, public.album_premi, public.album_bustine to service_role;

-- Stampa e aggiornamenti: crea le figurine che mancano per la stagione corrente. La prima volta e' la stampa (rose del
-- momento); le volte successive chi e' arrivato in una squadra entra come aggiornamento. Chi se ne va resta dov'era.
create or replace function private.album_sincronizza(p_league_id bigint)
returns smallint language plpgsql security definer set search_path = '' as $f$
declare
  v_stag smallint;
  v_prima boolean;
  v_conf boolean;
begin
  select stagione_corrente, coalesce(conferenze_attive, false) into v_stag, v_conf from public.leagues where id = p_league_id;
  v_prima := not exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag);
  insert into public.album_figurine (league_id, stagione, tipo, team_id)
  select p_league_id, v_stag, 'stemma', t.id from public.teams t where t.league_id = p_league_id and t.attiva
  on conflict do nothing;
  insert into public.album_figurine (league_id, stagione, tipo, team_id, player_id, overall, aggiornamento)
  select p_league_id, v_stag, 'giocatore', pi.team_id, pi.player_id, pi.overall_corrente, not v_prima
  from public.player_instances pi join public.teams t on t.id = pi.team_id and t.attiva
  where pi.league_id = p_league_id and not pi.ritirato
  on conflict do nothing;
  if v_conf then
    insert into public.album_figurine (league_id, stagione, tipo, conferenza)
    values (p_league_id, v_stag, 'conferenza', 'est'), (p_league_id, v_stag, 'conferenza', 'ovest')
    on conflict do nothing;
  end if;
  return v_stag;
end $f$;

create or replace function private.album_controlla_premi(p_league_id bigint, p_user uuid, p_stagione smallint)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_t record;
  v_nuovi jsonb := '[]'::jsonb;
  v_nome text;
  v_team_mio bigint;
begin
  for v_t in
    select f.team_id from public.album_figurine f
    where f.league_id = p_league_id and f.stagione = p_stagione and f.tipo in ('stemma', 'giocatore')
    group by f.team_id
    having bool_and(exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.ultra > 0))
  loop
    insert into public.album_premi (league_id, user_id, stagione, chiave) values (p_league_id, p_user, p_stagione, 'pagina:' || v_t.team_id)
    on conflict do nothing;
    if found then
      update public.casino_saldi set crediti = crediti + 200 where league_id = p_league_id and user_id = p_user;
      v_nuovi := v_nuovi || jsonb_build_object('pagina', v_t.team_id);
    end if;
  end loop;
  if not exists (
    select 1 from public.album_figurine f
    where f.league_id = p_league_id and f.stagione = p_stagione and f.tipo in ('stemma', 'giocatore')
      and not exists (select 1 from public.album_possesso ap where ap.user_id = p_user and ap.figurina_id = f.id and ap.normali + ap.ultra > 0))
  then
    insert into public.album_premi (league_id, user_id, stagione, chiave) values (p_league_id, p_user, p_stagione, 'album') on conflict do nothing;
    if found then
      select t.id, t.nome into v_team_mio, v_nome from public.teams t where t.league_id = p_league_id and t.user_id = p_user;
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
      values (p_league_id, 'album:' || p_stagione || ':' || p_user, 'lega', 'Album SpecialOne', v_team_mio,
              '📒 ALBUM COMPLETATO! ' || coalesce(v_nome, 'Una squadra') || ' ha attaccato l''ultima figurina della stagione ' || p_stagione || ' 👏', now())
      on conflict do nothing;
      v_nuovi := v_nuovi || jsonb_build_object('album', true);
    end if;
  end if;
  return v_nuovi;
end $f$;

create or replace function public.album_compra_bustina(p_league_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_saldo public.casino_saldi;
  v_stag smallint;
  v_k int;
  v_r numeric;
  v_tipo text;
  v_fig public.album_figurine;
  v_ultra boolean;
  v_nuova boolean;
  v_out jsonb := '[]'::jsonb;
  c_prezzo constant int := 100;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  if v_saldo.crediti < c_prezzo then raise exception using errcode = '22023', message = 'Crediti insufficienti: una bustina costa 100 crediti.'; end if;
  v_stag := private.album_sincronizza(p_league_id);
  update public.casino_saldi set crediti = crediti - c_prezzo, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;

  for v_k in 1..3 loop
    v_r := random();
    v_ultra := v_r < 0.02;
    v_tipo := case when v_ultra then 'ultra' when v_r < 0.12 then 'stemma' else 'giocatore' end;
    if v_tipo = 'stemma' then
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
    elsif v_tipo = 'giocatore' then
      -- I piu' forti escono piu' di rado: peso = 100 - overall (minimo 5). Estrazione pesata con chiave esponenziale.
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
      order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
    else
      -- Ultrarara: un giocatore (stesso peso) oppure, nelle leghe a conferenze, una delle due conference (circa 1 ultra su 10).
      if exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
      end if;
    end if;
    if v_fig.id is null then continue; end if;
    -- Le figurine delle conference esistono solo ultrarare.
    if v_fig.tipo = 'conferenza' then v_ultra := true; end if;
    select not exists (select 1 from public.album_possesso where user_id = v_utente and figurina_id = v_fig.id and (case when v_ultra then ultra else normali end) > 0) into v_nuova;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, ultra)
    values (p_league_id, v_utente, v_fig.id, case when v_ultra then 0 else 1 end, case when v_ultra then 1 else 0 end)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + case when v_ultra then 0 else 1 end,
      ultra = public.album_possesso.ultra + case when v_ultra then 1 else 0 end;
    v_out := v_out || jsonb_build_object('figurina_id', v_fig.id, 'tipo', v_fig.tipo, 'team_id', v_fig.team_id, 'player_id', v_fig.player_id,
      'conferenza', v_fig.conferenza, 'ultra', v_ultra, 'nuova', v_nuova);
    v_fig := null;
  end loop;

  insert into public.album_bustine (league_id, user_id, contenuto) values (p_league_id, v_utente, v_out);
  return jsonb_build_object('figurine', v_out, 'premi', private.album_controlla_premi(p_league_id, v_utente, v_stag),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $f$;

-- Ricicla tutti i doppioni: si tiene una copia per versione, il resto vale 10 crediti (normale) o 50 (ultrarara).
create or replace function public.album_ricicla_doppioni(p_league_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_utente uuid := (select auth.uid());
  v_n int; v_u int; v_crediti int;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  select coalesce(sum(greatest(0, normali - 1)), 0), coalesce(sum(greatest(0, ultra - 1)), 0) into v_n, v_u
  from public.album_possesso where league_id = p_league_id and user_id = v_utente;
  v_crediti := v_n * 10 + v_u * 50;
  if v_crediti = 0 then return jsonb_build_object('riciclati', 0, 'crediti_guadagnati', 0); end if;
  perform private.casino_saldo(p_league_id, v_utente);
  update public.album_possesso set normali = least(normali, 1), ultra = least(ultra, 1) where league_id = p_league_id and user_id = v_utente;
  update public.casino_saldi set crediti = crediti + v_crediti, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;
  return jsonb_build_object('riciclati', v_n + v_u, 'crediti_guadagnati', v_crediti,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $f$;

-- Prepara l'album (stampa/aggiornamenti) e restituisce la stagione: la pagina lo chiama all'apertura.
create or replace function public.album_apri(p_league_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_stag smallint;
begin
  if (select auth.uid()) is null or not (select private.e_membro(p_league_id)) then raise exception using errcode = '42501', message = 'Non partecipi a questa lega.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_stag := private.album_sincronizza(p_league_id);
  return jsonb_build_object('stagione', v_stag, 'crediti', (private.casino_saldo(p_league_id, (select auth.uid()))).crediti);
end $f$;

-- Classifica dei collezionisti: figurine diverse attaccate (normali o ultra), poi ultrarare.
create or replace function public.album_classifica(p_league_id bigint)
returns table (team_id bigint, attaccate integer, totale integer, ultra integer, pagine integer)
language sql stable security definer set search_path = '' as $f$
  with st as (select stagione_corrente s from public.leagues where id = p_league_id),
  tot as (select count(*)::int n from public.album_figurine f, st where f.league_id = p_league_id and f.stagione = st.s and f.tipo in ('stemma','giocatore'))
  select t.id,
         count(*) filter (where f.tipo in ('stemma','giocatore') and ap.normali + ap.ultra > 0)::int,
         (select n from tot),
         count(*) filter (where ap.ultra > 0)::int,
         (select count(*)::int from public.album_premi pr, st where pr.league_id = p_league_id and pr.user_id = ap.user_id and pr.stagione = st.s and pr.chiave like 'pagina:%')
  from public.album_possesso ap
  join public.album_figurine f on f.id = ap.figurina_id
  join st on f.stagione = st.s
  join public.teams t on t.league_id = p_league_id and t.user_id = ap.user_id
  where ap.league_id = p_league_id and (select private.e_membro(p_league_id))
  group by t.id, ap.user_id
  order by 2 desc, 4 desc, 1
$f$;

revoke all on function public.album_compra_bustina(bigint), public.album_ricicla_doppioni(bigint), public.album_apri(bigint), public.album_classifica(bigint) from public, anon;
grant execute on function public.album_compra_bustina(bigint), public.album_ricicla_doppioni(bigint), public.album_apri(bigint), public.album_classifica(bigint) to authenticated;

CREATE OR REPLACE FUNCTION private.betone_risolvi()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_s record;
  v_giuste integer;
  v_totale integer;
  v_n integer := 0;
begin
  for v_s in
    select s.id, s.league_id, s.user_id, s.giornata, s.gruppo
    from public.betone_schedine s
    where s.risolta_il is null
      and exists (select 1 from public.betone_pronostici p where p.schedina_id = s.id)
      and not exists (select 1 from public.betone_pronostici p
                        join public.fixtures f on f.id = p.fixture_id
                        left join public.matches m on m.fixture_id = f.id
                       where p.schedina_id = s.id and (f.stato <> 'simulata' or m.id is null))
  loop
    update public.betone_pronostici p
       set giusta = position((case when m.gol_home > m.gol_away then '1' when m.gol_home < m.gol_away then '2' else 'X' end) in p.scelta) > 0
      from public.matches m
     where p.schedina_id = v_s.id and m.fixture_id = p.fixture_id;
    select count(*) filter (where giusta), count(*) into v_giuste, v_totale from public.betone_pronostici where schedina_id = v_s.id;
    update public.betone_schedine set risolta_il = now(), giuste = v_giuste, totale = v_totale, perfetta = (v_giuste = v_totale) where id = v_s.id;
    -- Avviso neutro: dire "5 su 6" rivelerebbe i risultati di chi non ha ancora guardato la sua partita.
    -- Crediti (19/10/2026): 20 per pronostico giusto, 300 di bonus per la schedina perfetta (WIN). Stesso saldo del casino'.
    begin
      perform private.casino_saldo(v_s.league_id, v_s.user_id);
      update public.casino_saldi set crediti = crediti + 20 * v_giuste + (case when v_giuste = v_totale then 300 else 0 end), aggiornato_il = now()
       where league_id = v_s.league_id and user_id = v_s.user_id;
    exception when others then null;  -- senza squadra attiva niente crediti, ma la schedina si valuta lo stesso
    end;
    perform private.notifica(v_s.user_id, v_s.league_id, 'sistema', 'BetOne',
      'La tua schedina della giornata ' || v_s.giornata || ' è stata valutata.',
      jsonb_build_object('view', 'betone'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

commit;
