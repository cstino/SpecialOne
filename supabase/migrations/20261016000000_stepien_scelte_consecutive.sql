-- Funzioni degli scambi riscritte dalle definizioni vive: cambia solo il testo dei messaggi sulla regola Stepien.
-- Regola Stepien, versione severa (deciso il 15/10/2026 dopo lo scambio 583 Pro secco / ASD Cola Zero): una squadra non puo'
-- cedere due proprie scelte CONSECUTIVE NEL TEMPO. L'ordine e' ON n, OFF n, ON n+1, OFF n+1, ...: quindi ON-Season 2 e
-- OFF-Season 2 insieme no, e nemmeno OFF-Season 2 e ON-Season 3. (Prima: solo due stagioni consecutive nella stessa finestra.)
-- Non e' retroattiva: scatta solo se lo scambio che si propone/accetta cede una delle due scelte della coppia.
create or replace function private.viola_regola_stepien(p_team_id bigint, p_scelte_cedute bigint[])
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  with proprie as (
    select id, stagione * 2 + (finestra = 'off')::int as posto,
      (team_proprietario_id <> team_origine_id or id = any(p_scelte_cedute)) as ceduta,
      (id = any(p_scelte_cedute)) as in_questo_scambio
    from public.scelte_draft
    where team_origine_id = p_team_id
      and stato in ('futura', 'determinata')
  )
  select coalesce(bool_or(a.ceduta and b.ceduta and (a.in_questo_scambio or b.in_questo_scambio)), false)
  from proprie a join proprie b on b.posto = a.posto + 1
$function$;


