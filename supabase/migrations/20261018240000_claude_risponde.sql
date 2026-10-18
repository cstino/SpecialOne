-- ============================================================
--  Atletico Neurale (Serie F, squadra 283), affidata a Claude dal 18/10/2026: risponde in automatico alle domande
--  dei giornalisti e alle richieste dei giocatori (funzione conferenza-stampa, azione 'rispondi_claude').
--  Ritardo casuale per domanda (da 3 a 40 minuti dalla creazione), prima le domande della partita passata, poi
--  quelle pre partita; una risposta per giro, il cron gira ogni minuto.
-- ============================================================

begin;

alter table public.teams add column gestita_da_claude boolean not null default false;
update public.teams set gestita_da_claude = true where id = 283;

create or replace function private.lancia_risposte_claude()
returns integer language plpgsql security definer set search_path = '' as $f$
declare
  v_chiave text;
  v_tipo text;
  v_id bigint;
begin
  select decrypted_secret into v_chiave from vault.decrypted_secrets where name = 'chiave_simulazione';
  if v_chiave is null then return 0; end if;

  -- 1) domande dei giornalisti: prima 'dopo' (partita passata), poi 'pre' solo se non restano 'dopo' aperte
  select 'domanda', d.id into v_tipo, v_id
  from public.conferenze_domande d
  join public.teams t on t.id = d.team_id and t.gestita_da_claude
  where d.risposta is null and d.scade_il > now()
    and d.creata_il + (3 + abs(hashtext(d.id::text)) % 38) * interval '1 minute' <= now()
    and (d.tipo = 'dopo' or not exists (
           select 1 from public.conferenze_domande x
            where x.team_id = d.team_id and x.tipo = 'dopo' and x.risposta is null and x.scade_il > now()))
    and not exists (select 1 from private.risposte_claude_tentativi r
                     where r.tipo = 'domanda' and r.rif_id = d.id and (r.ultimo_il > now() - interval '3 minutes' or r.tentativi >= 6))
  order by (d.tipo = 'dopo') desc, d.id
  limit 1;

  -- 2) richieste dei giocatori
  if v_id is null then
    select 'richiesta', q.id into v_tipo, v_id
    from public.richieste_giocatori q
    join public.teams t on t.id = q.team_id and t.gestita_da_claude
    where q.stato = 'aperta' and q.scade_il > now()
      and q.creata_il + (3 + abs(hashtext(q.id::text)) % 38) * interval '1 minute' <= now()
      and not exists (select 1 from private.risposte_claude_tentativi r
                       where r.tipo = 'richiesta' and r.rif_id = q.id and (r.ultimo_il > now() - interval '3 minutes' or r.tentativi >= 6))
    order by q.id
    limit 1;
  end if;

  if v_id is null then return 0; end if;

  insert into private.risposte_claude_tentativi (tipo, rif_id) values (v_tipo, v_id)
  on conflict (tipo, rif_id) do update set ultimo_il = now(), tentativi = private.risposte_claude_tentativi.tentativi + 1;
  perform net.http_post(
    url := 'http://api-gw:8000/functions/v1/conferenza-stampa',
    body := jsonb_build_object('azione', 'rispondi_claude', 'tipo', v_tipo, 'id', v_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_chiave),
    timeout_milliseconds := 90000
  );
  return 1;
end $f$;

create table private.risposte_claude_tentativi (
  tipo text not null,
  rif_id bigint not null,
  ultimo_il timestamptz not null default now(),
  tentativi integer not null default 1,
  primary key (tipo, rif_id)
);

select cron.schedule('claude-risponde', '* * * * *', 'select private.lancia_risposte_claude();');

commit;
