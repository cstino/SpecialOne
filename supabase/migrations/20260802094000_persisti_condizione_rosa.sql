-- ============================================================
--  CONDIZIONE E INFORTUNI PERSISTENTI
--
--  Le colonne esistevano dal primo giorno e la Edge Function le leggeva, ma
--  non le riscriveva mai: ogni partita ripartiva da condizione 100 e nessun
--  infortunio. Con la condizione ferma a 100 nemmeno le sostituzioni potevano
--  scattare, perche' la soglia di cambio e' 55.
--
--  Il consumo e' di circa 13 punti a partita contro 8 di recupero: servono
--  quasi dieci giornate perche' un titolare scenda sotto soglia. Senza questa
--  persistenza il logoramento non si accumula e il meccanismo non esiste.
-- ============================================================

create or replace function public.aggiorna_condizione_rosa(
  p_league_id bigint,
  p_valori    jsonb
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_aggiornati integer;
begin
  if jsonb_typeof(p_valori) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload condizione non valido.';
  end if;

  with valori as (
    select *
    from jsonb_to_recordset(p_valori) as x(
      id                 bigint,
      condizione         smallint,
      infortunato_fino_a smallint
    )
  )
  update public.player_instances pi
  set condizione         = least(100, greatest(0, v.condizione)),
      infortunato_fino_a = greatest(0, v.infortunato_fino_a)
  from valori v
  where pi.id = v.id
    and pi.league_id = p_league_id;

  get diagnostics v_aggiornati = row_count;
  return v_aggiornati;
end;
$$;

revoke all on function public.aggiorna_condizione_rosa(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.aggiorna_condizione_rosa(bigint, jsonb)
  to service_role;

comment on function public.aggiorna_condizione_rosa(bigint, jsonb) is
  'Riscrive condizione e infortuni della rosa dopo una giornata simulata.';
