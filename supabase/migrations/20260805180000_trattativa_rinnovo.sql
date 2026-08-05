-- ============================================================
--  TRATTATIVA SUL RINNOVO (design §10.4 bis)
--
--  Richiesta dell'utente: il rinnovo non è più "prendere o lasciare". Si
--  tratta su DUE assi, ingaggio e durata, e l'esito dipende da mentalità e
--  morale (§10 bis).
--
--  Regole decise dall'utente:
--   · 3 tentativi per giocatore;
--   · il rifiuto è INFORMATIVO ("troppo poco", "ci siamo quasi") ma consuma
--     un tentativo;
--   · esauriti i tentativi il giocatore NON rinnova più con quella squadra e
--     va a scadenza — conseguenza definitiva, non un blocco temporaneo. Ora
--     che i rinnovi di off-season non esistono più (20260805170000) non c'è
--     modo di aggirarla aspettando giugno;
--   · il contatore NON si azzera mai, se non quando il giocatore firma.
--
--  I due assi si compensano: offrire meno anni di quanti ne voglia richiede
--  più soldi, e viceversa. Senza questo la durata sarebbe una scelta finta
--  (converrebbe sempre il massimo) invece che un secondo asse di trattativa.
-- ============================================================

alter table public.player_instances
  add column rinnovo_tentativi smallint not null default 0
    check (rinnovo_tentativi between 0 and 3);

comment on column public.player_instances.rinnovo_tentativi is
  'Tentativi di rinnovo già consumati (design §10.4 bis). A 3 il giocatore non rinnova più e va a scadenza. Si azzera solo firmando.';

-- ------------------------------------------------------------
--  Quanto il giocatore è disposto a scendere sotto la sua richiesta.
--  Tutto deterministico: dipende solo da mentalità, morale e classifica,
--  mai dal caso — due offerte identiche danno sempre lo stesso esito.
-- ------------------------------------------------------------

create or replace function private.rinnovo_tolleranza(
  p_morale smallint,
  p_bandiera smallint,
  p_economia smallint,
  p_vittorie smallint,
  p_posizione smallint,
  p_squadre smallint
) returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select greatest(0.00, least(0.25,
    0.05                                    -- base: un 5% lo concede chiunque
    + (p_morale - 50) / 500.0                -- morale 100 -> +0,10 · morale 0 -> -0,10
    + p_bandiera / 1000.0                    -- chi ama la maglia fa uno sconto
    - p_economia / 1000.0                    -- chi guarda i soldi non lo fa
    + (0.5 - ((p_posizione - 1)::numeric / greatest(1, p_squadre - 1))) * (p_vittorie / 500.0)
  ))::numeric;
$$;

revoke all on function private.rinnovo_tolleranza(smallint, smallint, smallint, smallint, smallint, smallint)
  from public, anon;
grant execute on function private.rinnovo_tolleranza(smallint, smallint, smallint, smallint, smallint, smallint)
  to authenticated, service_role;

-- ------------------------------------------------------------
--  Proposta + stato della trattativa (sostituisce proposta_rinnovo).
-- ------------------------------------------------------------

create or replace function public.proposta_rinnovo(p_instance_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_inst public.player_instances;
  v_league public.leagues;
  v_player public.players;
  v_proposta record;
  v_posizione smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  if not exists (
    select 1 from public.teams
    where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  return jsonb_build_object(
    'player_instance_id', v_inst.id,
    'ingaggio_attuale', v_inst.ingaggio,
    'scadenza_attuale', v_inst.contratto_scadenza,
    'stagione_corrente', v_league.stagione_corrente,
    'richiesta', v_proposta.richiesta,
    'durata', v_proposta.durata,
    'nuova_scadenza', greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + v_proposta.durata)::smallint),
    'tentativi_usati', v_inst.rinnovo_tentativi,
    'tentativi_totali', 3,
    'trattativa_chiusa', v_inst.rinnovo_tentativi >= 3,
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    )
  );
end;
$$;

