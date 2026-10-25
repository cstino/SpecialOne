-- Sala stampa: una risposta rimasta senza giudizio si libera da sola (25/10/2026). Il giudizio dell'AI si fa dentro la
-- richiesta dell'allenatore; se l'AI non risponde la funzione libera gia' la risposta (riprova), ma se la richiesta viene
-- interrotta a meta' (es. riavvio delle funzioni) la risposta restava salvata senza voto e la card diceva per sempre
-- "La sala stampa sta ascoltando…" (Popolo Della Gaina, 21/10). Dopo 5 minuti senza giudizio la risposta si libera:
-- se la domanda e' ancora aperta l'allenatore puo' rispondere di nuovo, se e' scaduta resta "no comment" (nessun effetto).
create or replace function private.libera_risposte_bloccate()
 returns integer language plpgsql volatile security definer set search_path to ''
as $function$
declare v_n integer;
begin
  update public.conferenze_domande set risposta = null, risposta_il = null
   where risposta is not null and voto is null and risposta_il < now() - interval '5 minutes';
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

select cron.schedule('conferenze_libera_bloccate', '* * * * *', 'select private.libera_risposte_bloccate();');
