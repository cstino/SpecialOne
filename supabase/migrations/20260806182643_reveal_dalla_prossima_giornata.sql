-- Il reveal e' una novita' introdotta a stagione gia' iniziata: le partite
-- precedenti restano risultati normali, dalla prima giornata futura in poi
-- ogni utente deve prima guardare l'animazione della propria squadra.
alter table public.leagues
  add column if not exists reveal_dalla_giornata smallint not null default 1
  check (reveal_dalla_giornata >= 1);

update public.leagues l
set reveal_dalla_giornata = coalesce(
  (
    select min(f.giornata)::smallint
    from public.fixtures f
    where f.league_id = l.id and f.stato <> 'simulata'
  ),
  l.giornate_totali + 1
)
where l.stato = 'stagione'
  and l.reveal_dalla_giornata = 1;

comment on column public.leagues.reveal_dalla_giornata is
  'Prima giornata dalla quale il risultato della propria squadra deve essere rivelato con l''animazione.';
