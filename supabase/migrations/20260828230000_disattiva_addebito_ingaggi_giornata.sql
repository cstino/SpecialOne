-- ============================================================
--  URGENTE: DISATTIVA IL PAGAMENTO RATEALE NOTTURNO
--  docs/decisioni-economia.md §4 ("pagamento rateale degli stipendi" e'
--  tra le cose da rimuovere al passo 6) — anticipato perche' e' diventato
--  bloccante in produzione, non per scelta di programmazione.
--
--  Il cron simula-giornata-notturna (ogni minuto) chiama
--  addebita_ingaggi_giornata dentro la Edge Function simula-giornata.
--  Quella funzione sottrae la quota giornaliera da teams.budget senza
--  protezione, e teams.budget ha vincolo >= 0.
--
--  Dal passo 3a in poi aste/rinnovi/scambi/scelte non muovono piu' cassa:
--  budget_ingaggi_riservato e' rimasto a 0 per quasi tutte le squadre.
--  La funzione notturna pero' e' rimasta quella vecchia, e continua a
--  provare a scalare la quota dal budget reale per OGNI giocatore in
--  rosa, incluso quelli il cui ingaggio non ha mai versato un euro in
--  quel budget. Su LegaBot, stagione 2, 7 squadre su 8 andrebbero sotto
--  zero con la quota della giornata 1 (verificato: Accademia 1908 a
--  -3.040.277, tutte le altre fra -900k e -1,7M, solo Cocacolers resta
--  positiva). La UPDATE viola il constraint, l'intera transazione della
--  Edge Function fallisce, risponde 500, e il cron ritenta da capo ogni
--  minuto senza mai riuscire — verificato in net._http_response: 360
--  tentativi su 360 falliti dalle 23:55 UTC del 27 agosto.
--
--  Diventa un no-op: nessun addebito, nessuna riga in transactions,
--  ritorna sempre 0. Il controllo sulla giornata completa resta, perche'
--  non ha nulla a che fare con la cassa ed e' comunque un prerequisito
--  sensato prima di chiudere la giornata.
-- ============================================================

create or replace function public.addebita_ingaggi_giornata(
  p_league_id bigint,
  p_giornata integer
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.fixtures
    where league_id = p_league_id and giornata = p_giornata and stato <> 'simulata'
  ) then
    raise exception using errcode = '55000', message = 'Non tutte le partite della giornata sono state simulate.';
  end if;

  return 0;
end;
$$;

comment on function public.addebita_ingaggi_giornata(bigint, integer) is
  'Disattivata (docs/decisioni-economia.md §4): il pagamento rateale non esiste piu'' sotto il tetto salariale. No-op mantenuto per compatibilita'' con la Edge Function simula-giornata, che la chiama ogni notte.';

revoke all on function public.addebita_ingaggi_giornata(bigint, integer) from public, anon, authenticated;
grant execute on function public.addebita_ingaggi_giornata(bigint, integer) to service_role;
