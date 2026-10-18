-- Atletico Neurale (Claude): spende i punti abilita' quando arrivano. Regola semplice e ripetibile: va al ramo con il
-- livello piu' basso (a parita': medico, poi training, poi vivaio), fino al massimo. Chiama la stessa funzione di tutti
-- (spendi_punto_abilita) con l'identita' dell'utente della squadra, e scrive in azioni_claude.
begin;

create or replace function private.claude_spendi_punti()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_t record;
  v_r public.team_risorse;
  v_ramo text;
  v_n integer := 0;
  v_guardia integer;
begin
  for v_t in select t.id, t.league_id, t.user_id from public.teams t where t.gestita_da_claude and t.user_id is not null loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_t.user_id, 'role', 'authenticated')::text, true);
    v_guardia := 0;
    loop
      v_guardia := v_guardia + 1;
      exit when v_guardia > 20;
      select * into v_r from public.team_risorse where team_id = v_t.id;
      exit when not found or v_r.livello_vivaio + v_r.livello_training + v_r.livello_medico >= v_r.punti_ricevuti;
      v_ramo := (select r from (values ('medico', v_r.livello_medico, 1), ('training', v_r.livello_training, 2), ('vivaio', v_r.livello_vivaio, 3)) x(r, lv, pr)
                  where lv < private.livello_ramo_massimo() order by lv, pr limit 1);
      exit when v_ramo is null;
      perform public.spendi_punto_abilita(v_t.id, v_ramo);
      insert into public.azioni_claude (league_id, team_id, tipo, dettaglio)
      values (v_t.league_id, v_t.id, 'risorse', jsonb_build_object('ramo', v_ramo, 'dopo', (select jsonb_build_object('vivaio', livello_vivaio, 'training', livello_training, 'medico', livello_medico) from public.team_risorse where team_id = v_t.id)));
      v_n := v_n + 1;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  return v_n;
end $f$;

select cron.schedule('claude-risorse', '7 * * * *', 'select private.claude_spendi_punti();');

commit;
