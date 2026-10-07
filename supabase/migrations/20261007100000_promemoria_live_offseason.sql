-- Promemoria push per la diretta di fine off-season (7 ottobre 2026): alle 13:00 e alle 13:29 (ora di Roma) ai
-- partecipanti delle leghe la cui off-season si chiude a breve. Due job una tantum di pg_cron (il cron del progetto
-- ragiona in UTC: 11:00 e 11:29 UTC = 13:00 e 13:29 ora legale di Roma), che dopo l'esecuzione si tolgono da soli.
-- Il controllo sull'orario di chiusura evita messaggi sbagliati se la scadenza viene spostata.

create or replace function private.promemoria_live_offseason(p_minuti_prima integer, p_forza boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_inviate integer := 0;
  v_n integer;
begin
  for v_lega in
    select o.league_id, o.scade_il
    from public.offseasons o
    join public.leagues l on l.id = o.league_id and l.fase_carriera = 'offseason'
    where o.stato = 'aperta'
      and (p_forza or (
        o.scade_il between clock_timestamp() + make_interval(mins => p_minuti_prima) - interval '5 minutes'
                       and clock_timestamp() + make_interval(mins => p_minuti_prima) + interval '5 minutes'))
  loop
    select count(*) into v_n from (
      select private.notifica(
        t.user_id, v_lega.league_id, 'sistema',
        case when p_minuti_prima >= 10 then 'Alle 13:30 si chiude l''off-season' else 'Si parte tra un minuto!' end,
        case when p_minuti_prima >= 10
          then 'Tra mezz''ora parte il draft dei giocatori in diretta, poi il sorteggio delle conference. Entra nell''app per non perderti niente.'
          else 'L''off-season si chiude alle 13:30: il draft in diretta comincia subito dopo. Apri l''app adesso.' end,
        jsonb_build_object('view', 'overview')
      )
      from public.teams t
      where t.league_id = v_lega.league_id and t.attiva and t.user_id is not null
    ) x;
    v_inviate := v_inviate + v_n;
  end loop;
  return v_inviate;
end;
$$;
revoke all on function private.promemoria_live_offseason(integer, boolean) from public, anon, authenticated;

select cron.schedule('promemoria-live-1300', '0 11 7 10 *',
  $cron$select private.promemoria_live_offseason(30); select cron.unschedule('promemoria-live-1300');$cron$);
select cron.schedule('promemoria-live-1329', '29 11 7 10 *',
  $cron$select private.promemoria_live_offseason(1); select cron.unschedule('promemoria-live-1329');$cron$);
