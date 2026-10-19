-- La proposta non e' vuota anche se contiene solo giocatori del vivaio.
begin;
alter table public.trade_proposals drop constraint trade_non_vuota;
alter table public.trade_proposals add constraint trade_non_vuota check (
  cardinality(giocatori_offerti) + cardinality(giocatori_richiesti) + cardinality(scelte_offerte) + cardinality(scelte_richieste)
  + cardinality(vivaio_offerti) + cardinality(vivaio_richiesti) > 0);
commit;
