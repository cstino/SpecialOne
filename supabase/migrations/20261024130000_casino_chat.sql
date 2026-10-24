-- Chat dei giochi multiplayer del casino' (24/10/2026, committente): CrazyOne e AviatOne una chat per lega,
-- BlackjackOne una chat per tavolo (la leggono solo i giocatori seduti). Testo libero fino a 140 caratteri e reazioni
-- rapide (che sono testo come gli altri). Si leggono gli ultimi 50 messaggi, quelli piu' vecchi di 24 ore si cancellano.
-- Un messaggio ogni 3 secondi a persona. Solo il proprietario del gioco puo' cancellare un messaggio o silenziare
-- una squadra. Si scrive e si legge solo con le funzioni qui sotto: le tabelle non hanno policy per i client.

create table public.casino_chat (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues (id) on delete cascade,
  canale text not null check (canale ~ '^(crazy|aviat|bj:[0-9]+)$'),
  user_id uuid not null,
  team_id bigint not null references public.teams (id) on delete cascade,
  testo text not null check (char_length(testo) between 1 and 140),
  creato_il timestamptz not null default now()
);
create index casino_chat_canale_idx on public.casino_chat (league_id, canale, id desc);
create index casino_chat_creato_idx on public.casino_chat (creato_il);
create index casino_chat_utente_idx on public.casino_chat (user_id, creato_il desc);
alter table public.casino_chat enable row level security;
grant select on public.casino_chat to anon;
grant select, insert, update, delete on public.casino_chat to authenticated, service_role;

create table public.casino_chat_silenzio (
  league_id bigint not null references public.leagues (id) on delete cascade,
  team_id bigint not null references public.teams (id) on delete cascade,
  creato_il timestamptz not null default now(),
  primary key (league_id, team_id)
);
alter table public.casino_chat_silenzio enable row level security;
grant select on public.casino_chat_silenzio to anon;
grant select, insert, update, delete on public.casino_chat_silenzio to authenticated, service_role;

-- Il proprietario del gioco (stesso criterio di crea_codice_occhiali).
create or replace function private.e_proprietario_gioco()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce((select u.email from auth.users u where u.id = (select auth.uid())) = 'cr.96bc@gmail.com', false)
$function$;

-- Controlla che l'utente possa stare in quel canale e restituisce la sua squadra.
create or replace function private.casino_chat_accesso(p_league_id bigint, p_canale text)
 returns bigint language plpgsql stable security definer set search_path to ''
as $function$
declare v_utente uuid := (select auth.uid()); v_team bigint; v_ok boolean;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.casino_visibile(v_utente) then raise exception using errcode = '42501', message = 'Il casinò non è ancora aperto.'; end if;
  select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = v_utente and t.attiva;
  if v_team is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  if p_canale = 'crazy' then
    select l.casino_crazyone into v_ok from public.leagues l where l.id = p_league_id;
  elsif p_canale = 'aviat' then
    select l.casino_aviatone into v_ok from public.leagues l where l.id = p_league_id;
  elsif p_canale ~ '^bj:[0-9]+$' then
    -- La chat del tavolo la vedono solo i giocatori seduti.
    select exists (select 1 from public.casino_bjl_posti p
                    where p.tavolo_id = split_part(p_canale, ':', 2)::bigint and p.league_id = p_league_id and p.user_id = v_utente) into v_ok;
  else
    raise exception using errcode = '22023', message = 'Canale non valido.';
  end if;
  if not coalesce(v_ok, false) then raise exception using errcode = '42501', message = 'Chat non disponibile.'; end if;
  return v_team;
end $function$;

