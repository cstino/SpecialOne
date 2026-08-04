-- Decisione dell'utente, 4 agosto 2026: le trattative aperte fra squadre
-- devono comparire nella card "Rumors" del mercato, visibili a tutta la
-- lega — non solo alle due squadre coinvolte.
--
-- trade_proposals resta protetta com'era (RLS: le pendenti le vedono solo
-- le due squadre coinvolte, design §9.3) perche' quella policy copre anche
-- il conguaglio e il messaggio, che restano privati. Questa RPC espone
-- volutamente solo il minimo che serve al "chi tratta chi": le due squadre
-- e gli id dei giocatori coinvolti, mai il conguaglio ne' il messaggio.
create or replace function public.trattative_pubbliche(p_league_id bigint)
returns table (
  id bigint,
  da_team_id bigint,
  a_team_id bigint,
  giocatori_offerti bigint[],
  giocatori_richiesti bigint[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select tp.id, tp.da_team_id, tp.a_team_id, tp.giocatori_offerti, tp.giocatori_richiesti
  from public.trade_proposals tp
  where tp.league_id = p_league_id
    and tp.stato = 'in_attesa'
    and (select private.e_membro(p_league_id))
  order by tp.creata_il desc;
$$;

revoke all on function public.trattative_pubbliche(bigint) from public, anon;
grant execute on function public.trattative_pubbliche(bigint) to authenticated;
