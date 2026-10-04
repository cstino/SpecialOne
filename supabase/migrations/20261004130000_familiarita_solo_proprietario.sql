-- ============================================================
--  FAMILIARITA': LA LEGGE SOLO IL PROPRIETARIO DELLA SQUADRA
--  Decisione del committente, 4 ottobre 2026 (registro tattico, punto 43)
--
--  formation_xp e indicazioni_xp erano leggibili da tutti i membri della
--  lega: da li' si poteva capire quali moduli e quali indicazioni di squadra
--  un avversario sta imparando, compreso lo schema RISERVA che si prepara
--  senza schierarlo, prima della partita. Dato tattico: resta riservato.
--  La Edge Function legge con la chiave di servizio e l'app legge solo la
--  riga della propria squadra, quindi nulla cambia per chi gioca.
-- ============================================================

begin;

drop policy if exists formation_xp_lettura on public.formation_xp;
create policy formation_xp_lettura on public.formation_xp
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = formation_xp.team_id and t.user_id = (select auth.uid())
  ));

drop policy if exists indicazioni_xp_lettura on public.indicazioni_xp;
create policy indicazioni_xp_lettura on public.indicazioni_xp
  for select to authenticated
  using (exists (
    select 1 from public.teams t
    where t.id = indicazioni_xp.team_id and t.user_id = (select auth.uid())
  ));

commit;
