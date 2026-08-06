-- ============================================================
--  LA MENTALITÀ SPOSTA IL MOLTIPLICATORE DELLA RICHIESTA (design §10.4 bis)
--
--  Segnalato dall'utente su un caso reale: M. Silvestri, 34 anni, OVR 72,
--  bandiera 55 (ramo dominante), già pagato esattamente il suo ingaggio
--  teorico (0,7 M€). Alla trattativa chiedeva 0,8 M€ — un aumento, per un
--  veterano in declino la cui mentalità dominante è "la maglia viene prima
--  dei soldi". La trattativa (private.rinnovo_tolleranza, già esistente)
--  gli fa comunque accettare qualcosa vicino al suo ingaggio attuale, ma la
--  RICHIESTA di partenza non lo sapeva mai: il moltiplicatore casuale era
--  fisso `uniform(1.00, 1.12)` per chiunque, sempre e solo un premio sopra
--  il teorico, mai uno sconto — indipendentemente da età, declino o
--  mentalità.
--
--  Ora il moltiplicatore si sposta attorno a un centro che dipende dal
--  bilancio bandiera/economia del giocatore:
--
--    centro = 1.06 + (economia - bandiera) / 500
--    moltiplicatore = uniform(centro - 0.06, centro + 0.06)
--
--  A bandiera ed economia pari (il caso medio, ~33 e 33) il centro resta
--  1.06 e il range è [1.00, 1.12): IDENTICO a prima, nessun giocatore
--  "medio" cambia comportamento. Solo chi ha un ramo dominante marcato si
--  sposta: bandiera forte spinge il range sotto 1.00 (può chiedere MENO
--  del teorico), economia forte lo spinge sopra 1.12 (chiede sempre di
--  più). Con Silvestri (bandiera 55, economia 17): centro ≈ 0,98, range
--  [0,92-1,04) — la richiesta possibile scende da [0,7-0,8] M€ a
--  [0,7-0,73] M€ (il pavimento sull'ingaggio attuale resta: non è
--  toccato in questa modifica, resta la protezione contro il sovrapprezzo
--  pagato in asta, decisione separata di design §10.4).
--
--  Clamp di sicurezza [0.75, 1.35] sul moltiplicatore: la mentalità è
--  generata su un range osservato di 10-70 per ramo (verificato sui 5.992
--  giocatori del catalogo), quindi lo scarto economia-bandiera resta
--  entro ±60 e il moltiplicatore entro [0.88, 1.24] — il clamp è solo una
--  rete di sicurezza se in futuro la generazione della mentalità cambiasse.
-- ============================================================

drop function if exists private.rinnovo_proposta(bigint, smallint, smallint, bigint);

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
      (abs(hashtext('ing:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_ing,
      (abs(hashtext('dur:' || p_instance_id || ':' || p_overall || ':' || p_eta || ':' || p_ingaggio)) % 1000) / 1000.0 as r_dur
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
    (case
      when p_eta <= 23 then 4
      when p_eta <= 29 then 3 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      when p_eta <= 31 then 2 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      when p_eta <= 33 then 2
      when p_eta <= 35 then 1 + (case when seme.r_dur < 0.5 then 0 else 1 end)
      else 1
    end)::smallint as durata
  from seme, centro;
$$;

revoke all on function private.rinnovo_proposta(bigint, smallint, smallint, bigint, smallint, smallint)
  from public, anon, authenticated;
grant execute on function private.rinnovo_proposta(bigint, smallint, smallint, bigint, smallint, smallint)
  to service_role;

-- ------------------------------------------------------------
--  I due chiamanti passano gia' v_player.mentalita_bandiera/economia:
--  basta aggiungerli alla chiamata.
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
  from private.rinnovo_proposta(
    v_inst.id, v_inst.overall_corrente, v_inst.eta_corrente, v_inst.ingaggio,
    v_player.mentalita_bandiera, v_player.mentalita_economia
  );

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
    'gia_rinnovato', v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente,
    'morale', v_inst.morale,
    'mentalita', jsonb_build_object(
      'bandiera', v_player.mentalita_bandiera,
      'economia', v_player.mentalita_economia,
      'vittorie', v_player.mentalita_vittorie
    )
  );
end;
$$;

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
  if v_inst.rinnovo_stagione is not null and v_inst.rinnovo_stagione = v_league.stagione_corrente then
    raise exception using errcode = '55000',
      message = 'Ha gia'' rinnovato in questa stagione: se ne riparla dalla prossima.';
  end if;
  if v_inst.rinnovo_tentativi >= 3 then
    raise exception using errcode = '55000',
      message = 'Ha chiuso la trattativa: andra'' a scadenza e lascera'' la squadra.';
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

  v_fattore_durata := 1 - abs(p_durata - v_proposta.durata) * 0.07;
  v_valore := p_ingaggio * v_fattore_durata;
  v_rapporto := v_valore / greatest(1, v_soglia);

  if v_rapporto >= 1 then
    v_scadenza := greatest(v_inst.contratto_scadenza, (v_league.stagione_corrente + p_durata)::smallint);
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
      'durata', p_durata,
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
$$;
