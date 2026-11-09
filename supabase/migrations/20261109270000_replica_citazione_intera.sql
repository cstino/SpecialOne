-- Sala stampa (richiesta del committente, 9/11/2026): la domanda di replica a chi viene citato riporta la risposta
-- INTERA dell'altra squadra. Prima si tagliava a 220 caratteri per stare sotto il limite della domanda (600), e chi
-- doveva replicare spesso non sapeva cosa gli avessero detto. Il limite della domanda sale a 1.600: la risposta
-- citata arriva al massimo a 1.200 caratteri, la frase del giornalista intorno a un centinaio. Le repliche ancora senza
-- risposta si ricompongono con la citazione completa, presa dalla risposta originale.

begin;

alter table public.conferenze_domande drop constraint conferenze_domande_domanda_check;
alter table public.conferenze_domande add constraint conferenze_domande_domanda_check
  check (char_length(domanda) >= 1 and char_length(domanda) <= 1600);

CREATE OR REPLACE FUNCTION public.applica_rivalita(p_domanda_id bigint, p_squadre jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_d public.conferenze_domande;
  v_s record;
  v_delta numeric;
  v_grado numeric;
  v_out jsonb := '[]'::jsonb;
  v_target public.teams;
  v_match bigint;
  v_attaccante text;
  v_tipo_squadra text;
begin
  select * into v_d from public.conferenze_domande where id = p_domanda_id;
  if not found then raise exception 'Domanda % inesistente.', p_domanda_id; end if;
  select coalesce(nullif(btrim(pr.nome_allenatore), ''), t.nome), t.nome into v_attaccante, v_tipo_squadra
    from public.teams t left join public.profiles pr on pr.user_id = t.user_id where t.id = v_d.team_id;

  for v_s in
    select (x->>'team_id')::bigint as team_id, x->>'direzione' as direzione
    from jsonb_array_elements(coalesce(p_squadre, '[]'::jsonb)) x
  loop
    continue when v_s.team_id = v_d.team_id;
    select * into v_target from public.teams where id = v_s.team_id and league_id = v_d.league_id;
    continue when not found;
    v_delta := case v_s.direzione when 'attacco' then 10 when 'elogio' then -6 else 0 end;
    continue when v_delta = 0;
    v_grado := private.sposta_rivalita(v_d.league_id, v_d.team_id, v_s.team_id, v_delta);
    v_out := v_out || jsonb_build_object('team_id', v_s.team_id, 'nome', v_target.nome, 'delta', v_delta, 'grado', v_grado);

    -- Diritto di replica: solo se attaccato e umano.
    if v_delta > 0 and v_target.user_id is not null and not v_target.controllata_da_pc then
      select m.id into v_match
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      where f.league_id = v_d.league_id and v_s.team_id in (f.home_team_id, f.away_team_id)
      order by m.simulata_il desc limit 1;
      if v_match is not null then
        insert into public.conferenze_domande (league_id, match_id, team_id, ordine, giornalista, domanda)
        values (v_d.league_id, v_match, v_s.team_id, 3,
                private.social_scegli('replica' || p_domanda_id || v_s.team_id, array['Sky Sport 24', 'Radio 24', 'Sport Mediaset', 'Corriere dello Sport', 'Rai Sport', 'Tuttosport']),
                'Mister, ' || v_attaccante || ' (' || v_tipo_squadra || ') ha parlato della vostra squadra: «' || coalesce(v_d.risposta, '') || '». Cosa risponde?')
        on conflict (match_id, team_id, ordine) do nothing;
        if found then
          perform private.notifica(v_target.user_id, v_d.league_id, 'sistema', 'Diritto di replica',
            v_attaccante || ' ha parlato di te in conferenza: i giornalisti vogliono la tua risposta.',
            jsonb_build_object('conferenza_match_id', v_match, 'view', 'salastampa'));
        end if;
      end if;
    end if;
  end loop;
  return v_out;
end;
$function$;

update public.conferenze_domande r
set domanda = substring(r.domanda from '^(.*?: «)') || o.risposta || '». Cosa risponde?'
from public.conferenze_domande o
where r.risposta is null
  and r.domanda like 'Mister, % ha parlato della vostra squadra: «%…». Cosa risponde?'
  and o.league_id = r.league_id and o.risposta is not null and o.id <> r.id
  and left(o.risposta, 220) = substring(r.domanda from '«(.*)…». Cosa risponde\?$');

commit;
