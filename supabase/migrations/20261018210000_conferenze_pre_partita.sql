-- ============================================================
--  Domanda PRE PARTITA (docs/decisioni-conferenze-stampa.md, 18/10/2026): verso le 16:00 i giornalisti fanno una
--  domanda sulla partita di stasera. La partita non e' ancora stata simulata, quindi la domanda e' legata alla
--  PARTITA IN CALENDARIO (fixture_id) e non al risultato (match_id nullo). tipo = 'pre' | 'dopo'.
--  Ogni partita ha un suo orario fisso tra le 13:00 e le 18:00 (a scatti di 5 minuti, scelto dall'id della partita):
--  i giornalisti arrivano a orari diversi. Una partita al minuto al massimo; si smette mezz'ora prima della simulazione.
-- ============================================================

begin;

alter table public.conferenze_domande
  add column tipo text not null default 'dopo' check (tipo in ('pre', 'dopo')),
  add column fixture_id bigint references public.fixtures(id) on delete cascade;
alter table public.conferenze_domande alter column match_id drop not null;
alter table public.conferenze_domande add constraint conferenze_domande_match_o_fixture check (match_id is not null or fixture_id is not null);
create unique index conferenze_domande_fixture_team_ordine_key on public.conferenze_domande (fixture_id, team_id, ordine) where fixture_id is not null;

create table private.conferenze_pre_richieste (
  fixture_id   bigint primary key references public.fixtures(id) on delete cascade,
  richiesta_il timestamptz not null default now(),
  tentativi    integer not null default 1
);

-- L'avviso: le domande "dopo" aspettano che si veda il risultato (come prima); quelle "pre" avvisano subito.
create or replace function private.avvisa_conferenza()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare
  v_user uuid;
begin
  if new.ordine = 1 then
    select t.user_id into v_user from public.teams t where t.id = new.team_id;
    if v_user is null then return new; end if;
    if new.tipo = 'pre' then
      perform private.notifica(v_user, new.league_id, 'sistema', 'Conferenza stampa',
        'I giornalisti vogliono sentirla prima della partita di stasera.',
        jsonb_build_object('conferenza_fixture_id', new.fixture_id, 'view', 'salastampa'));
    elsif private.conferenza_sbloccata(new.match_id, v_user) then
      perform private.notifica(v_user, new.league_id, 'sistema', 'Conferenza stampa',
        'I giornalisti ti aspettano in sala stampa dopo la partita.',
        jsonb_build_object('conferenza_match_id', new.match_id, 'view', 'salastampa'));
    end if;
  end if;
  return new;
end $f$;

create or replace function private.lancia_conferenze_pre()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_chiave text;
  v_fx bigint;
  v_lanciate integer := 0;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  for v_fx in
    select f.id
    from public.fixtures f
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa and l.stato = 'stagione' and l.fase_carriera = 'normale'
    where f.stato = 'programmata'
      -- Orario della domanda: per ogni partita un momento fisso tra 10 e 5 ore prima della simulazione
      -- (13:00-18:00 per le 23:00), a scatti di 5 minuti, cosi' i giornalisti arrivano a orari diversi.
      and f.data_sim - interval '10 hours' + (abs(hashtext('pre' || f.id::text)) % 61) * interval '5 minutes' <= now()
      and f.data_sim > now() + interval '30 minutes'
      and exists (select 1 from public.teams t
                  where t.id in (f.home_team_id, f.away_team_id) and t.user_id is not null and not t.controllata_da_pc
                    and not exists (select 1 from public.conferenze_domande d where d.fixture_id = f.id and d.team_id = t.id))
      and not exists (select 1 from private.conferenze_pre_richieste r
                      where r.fixture_id = f.id and (r.richiesta_il > now() - interval '3 minutes' or r.tentativi >= 8))
    order by f.id
    limit 1
  loop
    insert into private.conferenze_pre_richieste (fixture_id) values (v_fx)
    on conflict (fixture_id) do update set richiesta_il = now(), tentativi = private.conferenze_pre_richieste.tentativi + 1;
    perform net.http_post(
      url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
      body := jsonb_build_object('azione', 'genera_pre', 'fixture_id', v_fx),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
      timeout_milliseconds := 60000
    );
    v_lanciate := v_lanciate + 1;
  end loop;
  return v_lanciate;
end $f$;

select cron.schedule('conferenze-pre', '* * * * *', 'select private.lancia_conferenze_pre();');

commit;
