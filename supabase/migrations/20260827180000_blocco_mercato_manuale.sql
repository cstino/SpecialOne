-- Congelamento manuale del mercato, richiesto dall'utente per Real
-- Fampionato: l'off-season di quella lega e' stata bloccata ieri (scadenza
-- spostata al 2027, docs/decisioni sul momento) per poter sistemare le cose
-- con calma. Ma il mercato, per conto suo, continua ad aprire e chiudere
-- ogni giorno secondo l'orario normale (07:00-21:00 o il ciclo dinamico) —
-- non si accorge affatto che l'off-season e' in pausa. Serve un interruttore
-- esplicito, indipendente dall'orario: finche' e' alzato, quella lega non
-- deve muoversi.
--
-- Blocca due cose distinte:
--   1. Le offerte/svincoli/scambi: mercato_aperto_lega ritorna false a
--      prescindere dall'ora, prima di qualsiasi altro controllo.
--   2. L'estrazione notturna e i movimenti dei bot PC: il cron salta del
--      tutto le leghe bloccate, niente nuovi svincolati ne' offerte PC.
--
-- E' un interruttore manuale, non legato alla scadenza dell'off-season: va
-- riabbassato esplicitamente quando si riprende, non si sblocca da solo.

alter table public.leagues
  add column if not exists mercato_bloccato boolean not null default false;

comment on column public.leagues.mercato_bloccato is
  'Interruttore manuale: se vero, il mercato di questa lega resta chiuso a prescindere dall''orario (nessuna offerta, nessuno svincolo, nessuno scambio, nessuna estrazione notturna). Va riabbassato a mano quando si riprende.';

create or replace function private.mercato_aperto_lega(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with ciclo as (
    select
      (select max(m.simulata_il)
       from public.matches m
       join public.fixtures f on f.id = m.fixture_id
       where f.league_id = p_league_id) as ultima_partita_il,
      (select min(f.data_sim)
       from public.fixtures f
       where f.league_id = p_league_id and f.stato = 'programmata') as prossima_partita_il
  )
  select not coalesce((select l.mercato_bloccato from public.leagues l where l.id = p_league_id), false)
  and (
    exists (
      select 1 from private.mercato_override_admin o
      where o.league_id = p_league_id
        and o.giorno = (now() at time zone 'Europe/Rome')::date
    ) or coalesce(
      (select now() >= ultima_partita_il + interval '30 minutes'
               and now() < prossima_partita_il - interval '2 hours'
       from ciclo
       where ultima_partita_il is not null and prossima_partita_il is not null),
      (now() at time zone 'Europe/Rome')::time >= time '23:30'
        or (now() at time zone 'Europe/Rome')::time < time '21:00'
    )
  );
$$;

create or replace function private.estrai_svincolati()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oggi date;
  v_ora time;
  v_lega bigint;
  v_estratti integer := 0;
begin
  v_ora := (now() at time zone 'Europe/Rome')::time;
  if not (v_ora >= time '23:30' and v_ora < time '23:45') then return 0; end if;
  v_oggi := (now() at time zone 'Europe/Rome')::date;
  for v_lega in select id from public.leagues where stato = 'stagione' and not mercato_bloccato loop
    v_estratti := v_estratti + private.estrai_svincolati_lega(v_lega, v_oggi);
    perform private.offerte_mercato_squadre_pc(v_lega);
    perform private.proposte_mercato_squadre_pc(v_lega);
  end loop;
  return v_estratti;
end;
$$;

revoke all on function private.estrai_svincolati() from public, anon, authenticated;

-- Applicato subito a Real Fampionato, come richiesto.
update public.leagues set mercato_bloccato = true where id = 37;
