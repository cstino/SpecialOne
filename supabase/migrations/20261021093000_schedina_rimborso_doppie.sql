-- Rimborso (ok del committente): le schedine gia' pagate con la vecchia regola delle doppie (che dimezzavano il
-- moltiplicatore) ricevono la differenza con la regola nuova (doppie gratis). 7 schedine della giornata 14, 1.264 crediti.
with s as (
  select s.id, s.league_id, s.user_id, s.vinto,
         round(s.puntata * private.betone_moltiplicatore(s.totale, s.totale - s.giuste, 0))::bigint as nuovo
    from public.betone_schedine s
   where s.risolta_il is not null and s.puntata > 0
     and exists (select 1 from public.betone_pronostici p where p.schedina_id = s.id and length(p.scelta) = 2)
), diff as (
  select * from s where nuovo > vinto
), soldi as (
  update public.casino_saldi c set crediti = c.crediti + d.nuovo - d.vinto, aggiornato_il = now()
    from diff d where c.league_id = d.league_id and c.user_id = d.user_id
  returning c.user_id
)
update public.betone_schedine b set vinto = d.nuovo from diff d where b.id = d.id;
