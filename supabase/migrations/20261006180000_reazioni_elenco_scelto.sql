-- L'elenco delle reazioni lo hanno scelto i partecipanti (6 ottobre 2026): sostituisce quello provvisorio.
-- Codici validi: tenerli allineati a src/lib/reazioni.ts.
create or replace function public.invia_reazione(p_league_id bigint, p_contesto text, p_codice text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_team bigint;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere per mandare una reazione.';
  end if;
  select t.id into v_team from public.teams t where t.league_id = p_league_id and t.user_id = v_user and t.attiva;
  if v_team is null then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;
  if p_contesto not in ('draft', 'sorteggio', 'on') then
    raise exception using errcode = '22023', message = 'Contesto non valido.';
  end if;
  if p_codice not in ('fuoco', 'drafto', 'eddai', 'complimenti', 'pazzesco', 'nooo', 'imbarazzo', 'occhi', 'herewego', 'shalom', 'diavoli') then
    raise exception using errcode = '22023', message = 'Reazione non valida.';
  end if;
  if exists (
    select 1 from public.reazioni_live r
    where r.user_id = v_user and r.creata_il > clock_timestamp() - interval '4.6 seconds'
  ) then
    raise exception using errcode = '54000', message = 'Aspetta qualche secondo prima della prossima reazione.';
  end if;
  insert into public.reazioni_live (league_id, team_id, user_id, contesto, codice)
  values (p_league_id, v_team, v_user, p_contesto, p_codice);
  if random() < 0.05 then
    delete from public.reazioni_live where creata_il < clock_timestamp() - interval '1 hour';
  end if;
end;
$$;
revoke all on function public.invia_reazione(bigint, text, text) from public, anon;
grant execute on function public.invia_reazione(bigint, text, text) to authenticated;
