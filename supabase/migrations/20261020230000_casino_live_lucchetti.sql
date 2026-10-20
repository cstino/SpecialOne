-- Casino' live: niente piu' "ingorghi" (deadlock) e un secondo di tolleranza sulle scelte dei bonus.
-- 1) Le funzioni pubbliche di AviatOne e CrazyOne prendevano prima il lucchetto del saldo del giocatore e poi quello
--    della lega; chi teneva quello della lega e pagava un incasso automatico o un bonus aspettava il saldo -> deadlock,
--    una richiesta annullata (errore 500 sul telefono). Ora il lucchetto della lega si prende per primo, sempre.
-- 2) Caccia allo Stemma / CrazyOne: le scelte arrivate fino a 1 s dopo la scadenza (ritardo di rete) valgono; per non
--    dare vantaggi, posizioni e rotazioni si rivelano e il giro si paga solo dopo quel secondo.

CREATE OR REPLACE FUNCTION public.casino_av_live(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g public.casino_av_giri;
begin
  perform private.av_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));   -- prima del saldo: evita i deadlock
  perform private.casino_saldo(p_league_id, (select auth.uid()));
  g := private.av_giro(p_league_id);
  perform private.av_regola(g);
  return private.av_live_stato(p_league_id, g);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_av_punta(p_league_id bigint, p_puntata integer, p_auto numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_av_giri;
begin
  perform private.av_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));   -- prima del saldo: evita i deadlock
  v := private.casino_saldo(p_league_id, v_utente);
  g := private.av_giro(p_league_id);
  if clock_timestamp() >= g.parte_il then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo volo.'; end if;
  if p_puntata is null or p_puntata < 10 or p_puntata > 500 or p_puntata % 10 <> 0 then raise exception using errcode = '22023', message = 'Puntata non valida (da 10 a 500).'; end if;
  if p_auto is not null and (p_auto < 1.1 or p_auto > 1000) then raise exception using errcode = '22023', message = 'Incasso automatico non valido (da 1,10× a 1000×).'; end if;
  if exists (select 1 from public.casino_av_giocate where giro_id = g.id and user_id = v_utente) then
    raise exception using errcode = '55000', message = 'Hai già puntato su questo volo.';
  end if;
  if v.crediti < p_puntata then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti - p_puntata, giri = giri + 1, aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;
  insert into public.casino_av_giocate (giro_id, league_id, user_id, team_id, puntata, auto)
  values (g.id, p_league_id, v_utente, v.team_id, p_puntata, round(p_auto, 2));
  return private.av_live_stato(p_league_id, g);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_av_ritira(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); g public.casino_av_giri; q public.casino_av_giocate;
begin
  perform private.av_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('aviatone:' || p_league_id));   -- prima del saldo: evita i deadlock
  g := private.av_giro(p_league_id);
  if clock_timestamp() < g.parte_il then
    delete from public.casino_av_giocate where giro_id = g.id and user_id = v_utente returning * into q;
    if q.id is not null then
      update public.casino_saldi set crediti = crediti + q.puntata, giri = greatest(0, giri - 1), aggiornato_il = now()
       where league_id = p_league_id and user_id = v_utente;
    end if;
  end if;
  return private.av_live_stato(p_league_id, g);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_av_incassa_live(p_league_id bigint)
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
  return private.av_live_stato(p_league_id, g);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_ctl_live(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g public.casino_ctl_giri; v_prec bigint;
begin
  perform private.ctl_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('crazyone:' || p_league_id));   -- prima del saldo: evita i deadlock
  perform private.casino_saldo(p_league_id, (select auth.uid()));
  -- Il giro precedente si regola anche se nessuno era collegato al momento giusto.
  for v_prec in select id from public.casino_ctl_giri where league_id = p_league_id and not regolato
                  and coalesce(scelta_fine_il, esito_il) <= clock_timestamp() order by id loop
    perform private.ctl_regola(v_prec);
  end loop;
  g := private.ctl_giro(p_league_id);
  perform private.ctl_regola(g.id);
  return private.ctl_stato(p_league_id, g.id);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_ctl_punta(p_league_id bigint, p_puntate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid()); v public.casino_saldi; g public.casino_ctl_giri; q public.casino_ctl_giocate;
  c_caselle constant text[] := array['1','2','5','10','cf','pa','ch','ct'];
  v_k text; v_p int; v_tot int := 0; v_mappa jsonb := '{}'::jsonb; v_vecchio int := 0;
