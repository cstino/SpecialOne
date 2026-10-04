-- ============================================================
--  MINUTAGGIO: un problema sul minutaggio non deve mai bloccare il gioco
--  (suggerimento della revisione del 4 ottobre 2026)
--
--  I tre trigger del minutaggio girano dentro la stessa transazione di
--  operazioni che non devono fallire per colpa loro: salvare il risultato di
--  una partita (registra_risultato_partita), firmare un giocatore, fare uno
--  scambio. Se un giorno una colonna cambiasse nome o nascesse un vincolo
--  nuovo, un loro errore fermerebbe la simulazione di una giornata. Ogni corpo
--  e' quindi avvolto in un blocco che trasforma l'errore in un avviso nel log:
--  si perde al piu' l'informazione sul minutaggio, mai la partita.
-- ============================================================

begin;

create or replace function private.registra_assenze_partita()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    insert into private.assenze_partita (fixture_id, player_instance_id, motivo)
    select new.fixture_id, pi.id,
           case when coalesce(pi.infortunato_fino_a, 0) > 0 then 'infortunio' else 'squalifica' end
    from public.fixtures f
    join public.player_instances pi on pi.team_id in (f.home_team_id, f.away_team_id)
    where f.id = new.fixture_id
      and not pi.ritirato
      and (coalesce(pi.infortunato_fino_a, 0) > 0 or coalesce(pi.squalificato_fino_a, 0) > 0)
    on conflict do nothing;
  exception when others then
    raise warning 'registra_assenze_partita: assenze non registrate per la partita % (%)', new.fixture_id, sqlerrm;
  end;
  return new;
end;
$$;

create or replace function private.minutaggio_al_nuovo_contratto()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  begin
    if new.team_id is not null and new.minutaggio_promesso is null then
      new.minutaggio_promesso := private.minutaggio_alla_firma(new.league_id, new.overall_corrente, new.eta_corrente, new.player_id, new.posizioni_override);
      new.arrivo_stagione := (select l.stagione_corrente from public.leagues l where l.id = new.league_id);
    end if;
  exception when others then
    raise warning 'minutaggio_al_nuovo_contratto: promessa non assegnata al giocatore % (%)', new.id, sqlerrm;
  end;
  return new;
end;
$function$;

create or replace function private.reset_rinnovo_al_trasferimento()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if old.team_id is not null
     and new.team_id is not null
     and old.team_id is distinct from new.team_id then
    new.rinnovo_tentativi := 0;
  end if;

  -- Minutaggio (docs/decisioni-minutaggio.md §3, §5): a prova di errore.
  begin
    if old.team_id is distinct from new.team_id then
      new.richiamo_stagione := null;
      new.richiamo_giornata := null;
      new.richiesta_cessione_stagione := null;
      if new.team_id is null then
        new.minutaggio_promesso := null;
        new.arrivo_stagione := null;
      else
        new.arrivo_stagione := (select l.stagione_corrente from public.leagues l where l.id = new.league_id);
        if old.team_id is null then
          new.minutaggio_promesso := private.minutaggio_alla_firma(new.league_id, new.overall_corrente, new.eta_corrente, new.player_id, new.posizioni_override);
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'reset_rinnovo_al_trasferimento: minutaggio non aggiornato per il giocatore % (%)', new.id, sqlerrm;
  end;

  return new;
end;
$function$;

commit;
