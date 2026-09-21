-- ============================================================
--  IL TEMPO SCORRE ANCHE PER CHI E' SUL MERCATO
--
--  Seguito della segnalazione su Fellhauer. L'infortunio di uno svincolato non
--  si perdeva — quello era solo invisibile, ed e' stato risolto mostrandolo —
--  ma NON SCENDEVA MAI.
--
--  Il contatore cala in un punto solo: public.aggiorna_condizione_rosa, che
--  l'Edge Function alimenta con i giocatori DELLE SQUADRE CHE GIOCANO quella
--  giornata. Chi non ha squadra non entra in quell'elenco, quindi restava
--  fermo per sempre: un giocatore svincolato mentre era rotto sarebbe rimasto
--  invendibile fino al reset di fine stagione, anche dopo venti giornate.
--
--  Deciso con l'utente: "se Fellhauer dovesse tornare sul mercato tra
--  abbastanza giornate, non dovrebbe piu' essere infortunato". Scala di una
--  giornata a partita, come per chi e' in rosa.
--
--  LA CONDIZIONE NON SI TOCCA, e vale la pena dire perche' invece di lasciare
--  il dubbio: misurata prima di scrivere, quella degli svincolati e' gia' a
--  100 in tutte e tre le leghe (peggiore: 87). Non c'e' niente da riparare, e
--  aggiungere un recupero dove non serve e' solo un'altra cosa che puo'
--  rompersi.
--
--  IDEMPOTENZA. Stessa forma del countdown del vivaio, che ha lo stesso
--  problema: una tabella di guardia su (lega, giornata) e un inserimento che
--  non fa nulla se la riga c'e' gia'. Se il cron ritenta la simulazione, il
--  secondo giro non sconta una seconda giornata.
-- ============================================================

create table if not exists private.guarigioni_svincolati (
  league_id  bigint      not null references public.leagues(id) on delete cascade,
  giornata   smallint    not null,
  eseguito_il timestamptz not null default now(),
  primary key (league_id, giornata)
);

revoke all on table private.guarigioni_svincolati from public, anon, authenticated;

comment on table private.guarigioni_svincolati is
  'Registro di idempotenza per public.guarisci_svincolati: una riga per (lega, giornata) gia'' scontata.';

-- ------------------------------------------------------------
--  Scala di una giornata l'infortunio di chi e' sul mercato
--
--  Solo istanze orfane e non ritirate. Chi non e' mai stato in rosa vive in
--  free_agent_progression, non ha mai giocato e non puo' essersi rotto.
-- ------------------------------------------------------------
create or replace function public.guarisci_svincolati(p_league_id bigint, p_giornata smallint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scalati  integer := 0;
  v_guariti  integer := 0;
begin
  insert into private.guarigioni_svincolati (league_id, giornata)
  values (p_league_id, p_giornata)
  on conflict (league_id, giornata) do nothing;
  if not found then
    return jsonb_build_object('gia_eseguito', true, 'scalati', 0, 'guariti', 0);
  end if;

  with scalati as (
    update public.player_instances pi
    set infortunato_fino_a = greatest(0, pi.infortunato_fino_a - 1)
    where pi.league_id = p_league_id
      and pi.team_id is null
      and not pi.ritirato
      and pi.infortunato_fino_a > 0
    returning pi.infortunato_fino_a
  )
  select count(*)::integer, count(*) filter (where infortunato_fino_a = 0)::integer
  into v_scalati, v_guariti
  from scalati;

  return jsonb_build_object('gia_eseguito', false, 'scalati', v_scalati, 'guariti', v_guariti);
end;
$$;

revoke all on function public.guarisci_svincolati(bigint, smallint) from public, anon, authenticated;
grant execute on function public.guarisci_svincolati(bigint, smallint) to service_role;

comment on function public.guarisci_svincolati(bigint, smallint) is
  'Scala di una giornata l''infortunio degli svincolati. Idempotente per (lega, giornata). Chiamata dalla simulazione notturna accanto al countdown del vivaio.';
