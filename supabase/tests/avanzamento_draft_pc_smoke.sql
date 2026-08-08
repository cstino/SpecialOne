begin;

do $$
declare
  v_league_id bigint;
  v_user_id uuid;
  v_righe integer;
  v_visibili integer;
begin
  select l.id, t.user_id into v_league_id, v_user_id
  from public.leagues l
  join public.teams t on t.league_id = l.id and not t.controllata_da_pc and t.user_id is not null
  where exists (select 1 from public.teams pc where pc.league_id = l.id and pc.controllata_da_pc)
  order by l.id desc
  limit 1;

  if v_league_id is null then raise exception 'Nessuna lega PC disponibile per il test'; end if;
  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text, true);

  select count(*) into v_righe from public.teams where league_id = v_league_id and attiva;
  select count(*) into v_visibili from public.stato_avanzamento_draft(v_league_id);
  if v_visibili <> v_righe then
    raise exception 'Avanzamento incompleto: % righe su % squadre', v_visibili, v_righe;
  end if;

  if exists (
    select 1 from public.stato_avanzamento_draft(v_league_id)
    where giocatori < 0 or obiettivo <> 24
  ) then
    raise exception 'Conteggio giocatori non valido';
  end if;

  -- Se esiste ancora un PC incompleto lo porta a 24/24; se sono già tutti
  -- pronti restituisce false. In entrambi i casi deve essere autorizzato.
  perform public.completa_prossima_squadra_pc(v_league_id);
end;
$$;

rollback;

select l.id, l.nome, l.stato,
       count(*) filter (where d.stato = 'concluso') as squadre_complete,
       count(*) as squadre_totali
from public.leagues l
join public.teams t on t.league_id = l.id and t.attiva
left join public.draft_team_state d on d.team_id = t.id
where l.id = (select max(id) from public.leagues)
group by l.id;