-- Ultimi 50 messaggi (o quelli dopo p_dopo) del canale.
create or replace function public.casino_chat_leggi(p_league_id bigint, p_canale text, p_dopo bigint default 0)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare v_team bigint := private.casino_chat_accesso(p_league_id, p_canale); v_mod boolean := private.e_proprietario_gioco();
begin
  return jsonb_build_object(
    'mio_team_id', v_team,
    'mod', v_mod,
    'silenziato', exists (select 1 from public.casino_chat_silenzio s where s.league_id = p_league_id and s.team_id = v_team),
    'silenziati', case when v_mod then coalesce((select jsonb_agg(s.team_id) from public.casino_chat_silenzio s where s.league_id = p_league_id), '[]'::jsonb) end,
    'messaggi', coalesce((select jsonb_agg(m order by (m ->> 'id')::bigint) from (
        select jsonb_build_object('id', c.id, 'team_id', c.team_id, 'testo', c.testo, 'ora', floor(extract(epoch from c.creato_il) * 1000)) m
          from public.casino_chat c
         where c.league_id = p_league_id and c.canale = p_canale and c.id > coalesce(p_dopo, 0) and c.creato_il > now() - interval '24 hours'
         order by c.id desc limit 50) x), '[]'::jsonb));
end $function$;

-- Scrive un messaggio: massimo 140 caratteri, uno ogni 3 secondi, non se silenziati.
create or replace function public.casino_chat_invia(p_league_id bigint, p_canale text, p_testo text)
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
declare v_utente uuid := (select auth.uid()); v_team bigint := private.casino_chat_accesso(p_league_id, p_canale); v_testo text;
begin
  -- spazi ripetuti e a capo diventano uno spazio; caratteri di controllo via
  v_testo := btrim(regexp_replace(regexp_replace(coalesce(p_testo, ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g'));
  if v_testo = '' then raise exception using errcode = '22023', message = 'Scrivi qualcosa.'; end if;
  if char_length(v_testo) > 140 then raise exception using errcode = '22023', message = 'Massimo 140 caratteri.'; end if;
  if exists (select 1 from public.casino_chat_silenzio s where s.league_id = p_league_id and s.team_id = v_team) then
    raise exception using errcode = '42501', message = 'Sei stato silenziato in chat.';
  end if;
  perform pg_advisory_xact_lock(hashtext('casino_chat'), hashtext(v_utente::text));
  if exists (select 1 from public.casino_chat c where c.user_id = v_utente and c.creato_il > clock_timestamp() - interval '3 seconds') then
    raise exception using errcode = '55000', message = 'Piano: un messaggio ogni 3 secondi.';
  end if;
  insert into public.casino_chat (league_id, canale, user_id, team_id, testo) values (p_league_id, p_canale, v_utente, v_team, v_testo);
end $function$;

-- Solo il proprietario: cancella un messaggio.
create or replace function public.casino_chat_elimina(p_id bigint)
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
begin
  if not private.e_proprietario_gioco() then raise exception using errcode = '42501', message = 'Non puoi moderare la chat.'; end if;
  delete from public.casino_chat where id = p_id;
end $function$;

-- Solo il proprietario: silenzia (o riabilita) una squadra in tutte le chat del casino' della lega.
create or replace function public.casino_chat_silenzia(p_league_id bigint, p_team_id bigint, p_silenzia boolean)
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
begin
  if not private.e_proprietario_gioco() then raise exception using errcode = '42501', message = 'Non puoi moderare la chat.'; end if;
  if coalesce(p_silenzia, false) then
    insert into public.casino_chat_silenzio (league_id, team_id) values (p_league_id, p_team_id) on conflict do nothing;
  else
    delete from public.casino_chat_silenzio where league_id = p_league_id and team_id = p_team_id;
  end if;
end $function$;

revoke all on function public.casino_chat_leggi(bigint, text, bigint), public.casino_chat_invia(bigint, text, text),
  public.casino_chat_elimina(bigint), public.casino_chat_silenzia(bigint, bigint, boolean) from public, anon;
grant execute on function public.casino_chat_leggi(bigint, text, bigint), public.casino_chat_invia(bigint, text, text),
  public.casino_chat_elimina(bigint), public.casino_chat_silenzia(bigint, bigint, boolean) to authenticated;

-- Pulizia: ogni ora via i messaggi con piu' di 24 ore.
select cron.schedule('casino_chat_pulizia', '7 * * * *', $$delete from public.casino_chat where creato_il < now() - interval '24 hours'$$);
