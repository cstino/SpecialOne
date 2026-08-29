-- ============================================================
--  ADMIN: FORZA ESTRAZIONE MERCATO A SCELTE
--  Deciso il 29 agosto 2026, in conversazione con l'utente.
--
--  L'istante di estrazione di una finestra ON-Season e' calcolato una
--  volta sola, alla creazione della stagione, dalla data di calendario
--  gia' assegnata alla giornata di meta' stagione (una giornata al
--  giorno, il ritmo del cron notturno — docs/decisioni-draft-picks.md
--  §3.1). Chi usa il bottone admin "Simula giornata" per avanzare
--  velocemente gioca tutta la stagione in poco tempo reale, ma quella
--  data resta quella originale: la finestra ON-Season resta "Pronta"
--  ben oltre la fine della stagione simulata, finche' non arriva
--  davvero quel giorno di calendario.
--
--  Non e' un bug della logica di gioco (per il ritmo normale, una
--  giornata a notte, i tempi combaciano): e' un attrito fra la
--  simulazione veloce e un istante di estrazione pre-calcolato. Questa
--  RPC lascia all'admin la stessa scelta che gia' ha per le tre azioni
--  di riserva del cron (simula giornata, apri/chiudi mercato): un modo
--  per far succedere subito quello che il cron farebbe comunque,
--  quando serve testare senza aspettare il calendario reale.
--
--  Risolve solo finestre con estrazione_il gia' fissato (le ON-Season):
--  le OFF-Season si risolvono alla chiusura dell'off-season
--  (finalizza_offseason, legata a offseasons.scade_il), un meccanismo
--  diverso che questa funzione non tocca.
-- ============================================================

create or replace function public.admin_forza_estrazione_scelte(p_league_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente   uuid := (select auth.uid());
  v_lega     public.leagues;
  v_finestra record;
  v_risolte  jsonb := '[]'::jsonb;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il pannello admin.';
  end if;

  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega inesistente.';
  end if;
  if v_lega.admin_id <> v_utente then
    raise exception using errcode = '42501', message = 'Solo l''amministratore della lega puo'' forzare un''estrazione.';
  end if;

  for v_finestra in
    select league_id, stagione, finestra
    from public.finestre_scelte
    where league_id = p_league_id and risolta_il is null and estrazione_il is not null
    order by stagione, finestra
  loop
    perform private.risolvi_finestra_scelte(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, true);

    -- Stessa catena dell'automazione normale (avanza_finestre_scelte):
    -- risolta la ON-Season, si svela subito la OFF-Season della stessa
    -- stagione, se non l'ha gia' fatto qualcun altro nel frattempo.
    if v_finestra.finestra = 'on' and not exists (
      select 1 from public.finestre_scelte
      where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
    ) then
      perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
    end if;

    v_risolte := v_risolte || jsonb_build_object('stagione', v_finestra.stagione, 'finestra', v_finestra.finestra);
  end loop;

  return jsonb_build_object('risolte', v_risolte, 'numero', jsonb_array_length(v_risolte));
end;
$$;

comment on function public.admin_forza_estrazione_scelte(bigint) is
  'Solo admin: risolve subito ogni finestra ON-Season in sospeso della lega, ignorando la data di estrazione — per testare senza aspettare il calendario reale dopo una simulazione veloce.';

revoke all on function public.admin_forza_estrazione_scelte(bigint) from public, anon;
grant execute on function public.admin_forza_estrazione_scelte(bigint) to authenticated;
