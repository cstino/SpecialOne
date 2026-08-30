begin;

-- ============================================================
--  BUG CRITICO: da quando teams.budget e' stato rimosso
--  (docs/decisioni-economia.md, passo 6), risolvi_aste_giorno falliva
--  SEMPRE con "column budget does not exist" nell'insert di transactions,
--  non appena tentava di assegnare un'asta vinta. Il log del cron
--  (cron.job_run_details, job "risoluzione-aste", unico slot utile alle
--  21:03 Europe/Rome) lo conferma: fallito ogni giorno con questo errore
--  esatto. Siccome la funzione processa in un'unica chiamata le aste di
--  TUTTE le leghe per quel giorno, il primo errore interrompeva la
--  risoluzione per tutte — non solo per la lega dove capitava la prima
--  asta vincente. Risultato: nessuna asta si e' mai risolta da quando il
--  bug esiste, si sono solo accumulate "aperta" per sempre.
--
--  Fix: saldo_dopo non significa piu' nulla nel modello a tetto (non e'
--  piu' un saldo di cassa), stessa convenzione gia' usata altrove dopo
--  la riscrittura dell'economia (es. transactions 'draft_pick'): 0
--  letterale, il campo resta solo perche' la colonna e' NOT NULL.
-- ============================================================

create or replace function private.risolvi_aste_giorno(p_giorno date, p_league_id bigint default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asta              record;
  v_soglia            bigint;
  v_vincitore         record;
  v_stagione          smallint;
  v_prossima          integer;
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
    v_stagione := private.stagione_contratto(v_asta.league_id);
    select min(f.giornata) into v_prossima
    from public.fixtures f where f.league_id = v_asta.league_id and f.stato = 'programmata';
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
      and private.capienza_residua(b.team_id, v_stagione, v_asta.id) >= b.ingaggio_offerto
    order by b.ingaggio_offerto desc, b.aggiornata_il asc, b.id asc
    limit 1;

    if v_vincitore.id is null then
      update public.free_agent_auctions
      set stato = 'deserta', risolta_il = now()
      where id = v_asta.id;
    else
      -- Un giocatore svincolato conserva la propria istanza di lega: un
      -- insert semplice urterebbe unique(league_id, player_id). L'upsert
      -- riusa l'istanza solo se e' ancora libera; se nel frattempo e'
      -- stata assegnata altrove, questa sola asta fallisce senza segnarsi
      -- come conclusa (non l'intera risoluzione). L'overall/eta nel
      -- ramo insert vengono dal pool tracciato se il giocatore non e'
      -- mai stato scelto in questa lega; se invece esisteva gia'
      -- un'istanza (orfana, ri-firmata ora), l'upsert non tocca
      -- overall_corrente/eta_corrente: quelli maturati restano.
      insert into public.player_instances as pi
        (league_id, player_id, team_id, overall_corrente, eta_corrente, ingaggio, contratto_scadenza, giornata_acquisizione)
      select v_asta.league_id, p.id, v_vincitore.team_id,
             coalesce(fap.overall_corrente, p.overall), coalesce(fap.eta_corrente, p.eta),
             v_vincitore.ingaggio_offerto, v_stagione, v_prossima
      from public.players p
      left join public.free_agent_progression fap
        on fap.league_id = v_asta.league_id and fap.player_id = p.id
      where p.id = v_asta.player_id
      on conflict (league_id, player_id) do update
        set team_id = excluded.team_id,
            ingaggio = excluded.ingaggio,
            contratto_scadenza = excluded.contratto_scadenza,
            giornata_acquisizione = excluded.giornata_acquisizione
        where pi.team_id is null;
      get diagnostics v_istanze_assegnate = row_count;

      if v_istanze_assegnate <> 1 then
        raise exception using errcode = '55000',
          message = 'Il giocatore non e'' piu'' disponibile per questa asta.';
      end if;

      delete from public.free_agent_progression
      where league_id = v_asta.league_id and player_id = v_asta.player_id;

      insert into public.transactions
        (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
      values
        (v_asta.league_id, v_vincitore.team_id, 'asta_svincolato',
         -v_vincitore.ingaggio_offerto,
         'Asta vinta: ' || v_nome || ' — ' ||
         private.in_milioni(v_vincitore.ingaggio_offerto) ||
         ' M€ di ingaggio fino alla stagione ' || v_stagione,
         0);

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

commit;
