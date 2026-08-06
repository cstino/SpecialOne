-- Premi partita accreditati subito dopo la simulazione della giornata.
-- Il registro privato rende il pagamento idempotente in caso di retry del cron.
create table if not exists private.premi_partita_giornata (
  league_id bigint not null references public.leagues(id) on delete cascade,
  giornata integer not null check (giornata > 0),
  team_id bigint not null references public.teams(id) on delete cascade,
  esito text not null check (esito in ('vittoria', 'pareggio', 'sconfitta')),
  importo bigint not null check (importo > 0),
  creato_il timestamptz not null default now(),
  primary key (league_id, giornata, team_id)
);

create or replace function private.accredita_premi_partite_giornata(
  p_league_id bigint,
  p_giornata integer
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_partita record;
  v_vittoria bigint;
  v_pareggio bigint;
  v_sconfitta bigint;
  v_importo bigint;
  v_esito text;
  v_saldo bigint;
  v_accrediti integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;
  if exists (
    select 1 from public.fixtures
    where league_id = p_league_id and giornata = p_giornata and stato <> 'simulata'
  ) then
    return 0;
  end if;

  v_vittoria := round((v_lega.budget_iniziale::numeric * 0.54 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_pareggio := round((v_lega.budget_iniziale::numeric * 0.27 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_sconfitta := round((v_lega.budget_iniziale::numeric * 0.135 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;

  for v_partita in
    select f.home_team_id, f.away_team_id, m.gol_home, m.gol_away
    from public.fixtures f
    join public.matches m on m.fixture_id = f.id
    where f.league_id = p_league_id and f.giornata = p_giornata
  loop
    for v_esito, v_importo in
      select case when v_partita.gol_home > v_partita.gol_away then 'vittoria' when v_partita.gol_home = v_partita.gol_away then 'pareggio' else 'sconfitta' end,
             case when v_partita.gol_home > v_partita.gol_away then v_vittoria when v_partita.gol_home = v_partita.gol_away then v_pareggio else v_sconfitta end
    loop
      insert into private.premi_partita_giornata(league_id, giornata, team_id, esito, importo)
      values (p_league_id, p_giornata, v_partita.home_team_id, v_esito, v_importo)
      on conflict do nothing;
      if found then
        update public.teams set budget = budget + v_importo where id = v_partita.home_team_id returning budget into v_saldo;
        insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        values (p_league_id, v_partita.home_team_id, 'premi_partite', v_importo,
                'Premio ' || v_esito || ' - giornata ' || p_giornata, v_saldo);
        v_accrediti := v_accrediti + 1;
      end if;
    end loop;

    for v_esito, v_importo in
      select case when v_partita.gol_away > v_partita.gol_home then 'vittoria' when v_partita.gol_home = v_partita.gol_away then 'pareggio' else 'sconfitta' end,
             case when v_partita.gol_away > v_partita.gol_home then v_vittoria when v_partita.gol_home = v_partita.gol_away then v_pareggio else v_sconfitta end
    loop
      insert into private.premi_partita_giornata(league_id, giornata, team_id, esito, importo)
      values (p_league_id, p_giornata, v_partita.away_team_id, v_esito, v_importo)
      on conflict do nothing;
      if found then
        update public.teams set budget = budget + v_importo where id = v_partita.away_team_id returning budget into v_saldo;
        insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        values (p_league_id, v_partita.away_team_id, 'premi_partite', v_importo,
                'Premio ' || v_esito || ' - giornata ' || p_giornata, v_saldo);
        v_accrediti := v_accrediti + 1;
      end if;
    end loop;
  end loop;
  return v_accrediti;
end;
$$;

revoke all on function private.accredita_premi_partite_giornata(bigint, integer) from public, anon, authenticated;
grant execute on function private.accredita_premi_partite_giornata(bigint, integer) to service_role;

-- L'ultima partita salvata della giornata attiva il pagamento. In questo modo
-- il premio non dipende dall'Edge Function e non puo' perdersi se il cron
-- termina dopo aver registrato il risultato ma prima delle operazioni finali.
create or replace function private.paga_premi_quando_giornata_completa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stato = 'simulata' and old.stato <> 'simulata' then
    perform private.accredita_premi_partite_giornata(new.league_id, new.giornata);
  end if;
  return new;
end;
$$;

drop trigger if exists fixtures_paga_premi_giornata on public.fixtures;
create trigger fixtures_paga_premi_giornata
after update of stato on public.fixtures
for each row execute function private.paga_premi_quando_giornata_completa();

-- Le vecchie funzioni di chiusura stagione sommano i premi di tutte le
-- giornate. Da ora sono gia' stati incassati: annulliamo quella sola riga e
-- restituiamo il suo importo, lasciando invariati sponsor e premio classifica.
create or replace function private.annulla_premio_partite_stagionale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.tipo = 'premi_partite' and new.descrizione like 'Premi partita stagione %' then
    update public.teams set budget = budget - new.importo where id = new.team_id;
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists transactions_annulla_premio_partite_stagionale on public.transactions;
create trigger transactions_annulla_premio_partite_stagionale
before insert on public.transactions
for each row execute function private.annulla_premio_partite_stagionale();
