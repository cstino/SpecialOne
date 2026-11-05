-- Correzione una tantum dello storico dei rinnovi (vedi 20261105093000), con copia delle righe originali.
-- Aumenti: il segno si inverte (importo esatto). Riduzioni scritte come 1 euro: ricostruite dall'ingaggio
-- precedente dello stesso giocatore nella stessa squadra, solo dal 1/9/2026 (prima l'economia era diversa).
begin;
create table if not exists private.transactions_rinnovi_backup_20261105 as select * from public.transactions where tipo = 'rinnovo_in_stagione';
update public.transactions set importo = -importo where tipo = 'rinnovo_in_stagione' and importo > 1 and creata_il < '2026-11-05 08:39:00+00';
with mov as (
  select t.id, t.team_id, t.creata_il, t.tipo, t.importo,
    trim(regexp_replace(split_part(regexp_replace(t.descrizione, '^[^:]+: ', ''), ' — ', 1), ' fino alla stagione [0-9]+$', '')) as nome,
    case
      when t.descrizione ~ '^Rinnovo: ' then (substring(t.descrizione from '— ([0-9]+(?:\.[0-9]+)?) M€')::numeric * 1000000)::bigint
      when t.descrizione ~ '^Asta vinta: ' then -t.importo
      when t.descrizione ~ '^Ingaggio draft: ' then -t.importo
    end as ingaggio_nuovo
  from public.transactions t
  where t.descrizione ~ '^(Rinnovo|Rinnovo PC|Asta vinta|Ingaggio draft): '
), r as (
  select m.*, (select p.ingaggio_nuovo from mov p where p.team_id = m.team_id and p.nome = m.nome and (p.creata_il, p.id) < (m.creata_il, m.id) and p.ingaggio_nuovo is not null order by p.creata_il desc, p.id desc limit 1) as ingaggio_prima
  from mov m where m.tipo = 'rinnovo_in_stagione' and m.importo = 1
)
update public.transactions t set importo = r.ingaggio_prima - r.ingaggio_nuovo from r where t.id = r.id and r.creata_il >= '2026-09-01' and r.ingaggio_prima > r.ingaggio_nuovo;
commit;
