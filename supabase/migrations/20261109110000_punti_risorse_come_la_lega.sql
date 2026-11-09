-- Punti risorse a chi entra a lega avviata (decisione del committente, 9/11/2026): gli stessi punti ricevuti finora
-- dalle altre squadre della lega, non piu' 10 fissi. Con la regola del 6/10/2026 le 4 squadre entrate in Serie F nella
-- Season 3 (310-313) hanno ricevuto 10 punti contro i 18 di tutte le altre (10 d'ingresso + 2 a ogni quarto della
-- Season 2): si portano a 18 e ricevono la notifica.

begin;

create or replace function private.crea_risorse_squadra()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  insert into public.team_risorse (team_id, league_id, punti_ricevuti)
  values (
    new.id, new.league_id,
    case when new.entrata_stagione >= 2 and not new.controllata_da_pc then
      -- Quanto hanno ricevuto finora le altre squadre umane della lega (almeno i 10 d'ingresso).
      greatest(private.punti_ingresso_a_lega_avviata(),
               coalesce((select max(r.punti_ricevuti) from public.team_risorse r
                           join public.teams t on t.id = r.team_id
                          where r.league_id = new.league_id and t.attiva and not t.controllata_da_pc), 0))::smallint
    else 0 end
  )
  on conflict (team_id) do nothing;
  return new;
end;
$function$;

do $$
begin
  if (select count(*) from public.team_risorse where team_id in (310, 311, 312, 313) and punti_ricevuti = 10) <> 4 then
    raise exception 'attese 4 squadre a 10 punti';
  end if;
  if (select count(distinct r.punti_ricevuti) from public.team_risorse r join public.teams t on t.id = r.team_id
       where r.league_id = 63 and t.attiva and r.team_id < 310) <> 1 then
    raise exception 'le altre squadre non sono tutte allo stesso punteggio';
  end if;
end $$;

update public.team_risorse set punti_ricevuti = 18, aggiornata_il = now() where team_id in (310, 311, 312, 313);

select private.notifica(t.user_id, t.league_id, 'sistema', 'Punti abilità disponibili',
  'Hai ricevuto 8 punti abilità in più: ora hai gli stessi punti delle altre squadre della lega. Spendili nelle risorse del club.',
  jsonb_build_object('view', 'risorse'))
from public.teams t where t.id in (310, 311, 312, 313) and t.user_id is not null;

commit;
