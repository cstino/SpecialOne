-- Punti abilita' alle squadre che entrano a lega avviata (6 ottobre 2026). Le squadre originali della Serie F hanno
-- ricevuto 10 punti nella stagione 1 e li hanno spesi; chi entra dalla stagione 2 partiva da zero e i quarti di
-- stagione gia' passati non si recuperano. Deciso col committente: 10 punti da distribuire a ogni nuova squadra, anche a
-- quelle che entreranno dopo. Poi, dalla stagione 2, ricevono come tutti i 2 punti a ogni quarto di stagione (tetto 20).

create or replace function private.punti_ingresso_a_lega_avviata()
returns smallint language sql immutable set search_path = '' as $$ select 10::smallint $$;

create or replace function private.crea_risorse_squadra()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.team_risorse (team_id, league_id, punti_ricevuti)
  values (
    new.id, new.league_id,
    case when new.entrata_stagione >= 2 and not new.controllata_da_pc then private.punti_ingresso_a_lega_avviata() else 0 end
  )
  on conflict (team_id) do nothing;
  return new;
end;
$$;

-- Le nuove squadre gia' entrate (Serie F, stagione 2) che non hanno ricevuto ne' speso niente.
update public.team_risorse r
set punti_ricevuti = private.punti_ingresso_a_lega_avviata(), aggiornata_il = now()
from public.teams t
where t.id = r.team_id and t.league_id = 63 and t.attiva and not t.controllata_da_pc and t.entrata_stagione = 2
  and r.punti_ricevuti = 0 and r.livello_vivaio + r.livello_training + r.livello_medico = 0;
