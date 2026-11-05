-- Sponsor: i contratti attivi si verificano anche da soli ogni 10 minuti, cosi' premio e notifica arrivano appena
-- l'allenatore ha visto la partita decisiva (o dopo 24 ore), senza dover aprire la pagina Sponsor.
create or replace function private.sponsor_valuta_tutti()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare v record; v_n integer := 0;
begin
  for v in select distinct c.team_id, t.user_id from public.sponsor_contratti c join public.teams t on t.id = c.team_id
           where c.stato = 'attiva' and t.user_id is not null loop
    perform private.sponsor_valuta(v.team_id, v.user_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke all on function private.sponsor_valuta_tutti() from public, anon, authenticated;
select cron.schedule('sponsor-valuta', '*/10 * * * *', 'select private.sponsor_valuta_tutti()');
