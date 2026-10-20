-- AviatOne: l'incasso a mano vale al MOMENTO DEL TOCCO (orario mandato dal telefono, allineato a quello del server),
-- non all'arrivo della richiesta. Decisione del committente (20/10/2026): gruppo di amici e crediti finti, quindi ci si
-- fida dell'orario del telefono; cosi' chi ha la connessione lenta non perde un incasso fatto in tempo.
-- Limiti tecnici: il tocco non puo' essere nel futuro (si usa l'arrivo), ne' piu' di 30 s prima dell'arrivo; deve
-- cadere tra il decollo e l'esplosione del volo. Vale anche se la richiesta arriva dopo l'esplosione o a volo finito
-- (si cerca la puntata ancora aperta dell'utente negli ultimi 3 minuti, non solo nel giro corrente).
CREATE OR REPLACE FUNCTION public.casino_av_incassa_live(p_league_id bigint, p_tocco bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid()); g public.casino_av_giri; g_corr public.casino_av_giri; q public.casino_av_giocate;
  v_ora timestamptz; v_tocco timestamptz; v_m numeric; v_incasso jsonb;
begin
  perform private.av_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));   -- prima del saldo: evita i deadlock
  g_corr := private.av_giro(p_league_id);
  -- La puntata ancora aperta piu' recente dell'utente (anche di un volo appena finito).
  select q2.* into q from public.casino_av_giocate q2 join public.casino_av_giri g2 on g2.id = q2.giro_id
   where q2.league_id = p_league_id and q2.user_id = v_utente and q2.incassato is null and g2.apre_il > clock_timestamp() - interval '3 minutes'
   order by q2.id desc limit 1;
  if q.id is not null then
    select * into g from public.casino_av_giri where id = q.giro_id;
    perform private.av_regola(g);                       -- prima gli incassi automatici gia' maturati
    select * into q from public.casino_av_giocate where id = q.id for update;
    v_ora := clock_timestamp();
    v_tocco := case when p_tocco is null then v_ora else least(to_timestamp(p_tocco / 1000.0), v_ora) end;
    if q.incassato is null and v_tocco >= v_ora - interval '30 seconds' and v_tocco >= g.parte_il and v_tocco < g.finisce_il then
      v_m := private.av_molt(extract(epoch from v_tocco - g.parte_il));
      if v_m < g.crash then
        perform private.av_paga(q.id, v_m);
        v_incasso := jsonb_build_object('giro', g.id, 'molt', v_m, 'vinto', floor(q.puntata * v_m));
      end if;
    end if;
    if p_tocco is not null then
      update public.casino_av_giocate set ritardo_ms = least(greatest(floor(extract(epoch from v_ora) * 1000) - p_tocco, -5000), 600000) where id = q.id;
    end if;
  end if;
  perform private.av_regola(g_corr);
  return private.av_live_stato(p_league_id, g_corr) || jsonb_build_object('mio_incasso', v_incasso);
end $function$;
