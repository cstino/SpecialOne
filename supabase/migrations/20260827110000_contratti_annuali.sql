-- ============================================================
--  ECONOMIA A TETTO SALARIALE — passo 2: contratti annuali
--  docs/decisioni-economia.md §2
--
--  I contratti durano una stagione e il rinnovo estende di un anno, mai di
--  piu'. E' la scelta che rende il controllo di capienza ESATTO invece che
--  prudenziale: al momento della firma il tetto e gli ingaggi della stagione
--  entrante sono entrambi noti, quindi non c'e' nulla da stimare.
--
--  Promemoria sul quando: i rinnovi si trattano A STAGIONE IN CORSO, non in
--  off-season (20260805170000_via_rinnovi_offseason.sql). Chi non e' stato
--  rinnovato durante la stagione lascia la squadra alla chiusura
--  dell'off-season ed entra nel pool degli svincolati. Per questo la
--  capienza si verifica su `stagione_corrente + 1`.
-- ============================================================

-- ------------------------------------------------------------
--  La durata richiesta dal giocatore e' sempre 1
--
--  Cambiare qui invece che nei tre chiamanti non e' una scorciatoia: la
--  durata smette di essere una variabile del gioco, quindi il posto giusto
--  per fissarla e' la funzione che la produce. proposta_rinnovo (anteprima
--  mostrata dall'interfaccia) e gestisci_rinnovi_squadre_pc (rinnovi delle
--  squadre PC) si allineano da sole, senza riscritture.
--
--  `richiesta` non cambia di una virgola: dipende da r_ing, che e' un seme
--  distinto da quello della durata.
-- ------------------------------------------------------------

create or replace function private.rinnovo_proposta(
  p_instance_id bigint,
  p_overall smallint,
  p_eta smallint,
  p_ingaggio bigint,
  p_bandiera smallint,
  p_economia smallint
) returns table (richiesta bigint, durata smallint)
language sql
stable
parallel safe
set search_path = ''
as $$
  with seme as (
    select
      (abs(hashtext('ing:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_ing
  ), centro as (
    select 1.06 + (p_economia - p_bandiera) / 500.0 as valore
  )
  select
    greatest(
      500000::bigint,
      p_ingaggio,
      (round(
        private.ingaggio_teorico(p_overall, p_eta)
        * greatest(0.75, least(1.35, centro.valore + (seme.r_ing - 0.5) * 0.12))
        / 100000
      ) * 100000)::bigint
    ) as richiesta,
    1::smallint as durata
  from seme, centro;
$$;

comment on function private.rinnovo_proposta(bigint, smallint, smallint, bigint, smallint, smallint) is
  'Richiesta economica del giocatore per il rinnovo. La durata e'' sempre 1: i contratti sono annuali (docs/decisioni-economia.md §2).';

revoke all on function private.rinnovo_proposta(bigint, smallint, smallint, bigint, smallint, smallint)
  from public, anon, authenticated;
grant execute on function private.rinnovo_proposta(bigint, smallint, smallint, bigint, smallint, smallint)
  to service_role;

-- ------------------------------------------------------------
--  offri_rinnovo: durata fissa a 1 e capienza al posto della sostenibilita'
--
--  Tre modifiche rispetto alla versione di 20260826240000:
--
--  1. p_durata deve valere 1. Il parametro resta nella firma per non
--     rompere la chiamata del frontend, che verra' ripulita al passo 6.
--
--  2. Sparisce il fattore di durata. Valeva
--        1 - abs(p_durata - v_proposta.durata) * 0.07
--     cioe' penalizzava fino al 21% chi offriva una durata diversa da
--     quella desiderata dal giocatore. Ora che la durata non e' piu'
--     negoziabile, tenere una penalita' su una variabile che il manager
--     non controlla sarebbe solo una tassa incomprensibile.
--
--  3. verifica_sostenibilita -> verifica_capienza sulla stagione entrante.
--     Il delta resta calcolato come prima: se il contratto era in scadenza
--     il vecchio ingaggio non fa parte del monte della prossima stagione,
--     quindi il rinnovo aggiunge l'intero nuovo importo.
-- ------------------------------------------------------------

create or replace function public.offri_rinnovo(p_instance_id bigint, p_ingaggio bigint, p_durata smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_team public.teams;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
  v_tolleranza numeric;
  v_soglia numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo è 0,5 M€.';
  end if;
  if p_durata <> 1 then
    raise exception using errcode = '22023',
      message = 'I contratti durano una stagione: il rinnovo estende di un anno.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non è nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha già annunciato il ritiro: non rinnoverà il contratto.';
  end if;
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha già rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andrà a scadenza e lascerà la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1::smallint), v_league.n_squadre::smallint
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);

  -- Niente fattore di durata: si giudica solo la cifra offerta.
  v_valore := p_ingaggio;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    perform private.verifica_capienza(
      v_team.id,
      p_ingaggio - case
        when v_inst.contratto_scadenza > v_league.stagione_corrente then v_inst.ingaggio
        else 0 end,
      (v_league.stagione_corrente + 1)::smallint
    );

    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + 1)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0,
        rinnovo_stagione = v_league.stagione_corrente
    where id = v_inst.id;

    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_inst.league_id, v_team.id, 'rinnovo_in_stagione',
      greatest(1, p_ingaggio - v_inst.ingaggio),
      'Rinnovo: ' || coalesce(v_player.nome, 'giocatore') || ' — '
        || round(p_ingaggio / 1000000.0, 1) || ' M€ fino alla stagione ' || v_scadenza,
      v_team.budget
    );

    return jsonb_build_object(
      'esito', 'accettato',
      'ingaggio', p_ingaggio,
      'durata', 1,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  v_tentativi := (v_inst.rinnovo_tentativi + 1)::smallint;
  update public.player_instances set rinnovo_tentativi = v_tentativi where id = v_inst.id;

  return jsonb_build_object(
    'esito', case when v_tentativi >= 3 then 'chiusa' else 'rifiutato' end,
    'tentativi_usati', v_tentativi,
    'tentativi_totali', 3,
    'messaggio', case
      when v_tentativi >= 3 then 'Basta così, mister. Andrò a scadenza.'
      when v_rapporto >= 0.95 then 'Ci siamo quasi, ma non ancora.'
      when v_rapporto >= 0.85 then 'È troppo poco per quello che valgo.'
      else 'Non se ne parla nemmeno, mister.'
    end
  );
end;
$function$;

comment on function public.offri_rinnovo(bigint, bigint, smallint) is
  'Tratta il rinnovo annuale di un giocatore in rosa. p_durata deve valere 1. La capienza si verifica sulla stagione entrante (docs/decisioni-economia.md §2).';

revoke all on function public.offri_rinnovo(bigint, bigint, smallint) from public, anon;
grant execute on function public.offri_rinnovo(bigint, bigint, smallint) to authenticated;

-- ------------------------------------------------------------
--  Nota su cosa NON e' stato toccato qui
--
--  - public.gestisci_rinnovi_squadre_pc si allinea da sola alla durata 1,
--    ma NON verifica ancora la capienza: le squadre PC possono sfondare il
--    tetto. Va sistemata al passo 3 insieme agli altri percorsi PC
--    (offerte_mercato_squadre_pc, proposte_mercato_squadre_pc).
--
--  - public.accetta_rinnovo_stagione e' codice morto: il frontend non la
--    chiama e invoca private.rinnovo_proposta con la vecchia firma a 4
--    argomenti, che non esiste piu'. Va rimossa, ma in una migrazione di
--    pulizia sua, non qui.
-- ------------------------------------------------------------
