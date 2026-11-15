-- Sponsor: nel contratto firmato si vede quante partite restano per completarlo (richiesta del committente,
-- 15/11/2026: «dovrebbe mostrare quante giornate ho ancora a disposizione»). Il conto viene dalle partite fissate
-- alla firma (fixture_ids) non ancora giocate. Il resto della funzione e' quello vivo, riletto dal database.

CREATE OR REPLACE FUNCTION public.sponsor_stato(p_league_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_team public.teams;
  v_prossima smallint;
  v_cat text;
  v_attivi boolean := private.sponsor_attivi(p_league_id);
begin
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_utente and attiva;
  if v_team.id is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  perform pg_advisory_xact_lock(hashtext('sponsor'), v_team.id::int);
  perform private.sponsor_valuta(v_team.id, v_utente);
  if v_attivi then
    v_prossima := private.prossima_giornata_lega(p_league_id);
    -- Le offerte valgono fino alla prossima giornata: poi si rifanno sulla situazione nuova.
    update public.sponsor_contratti set stato = 'scartata', chiusa_il = now()
    where team_id = v_team.id and stato = 'offerta' and giornata_offerta < v_prossima;
    foreach v_cat in array array['breve', 'lungo'] loop
      if not exists (select 1 from public.sponsor_contratti where team_id = v_team.id and categoria = v_cat and stato in ('offerta', 'attiva'))
         and not exists (select 1 from public.sponsor_contratti where team_id = v_team.id and categoria = v_cat and stato = 'rinunciata'
                           and chiusa_il > now() - interval '24 hours') then
        perform private.sponsor_genera(v_team.id, v_cat);
      end if;
    end loop;
  end if;
  return jsonb_build_object(
    'attivi', v_attivi,
    'contratti', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'categoria', c.categoria, 'tipo', c.tipo, 'titolo', c.titolo, 'descrizione', c.descrizione,
        'premio', c.premio, 'effetto_tifo', c.effetto_tifo, 'partite', c.partite, 'stato', c.stato, 'progresso', c.progresso,
        'scelta_il', c.scelta_il, 'chiusa_il', c.chiusa_il,
        -- quante partite del contratto restano da giocare (solo per quelli firmati: le partite sono gia' fissate)
        'restano', case when c.stato = 'attiva' and c.fixture_ids is not null then (select count(*) from public.fixtures f where f.id = any(c.fixture_ids) and f.stato <> 'simulata') end,
        'azienda', jsonb_build_object('nome', a.nome, 'slug', a.slug, 'colore', a.colore))
        order by c.id desc)
      from public.sponsor_contratti c join public.sponsor_aziende a on a.id = c.azienda_id
      where c.team_id = v_team.id and (c.stato in ('offerta', 'attiva') or (c.stato in ('completata', 'fallita', 'rinunciata') and c.chiusa_il > now() - interval '14 days'))), '[]'::jsonb),
    'pausa', (select jsonb_object_agg(c.categoria, c.chiusa_il + interval '24 hours') from public.sponsor_contratti c
              where c.team_id = v_team.id and c.stato = 'rinunciata' and c.chiusa_il > now() - interval '24 hours'),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end;
$function$;
