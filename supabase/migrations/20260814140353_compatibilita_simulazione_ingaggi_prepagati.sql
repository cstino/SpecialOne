-- La lega attiva registra gli ingaggi come costo iniziale di draft/asta.
-- L'Edge Function aggiornata chiama questa RPC al termine della giornata: la
-- funzione esplicita il modello prepagato e impedisce che una RPC assente
-- trasformi una simulazione gia' registrata in un errore 500.

create or replace function public.addebita_ingaggi_giornata(
  p_league_id bigint,
  p_giornata integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.leagues l
    where l.id = p_league_id and l.stato = 'stagione'
  ) then
    return 0;
  end if;

  if exists (
    select 1 from public.fixtures f
    where f.league_id = p_league_id
      and f.giornata = p_giornata
      and f.stato <> 'simulata'
  ) then
    raise exception using errcode = '55000', message = 'Non tutte le partite della giornata sono state simulate.';
  end if;

  return 0;
end;
$$;

revoke all on function public.addebita_ingaggi_giornata(bigint, integer) from public, anon, authenticated;
grant execute on function public.addebita_ingaggi_giornata(bigint, integer) to service_role;

comment on function public.addebita_ingaggi_giornata(bigint, integer) is
  'Compatibilita per leghe con ingaggi gia pagati al draft o in asta: non addebita una seconda volta gli stipendi.';
