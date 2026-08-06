-- Ridistribuzione del monte economico: meno distanza fra vittoria e sconfitta,
-- piu' stabilita' tramite l'incasso della gara in casa. Il totale medio resta
-- pressoché invariato rispetto ai precedenti coefficienti 0.54/0.27/0.135.
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
  v_pagamento record;
  v_vittoria bigint;
  v_pareggio bigint;
  v_sconfitta bigint;
  v_incasso_casa bigint;
  v_saldo bigint;
  v_accrediti integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;
  if exists (select 1 from public.fixtures where league_id = p_league_id and giornata = p_giornata and stato <> 'simulata') then return 0; end if;

  v_vittoria := round((v_lega.budget_iniziale::numeric * 0.48 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_pareggio := round((v_lega.budget_iniziale::numeric * 0.24 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_sconfitta := round((v_lega.budget_iniziale::numeric * 0.12 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_incasso_casa := round((v_lega.budget_iniziale::numeric * 0.08 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;

  for v_pagamento in
    select f.home_team_id as team_id,
           case when m.gol_home > m.gol_away then 'vittoria' when m.gol_home = m.gol_away then 'pareggio' else 'sconfitta' end as esito,
           (case when m.gol_home > m.gol_away then v_vittoria when m.gol_home = m.gol_away then v_pareggio else v_sconfitta end)
             + case when f.campo_neutro then v_incasso_casa / 2 else v_incasso_casa end as importo,
           case when f.campo_neutro then ' + quota campo neutro' else ' + incasso casa' end as nota
    from public.fixtures f join public.matches m on m.fixture_id = f.id
    where f.league_id = p_league_id and f.giornata = p_giornata
    union all
    select f.away_team_id,
           case when m.gol_away > m.gol_home then 'vittoria' when m.gol_home = m.gol_away then 'pareggio' else 'sconfitta' end,
           (case when m.gol_away > m.gol_home then v_vittoria when m.gol_home = m.gol_away then v_pareggio else v_sconfitta end)
             + case when f.campo_neutro then v_incasso_casa / 2 else 0 end,
           case when f.campo_neutro then ' + quota campo neutro' else '' end
    from public.fixtures f join public.matches m on m.fixture_id = f.id
    where f.league_id = p_league_id and f.giornata = p_giornata
  loop
    insert into private.premi_partita_giornata(league_id, giornata, team_id, esito, importo)
    values (p_league_id, p_giornata, v_pagamento.team_id, v_pagamento.esito, v_pagamento.importo)
    on conflict do nothing;
    if not found then continue; end if;
    update public.teams set budget = budget + v_pagamento.importo where id = v_pagamento.team_id returning budget into v_saldo;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_pagamento.team_id, 'premi_partite', v_pagamento.importo,
            'Premio ' || v_pagamento.esito || v_pagamento.nota || ' - giornata ' || p_giornata, v_saldo);
    v_accrediti := v_accrediti + 1;
  end loop;
  return v_accrediti;
end;
$$;

-- Riallinea una giornata gia' pagata con le nuove regole, senza riscrivere
-- il registro append-only: la differenza resta visibile in Finanza.
create or replace function private.ricalcola_premi_partite_giornata(
  p_league_id bigint,
  p_giornata integer
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_pagamento record;
  v_vittoria bigint;
  v_pareggio bigint;
  v_sconfitta bigint;
  v_incasso_casa bigint;
  v_differenza bigint;
  v_saldo bigint;
  v_rettifiche integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id for update;
  if not found then return 0; end if;
  v_vittoria := round((v_lega.budget_iniziale::numeric * 0.48 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_pareggio := round((v_lega.budget_iniziale::numeric * 0.24 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_sconfitta := round((v_lega.budget_iniziale::numeric * 0.12 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;
  v_incasso_casa := round((v_lega.budget_iniziale::numeric * 0.08 / greatest(v_lega.partite_per_squadra, 1)) / 100000) * 100000;

  for v_pagamento in
    select p.team_id, p.importo as precedente,
           (case
             when p.esito = 'vittoria' then v_vittoria
             when p.esito = 'pareggio' then v_pareggio
             else v_sconfitta
           end) + case
             when f.home_team_id = p.team_id then case when f.campo_neutro then v_incasso_casa / 2 else v_incasso_casa end
             when f.campo_neutro then v_incasso_casa / 2
             else 0
           end as corretto
    from private.premi_partita_giornata p
    join public.fixtures f on f.league_id = p.league_id and f.giornata = p.giornata
      and p.team_id in (f.home_team_id, f.away_team_id)
    where p.league_id = p_league_id and p.giornata = p_giornata
  loop
    v_differenza := v_pagamento.corretto - v_pagamento.precedente;
    if v_differenza = 0 then continue; end if;
    update private.premi_partita_giornata
    set importo = v_pagamento.corretto
    where league_id = p_league_id and giornata = p_giornata and team_id = v_pagamento.team_id;
    update public.teams set budget = budget + v_differenza where id = v_pagamento.team_id returning budget into v_saldo;
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_pagamento.team_id, 'rettifica_premi_partite', v_differenza,
            'Rettifica premio + incasso casa - giornata ' || p_giornata, v_saldo);
    v_rettifiche := v_rettifiche + 1;
  end loop;
  return v_rettifiche;
end;
$$;
