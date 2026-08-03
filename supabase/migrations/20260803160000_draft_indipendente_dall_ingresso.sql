-- ============================================================
--  OGNI SQUADRA INIZIA IL DRAFT APPENA ENTRA, NON QUANDO LA LEGA È PIENA
--
--  Decisione dell'utente, 3 agosto 2026. Design §4.1 dice gia' «nessun
--  ordine di turno, ogni squadra pesca per conto proprio, senza aspettare
--  le altre»: qui si toglie l'ultimo pezzo che contraddiceva quel principio,
--  cioe' il cancello «prima devono esserci tutte le N squadre» che
--  avvia_draft imponeva prima di far partire chiunque.
--
--  Il pattern esiste gia' identico per l'ingresso durante l'off-season
--  (entra_in_lega, ramo fase_carriera='offseason'): un nuovo entrante riceve
--  subito il proprio draft_team_state e puo' aprire pacchetti senza
--  aspettare nessuno. Qui si estende lo stesso pattern all'ingresso
--  INIZIALE, cioe' a stagione 1 prima che la lega sia mai partita.
--
--  RETROCOMPATIBILE DI PROPOSITO. Le leghe gia' ferme in stato 'setup' (due,
--  al momento di questa migrazione, entrambe leghe di prova con una sola
--  squadra) continuano a funzionare esattamente come prima: entra_in_lega
--  accetta ancora 'setup', e avvia_draft resta la via per farle partire una
--  volta piene. Non le si tocca e non si droppa nessuna funzione: sarebbe
--  un cambiamento distruttivo su leghe esistenti per un problema che non
--  hanno. Le leghe NUOVE, create dopo questa migrazione, nascono gia' in
--  stato 'draft' e non passano mai da 'setup'.
-- ============================================================

create or replace function public.crea_lega(
  p_nome_lega text,
  p_nome_squadra text,
  p_stemma_url text,
  p_n_squadre smallint,
  p_n_gironi smallint,
  p_budget_iniziale bigint,
  p_reroll_draft smallint,
  p_slot_rosa smallint,
  p_portieri_minimi smallint,
  p_campionati_attivi text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);
  p_portieri_minimi := 0;

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa <> 24 then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      -- Nasce gia' in 'draft': l'admin non aspetta gli altri per cominciare.
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi, stato
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_reroll_draft, 24, p_portieri_minimi,
        p_campionati_attivi, 'draft'
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, budget, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
    v_league.budget_iniziale, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  -- Contatore di lega (usato per numerare draft_picks, design §4) e stato di
  -- draft della squadra dell'admin: da qui puo' gia' aprire il primo pacchetto.
  insert into public.draft_state (league_id) values (v_league.id);
  insert into public.draft_team_state (team_id, league_id) values (v_team.id, v_league.id);

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

revoke all on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) from public, anon, authenticated;
grant execute on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) to authenticated;

-- ------------------------------------------------------------

create or replace function public.entra_in_lega(
  p_codice text,
  p_nome_squadra text,
  p_stemma_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_partecipanti integer;
  v_ordine integer;
  v_offseason public.offseasons;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;

  p_codice := upper(trim(p_codice));
  p_nome_squadra := trim(p_nome_squadra);

  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non e'' valido.';
  end if;

  select * into v_league from public.leagues where codice_invito = p_codice for update;
  if not found then raise exception using errcode = 'P0002', message = 'Codice invito non trovato.'; end if;
  -- 'draft' aggiunto qui: il draft iniziale ormai comincia squadra per
  -- squadra, quindi una lega che ha gia' iniziato accetta ancora chi entra,
  -- finche' restano posti. 'setup' resta per le leghe nate prima di questa
  -- migrazione, che aspettano ancora avvia_draft.
  if not (v_league.stato in ('setup', 'draft') or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (select 1 from public.teams where league_id = v_league.id and user_id = v_user_id) then
    raise exception using errcode = '23505', message = 'Hai gia'' una squadra in questa lega.';
  end if;
  if not private.stemma_libero_in_lega(v_league.id, p_stemma_url, null) then
    raise exception using errcode = '23505', message = 'Questo stemma e'' gia'' usato nella lega.';
  end if;

  select count(*) into v_partecipanti from public.teams where league_id = v_league.id and attiva;
  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha gia'' raggiunto il numero massimo di squadre.';
  end if;
  select coalesce(max(ordine_draft), -1) + 1 into v_ordine
  from public.teams where league_id = v_league.id;

  begin
    insert into public.teams(
      league_id, user_id, nome, stemma_url, budget, reroll_rimasti,
      ordine_draft, attiva, entrata_stagione
    ) values (
      v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
      v_league.budget_iniziale, v_league.reroll_draft, v_ordine, true,
      case when v_league.fase_carriera = 'offseason' then v_league.stagione_corrente + 1 else 1 end
    ) returning * into v_team;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'Questo nome squadra e'' gia'' usato nella lega.';
  end;

  insert into public.transactions(league_id, team_id, tipo, importo, descrizione, saldo_dopo)
  values (v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
          case when v_league.fase_carriera = 'offseason'
            then 'Dotazione squadra entrante stagione ' || (v_league.stagione_corrente + 1)
            else 'Dotazione iniziale della lega' end,
          v_league.budget_iniziale);

  if v_league.fase_carriera = 'offseason' then
    select * into v_offseason from public.offseasons
    where league_id = v_league.id and stato = 'aperta' order by stagione_a desc limit 1;
    if not found or now() >= v_offseason.scade_il then
      raise exception using errcode = '55000', message = 'La finestra d''ingresso e'' terminata.';
    end if;
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
    insert into public.draft_state(league_id, pick_numero, stato)
    values (v_league.id,
      coalesce((select max(dp.pick_numero) + 1 from public.draft_picks dp where dp.league_id = v_league.id), 0),
      'in_corso')
    on conflict (league_id) do update set stato = 'in_corso', aggiornato_il = now();
    perform private.notifica(v_league.admin_id, v_league.id, 'sistema', 'Nuova squadra iscritta',
      v_team.nome || ' e'' entrata e puo'' iniziare il draft.', jsonb_build_object('team_id', v_team.id));
  elsif v_league.stato = 'draft' then
    -- Draft iniziale gia' in corso per altre squadre: draft_state esiste
    -- gia' (creato da crea_lega), qui basta lo stato per la squadra nuova.
    insert into public.draft_team_state(team_id, league_id) values (v_team.id, v_league.id);
  end if;
  -- v_league.stato = 'setup': nessuna riga di draft_team_state, come prima.
  -- Aspetta avvia_draft quando la lega si riempie.

  return jsonb_build_object('league_id', v_league.id, 'team_id', v_team.id,
    'codice_invito', v_league.codice_invito, 'offseason', v_league.fase_carriera = 'offseason');
end;
$$;

revoke all on function public.entra_in_lega(text, text, text) from public, anon, authenticated;
grant execute on function public.entra_in_lega(text, text, text) to authenticated;
