-- ============================================================
--  NOMI FUORI REGOLA: RINOMINATE LE TRE SQUADRE (5 ottobre 2026)
--  Scelti dal committente. Le sigle restano quelle di prima (REG, ESA, REG).
-- ============================================================

update public.teams set nome = 'Regginho FC' where id in (83, 276);
update public.teams set nome = 'ES ATLETICO BAR SPORT' where id = 268;
