-- ON-Season 2 della Serie F: le 16 posizioni erano quelle del vecchio metodo (percorso nei playoff). Con il metodo nuovo
-- (monte ingaggi, dal minore al maggiore, calcolato alla chiusura dell'off-season) quelle posizioni sarebbero fuorvianti:
-- si tornano a «da determinare» finche' la chiusura non assegna le 24 posizioni (private.assegna_posizioni_on_per_monte_ingaggi).
update public.scelte_draft
set stato = 'futura', posizione = null, aggiornata_il = now()
where league_id = 63 and stagione = 2 and finestra = 'on' and stato = 'determinata'
  and not exists (select 1 from public.finestre_scelte f where f.league_id = 63 and f.stagione = 2 and f.finestra = 'on');
