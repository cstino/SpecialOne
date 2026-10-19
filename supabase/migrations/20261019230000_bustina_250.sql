-- Bustina dell'album a 250 crediti (4 al giorno con i 1.000 crediti gratis). Riscritta dalla definizione viva.
begin;
CREATE OR REPLACE FUNCTION public.album_compra_bustina(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_saldo public.casino_saldi;
  v_stag smallint;
  v_k int;
  v_r numeric;
  v_tipo text;
  v_fig public.album_figurine;
  v_ultra boolean;
  v_nuova boolean;
  v_out jsonb := '[]'::jsonb;
  c_prezzo constant int := 250;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.album_attivo(p_league_id) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  if v_saldo.crediti < c_prezzo then raise exception using errcode = '22023', message = 'Crediti insufficienti: una bustina costa 250 crediti.'; end if;
  v_stag := private.album_sincronizza(p_league_id);
  update public.casino_saldi set crediti = crediti - c_prezzo, aggiornato_il = now() where league_id = p_league_id and user_id = v_utente;

  for v_k in 1..3 loop
    v_r := random();
    v_ultra := v_r < 0.02;
    v_tipo := case when v_ultra then 'ultra' when v_r < 0.12 then 'stemma' else 'giocatore' end;
    if v_tipo = 'stemma' then
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
    elsif v_tipo = 'giocatore' then
      -- I piu' forti escono piu' di rado: peso = 100 - overall (minimo 5). Estrazione pesata con chiave esponenziale.
      select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
      order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
    else
      -- Ultrarara: un giocatore (stesso peso) oppure, nelle leghe a conferenze, una delle due conference (circa 1 ultra su 10).
      if exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
      end if;
    end if;
    if v_fig.id is null then continue; end if;
    -- Le figurine delle conference esistono solo ultrarare.
    if v_fig.tipo = 'conferenza' then v_ultra := true; end if;
    select not exists (select 1 from public.album_possesso where user_id = v_utente and figurina_id = v_fig.id and (case when v_ultra then ultra else normali end) > 0) into v_nuova;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, ultra)
    values (p_league_id, v_utente, v_fig.id, case when v_ultra then 0 else 1 end, case when v_ultra then 1 else 0 end)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + case when v_ultra then 0 else 1 end,
      ultra = public.album_possesso.ultra + case when v_ultra then 1 else 0 end;
    v_out := v_out || jsonb_build_object('figurina_id', v_fig.id, 'tipo', v_fig.tipo, 'team_id', v_fig.team_id, 'player_id', v_fig.player_id,
      'conferenza', v_fig.conferenza, 'ultra', v_ultra, 'nuova', v_nuova);
    v_fig := null;
  end loop;

  insert into public.album_bustine (league_id, user_id, contenuto) values (p_league_id, v_utente, v_out);
  return jsonb_build_object('figurine', v_out, 'premi', private.album_controlla_premi(p_league_id, v_utente, v_stag),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
commit;
