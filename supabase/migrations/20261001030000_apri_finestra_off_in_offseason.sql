-- ============================================================
--  MERCATO A SCELTE: LA FINESTRA OFF-SEASON SI APRE CON L'OFF-SEASON
--
--  La OFF-Season X veniva aperta solo alla chiusura della ON-Season X, a meta'
--  stagione: in quel momento l'ordine di scelta non esiste ancora (lo decidono
--  i playoff), svela_finestra_scelte rifiuta e nessuno riprovava piu'. In
--  LegaBot le OFF delle stagioni 2 e 3 erano state recuperate a mano e la 4 non
--  e' mai nata.
--
--  Ora, quando una lega passa a fase_carriera = 'offseason' (prepara_offseason
--  fissa anche offseason_fine), un trigger:
--    1. riprova l'ordine dai playoff (idempotente: esce se gia' assegnato), in
--       caso l'assegnazione a fine tabellone fosse fallita;
--    2. svela la finestra OFF della stagione appena giocata, con estrazione
--       alla scadenza dell'off-season (svela_finestra_scelte la ricava da
--       offseason_fine).
--  Ognuno in un blocco suo: un fallimento qui non deve mai impedire
--  l'apertura dell'off-season.
-- ============================================================

create or replace function private.apri_finestra_off_in_offseason()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform private.assegna_posizioni_playoff(new.id, new.stagione_corrente);
  exception when others then
    raise warning 'mercato a scelte: ordine dai playoff non assegnato per lega % stagione %: % (%)',
      new.id, new.stagione_corrente, sqlerrm, sqlstate;
  end;

  begin
    if not exists (
      select 1 from public.finestre_scelte
      where league_id = new.id and stagione = new.stagione_corrente and finestra = 'off'
    ) then
      perform private.svela_finestra_scelte(new.id, new.stagione_corrente, 'off');
    end if;
  exception when others then
    raise warning 'mercato a scelte: OFF di lega % stagione % non apribile in off-season: % (%)',
      new.id, new.stagione_corrente, sqlerrm, sqlstate;
  end;

  return null;
end;
$$;

drop trigger if exists leagues_apri_finestra_off on public.leagues;
create trigger leagues_apri_finestra_off
  after update of fase_carriera on public.leagues
  for each row
  when (new.fase_carriera = 'offseason' and old.fase_carriera is distinct from 'offseason')
  execute function private.apri_finestra_off_in_offseason();

-- LegaBot e' gia' in off-season (stagione 4): si recupera qui.
do $$
declare
  v_lega public.leagues;
begin
  for v_lega in select * from public.leagues where fase_carriera = 'offseason' and offseason_fine > now() loop
    begin
      perform private.assegna_posizioni_playoff(v_lega.id, v_lega.stagione_corrente);
    exception when others then
      raise warning 'recupero ordine lega %: % (%)', v_lega.id, sqlerrm, sqlstate;
    end;
    begin
      if not exists (
        select 1 from public.finestre_scelte
        where league_id = v_lega.id and stagione = v_lega.stagione_corrente and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(v_lega.id, v_lega.stagione_corrente, 'off');
      end if;
    exception when others then
      raise warning 'recupero OFF lega %: % (%)', v_lega.id, sqlerrm, sqlstate;
    end;
  end loop;
end;
$$;
