-- Segnalazione al proprietario del gioco di un'anomalia trovata dalla simulazione (27/10/2026): per ora la usa il
-- controllo finale della cronaca in simula-giornata (cronaca che non coincide con il motore, corretta prima del
-- salvataggio). Notifica senza lega, visibile nella campanella del proprietario. Solo il server puo' chiamarla.
create or replace function public.segnala_anomalia(p_titolo text, p_corpo text, p_dati jsonb default '{}'::jsonb)
 returns bigint language plpgsql volatile security definer set search_path to ''
as $function$
declare v_utente uuid;
begin
  select id into v_utente from auth.users where email = 'cr.96bc@gmail.com';
  if v_utente is null then return null; end if;
  return private.notifica(v_utente, null, 'sistema', coalesce(nullif(btrim(p_titolo), ''), 'Anomalia'), p_corpo, coalesce(p_dati, '{}'::jsonb));
end $function$;
revoke all on function public.segnala_anomalia(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.segnala_anomalia(text, text, jsonb) to service_role;
