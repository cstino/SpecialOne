-- Lo stesso controllo del cap vale per i rinnovi delle squadre PC.
-- La funzione precedente controllava solo la stagione entrante, prorogava
-- secondo la durata proposta (anziché un anno) e leggeva teams.budget,
-- colonna rimossa con l'economia a tetto.
-- docs/decisioni-economia.md §1-2: contratto annuale e cap per ogni stagione.
create or replace function public.gestisci_rinnovi_squadre_pc(p_league_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_riga record;
  v_proposta record;
  v_ingaggio bigint;
  v_scadenza smallint;
  v_rinnovati integer := 0;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found or v_lega.stato <> 'stagione' then return 0; end if;

  for v_riga in
    select pi.*, p.nome, p.mentalita_bandiera, p.mentalita_economia
    from public.player_instances pi
    join public.teams t on t.id = pi.team_id
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and t.controllata_da_pc and t.attiva
      and pi.contratto_scadenza = v_lega.stagione_corrente
      and not pi.ritirato and not pi.ritiro_annunciato
      and (pi.rinnovo_stagione is null or pi.rinnovo_stagione <> v_lega.stagione_corrente)
  loop
    if v_riga.eta_corrente >= 34 and v_riga.ingaggio > 5000000 and random() < 0.18 then continue; end if;
    select * into v_proposta from private.rinnovo_proposta(
      v_riga.id, v_riga.overall_corrente, v_riga.eta_corrente, v_riga.ingaggio,
      v_riga.mentalita_bandiera, v_riga.mentalita_economia
    );
    v_ingaggio := greatest(v_riga.ingaggio, round(v_proposta.richiesta * (1.01 + random() * 0.08))::bigint);

    perform 1 from public.teams where id = v_riga.team_id for update;
    if private.capienza_residua(v_riga.team_id, v_lega.stagione_corrente) < v_ingaggio - v_riga.ingaggio
       or private.capienza_residua(v_riga.team_id, (v_lega.stagione_corrente + 1)::smallint) < v_ingaggio then
      continue;
    end if;

    v_scadenza := (v_lega.stagione_corrente + 1)::smallint;
    update public.player_instances
    set ingaggio = v_ingaggio, contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0, rinnovo_stagione = v_lega.stagione_corrente
    where id = v_riga.id;
    perform private.spinta_morale_rinnovo(v_riga.id);
    insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (p_league_id, v_riga.team_id, 'rinnovo_in_stagione', greatest(1, v_ingaggio - v_riga.ingaggio),
            'Rinnovo PC: ' || v_riga.nome || ' fino alla stagione ' || v_scadenza, 0);
    v_rinnovati := v_rinnovati + 1;
  end loop;
  return v_rinnovati;
end;
$$;

revoke all on function public.gestisci_rinnovi_squadre_pc(bigint) from public, anon, authenticated;
grant execute on function public.gestisci_rinnovi_squadre_pc(bigint) to service_role;
