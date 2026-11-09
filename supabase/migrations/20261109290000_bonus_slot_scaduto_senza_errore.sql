-- SlotOne, minigiochi (9/11/2026): una mossa arrivata dopo i 3 minuti (bonus gia' giocato da solo) non da' piu'
-- errore ("Something went wrong" sullo schermo) ma restituisce il bonus finito con 'scaduto': la finestra lo mostra.

CREATE OR REPLACE FUNCTION public.casino_slot_bonus_gioca(p_league_id bigint, p_bonus_id bigint, p_mossa integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid()); b public.casino_slot_bonus; v_n int; v_gol boolean; v_fine boolean := false;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  perform private.casino_saldo(p_league_id, v_utente);          -- blocca il saldo (stesso ordine di tutti)
  select * into b from public.casino_slot_bonus where id = p_bonus_id and league_id = p_league_id and user_id = v_utente for update;
  if b.id is null then raise exception using errcode = '42501', message = 'Minigioco non trovato.'; end if;
  -- tempo scaduto (chiuso adesso o gia' dal cron): niente errore, si restituisce il bonus finito con 'scaduto' e la
  -- finestra mostra com'e' andata
  if b.stato = 'aperto' and now() > b.scade_il then perform private.casino_bonus_chiudi(b.id, true); b.stato := 'finito'; end if;
  if b.stato <> 'aperto' then
    return jsonb_build_object('bonus', private.casino_bonus_json(b.id), 'scaduto', true, 'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
  end if;
  v_n := jsonb_array_length(b.mosse);
  if b.tipo = 'stemma' then
    if p_mossa is null or p_mossa not between 0 and 8 then raise exception using errcode = '22023', message = 'Scudo non valido.'; end if;
    if exists (select 1 from jsonb_array_elements(b.mosse) m where (m ->> 'i')::int = p_mossa) then raise exception using errcode = '22023', message = 'Hai già scelto questo scudo.'; end if;
    update public.casino_slot_bonus set mosse = b.mosse || jsonb_build_object('i', p_mossa, 'v', (b.segreto -> 'valori' ->> p_mossa)::int) where id = b.id;
    v_fine := v_n + 1 >= 3;
  else
    if p_mossa is null or p_mossa not between 0 and 2 then raise exception using errcode = '22023', message = 'Zona non valida.'; end if;
    v_gol := (b.segreto -> 'gol' ->> v_n)::boolean;
    update public.casino_slot_bonus set mosse = b.mosse || jsonb_build_object('zona', p_mossa, 'gol', v_gol,
        'portiere', case when v_gol then (p_mossa + 1 + floor(random() * 2)::int) % 3 else p_mossa end) where id = b.id;
    v_fine := (not v_gol) or v_n + 1 >= 5;
  end if;
  if v_fine then perform private.casino_bonus_chiudi(b.id); end if;
  return jsonb_build_object('bonus', private.casino_bonus_json(b.id),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
