-- Richieste dei giocatori: una risposta rimasta a meta' non e' un silenzio (segnalazione del 14/11/2026).
-- Caso vero: Jeffrey's Eleven risponde a un giocatore, la valutazione dell'AI non arriva in fondo (funzione caduta o
-- riavviata in quel momento), la risposta resta salvata e la richiesta «aperta»; l'allenatore non puo' riprovare e
-- alla scadenza il gioco lo punisce come se non avesse risposto (morale -4 e sfogo sui social).
-- Ora: 1) la scadenza punisce solo chi non ha scritto niente; 2) le risposte a meta' vengono rivalutate da sole ogni
-- minuto (azione riprendi_richiesta di conferenza-stampa); 3) se dopo un giorno dalla scadenza l'AI non ce l'ha
-- ancora fatta, la richiesta si chiude senza effetti, mai contro l'allenatore.

CREATE OR REPLACE FUNCTION private.scadi_richieste()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r record;
  v_effetto smallint;
  v_n integer := 0;
begin
  for v_r in
    select r.*, p.nome, t.user_id
    from public.richieste_giocatori r
    join public.player_instances pi on pi.id = r.player_instance_id
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = r.team_id
    -- solo chi non ha risposto davvero. Una risposta salvata ma non ancora valutata NON e' un silenzio (bug del
    -- 12/11/2026): la riprende private.rilancia_richieste_a_meta().
    where r.stato = 'aperta' and r.scade_il < now() and r.risposta is null
    for update of r skip locked
  loop
    if v_r.tipo = 'giorno_libero' then
      v_effetto := private.applica_giorno_libero(v_r.team_id, -1.5, false);
    else
      v_effetto := private.richiesta_morale_giocatore(v_r.player_instance_id, -1.5);
    end if;
    update public.richieste_giocatori set stato = 'scaduta', voto = -1.5, effetto_morale = v_effetto where id = v_r.id;

    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
    values (v_r.league_id, 'ignorata:' || v_r.id, 'giocatore', v_r.nome, v_r.team_id, v_r.player_instance_id,
      case when v_r.tipo = 'giorno_libero' then private.social_scegli('ig' || v_r.id, array[
             'Ho chiesto al mister un giorno di riposo a nome di tutto il gruppo. Nessuna risposta. Lo spogliatoio se lo ricorderà.',
             'Da capitano ho portato al mister una richiesta della squadra. Silenzio totale. Non è così che si guida un gruppo.',
             'Volevamo solo un giorno libero, lo abbiamo chiesto con rispetto. Il mister non si è nemmeno degnato di rispondere.'])
      else private.social_scegli('ig' || v_r.id, array[
             'Ho scritto al mister. Nemmeno una risposta. Evidentemente non conto niente qui. 😶',
             'Chiedere un confronto e ricevere il silenzio: questa è la considerazione che ho in questa squadra.',
             'Messaggio al mister: visualizzato e ignorato. Ne prendo atto.',
             'Non pretendevo un sì, mi bastava una risposta. Neanche quella.'])
      end, now())
    on conflict (league_id, chiave) do nothing;

    perform private.notifica(v_r.user_id, v_r.league_id, 'sistema', 'Richiesta ignorata',
      case when v_r.tipo = 'giorno_libero'
        then 'Non hai risposto al capitano ' || v_r.nome || ': morale ' || v_effetto || ' a tutta la squadra, e si è sfogato sui social.'
        else v_r.nome || ' si è sentito ignorato: morale ' || v_effetto || ', e si è sfogato sui social.' end,
      jsonb_build_object('player_instance_id', v_r.player_instance_id, 'view', 'spogliatoio'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

create or replace function private.rilancia_richieste_a_meta()
returns integer language plpgsql security definer set search_path to '' as $$
declare
  v_chiave text;
  v_id bigint;
  v_n integer := 0;
begin
  -- 3) l'AI non ce l'ha fatta per un giorno intero: si chiude senza effetti
  update public.richieste_giocatori
     set stato = 'risposta', voto = 0, effetto_morale = 0, reazione = 'Ricevuto, mister.',
         valutazione = jsonb_build_object('chiusa_senza_valutazione', true)
   where stato = 'aperta' and risposta is not null and tipo <> 'giorno_libero' and scade_il < now() - interval '1 day';

  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;
  -- 2) una alla volta, la piu' vecchia; non prima di 3 minuti dalla risposta (la valutazione normale e' ancora in corso)
  --    e non piu' di una volta ogni 3 minuti per la stessa richiesta
  select q.id into v_id
  from public.richieste_giocatori q
  where q.stato = 'aperta' and q.risposta is not null and q.risposta_il < now() - interval '3 minutes'
    and not exists (select 1 from private.risposte_claude_tentativi r
                     where r.tipo = 'riprendi' and r.rif_id = q.id and r.ultimo_il > now() - interval '3 minutes')
  order by q.risposta_il
  limit 1;
  if v_id is null then return 0; end if;
  insert into private.risposte_claude_tentativi (tipo, rif_id) values ('riprendi', v_id)
  on conflict (tipo, rif_id) do update set ultimo_il = now(), tentativi = private.risposte_claude_tentativi.tentativi + 1;
  perform net.http_post(
    url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
    body := jsonb_build_object('azione', 'riprendi_richiesta', 'richiesta_id', v_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
    timeout_milliseconds := 90000
  );
  return 1;
end $$;
revoke all on function private.rilancia_richieste_a_meta() from public, anon, authenticated;

select cron.schedule('richieste-a-meta', '* * * * *', 'select private.rilancia_richieste_a_meta();');
