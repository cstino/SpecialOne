-- Quale modello AI ha scritto ogni domanda (gemini-3.5-flash, gemini-2.5-flash, groq:...), per capire da dove arrivano gli errori.
alter table public.conferenze_domande add column if not exists modello text;
