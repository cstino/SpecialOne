-- AviatOne: misura del ritardo tra il tocco su INCASSA e l'arrivo della richiesta al server (lamentele di incassi
-- "fatti dopo qualche secondo"). Solo diagnostica, non cambia il pagamento.
alter table public.casino_av_giocate add column if not exists ritardo_ms integer;
drop function if exists public.casino_av_incassa_live(bigint);
CREATE OR REPLACE FUNCTION public.casino_av_incassa_live(p_league_id bigint, p_tocco bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); g public.casino_av_giri; q public.casino_av_giocate; v_ora timestamptz; v_m numeric;
begin
  perform private.av_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));   -- prima del saldo: evita i deadlock
  g := private.av_giro(p_league_id);
  perform private.av_regola(g);
  v_ora := clock_timestamp();
  select * into q from public.casino_av_giocate where giro_id = g.id and user_id = v_utente and incassato is null for update;
  if q.id is not null and v_ora >= g.parte_il and v_ora < g.finisce_il then
    v_m := private.av_molt(extract(epoch from v_ora - g.parte_il));
    if v_m < g.crash then perform private.av_paga(q.id, v_m); end if;
  end if;
  -- Solo diagnostica: quanto tempo e' passato tra il tocco sul telefono (orologio allineato al server) e l'arrivo qui.
  -- Il pagamento usa SEMPRE l'orario di arrivo: fidarsi dell'orario del telefono permetterebbe di barare.
  if q.id is not null and p_tocco is not null then
    update public.casino_av_giocate set ritardo_ms = least(greatest(floor(extract(epoch from v_ora) * 1000) - p_tocco, -5000), 600000) where id = q.id;
  end if;
  return private.av_live_stato(p_league_id, g);
end $function$;
revoke all on function public.casino_av_incassa_live(bigint, bigint) from public, anon;
grant execute on function public.casino_av_incassa_live(bigint, bigint) to authenticated;