-- ------------------------------------------------------------
--  L'offerta della squadra. Sostituisce accetta_rinnovo_stagione, che
--  accettava solo la proposta identica: la firma la fa questa, quando
--  l'offerta supera la soglia.
-- ------------------------------------------------------------

create or replace function public.offri_rinnovo(
  p_instance_id bigint,
  p_ingaggio bigint,
  p_durata smallint
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  v_fattore_durata numeric;
  v_valore numeric;
  v_rapporto numeric;
  v_scadenza smallint;
  v_tentativi smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di trattare un rinnovo.';
  end if;
  if p_ingaggio < 500000 then
    raise exception using errcode = '22023', message = 'L''ingaggio minimo e'' 0,5 M€.';
  end if;
  if p_durata not between 1 and 4 then
    raise exception using errcode = '22023', message = 'La durata deve essere fra 1 e 4 stagioni.';
  end if;

  select * into v_inst from public.player_instances where id = p_instance_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore non trovato.';
  end if;

  select * into v_team from public.teams
  where id = v_inst.team_id and league_id = v_inst.league_id and user_id = v_user_id and attiva;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non e'' nella tua rosa.';
  end if;

  select * into v_league from public.leagues where id = v_inst.league_id;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'I rinnovi si trattano solo a stagione avviata.';
  end if;
  if v_inst.ritirato or v_inst.ritiro_annunciato then
    raise exception using errcode = '55000', message = 'Ha gia'' annunciato il ritiro: non rinnovera'' il contratto.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andra'' a scadenza e lascera'' la squadra.';
  end if;

  select * into v_player from public.players where id = v_inst.player_id;
  select * into v_proposta
  from private.rinnovo_proposta(v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio);

  select coalesce(st.posizione, 1) into v_posizione
  from public.seasons se
  join public.standings st on st.season_id = se.id and st.team_id = v_inst.team_id
  where se.league_id = v_inst.league_id and se.numero = v_league.stagione_corrente;

  v_tolleranza := private.rinnovo_tolleranza(
    v_inst.morale, v_player.mentalita_bandiera, v_player.mentalita_economia,
    v_player.mentalita_vittorie, coalesce(v_posizione, 1), v_league.n_squadre
  );
  v_soglia := v_proposta.richiesta * (1 - v_tolleranza);

  -- I due assi si compensano: allontanarsi dalla durata voluta svaluta
  -- l'offerta del 7% per stagione di scarto, e va compensato con l'ingaggio.
  v_fattore_durata := 1 - abs(p_durata - v_proposta.durata) * 0.07;
  v_valore := p_ingaggio * v_fattore_durata;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + p_durata)::smallint);
    update public.player_instances
    set ingaggio = p_ingaggio,
        contratto_scadenza = v_scadenza,
        rinnovo_tentativi = 0        -- firmato: la trattativa riparte pulita
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
      'durata', p_durata,
      'contratto_scadenza', v_scadenza,
      'tentativi_usati', 0,
      'messaggio', 'Ci sto, mister. Grazie della fiducia.'
    );
  end if;

  -- Rifiuto: consuma un tentativo e dice quanto si era lontani, mai la cifra.
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
$$;

revoke all on function public.offri_rinnovo(bigint, bigint, smallint) from public, anon;
grant execute on function public.offri_rinnovo(bigint, bigint, smallint) to authenticated;

comment on function public.offri_rinnovo(bigint, bigint, smallint) is
  'Offerta di rinnovo su ingaggio e durata (design §10.4 bis). Soglia da mentalità e morale, 3 tentativi, poi il giocatore va a scadenza.';

-- La vecchia accetta_rinnovo_stagione accettava solo la proposta identica:
-- offri_rinnovo la copre interamente (offrire esattamente la richiesta
-- supera sempre la soglia). Si droppa per non lasciare due porte sullo
-- stesso meccanismo, di cui una che ignora i tentativi.
drop function if exists public.accetta_rinnovo_stagione(bigint, bigint, smallint);
