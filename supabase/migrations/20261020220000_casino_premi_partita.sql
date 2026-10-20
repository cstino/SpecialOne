-- Premi partita in crediti del casino' (idea dal gruppo, 20/10/2026): nelle partite di campionato e playoff chi vince
-- prende 300 crediti, chi pareggia 150, chi perde 100 (playoff ai rigori: chi passa 300, chi esce 100).
-- NIENTE SPOILER: il premio si paga solo quando il giocatore ha gia' visto la partita (match_reveals) oppure quando
-- la partita e' stata giocata da almeno 24 ore; nessuna notifica, solo un avviso nella pagina del casino'.
-- Vale dalle partite dopo il lancio (id > 1513). Le amichevoli stanno in un'altra tabella e non contano.

create table if not exists public.casino_premi_partita (
  match_id bigint not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  esito text not null check (esito in ('vittoria', 'pareggio', 'sconfitta')),
  avversario_id bigint not null references public.teams(id) on delete cascade,
  crediti integer not null check (crediti > 0),
  visto boolean not null default false,
  creato_il timestamptz not null default now(),
  primary key (match_id, user_id)
);
alter table public.casino_premi_partita enable row level security;
-- Nessuna policy: si legge solo dalle funzioni. Permessi espliciti (regola del 20/10/2026, vedi CLAUDE.md).
grant select on public.casino_premi_partita to anon;
grant select, insert, update, delete on public.casino_premi_partita to authenticated, service_role;

-- Paga i premi maturati di un giocatore in una lega; restituisce quanti crediti ha aggiunto.
create or replace function private.casino_premi_partita(p_league_id bigint, p_user uuid) returns integer language plpgsql security definer set search_path to '' as $$
declare r record; v_tot integer := 0; v_esito text; v_crediti integer;
begin
  for r in
    select m.id as match_id, t.id as team_id,
           case when f.home_team_id = t.id then f.away_team_id else f.home_team_id end as avversario,
           case when f.home_team_id = t.id then m.gol_home else m.gol_away end as gf,
           case when f.home_team_id = t.id then m.gol_away else m.gol_home end as gs,
           case when f.home_team_id = t.id then m.rigori_home else m.rigori_away end as rf,
           case when f.home_team_id = t.id then m.rigori_away else m.rigori_home end as rs
      from public.teams t
      join public.fixtures f on f.league_id = t.league_id and t.id in (f.home_team_id, f.away_team_id)
      join public.matches m on m.fixture_id = f.id
     where t.league_id = p_league_id and t.user_id = p_user and t.attiva
       and m.id > 1513
       and not exists (select 1 from public.casino_premi_partita p where p.match_id = m.id and p.user_id = p_user)
       and (exists (select 1 from public.match_reveals mr where mr.match_id = m.id and mr.user_id = p_user)
            or m.simulata_il < now() - interval '24 hours')
  loop
    v_esito := case when r.gf > r.gs then 'vittoria' when r.gf < r.gs then 'sconfitta'
                    when r.rf is not null and r.rs is not null and r.rf <> r.rs then case when r.rf > r.rs then 'vittoria' else 'sconfitta' end
                    else 'pareggio' end;
    v_crediti := case v_esito when 'vittoria' then 300 when 'pareggio' then 150 else 100 end;
    insert into public.casino_premi_partita (match_id, user_id, league_id, team_id, esito, avversario_id, crediti)
    values (r.match_id, p_user, p_league_id, r.team_id, v_esito, r.avversario, v_crediti)
    on conflict do nothing;
    if found then v_tot := v_tot + v_crediti; end if;
  end loop;
  if v_tot > 0 then
    update public.casino_saldi set crediti = crediti + v_tot, aggiornato_il = now() where league_id = p_league_id and user_id = p_user;
  end if;
  return v_tot;
end $$;

-- Premi pagati e non ancora mostrati: li restituisce per l'avviso nel casino' e li segna come visti.
create or replace function private.casino_premi_da_vedere(p_league_id bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('esito', p.esito, 'crediti', p.crediti, 'avversario_id', p.avversario_id) order by p.match_id), '[]'::jsonb)
    into v from public.casino_premi_partita p where p.league_id = p_league_id and p.user_id = p_user and not p.visto;
  update public.casino_premi_partita set visto = true where league_id = p_league_id and user_id = p_user and not visto;
  return v;
end $$;
revoke all on function private.casino_premi_partita(bigint, uuid), private.casino_premi_da_vedere(bigint, uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.casino_saldo(p_league_id bigint, p_user uuid)
 RETURNS casino_saldi
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v public.casino_saldi;
  v_team bigint;
  v_sett date := private.casino_settimana();
  v_settimane integer;
begin
  select * into v from public.casino_saldi where league_id = p_league_id and user_id = p_user for update;
  if not found then
    select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = p_user and t.attiva;
    if v_team is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
    insert into public.casino_saldi (league_id, user_id, team_id, crediti, settimana) values (p_league_id, p_user, v_team, 1000, v_sett)
    returning * into v;
    if private.casino_premi_partita(p_league_id, p_user) > 0 then
      select * into v from public.casino_saldi where league_id = p_league_id and user_id = p_user;
    end if;
    return v;
  end if;
  v_settimane := v_sett - v.settimana;  -- giorni passati dall'ultima ricarica (1.000 crediti al giorno, anche arretrati)
  if v_settimane > 0 then
    update public.casino_saldi set crediti = crediti + 1000 * v_settimane, settimana = v_sett, aggiornato_il = now()
     where league_id = p_league_id and user_id = p_user returning * into v;
  end if;
  -- Premi partita maturati (20/10/2026): solo per partite gia' viste o giocate da almeno 24 ore, cosi' i crediti
  -- non svelano il risultato prima che uno guardi la partita.
  if private.casino_premi_partita(p_league_id, p_user) > 0 then
    select * into v from public.casino_saldi where league_id = p_league_id and user_id = p_user;
  end if;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.casino_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v public.casino_saldi;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  if not exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa) then
    raise exception using errcode = '55000', message = 'Il casinò non è attivo in questa lega.';
  end if;
  v := private.casino_saldo(p_league_id, v_utente);
  return jsonb_build_object('crediti', v.crediti, 'giri_gratis', v.giri_gratis, 'puntata_gratis', v.puntata_gratis,
    'simboli', private.casino_simboli(p_league_id), 'max_vincita', v.max_vincita, 'giri', v.giri, 'bustine_gratis', v.bustine_gratis, 'album', private.album_attivo(p_league_id),
    'crazyone', (select l.casino_crazyone from public.leagues l where l.id = p_league_id),
    'aviatone', (select l.casino_aviatone from public.leagues l where l.id = p_league_id),
    'premi', private.casino_premi_da_vedere(p_league_id, v_utente),
    'prossima_ricarica', ((v.settimana::timestamp + interval '23 hours') at time zone 'Europe/Rome'));
end $function$;
