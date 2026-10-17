-- ============================================================
--  Niente spoiler dalle notifiche: l'avviso "I giornalisti ti aspettano in sala stampa" arrivava appena
--  generate le domande, cioe' prima che l'allenatore guardasse il risultato (VEDI RISULTATO). Ora parte
--  quando succedono entrambe le cose, nell'ordine in cui capitano:
--    - domande create dopo che il risultato e' gia' stato visto  -> avviso alla creazione;
--    - risultato visto dopo la creazione delle domande           -> avviso alla rivelazione.
--  Nelle giornate prima del reveal della lega (reveal_dalla_giornata) non c'e' nulla da aspettare: avviso subito.
-- ============================================================

begin;

create or replace function private.conferenza_sbloccata(p_match_id bigint, p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from public.match_reveals r where r.match_id = p_match_id and r.user_id = p_user_id)
      or exists (
        select 1 from public.matches m
          join public.fixtures f on f.id = m.fixture_id
          join public.leagues l on l.id = f.league_id
         where m.id = p_match_id and f.giornata < l.reveal_dalla_giornata)
$f$;

create or replace function private.avvisa_conferenza()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare
  v_user uuid;
begin
  if new.ordine = 1 then
    select t.user_id into v_user from public.teams t where t.id = new.team_id;
    if v_user is not null and private.conferenza_sbloccata(new.match_id, v_user) then
      perform private.notifica(v_user, new.league_id, 'sistema', 'Conferenza stampa',
        'I giornalisti ti aspettano in sala stampa dopo la partita.',
        jsonb_build_object('conferenza_match_id', new.match_id, 'view', 'salastampa'));
    end if;
  end if;
  return new;
end $f$;

create or replace function private.avvisa_conferenza_alla_rivelazione()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare
  v_d record;
begin
  for v_d in
    select d.league_id, d.match_id
      from public.conferenze_domande d join public.teams t on t.id = d.team_id
     where d.match_id = new.match_id and d.ordine = 1 and t.user_id = new.user_id
  loop
    perform private.notifica(new.user_id, v_d.league_id, 'sistema', 'Conferenza stampa',
      'I giornalisti ti aspettano in sala stampa dopo la partita.',
      jsonb_build_object('conferenza_match_id', v_d.match_id, 'view', 'salastampa'));
  end loop;
  return new;
end $f$;

create trigger match_reveals_avviso_conferenza
  after insert on public.match_reveals
  for each row execute function private.avvisa_conferenza_alla_rivelazione();

commit;
