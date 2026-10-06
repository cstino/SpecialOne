-- Aubameyang, nel pool dell'OFF-Season 1 della Serie F, e' finito nella rosa di Juventu' Nazionale (mini-draft
-- delle nuove squadre, 6 ottobre 2026) e la squadra lo tiene. Il pool torna a 23 giocatori (6 attaccanti) con un
-- attaccante libero simile: A. Lacazette, ST, overall 79, 35 anni, ingaggio teorico 1,3 M EUR (come Aubameyang).
-- Nessuna lista di preferenze lo nominava (0), quindi non c'e' niente da riscrivere.
do $$
declare v_aub bigint := 749; v_nuovo bigint := 512; v_lega bigint := 63;
begin
  if exists (select 1 from public.player_instances pi where pi.league_id = v_lega and pi.player_id = v_aub and pi.team_id is not null)
     and exists (select 1 from public.scelte_pool where league_id = v_lega and stagione = 1 and finestra = 'off' and player_id = v_aub)
     and not exists (select 1 from public.player_instances pi where pi.league_id = v_lega and pi.player_id = v_nuovo)
     and not exists (select 1 from public.finestre_scelte where league_id = v_lega and stagione = 1 and finestra = 'off' and risolta_il is not null)
  then
    delete from public.scelte_preferenze pr using public.scelte_draft sd
      where pr.scelta_id = sd.id and sd.league_id = v_lega and sd.stagione = 1 and sd.finestra = 'off' and pr.player_id = v_aub;
    delete from public.scelte_pool where league_id = v_lega and stagione = 1 and finestra = 'off' and player_id = v_aub;
    insert into public.scelte_pool (league_id, stagione, finestra, player_id, ingaggio_teorico)
    select v_lega, 1, 'off', p.id, private.ingaggio_teorico(coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta))
    from public.players p
    left join public.free_agent_progression fap on fap.league_id = v_lega and fap.player_id = p.id
    where p.id = v_nuovo;
  end if;
end $$;
