-- Retromarcia (7 ottobre 2026): la sospensione vale solo per gli svincolati dell'off-season appena chiusa,
-- gia' marcati con sospeso = true nella migrazione 20261007170000. Dalle prossime off-season gli svincolati
-- tornano a entrare normalmente nel mercato free agent: niente piu' sospensione automatica.
drop trigger if exists rilasci_in_coda_sospendi_offseason on private.rilasci_in_coda;
drop function if exists private.rilasci_in_coda_sospendi_offseason();
