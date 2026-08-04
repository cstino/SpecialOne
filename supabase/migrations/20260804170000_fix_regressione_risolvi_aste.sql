-- ============================================================
--  FIX: risolvi_aste_giorno aveva perso due correzioni gia' fatte il
--  2 agosto, riportando indietro due bug gia' risolti
--
--  Segnalato dall'utente: chiuso il mercato in anticipo dal pannello admin
--  per test, TUTTE le aste con offerte sono finite deserte nonostante
--  offerte superiori alla richiesta del giocatore (es. J. Tah: offerte da
--  13/11,1/10 M€ contro una richiesta di 9,4 M€).
--
--  Causa. 20260802211000_limiti_rosa.sql aveva gia' corretto
--  risolvi_aste_giorno due volte:
--    1. il controllo posti liberi confrontava con v_lega.slot_rosa, che pero'
--       da quella stessa migrazione in poi e' un valore fisso legato
--       all'obiettivo del DRAFT (24, decisioni-fase1 "rosa fissata a 24") e
--       non piu' al tetto di stagione. Ogni squadra finisce il draft esatta-
--       mente a 24/24, quindi "< slot_rosa" e' falso per definizione appena
--       il draft e' concluso: NESSUNA squadra puo' mai vincere un'asta. Va
--       confrontato con private.rosa_massima() (21-30, il tetto vero di
--       stagione per mercato e aste, invariato dalla stessa decisione).
--    2. l'assegnazione del vincitore faceva un insert semplice invece di un
--       upsert su player_instances, che pero' ha unique(league_id, player_id):
--       un giocatore gia' svincolato (istanza esistente con team_id null) fa
--       fallire l'insert con una violazione di vincolo, e senza gestione
--       dell'eccezione l'intera risoluzione della giornata si annulla — non
--       solo quell'asta, tutte quelle ancora da processare nello stesso ciclo.
--
--  20260803190000_pannello_admin_fallback_cron.sql ha riscritto la funzione
--  per aggiungere il filtro p_league_id ripartendo pero' da una copia
--  precedente a entrambe le correzioni: le ha annullate senza che nessuno se
--  ne accorgesse, perche' il comportamento e' identico finche' non lo si
--  osserva a fine giornata (l'esito "deserta" non genera errori, solo
--  notifiche "Asta persa" plausibili). 20260804120000_rinnovo_ancorato_e_
--  stagioni.sql ha ereditato la stessa regressione limitandosi a cambiare il
--  testo delle notifiche.
--
--  Si riapplicano qui entrambe le correzioni sopra la versione attuale
--  (con p_league_id e col testo "una stagione"), senza toccare nient'altro.
-- ============================================================

create or replace function private.risolvi_aste_giorno(
  p_giorno date,
  p_league_id bigint default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_lega              public.leagues;
  v_prorata           bigint;
  v_nome              text;
  v_assegnate         integer := 0;
  v_istanze_assegnate integer;
  v_off               record;
begin
  for v_asta in
    select a.* from public.free_agent_auctions a
    where a.giorno = p_giorno and a.stato = 'aperta'
      and (p_league_id is null or a.league_id = p_league_id)
    order by a.id
    for update
  loop
    select * into v_lega from public.leagues where id = v_asta.league_id;
    select soglia into v_soglia from private.auction_thresholds where auction_id = v_asta.id;
    select p.nome into v_nome from public.players p where p.id = v_asta.player_id;

    v_vincitore := null;

    select b.* into v_vincitore
    from public.free_agent_bids b
    join public.teams t on t.id = b.team_id
    where b.auction_id = v_asta.id
      and b.ingaggio_offerto >= v_soglia
      and (select count(*) from public.player_instances pi where pi.team_id = b.team_id)
          < private.rosa_massima()
      and t.budget >= round(b.ingaggio_offerto::numeric
                            * private.giornate_rimanenti(v_lega.id)
                            / greatest(v_lega.giornate_totali, 1))
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      v_prorata := round(v_vincitore.ingaggio_offerto::numeric
                         * private.giornate_rimanenti(v_lega.id)
                         / greatest(v_lega.giornate_totali, 1));

      -- Un giocatore svincolato conserva la propria istanza di lega: un
      -- insert semplice urterebbe unique(league_id, player_id). L'upsert
      -- riusa l'istanza solo se e' ancora libera; se nel frattempo e' stata
      -- assegnata altrove, questa sola asta fallisce senza addebitare
      -- budget ne' segnarsi come conclusa (non l'intera risoluzione).
      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio)
      select v_asta.league_id, p.id, v_vincitore.team_id, p.overall, p.eta,
             v_vincitore.ingaggio_offerto
      from public.players p where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      update public.teams set budget = budget - v_prorata where id = v_vincitore.team_id;

      if v_prorata <> 0 then
        insert into public.transactions
          (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
        select v_asta.league_id, v_vincitore.team_id, 'asta_svincolato', -v_prorata,
               'Asta vinta: ' || v_nome,
               (select budget from public.teams where id = v_vincitore.team_id);
      end if;

      update public.free_agent_auctions
      set stato = 'assegnata', vincitore_team_id = v_vincitore.team_id,
          ingaggio_finale = v_vincitore.ingaggio_offerto, risolta_il = now()
      where id = v_asta.id;

      v_assegnate := v_assegnate + 1;
    end if;

    for v_off in
      select b.team_id, t.user_id from public.free_agent_bids b
      join public.teams t on t.id = b.team_id
      where b.auction_id = v_asta.id
    loop
      perform private.notifica(
        v_off.user_id, v_asta.league_id, 'mercato_asta',
        case when v_vincitore.id is not null and v_off.team_id = v_vincitore.team_id
             then 'Asta vinta: ' || v_nome
             else 'Asta persa: ' || v_nome end,
        case
          when v_vincitore.id is null then 'Nessuna offerta ha raggiunto la richiesta del giocatore.'
          when v_off.team_id = v_vincitore.team_id then 'Entra in rosa con un contratto di una stagione.'
          else 'Se l''e'' aggiudicato ' ||
               (select nome from public.teams where id = v_vincitore.team_id) ||
               ' per ' || private.in_milioni(v_vincitore.ingaggio_offerto) || ' M€.'
        end,
        jsonb_build_object('asta_id', v_asta.id)
      );
    end loop;
  end loop;

  return v_assegnate;
end;
$$;

revoke all on function private.risolvi_aste_giorno(date, bigint) from public, anon, authenticated;
grant execute on function private.risolvi_aste_giorno(date, bigint) to service_role;
