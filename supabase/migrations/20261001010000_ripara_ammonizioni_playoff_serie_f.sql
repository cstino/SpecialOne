-- ============================================================
--  SERIE F: RIPARA LE AMMONIZIONI DEI PLAYOFF
--
--  Bug: private.crea_tabelloni azzera ammonizioni_stagione quando nasce il
--  tabellone, cioe' dentro registra_risultato_partita dell'ultima partita
--  di stagione regolare. Subito dopo, nella stessa giornata, la Edge
--  Function riscriveva i cartellini partendo dai valori letti PRIMA
--  dell'azzeramento: il conto della stagione regolare tornava in vita e ai
--  playoff sono scattate diffide che non dovevano esserci.
--
--  Qui: il conto riparte dai soli cartellini dei playoff (giallo e doppio
--  giallo valgono un'ammonizione, come nella Edge Function), e si tolgono
--  le squalifiche per diffida della giornata 32 ancora da scontare. Quelle
--  della giornata 31 sono gia' state scontate e non si possono restituire.
--  Mittelstadt (6102) resta squalificato: alla giornata 32 e' stato anche
--  espulso per doppia ammonizione.
-- ============================================================

update public.player_instances pi
set ammonizioni_stagione = 0
from public.teams t
where pi.team_id = t.id and t.league_id = 63;

update public.player_instances pi
set ammonizioni_stagione = g.n
from (
  select (e->>'giocatore')::bigint as instance_id, count(*)::smallint as n
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  cross join lateral jsonb_array_elements(m.blocchi) e
  where m.league_id = 63
    and f.bracket_tie_id is not null
    and e->>'tipo' = 'cartellino'
    and e->>'colore' in ('giallo', 'doppio_giallo')
  group by 1
) g
where pi.id = g.instance_id;

update public.player_instances
set squalificato_fino_a = 0
where id in (5790, 5829, 6098, 6147, 6910);
