-- ============================================================
--  OFF-SEASON: VIA IL TRIGGER CHE LA FORZAVA A UN GIORNO
--
--  offseasons_durata_un_giorno (20260802221000) riscriveva scade_il a +1
--  giorno su ogni nuova off-season, scavalcando la durata decisa in
--  prepara_offseason (ora leagues.durata_offseason_ore). Si toglie.
--
--  Serie F (aperta il 3 ottobre 2026 alle 23:55 con 24 ore per colpa del
--  trigger) passa a 48 ore dall'apertura, e si svela la finestra OFF della
--  stagione 1, che all'apertura non era nata: l'estrazione segue la nuova
--  fine dell'off-season.
-- ============================================================

drop trigger if exists offseasons_durata_un_giorno on public.offseasons;
drop function if exists private.forza_offseason_un_giorno();

-- Per le leghe nuove il default resta quello che i gruppi vivevano davvero
-- (un giorno), non i 7 giorni scritti in prepara_offseason e mai applicati.
alter table public.leagues alter column durata_offseason_ore set default 24;
update public.leagues set durata_offseason_ore = 24 where id <> 63 and durata_offseason_ore = 168;

update public.offseasons o
set scade_il = o.creata_il + interval '48 hours'
where o.league_id = 63 and o.stato = 'aperta';

update public.leagues l
set offseason_fine = o.scade_il
from public.offseasons o
where l.id = 63 and o.league_id = 63 and o.stato = 'aperta';

do $$
begin
  perform private.assegna_posizioni_playoff(63, 1::smallint);
  if not exists (select 1 from public.finestre_scelte where league_id = 63 and stagione = 1 and finestra = 'off') then
    perform private.svela_finestra_scelte(63, 1::smallint, 'off');
  end if;
end;
$$;