CREATE OR REPLACE FUNCTION public.proponi_scambio(p_a_team_id bigint, p_giocatori_offerti bigint[] DEFAULT '{}'::bigint[], p_giocatori_richiesti bigint[] DEFAULT '{}'::bigint[], p_scelte_offerte bigint[] DEFAULT '{}'::bigint[], p_scelte_richieste bigint[] DEFAULT '{}'::bigint[], p_messaggio text DEFAULT NULL::text)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_dest public.teams;
  v_mia public.teams;
  v_lega public.leagues;
  v_g_off bigint[] := coalesce(p_giocatori_offerti, '{}');
  v_g_ric bigint[] := coalesce(p_giocatori_richiesti, '{}');
  v_s_off bigint[] := coalesce(p_scelte_offerte, '{}');
  v_s_ric bigint[] := coalesce(p_scelte_richieste, '{}');
  v_n integer;
  v_scadenza timestamptz;
  v_proposta public.trade_proposals;
  v_utente_dest uuid;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;
  select * into v_dest from public.teams where id = p_a_team_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Squadra destinataria inesistente.';
  end if;
  select * into v_mia from public.teams where league_id = v_dest.league_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;
  if v_mia.id = v_dest.id then
    raise exception using errcode = '22023', message = 'Non puoi proporre uno scambio a te stesso.';
  end if;
  select * into v_lega from public.leagues where id = v_dest.league_id;
  if v_lega.stato <> 'stagione' or not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso.';
  end if;

  if cardinality(v_g_off) + cardinality(v_g_ric) + cardinality(v_s_off) + cardinality(v_s_ric) = 0 then
    raise exception using errcode = '22023', message = 'Una proposta deve contenere almeno un giocatore o una scelta.';
  end if;

  if cardinality(array(select distinct unnest(v_g_off))) <> cardinality(v_g_off)
     or cardinality(array(select distinct unnest(v_g_ric))) <> cardinality(v_g_ric)
     or v_g_off && v_g_ric then
    raise exception using errcode = '22023', message = 'Un giocatore compare due volte nella proposta.';
  end if;
  if cardinality(array(select distinct unnest(v_s_off))) <> cardinality(v_s_off)
     or cardinality(array(select distinct unnest(v_s_ric))) <> cardinality(v_s_ric)
     or v_s_off && v_s_ric then
    raise exception using errcode = '22023', message = 'Una scelta compare due volte nella proposta.';
  end if;

  select count(*) into v_n from public.player_instances
  where id = any(v_g_off) and team_id = v_mia.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo un giocatore che non e'' tuo.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_g_ric) and team_id = v_dest.id and league_id = v_lega.id;
  if v_n <> cardinality(v_g_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo un giocatore che non e'' di quella squadra.';
  end if;
  if exists (select 1 from public.player_instances where id = any(v_g_off || v_g_ric) and ritiro_annunciato) then
    raise exception using errcode = '55000', message = 'Uno dei giocatori coinvolti ha annunciato il ritiro.';
  end if;

  -- Una scelta si offre solo finche' non e' stata esercitata: 'usata' e
  -- 'vuota' sono gia' storia, non piu' un asset.
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_off) and team_proprietario_id = v_mia.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_off) then
    raise exception using errcode = '22023', message = 'Stai offrendo una scelta che non possiedi o gia'' esercitata.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_s_ric) and team_proprietario_id = v_dest.id and league_id = v_lega.id
    and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_s_ric) then
    raise exception using errcode = '22023', message = 'Stai chiedendo una scelta che quella squadra non possiede o gia'' esercitata.';
  end if;

  -- Regola Stepien: nessuna delle due squadre puo' restare senza la
  -- propria scelta d'origine in due stagioni consecutive della stessa
  -- finestra (docs/decisioni-draft-picks.md §7).
  if cardinality(v_s_off) > 0 and private.viola_regola_stepien(v_mia.id, v_s_off) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;
  if cardinality(v_s_ric) > 0 and private.viola_regola_stepien(v_dest.id, v_s_ric) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_dest.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  v_scadenza := (date_trunc('day', now() at time zone 'Europe/Rome') + interval '21 hours') at time zone 'Europe/Rome';
  if v_scadenza <= now() then v_scadenza := v_scadenza + interval '1 day'; end if;

  insert into public.trade_proposals(
    league_id, da_team_id, a_team_id,
    giocatori_offerti, giocatori_richiesti, scelte_offerte, scelte_richieste,
    messaggio, scade_il
  ) values (
    v_lega.id, v_mia.id, v_dest.id,
    v_g_off, v_g_ric, v_s_off, v_s_ric,
    nullif(btrim(coalesce(p_messaggio, '')), ''), v_scadenza
  ) returning * into v_proposta;

  select user_id into v_utente_dest from public.teams where id = v_dest.id;
  if v_utente_dest is not null then
    perform private.notifica(v_utente_dest, v_lega.id, 'mercato_proposta', 'Proposta di mercato da ' || v_mia.nome,
      'Proposta di mercato: scade alle 21:00.', jsonb_build_object('proposta_id', v_proposta.id));
  end if;
  return v_proposta;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rispondi_a_proposta(p_proposta_id bigint, p_accetta boolean)
 RETURNS trade_proposals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente     uuid := (select auth.uid());
  v_p          public.trade_proposals;
  v_lega       public.leagues;
  v_da         public.teams;
  v_a          public.teams;
  v_stagione   smallint;
  v_n          integer;
  v_rosa_da    integer;
  v_rosa_a     integer;
  v_prossima   integer;
  v_tutti      bigint[];
  v_form_tolte integer := 0;
  v_nota       text := '';
  v_delta_da   bigint;
  v_delta_a    bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per usare il mercato.';
  end if;

  select * into v_p from public.trade_proposals where id = p_proposta_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Proposta inesistente.';
  end if;
  if not (select private.e_mia_squadra(v_p.a_team_id)) then
    raise exception using errcode = '42501', message = 'Questa proposta non e'' indirizzata a te.';
  end if;
  if v_p.stato <> 'in_attesa' then
    raise exception using errcode = '55000', message = 'Questa proposta e'' gia'' stata risolta.';
  end if;
  if now() >= v_p.scade_il then
    raise exception using errcode = '55000', message = 'Questa proposta e'' scaduta.';
  end if;

  if not coalesce(p_accetta, false) then
    update public.trade_proposals set stato = 'rifiutata', risolta_il = now()
    where id = v_p.id
    returning * into v_p;

    perform private.notifica(
      (select user_id from public.teams where id = v_p.da_team_id),
      v_p.league_id, 'mercato_esito', 'Proposta rifiutata',
      (select nome from public.teams where id = v_p.a_team_id) || ' ha rifiutato la tua proposta.',
      jsonb_build_object('proposta_id', v_p.id)
    );
    return v_p;
  end if;

  if not private.mercato_aperto_lega(v_p.league_id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: si conclude dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select * into v_lega from public.leagues where id = v_p.league_id;

  perform 1 from public.teams where id in (v_p.da_team_id, v_p.a_team_id) order by id for update;
  select * into v_da from public.teams where id = v_p.da_team_id;
  select * into v_a  from public.teams where id = v_p.a_team_id;

  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_offerti) and team_id = v_da.id;
  if v_n <> cardinality(v_p.giocatori_offerti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore offerto non e'' piu'' in quella rosa: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.player_instances
  where id = any(v_p.giocatori_richiesti) and team_id = v_a.id;
  if v_n <> cardinality(v_p.giocatori_richiesti) then
    raise exception using errcode = '55000',
      message = 'Un giocatore richiesto non e'' piu'' nella tua rosa: la proposta non e'' piu'' valida.';
  end if;
  if exists (
    select 1 from public.player_instances
    where id = any(v_p.giocatori_offerti || v_p.giocatori_richiesti) and ritiro_annunciato
  ) then
    raise exception using errcode = '55000',
      message = 'Uno dei giocatori coinvolti ha annunciato il ritiro: la proposta non e'' piu'' valida.';
  end if;

  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_offerte) and team_proprietario_id = v_da.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_offerte) then
    raise exception using errcode = '55000',
      message = 'Una scelta offerta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;
  select count(*) into v_n from public.scelte_draft
  where id = any(v_p.scelte_richieste) and team_proprietario_id = v_a.id and stato in ('futura', 'determinata');
  if v_n <> cardinality(v_p.scelte_richieste) then
    raise exception using errcode = '55000',
      message = 'Una scelta richiesta non e'' piu'' disponibile: la proposta non e'' piu'' valida.';
  end if;

  if cardinality(v_p.scelte_offerte) > 0 and private.viola_regola_stepien(v_da.id, v_p.scelte_offerte) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: ' || v_da.nome || ' non puo'' cedere due proprie scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva). La proposta non e'' piu'' valida.';
  end if;
  if cardinality(v_p.scelte_richieste) > 0 and private.viola_regola_stepien(v_a.id, v_p.scelte_richieste) then
    raise exception using errcode = '22023',
      message = 'Regola Stepien: non puoi cedere due tue scelte consecutive (la ON e la OFF della stessa stagione, oppure la OFF di una stagione e la ON della successiva).';
  end if;

  select count(*) into v_rosa_da from public.player_instances where team_id = v_da.id;
  select count(*) into v_rosa_a  from public.player_instances where team_id = v_a.id;
  v_rosa_da := v_rosa_da - cardinality(v_p.giocatori_offerti) + cardinality(v_p.giocatori_richiesti);
  v_rosa_a  := v_rosa_a  - cardinality(v_p.giocatori_richiesti) + cardinality(v_p.giocatori_offerti);
  if v_rosa_da > private.rosa_massima() or v_rosa_a > private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Lo scambio porterebbe una rosa oltre i 30 giocatori.';
  end if;
  if v_rosa_da < private.rosa_minima() or v_rosa_a < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Lo scambio lascerebbe una rosa sotto i 21 giocatori.';
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  update public.player_instances set team_id = v_a.id,  giornata_acquisizione = v_prossima where id = any(v_p.giocatori_offerti);
  update public.player_instances set team_id = v_da.id, giornata_acquisizione = v_prossima where id = any(v_p.giocatori_richiesti);
  update public.scelte_draft set team_proprietario_id = v_a.id,  aggiornata_il = now() where id = any(v_p.scelte_offerte);
  update public.scelte_draft set team_proprietario_id = v_da.id, aggiornata_il = now() where id = any(v_p.scelte_richieste);

  v_stagione := private.stagione_contratto(v_p.league_id);
  if private.monte_ingaggi(v_da.id, v_stagione) + private.ingaggi_impegnati_aste(v_da.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio porterebbe ' || v_da.nome || ' oltre il tetto ingaggi.';
  end if;
  if private.monte_ingaggi(v_a.id, v_stagione) + private.ingaggi_impegnati_aste(v_a.id, null) > v_lega.tetto_ingaggi then
    raise exception using errcode = '22023',
      message = 'Questo scambio ti porterebbe oltre il tetto ingaggi.';
  end if;

  v_tutti := v_p.giocatori_offerti || v_p.giocatori_richiesti;
  if v_prossima is not null and cardinality(v_tutti) > 0 then
    -- Le formazioni NON si cancellano piu' (8 ottobre 2026): si tolgono solo i giocatori ceduti, e il resto
    -- (modulo, stile, ruoli, compiti, schieramento, panchina) resta com'era. Il posto lasciato libero in campo
    -- lo riempie la formazione automatica alla simulazione, o l'allenatore prima.
    v_form_tolte := private.togli_giocatori_dalle_formazioni(v_lega.id, array[v_da.id, v_a.id], v_tutti, v_prossima);
  end if;
  if v_form_tolte > 0 then
    v_nota := ' Controlla la formazione: era schierato un giocatore coinvolto.';
  end if;

  select coalesce(sum(ingaggio), 0) into v_delta_da
  from public.player_instances where id = any(v_p.giocatori_richiesti);
  v_delta_da := v_delta_da - coalesce((select sum(ingaggio) from public.player_instances where id = any(v_p.giocatori_offerti)), 0);
  v_delta_a := -v_delta_da;

  if v_delta_da <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_da.id, 'mercato_scambio', v_delta_da, 'Scambio con ' || v_a.nome, 0);
  end if;
  if v_delta_a <> 0 then
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_a.id, 'mercato_scambio', v_delta_a, 'Scambio con ' || v_da.nome, 0);
  end if;

  update public.trade_proposals set stato = 'accettata', risolta_il = now()
  where id = v_p.id
  returning * into v_p;

  perform private.notifica(v_da.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_a.nome,
    'La tua proposta e'' stata accettata.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica(v_a.user_id, v_lega.id, 'mercato_esito', 'Scambio concluso con ' || v_da.nome,
    'Hai accettato la proposta.' || v_nota, jsonb_build_object('proposta_id', v_p.id));
  perform private.notifica_scambio_ufficiale(v_lega.id, v_da.id, v_a.id, v_p.id);

  return v_p;
end;
$function$;