begin
  perform private.ctl_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('crazyone:' || p_league_id));   -- prima del saldo: evita i deadlock
  v := private.casino_saldo(p_league_id, v_utente);
  g := private.ctl_giro(p_league_id);
  if clock_timestamp() >= g.chiude_il then raise exception using errcode = '55000', message = 'Puntate chiuse: aspetta il prossimo giro.'; end if;
  for v_k, v_p in select key, (value #>> '{}')::int from jsonb_each(coalesce(p_puntate, '{}'::jsonb)) loop
    if not (v_k = any(c_caselle)) or v_p < 0 or v_p % 10 <> 0 or v_p > 500 then raise exception using errcode = '22023', message = 'Puntata non valida.'; end if;
    if v_p > 0 then v_mappa := v_mappa || jsonb_build_object(v_k, v_p); v_tot := v_tot + v_p; end if;
  end loop;
  if v_tot > 2000 then raise exception using errcode = '22023', message = 'Al massimo 2.000 crediti a giro.'; end if;
  select * into q from public.casino_ctl_giocate where giro_id = g.id and user_id = v_utente for update;
  if q.id is not null then v_vecchio := q.totale; end if;
  if v.crediti + v_vecchio < v_tot then raise exception using errcode = '22023', message = 'Crediti insufficienti: arrivano 1.000 crediti nuovi ogni giorno.'; end if;
  update public.casino_saldi set crediti = crediti + v_vecchio - v_tot,
         giri = giri + (case when q.id is null and v_tot > 0 then 1 when q.id is not null and v_tot = 0 then -1 else 0 end), aggiornato_il = now()
   where league_id = p_league_id and user_id = v_utente;
  if v_tot = 0 then
    delete from public.casino_ctl_giocate where id = q.id;
  elsif q.id is null then
    insert into public.casino_ctl_giocate (giro_id, league_id, user_id, team_id, puntate, totale) values (g.id, p_league_id, v_utente, v.team_id, v_mappa, v_tot);
  else
    update public.casino_ctl_giocate set puntate = v_mappa, totale = v_tot where id = q.id;
  end if;
  return private.ctl_stato(p_league_id, g.id);
end $function$;

CREATE OR REPLACE FUNCTION public.casino_ctl_scegli(p_league_id bigint, p_scelta integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_utente uuid := (select auth.uid()); g public.casino_ctl_giri; v_ora timestamptz := clock_timestamp();
begin
  perform private.ctl_attivo(p_league_id);
  perform pg_advisory_xact_lock(hashtext('crazyone:' || p_league_id));
  g := private.ctl_giro(p_league_id);
  if g.esito not in ('ch', 'ct') or v_ora < g.esito_il or v_ora >= g.scelta_fine_il + interval '1 second' then
    raise exception using errcode = '55000', message = 'Non è il momento di scegliere.';
  end if;
  if p_scelta is null or p_scelta < 0 or p_scelta > (case g.esito when 'ch' then 107 else 2 end) then
    raise exception using errcode = '22023', message = 'Scelta non valida.';
  end if;
  update public.casino_ctl_giocate set scelta = p_scelta, scelta_auto = false
   where giro_id = g.id and user_id = v_utente and coalesce((puntate ->> g.esito)::int, 0) > 0;
  if not found then raise exception using errcode = '55000', message = 'Non hai puntato su questo bonus.'; end if;
  return private.ctl_stato(p_league_id, g.id);
end $function$;

CREATE OR REPLACE FUNCTION private.ctl_stato(p_league_id bigint, p_giro bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g public.casino_ctl_giri; v_ora timestamptz := clock_timestamp(); v_giro jsonb;
begin
  select * into g from public.casino_ctl_giri where id = p_giro;
  v_giro := jsonb_build_object('id', g.id,
    'apre', floor(extract(epoch from g.apre_il) * 1000), 'chiude', floor(extract(epoch from g.chiude_il) * 1000),
    'esito_il', floor(extract(epoch from g.esito_il) * 1000), 'fine', floor(extract(epoch from g.fine_il) * 1000),
    'scelta_fine', case when g.scelta_fine_il is not null then floor(extract(epoch from g.scelta_fine_il) * 1000) end,
    'regolato', g.regolato);
  if v_ora >= g.chiude_il then
    v_giro := v_giro || jsonb_build_object('top_casella', g.top_casella, 'top_molt', g.top_molt, 'spicchio', g.spicchio, 'esito', g.esito);
  end if;
  if v_ora >= g.esito_il then
    if g.esito in ('cf', 'pa') then v_giro := v_giro || jsonb_build_object('bonus', g.bonus); end if;
    if g.esito = 'ch' then
      v_giro := v_giro || jsonb_build_object('valori', (select jsonb_agg(x::int order by x::int) from jsonb_array_elements_text(g.bonus -> 'tavola') x));
      if v_ora >= g.scelta_fine_il + interval '1 second' then v_giro := v_giro || jsonb_build_object('tavola', g.bonus -> 'tavola'); end if;
    end if;
    if g.esito = 'ct' then
      v_giro := v_giro || jsonb_build_object('ruota', g.bonus -> 'ruota');
      if v_ora >= g.scelta_fine_il + interval '1 second' then v_giro := v_giro || jsonb_build_object('rotazioni', g.bonus -> 'rotazioni'); end if;
    end if;
  end if;
  return jsonb_build_object(
    'adesso', floor(extract(epoch from v_ora) * 1000),
    'giro', v_giro,
    'giocate', coalesce((select jsonb_agg(jsonb_build_object('team_id', q.team_id, 'totale', q.totale, 'mia', q.user_id = (select auth.uid()),
                          'vinto', case when g.regolato then q.vinto end,
                          'puntate', case when q.user_id = (select auth.uid()) then q.puntate end,
                          'scelta', case when q.user_id = (select auth.uid()) or g.regolato then q.scelta end,
                          'scelta_auto', q.scelta_auto) order by q.totale desc, q.id)
                        from public.casino_ctl_giocate q where q.giro_id = g.id), '[]'::jsonb),
    'crediti', (select s.crediti from public.casino_saldi s where s.league_id = p_league_id and s.user_id = (select auth.uid())),
    'storia', coalesce((select jsonb_agg(x.esito order by x.id desc) from (select id, esito from public.casino_ctl_giri
                         where league_id = p_league_id and esito_il <= v_ora order by id desc limit 14) x), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.ctl_regola(p_giro bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  g public.casino_ctl_giri; q public.casino_ctl_giocate; v_p int; v_m int; v_b int; v_vinto bigint; v_scelta int; v_nome text;
  v_ruota int[]; v_rot int[];
begin
  select * into g from public.casino_ctl_giri where id = p_giro for update;
  if g.regolato or clock_timestamp() < coalesce(g.scelta_fine_il + interval '1 second', g.esito_il) then return; end if;
  if g.esito = 'ct' then
    v_ruota := array(select x::int from jsonb_array_elements_text(g.bonus -> 'ruota') x);
    v_rot := array(select x::int from jsonb_array_elements_text(g.bonus -> 'rotazioni') x);
  end if;
  for q in select * from public.casino_ctl_giocate where giro_id = g.id for update loop
    v_p := coalesce((q.puntate ->> g.esito)::int, 0);
    v_vinto := 0;
    if v_p > 0 then
      v_m := case when g.top_casella = g.esito then g.top_molt else 1 end;
      if g.esito in ('1', '2', '5', '10') then
        v_vinto := v_p::bigint * g.esito::int * v_m + v_p;
      elsif g.esito in ('cf', 'pa') then
        v_vinto := v_p::bigint * least((g.bonus ->> 'valore')::int * v_m, 2500) + v_p;
      else
        v_scelta := q.scelta;
        if v_scelta is null then
          v_scelta := case when g.esito = 'ch' then floor(random() * 108)::int else floor(random() * 3)::int end;
          update public.casino_ctl_giocate set scelta = v_scelta, scelta_auto = true where id = q.id;
        end if;
        v_b := case when g.esito = 'ch' then (g.bonus -> 'tavola' ->> v_scelta)::int
                    else (private.ct_cammino_crazy(v_ruota, v_rot, v_scelta) ->> 'valore')::int end;
        v_vinto := v_p::bigint * least(v_b * v_m, 2500) + v_p;
      end if;
    end if;
    if v_vinto > 0 then
      update public.casino_ctl_giocate set vinto = v_vinto where id = q.id;
      update public.casino_saldi set crediti = crediti + v_vinto, totale_vinto = totale_vinto + v_vinto,
             max_vincita = greatest(max_vincita, v_vinto), aggiornato_il = now()
       where league_id = q.league_id and user_id = q.user_id;
      if v_vinto >= 1000 and v_vinto >= 100 * q.totale then
        select nome into v_nome from public.teams where id = q.team_id;
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
        values (q.league_id, 'crazyone-live:' || q.id, 'lega', 'BetOne Casinò', q.team_id,
                '🎡 CRAZYONE! ' || v_nome || ' vince ' || to_char(v_vinto, 'FM999G999G999') || ' crediti con un solo giro di ruota 🤑', now())
        on conflict do nothing;
      end if;
    end if;
  end loop;
  update public.casino_ctl_giri set regolato = true where id = g.id;
end $function$;
