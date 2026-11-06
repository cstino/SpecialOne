-- Proposte di scambio che decadono (richiesta del committente, 6/11/2026).
--
-- Quando uno scambio va a buon fine, le altre proposte ancora in attesa che coinvolgono gli stessi
-- giocatori, scelte o prospetti del vivaio non possono piu' andare in porto: rispondi_a_proposta le
-- bloccava gia' all'accettazione ("non e' piu' nella tua rosa"), ma restavano in attesa fino alla
-- scadenza, nella lista di chi le aveva ricevute e di chi le aveva fatte, senza che nessuno lo sapesse.
-- Ora si chiudono subito come 'decaduta' e la squadra rimasta fuori dallo scambio riceve una notifica.
-- Trigger e non dentro rispondi_a_proposta: cosi' vale per ogni strada che accetta una proposta
-- (risposta dell'allenatore, risposta automatica delle squadre del computer).

alter table public.trade_proposals drop constraint trade_proposals_stato_check;
alter table public.trade_proposals add constraint trade_proposals_stato_check
  check (stato = any (array['in_attesa', 'accettata', 'rifiutata', 'ritirata', 'scaduta', 'decaduta']));

create or replace function private.decadi_proposte_concorrenti()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_giocatori bigint[] := new.giocatori_offerti || new.giocatori_richiesti;
  v_scelte bigint[] := new.scelte_offerte || new.scelte_richieste;
  v_vivaio bigint[] := new.vivaio_offerti || new.vivaio_richiesti;
  v_p public.trade_proposals;
  v_nomi text;
  v_avviso uuid;
  v_altra text;
begin
  for v_p in
    update public.trade_proposals
    set stato = 'decaduta', risolta_il = now()
    where league_id = new.league_id and stato = 'in_attesa' and id <> new.id
      and ((giocatori_offerti || giocatori_richiesti) && v_giocatori
        or (scelte_offerte || scelte_richieste) && v_scelte
        or (vivaio_offerti || vivaio_richiesti) && v_vivaio)
    returning *
  loop
    select string_agg(p.nome, ', ' order by p.nome) into v_nomi
    from public.player_instances pi join public.players p on p.id = pi.player_id
    where pi.id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and pi.id = any(v_giocatori);

    -- Si avvisa chi e' rimasto fuori dallo scambio concluso (le due squadre che l'hanno chiuso lo sanno).
    for v_avviso, v_altra in
      select t.user_id, (select o.nome from public.teams o
                         where o.id = case when t.id = v_p.da_team_id then v_p.a_team_id else v_p.da_team_id end)
      from public.teams t
      where t.id in (v_p.da_team_id, v_p.a_team_id) and t.id not in (new.da_team_id, new.a_team_id)
        and t.user_id is not null
    loop
      perform private.notifica(v_avviso, new.league_id, 'mercato_esito', 'Proposta decaduta',
        'La proposta di scambio con ' || v_altra || ' non e'' piu'' valida: '
          || coalesce(v_nomi || case when v_nomi like '%,%' then ' sono gia'' stati scambiati' else ' e'' gia'' stato scambiato' end,
                      'una scelta o un giocatore del vivaio e'' gia'' stato scambiato')
          || ' in un''altra trattativa.',
        jsonb_build_object('proposta_id', v_p.id));
    end loop;
  end loop;
  return null;
end;
$$;

drop trigger if exists trade_proposals_decadi_concorrenti on public.trade_proposals;
create trigger trade_proposals_decadi_concorrenti
  after update of stato on public.trade_proposals
  for each row when (new.stato = 'accettata' and old.stato is distinct from 'accettata')
  execute function private.decadi_proposte_concorrenti();
