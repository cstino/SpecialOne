-- Season 3, diario §9: foto scontornate in stile card FUT, solo per le figurine dell'album.
-- Percorso nel bucket pubblico player-photos (cutout/<id>.webp), scaricate da TheSportsDB con
-- tools/importazione/scarica_figurine.py. Null = la figurina usa la foto di sempre (foto_url).
alter table public.players add column if not exists foto_figurina text;
