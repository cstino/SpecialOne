-- SocialOne: i giornali non citano piu' overall e potenziale (richiesta del committente, 6/11/2026).
-- L'overall e' un numero del gioco: un giornale vero scrive "uno dei migliori nel suo ruolo", "un talento destinato a
-- crescere". Il numero resta dietro le quinte e sceglie la frase. Le analisi degli influencer restano coi numeri della
-- partita (possesso, tiri), che sono quelli che si leggono anche sui giornali veri.

-- Come un giornale descrive un giocatore, dalla sua qualita' (e dall'eta', per i giovani col margine).
create or replace function private.stampa_giudizio(p_ovr integer, p_eta integer, p_pot integer, p_seme text)
returns text language sql immutable set search_path = '' as $$
  select private.social_scegli('gz' || p_seme, case
    when p_ovr >= 86 then array['uno dei giocatori più forti del campionato', 'un fuoriclasse vero', 'un campione affermato']
    when coalesce(p_eta, 25) <= 21 and coalesce(p_pot, 0) - p_ovr >= 8 then array['un talento destinato a crescere', 'uno dei giovani più promettenti della lega', 'un predestinato, a sentire chi lo conosce']
    when p_ovr >= 82 then array['uno dei migliori nel suo ruolo', 'un titolare di lusso', 'un giocatore che sposta gli equilibri']
    when p_ovr >= 78 then array['un titolare affidabile', 'un giocatore di qualità', 'un elemento di sicuro rendimento']
    when p_ovr >= 74 then array['un giocatore di sostanza', 'un rinforzo concreto', 'un elemento utile alla causa']
    when p_ovr >= 70 then array['un rinforzo per la rotazione', 'un uomo di fiducia per la panchina', 'un jolly per le seconde linee']
    when coalesce(p_eta, 25) <= 22 then array['una scommessa per il futuro', 'un giovane da far crescere']
    else array['un rincalzo', 'un ricambio per la rosa'] end)
$$;

-- Il potenziale di un giovane, a parole.
create or replace function private.stampa_prospetto(p_pot integer, p_seme text)
returns text language sql immutable set search_path = '' as $$
  select private.social_scegli('pr' || p_seme, case
    when p_pot >= 88 then array['chi lo ha visto giocare giura che diventerà un campione', 'in molti lo considerano un futuro top player']
    when p_pot >= 82 then array['ha i numeri per diventare un titolare di alto livello', 'gli addetti ai lavori lo vedono già in prima squadra tra poco']
    else array['ha margini di crescita interessanti', 'può ritagliarsi uno spazio importante col tempo'] end)
$$;

CREATE OR REPLACE FUNCTION private.stampa_scambio(p_trade_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tp public.trade_proposals;
  v_da public.teams;
  v_a public.teams;
  v_top record;
  v_ha_top boolean;
  v_dest public.teams;
  v_orig public.teams;
  v_contro text;
  v_insieme text;
  v_in_da numeric; v_out_da numeric; v_voto_da numeric;
  v_in_a numeric;  v_out_a numeric;  v_voto_a numeric;
  v_best_in_da text; v_best_in_a text; v_best_out_da text; v_best_out_a text;
  v_testo text;
  v_morale integer;
  v_insider text;
  v_post bigint;
  v_basso public.teams;
  v_voto_basso numeric;
  v_alto public.teams;
  v_voto_alto numeric;
  v_n integer := 0;
  v_k text := p_trade_id::text;
begin
  select * into v_tp from public.trade_proposals where id = p_trade_id and stato = 'accettata';
  if not found then return 0; end if;
  select * into v_da from public.teams where id = v_tp.da_team_id;
  select * into v_a from public.teams where id = v_tp.a_team_id;

  -- Tutto quello che si muove, con la squadra che lo riceve. Le scelte valgono come un buon titolare.
  create temp table if not exists tmp_stampa_mossi (pi_id bigint, nome text, ovr integer, eta integer, pot integer, ruolo text,
    ingaggio numeric, dest bigint, valore numeric) on commit drop;
  truncate pg_temp.tmp_stampa_mossi;
  insert into pg_temp.tmp_stampa_mossi
  select pi.id, p.nome, pi.overall_corrente, pi.eta_corrente, p.potential, (coalesce(pi.posizioni_override, p.posizioni))[1], pi.ingaggio,
         case when pi.id = any (v_tp.giocatori_offerti) then v_tp.a_team_id else v_tp.da_team_id end,
         private.stampa_valore(pi.overall_corrente, pi.eta_corrente, p.potential)
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.id = any (v_tp.giocatori_offerti || v_tp.giocatori_richiesti);
  insert into pg_temp.tmp_stampa_mossi
  select null, p.nome, p.overall, p.eta, p.potential, (coalesce(vp.posizioni_override, p.posizioni))[1], vp.ingaggio,
         case when vp.id = any (v_tp.vivaio_offerti) then v_tp.a_team_id else v_tp.da_team_id end,
         private.stampa_valore(p.overall, p.eta, p.potential)
  from public.vivaio_prospetti vp join public.players p on p.id = vp.player_id
  where vp.id = any (v_tp.vivaio_offerti || v_tp.vivaio_richiesti);
  insert into pg_temp.tmp_stampa_mossi
  select null::bigint, null::text, null::integer, null::integer, null::integer, null::text, null::numeric, v_tp.a_team_id, private.stampa_valore(74, 25, 74) from unnest(v_tp.scelte_offerte)
  union all
  select null, null, null, null, null, null, null, v_tp.da_team_id, private.stampa_valore(74, 25, 74) from unnest(v_tp.scelte_richieste);

  -- Valore ricevuto da ciascuna squadra: il pezzo migliore conta per intero, gli altri via via meno (0,7^n).
  select coalesce(sum(valore * power(0.7, rn - 1)) filter (where dest = v_da.id), 0),
         coalesce(sum(valore * power(0.7, rn - 1)) filter (where dest = v_a.id), 0)
    into v_in_da, v_in_a
  from (select dest, valore, row_number() over (partition by dest order by valore desc) as rn from pg_temp.tmp_stampa_mossi) x;
  v_out_da := v_in_a; v_out_a := v_in_da;
  v_voto_da := least(9, greatest(4, round((6 + 3.5 * (v_in_da - v_out_da) / greatest(v_in_da, v_out_da, 1)) * 2) / 2));
  v_voto_a  := least(9, greatest(4, round((6 + 3.5 * (v_in_a - v_out_a) / greatest(v_in_a, v_out_a, 1)) * 2) / 2));
  select nome into v_best_in_da from pg_temp.tmp_stampa_mossi where dest = v_da.id and nome is not null order by ovr desc nulls last limit 1;
  select nome into v_best_in_a from pg_temp.tmp_stampa_mossi where dest = v_a.id and nome is not null order by ovr desc nulls last limit 1;
  v_best_out_da := v_best_in_a; v_best_out_a := v_best_in_da;

  -- 1. La Gazzetta: l'ufficialita', col nome piu' pesante dello scambio in testa.
  select * into v_top from pg_temp.tmp_stampa_mossi where nome is not null order by ovr desc nulls last, valore desc limit 1;
  v_ha_top := found;
  if v_ha_top then
    select * into v_dest from public.teams where id = v_top.dest;
    select * into v_orig from public.teams where id = case when v_top.dest = v_da.id then v_a.id else v_da.id end;
    if v_top.dest = v_a.id then
      v_contro := case when cardinality(v_tp.giocatori_richiesti) + cardinality(v_tp.vivaio_richiesti) + cardinality(v_tp.scelte_richieste) > 0
        then private.descrizione_cessione(v_tp.giocatori_richiesti, v_tp.vivaio_richiesti, v_tp.scelte_richieste) end;
      v_insieme := case when v_top.pi_id is not null and cardinality(array_remove(v_tp.giocatori_offerti, v_top.pi_id)) + cardinality(v_tp.vivaio_offerti) + cardinality(v_tp.scelte_offerte) > 0
        then private.descrizione_cessione(array_remove(v_tp.giocatori_offerti, v_top.pi_id), v_tp.vivaio_offerti, v_tp.scelte_offerte) end;
    else
      v_contro := case when cardinality(v_tp.giocatori_offerti) + cardinality(v_tp.vivaio_offerti) + cardinality(v_tp.scelte_offerte) > 0
        then private.descrizione_cessione(v_tp.giocatori_offerti, v_tp.vivaio_offerti, v_tp.scelte_offerte) end;
      v_insieme := case when v_top.pi_id is not null and cardinality(array_remove(v_tp.giocatori_richiesti, v_top.pi_id)) + cardinality(v_tp.vivaio_richiesti) + cardinality(v_tp.scelte_richieste) > 0
        then private.descrizione_cessione(array_remove(v_tp.giocatori_richiesti, v_top.pi_id), v_tp.vivaio_richiesti, v_tp.scelte_richieste) end;
    end if;
    v_testo := private.social_scegli('gs' || v_k, array[
      '🔴 UFFICIALE | ' || v_top.nome || ' è un nuovo giocatore di ' || v_dest.nome || '. ' || initcap(left(private.ruolo_esteso(v_top.ruolo), 1)) || substr(private.ruolo_esteso(v_top.ruolo), 2)
        || ' di ' || v_top.eta || ' anni, ' || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || ', lascia ' || v_orig.nome
        || coalesce(' nell''operazione che porta in direzione opposta ' || v_contro, ' senza contropartite tecniche') || '.'
        || coalesce(' Con lui si trasferisce anche ' || v_insieme || '.', '')
        || coalesce(' Ingaggio da ' || private.milioni(v_top.ingaggio) || ' a stagione.', ''),
      '🔴 È FATTA | ' || v_dest.nome || ' e ' || v_orig.nome || ' chiudono lo scambio: ' || v_top.nome || ' (' || private.ruolo_esteso(v_top.ruolo) || ', '
        || v_top.eta || ' anni) cambia maglia. Per ' || v_dest.nome || ' arriva ' || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || '.'
        || coalesce(' ' || v_orig.nome || ' riceve ' || v_contro || '.', '')
        || coalesce(' Nell''affare entra anche ' || v_insieme || '.', ''),
      '🔴 COLPO ' || upper(v_dest.nome) || ' | Preso ' || v_top.nome || ', ' || private.ruolo_esteso(v_top.ruolo) || ' di ' || v_top.eta || ' anni: '
        || private.stampa_giudizio(v_top.ovr, v_top.eta, v_top.pot, 'gs' || v_k) || '. Saluta ' || v_orig.nome || ' dopo una trattativa lampo.'
        || coalesce(' La contropartita: ' || v_contro || '.', '')
        || coalesce(' Per lui ' || private.milioni(v_top.ingaggio) || ' di ingaggio.', '')]);
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, player_instance_id, testo, creato_il)
    values (v_tp.league_id, 'stampa-scambio:' || v_k, 'testata', 'La Gazzetta dello Sprint', 'gazzettasprint', 'gazzettasprint',
            v_dest.id, v_orig.id, v_top.pi_id, left(v_testo, 700), v_tp.risolta_il + interval '3 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;

  -- 2. Le pagelle del Corriere dello Spot.
  v_testo := '📝 PAGELLE DEL MERCATO' || chr(10) || chr(10)
    || v_da.nome || ' ' || private.voto_testo(v_voto_da) || ' — '
    || private.social_scegli('pd' || v_k, case
         when v_voto_da >= 7.5 then array['Colpo da applausi: ' || coalesce(v_best_in_da, 'quello che arriva') || ' alza subito il livello.', 'Operazione da prima pagina. ' || coalesce(v_best_in_da, 'L''acquisto') || ' cambia la squadra.']
         when v_voto_da >= 6.5 then array['Buon affare: ' || coalesce(v_best_in_da, 'l''innesto') || ' è un rinforzo che serve.', 'Mossa intelligente, con ' || coalesce(v_best_in_da, 'il nuovo arrivo') || ' si guadagna qualcosa.']
         when v_voto_da >= 6 then array['Operazione equilibrata, senza squilli.', 'Scambio alla pari: né vinto né perso.']
         when v_voto_da >= 5 then array['Qualche dubbio: perdere ' || coalesce(v_best_out_da, 'quei pezzi') || ' pesa più di quanto sembri.', 'Affare che non convince fino in fondo: senza ' || coalesce(v_best_out_da, 'chi parte') || ' la rosa si impoverisce.']
         else array['Bocciati: via ' || coalesce(v_best_out_da, 'tanta qualità') || ' e in cambio troppo poco.', 'Mercato da dimenticare: la cessione di ' || coalesce(v_best_out_da, 'quei giocatori') || ' farà rumore.'] end)
    || chr(10)
    || v_a.nome || ' ' || private.voto_testo(v_voto_a) || ' — '
    || private.social_scegli('pa' || v_k, case
         when v_voto_a >= 7.5 then array['Colpo da applausi: ' || coalesce(v_best_in_a, 'quello che arriva') || ' alza subito il livello.', 'Operazione da prima pagina. ' || coalesce(v_best_in_a, 'L''acquisto') || ' cambia la squadra.']
         when v_voto_a >= 6.5 then array['Buon affare: ' || coalesce(v_best_in_a, 'l''innesto') || ' è un rinforzo che serve.', 'Mossa intelligente, con ' || coalesce(v_best_in_a, 'il nuovo arrivo') || ' si guadagna qualcosa.']
         when v_voto_a >= 6 then array['Operazione equilibrata, senza squilli.', 'Scambio alla pari: né vinto né perso.']
         when v_voto_a >= 5 then array['Qualche dubbio: perdere ' || coalesce(v_best_out_a, 'quei pezzi') || ' pesa più di quanto sembri.', 'Affare che non convince fino in fondo: senza ' || coalesce(v_best_out_a, 'chi parte') || ' la rosa si impoverisce.']
         else array['Bocciati: via ' || coalesce(v_best_out_a, 'tanta qualità') || ' e in cambio troppo poco.', 'Mercato da dimenticare: la cessione di ' || coalesce(v_best_out_a, 'quei giocatori') || ' farà rumore.'] end);
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
  values (v_tp.league_id, 'pagelle-scambio:' || v_k, 'testata', 'Corriere dello Spot', 'corrierespot', 'corrierespot',
          v_da.id, v_a.id, left(v_testo, 700), v_tp.risolta_il + interval '25 minutes')
  on conflict (league_id, chiave) do nothing
  returning id into v_post;
  v_n := v_n + 1;

  -- Un tifoso risponde alle pagelle: quello bocciato protesta, altrimenti quello promosso gongola.
  if v_post is not null then
    if v_voto_da <= v_voto_a then v_basso := v_da; v_voto_basso := v_voto_da; v_alto := v_a; v_voto_alto := v_voto_a;
    else v_basso := v_a; v_voto_basso := v_voto_a; v_alto := v_da; v_voto_alto := v_voto_da; end if;
    if v_voto_basso <= 5.5 then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
      values (v_tp.league_id, 'pagelle-tifoso:' || v_k, 'tifosi',
              (private.tifoso_finto('pg' || v_k, v_basso.nome)).nome, (private.tifoso_finto('pg' || v_k, v_basso.nome)).handle, v_basso.id, v_post,
              private.social_scegli('pgt' || v_k, array[
                private.voto_testo(v_voto_basso) || '?? ma l''avete vista giocare @' || private.handle_squadra(v_basso.nome) || ' almeno una volta? giornalai',
                'voto ridicolo. tra due mesi venite a chiedere scusa 🤡',
                'il @corrierespot non ci capisce niente di calcio, come sempre',
                'ok il ' || private.voto_testo(v_voto_basso) || ' ma ne riparliamo a fine stagione. salvate il post 📌']),
              v_tp.risolta_il + interval '32 minutes')
      on conflict (league_id, chiave) do nothing;
    elsif v_voto_alto >= 7 then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
      values (v_tp.league_id, 'pagelle-tifoso:' || v_k, 'tifosi',
              (private.tifoso_finto('pg' || v_k, v_alto.nome)).nome, (private.tifoso_finto('pg' || v_k, v_alto.nome)).handle, v_alto.id, v_post,
              private.social_scegli('pgt' || v_k, array[
                'pure il @corrierespot lo dice. mercato da paura @' || private.handle_squadra(v_alto.nome) || ' 🔥',
                private.voto_testo(v_voto_alto) || ' è pure poco. ditelo che vi rode 😎',
                'finalmente una pagella giusta. si vola 🚀']),
              v_tp.risolta_il + interval '32 minutes')
      on conflict (league_id, chiave) do nothing;
    end if;
  end if;

  -- 3. Il retroscena (sei scambi su dieci): verosimile, mai dati veri delle trattative.
  if v_ha_top and abs(hashtext('ins' || v_k)) % 10 < 6 then
    v_morale := null;
    if v_top.pi_id is not null then
      select tg.morale_prima into v_morale from private.trasferimenti_giocatori tg
       where tg.player_instance_id = v_top.pi_id and tg.creato_il between v_tp.risolta_il - interval '10 minutes' and v_tp.risolta_il + interval '1 hour'
       order by tg.creato_il desc limit 1;
    end if;
    v_insider := case when abs(hashtext('chi' || v_k)) % 2 = 0 then 'fabrizioromanzo' else 'dimarzipane' end;
    v_testo := case
      when v_morale is not null and v_morale < 45 then private.social_scegli('rt' || v_k, array[
        'Mi risulta che ' || v_top.nome || ' avesse chiesto di partire già da qualche settimana. Rapporti freddi con lo staff di ' || v_orig.nome || ': l''addio era nell''aria.',
        'Dietro la cessione di ' || v_top.nome || ' c''è un malumore che durava da tempo. Il giocatore voleva cambiare aria e ' || v_dest.nome || ' ha colto l''occasione al volo.'])
      when v_top.eta >= 30 then private.social_scegli('rt' || v_k, array[
        v_orig.nome || ' voleva abbassare l''età media della rosa: per questo ha aperto alla cessione di ' || v_top.nome || '. Il giocatore ha accettato senza fare storie.',
        'A ' || v_top.eta || ' anni ' || v_top.nome || ' cercava un progetto per vincere subito. ' || v_dest.nome || ' gli ha garantito un ruolo centrale: decisivo il colloquio con l''allenatore.'])
      when v_top.eta <= 21 then private.social_scegli('rt' || v_k, array[
        v_dest.nome || ' seguiva ' || v_top.nome || ' da tempo: decisiva la promessa di minuti da protagonista. Il ragazzo ha detto sì in poche ore.',
        'Su ' || v_top.nome || ' c''erano gli occhi di mezza lega, ma ' || v_dest.nome || ' si è mossa prima di tutti. Talento puro, lo staff lo considera un investimento per anni.'])
      else private.social_scegli('rt' || v_k, array[
        v_dest.nome || ' cercava un ' || private.ruolo_esteso(v_top.ruolo) || ' da settimane: ' || v_top.nome || ' era la prima scelta dello staff tecnico. Trattativa lampo.',
        'L''allenatore di ' || v_dest.nome || ' ha chiamato personalmente ' || v_top.nome || ' prima di chiudere. Una telefonata che ha convinto il giocatore.'])
    end;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, player_instance_id, testo, creato_il)
    values (v_tp.league_id, 'retroscena-scambio:' || v_k, 'testata',
            case v_insider when 'fabrizioromanzo' then 'Fabrizio Romanzo' else 'Gianluca Di Marzipane' end, v_insider, v_insider,
            v_dest.id, v_orig.id, v_top.pi_id,
            case v_insider when 'fabrizioromanzo' then '🚨 ' else 'ESCLUSIVA | ' end || v_testo, v_tp.risolta_il + interval '70 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION private.social_genera_stampa()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- Solo gli eventi da oggi in poi: niente valanga di articoli sugli scambi delle settimane scorse.
  v_dal timestamptz := greatest(now() - interval '3 days', timestamptz '2026-11-06 12:00:00+00');
  v_n integer := 0;
  v_r record;
  v_g record;
  v_m record;
  v_s record;
  v_post bigint;
  v_k text;
  v_tab text;
begin
  -- 1. Scambi.
  for v_r in
    select tp.id from public.trade_proposals tp
    join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
    where tp.stato = 'accettata' and tp.risolta_il > v_dal
      and not exists (select 1 from public.social_posts sp where sp.league_id = tp.league_id and sp.chiave = 'pagelle-scambio:' || tp.id)
    order by tp.risolta_il
  loop
    v_n := v_n + private.stampa_scambio(v_r.id);
  end loop;

  -- 2. Aste degli svincolati: Sky Spot 24.
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
  select a.league_id, 'stampa-asta:' || a.id, 'testata', 'Sky Spot 24', 'skyspot24', 'skyspot24', a.vincitore_team_id, pi.id,
         private.social_scegli('ss' || a.id, array[
           '⚡ BREAKING | ' || p.nome || ' è di ' || t.nome || '. Lo svincolato (' || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1]) || ', '
             || coalesce(pi.eta_corrente, p.eta) || ' anni) firma per ' || private.milioni(a.ingaggio_finale) || ': '
             || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id) || '.',
           '⚡ ULTIM''ORA | Colpo dagli svincolati per ' || t.nome || ': preso ' || p.nome || ', ' || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1])
             || ' di ' || coalesce(pi.eta_corrente, p.eta) || ' anni, ' || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id)
             || '. Ingaggio da ' || private.milioni(a.ingaggio_finale) || '.',
           '⚡ BREAKING | ' || t.nome || ' vince l''asta per ' || p.nome || '. ' || coalesce(pi.eta_corrente, p.eta) || ' anni, '
             || private.stampa_giudizio(coalesce(pi.overall_corrente, p.overall), coalesce(pi.eta_corrente, p.eta), p.potential, 'ss' || a.id) || ': arriva a ' || private.milioni(a.ingaggio_finale) || ' a stagione.']),
         a.risolta_il + interval '2 minutes'
  from public.free_agent_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  left join public.player_instances pi on pi.league_id = a.league_id and pi.player_id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > v_dal and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_post = row_count; v_n := v_n + v_post;

  -- 3. UNDER: TuttoMercatoWop.
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
  select a.league_id, 'stampa-under:' || a.id, 'testata', 'TuttoMercatoWop', 'tmwop', 'tmwop', a.vincitore_team_id, pi.id,
         private.social_scegli('tm' || a.id, array[
           '👀 TALENTO | ' || t.nome || ' si assicura ' || p.nome || ', ' || coalesce(pi.eta_corrente, p.eta) || ' anni, '
             || private.ruolo_esteso((coalesce(pi.posizioni_override, p.posizioni))[1]) || '. Oggi è ancora acerbo, ma ' || private.stampa_prospetto(p.potential, 'tm' || a.id)
             || '. Nome da segnare sul taccuino.',
           '👀 OCCHIO A LUI | ' || p.nome || ' (' || coalesce(pi.eta_corrente, p.eta) || ') è un nuovo giocatore di ' || t.nome
             || '. Gli osservatori ne parlano un gran bene: ' || private.stampa_prospetto(p.potential, 'tm' || a.id) || '. Tra un paio di stagioni potrebbe valere molto più di quanto è costato ('
             || private.milioni(a.ingaggio_finale) || ').']),
         a.risolta_il + interval '4 minutes'
  from public.under_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  left join public.player_instances pi on pi.league_id = a.league_id and pi.player_id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > v_dal and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_post = row_count; v_n := v_n + v_post;

  -- 4. Gli influencer, una volta per giornata giocata.
  for v_g in
    select f.league_id, f.season_id, f.giornata, max(m.simulata_il) as quando
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    join public.leagues l on l.id = f.league_id and l.conferenze_stampa
    where m.simulata_il > v_dal
    group by f.league_id, f.season_id, f.giornata
    having not exists (select 1 from public.social_posts sp where sp.league_id = f.league_id
                        and sp.chiave = 'omino:' || f.season_id || ':' || f.giornata)
  loop
    v_k := v_g.season_id || ':' || v_g.giornata;

    -- L'Ultimo Omino: la partita con la storia tattica piu' forte (chi vince col pallone agli altri, o chi domina).
    select x.*, case when x.gol_v = x.gol_p then 'pari' when x.poss_v < 0.45 then 'rimessa' else 'dominio' end as storia
      into v_m
    from (
      select m.id, th.nome as casa, ta.nome as ospite, m.gol_home, m.gol_away,
             case when m.gol_home >= m.gol_away then th.nome else ta.nome end as vinc,
             case when m.gol_home >= m.gol_away then ta.nome else th.nome end as perd,
             case when m.gol_home >= m.gol_away then f.home_team_id else f.away_team_id end as vinc_id,
             case when m.gol_home >= m.gol_away then f.away_team_id else f.home_team_id end as perd_id,
             greatest(m.gol_home, m.gol_away) as gol_v, least(m.gol_home, m.gol_away) as gol_p,
             case when m.gol_home >= m.gol_away then m.modulo_home else m.modulo_away end as mod_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'possesso')::numeric as poss_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'tiri')::integer as tiri_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'away' else 'home' end ->> 'tiri')::integer as tiri_p,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'inPorta')::integer as porta_v,
             (m.stats_squadra -> case when m.gol_home >= m.gol_away then 'home' else 'away' end ->> 'passaggiPct')::numeric as pass_v
      from public.matches m join public.fixtures f on f.id = m.fixture_id
      join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
      where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
        and m.stats_squadra ? 'home'
    ) x
    order by case when x.gol_v > x.gol_p and x.poss_v < 0.45 then (0.5 - x.poss_v) * 200 + (x.gol_v - x.gol_p)
                  else abs(x.poss_v - 0.5) * 100 + abs(x.tiri_v - x.tiri_p) end desc, x.id
    limit 1;
    if found then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
      values (v_g.league_id, 'omino:' || v_k, 'influencer', 'L''Ultimo Omino', 'ultimoomino', 'ultimoomino', v_m.vinc_id, v_m.perd_id,
        '🧠 ANALISI | ' || v_m.casa || ' ' || v_m.gol_home || '-' || v_m.gol_away || ' ' || v_m.ospite || chr(10) || chr(10) || case v_m.storia
          when 'rimessa' then private.social_scegli('om' || v_k, array[
            v_m.vinc || ' vince con appena il ' || round(v_m.poss_v * 100) || '% di possesso. Blocco basso, ripartenze e ' || v_m.porta_v
              || ' tiri in porta: il ' || coalesce(v_m.mod_v, 'modulo') || ' ha fatto esattamente quello che doveva. Il possesso non vince le partite.',
            'Partita da manuale del contropiede. ' || v_m.perd || ' tiene il pallone (' || round((1 - v_m.poss_v) * 100) || '%) ma non punge, '
              || v_m.vinc || ' aspetta e colpisce. Cinismo puro.'])
          when 'dominio' then private.social_scegli('om' || v_k, array[
            'Dominio totale di ' || v_m.vinc || ': ' || round(v_m.poss_v * 100) || '% di possesso, ' || v_m.tiri_v || ' tiri contro ' || v_m.tiri_p
              || ', ' || round(coalesce(v_m.pass_v, 0) * 100) || '% di passaggi riusciti. Il ' || coalesce(v_m.mod_v, 'modulo') || ' ha tenuto pallone e partita.',
            v_m.vinc || ' ha schiacciato ' || v_m.perd || ' nella sua metà campo. ' || v_m.tiri_v || ' tiri a ' || v_m.tiri_p
              || ': quando il pressing funziona così, il risultato è una conseguenza.'])
          else private.social_scegli('om' || v_k, array[
            'Pareggio bugiardo? Tiri ' || v_m.tiri_v || '-' || v_m.tiri_p || ', possesso ' || round(v_m.poss_v * 100) || '-' || round((1 - v_m.poss_v) * 100)
              || '. Chi ha creato di più non ha trovato la giocata giusta negli ultimi metri.',
            'Due squadre che si annullano. Linee strette, pochi spazi tra le linee, ' || (v_m.tiri_v + v_m.tiri_p) || ' tiri in tutto. Partita a scacchi.']) end,
        v_g.quando + interval '40 minutes')
      on conflict (league_id, chiave) do nothing;
      v_n := v_n + 1;
    end if;

    -- Lele Adami: il giocatore della giornata.
    select p.nome, ms.gol, ms.assist, ms.team_id, ms.player_instance_id,
           case when ms.team_id = f.home_team_id then ta.nome else th.nome end as avv
      into v_s
    from public.match_stats ms
    join public.matches m on m.id = ms.match_id join public.fixtures f on f.id = m.fixture_id
    join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
    join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
    where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
      and ms.gol + ms.assist >= 2
    order by ms.gol * 3 + ms.assist * 2 + ms.tiri_porta * 0.3 + ms.dribbling * 0.1 desc, ms.player_instance_id
    limit 1;
    if found then
      v_tab := case v_s.gol when 0 then '' when 1 then 'un gol' when 2 then 'una doppietta' when 3 then 'una tripletta' else v_s.gol || ' gol' end
        || case when v_s.gol > 0 and v_s.assist > 0 then ' e ' else '' end
        || case v_s.assist when 0 then '' when 1 then 'un assist' else v_s.assist || ' assist' end;
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, player_instance_id, testo, creato_il)
      values (v_g.league_id, 'adami:' || v_k, 'influencer', 'Lele Adami', 'leleadami', 'leleadami', v_s.team_id, v_s.player_instance_id,
        private.social_scegli('la' || v_k, array[
          'Ragazzi, ' || v_s.nome || '! ' || initcap(left(v_tab, 1)) || substr(v_tab, 2) || ' contro ' || v_s.avv || '. Questo è calcio, questa è poesia, questa è libertà di interpretare il ruolo! 🎙️',
          'Io mi alzo in piedi per ' || v_s.nome || '. ' || initcap(left(v_tab, 1)) || substr(v_tab, 2) || ': non gioca a calcio, lo racconta. Chi non si emoziona così ha sbagliato sport.',
          v_s.nome || ' è un giocatore che ti riconcilia col pallone. Contro ' || v_s.avv || ' ha fatto ' || v_tab
            || ', ma soprattutto ha fatto innamorare. Il calcio è dei romantici! ❤️']),
        v_g.quando + interval '65 minutes')
      on conflict (league_id, chiave) do nothing;
      v_n := v_n + 1;
    end if;

    -- Calciatori Bruttini: la batosta della giornata (almeno 3 gol di scarto), e un tifoso che non la prende bene.
    select m.id, case when m.gol_home > m.gol_away then ta.nome else th.nome end as perd,
           case when m.gol_home > m.gol_away then th.nome else ta.nome end as vinc,
           case when m.gol_home > m.gol_away then f.away_team_id else f.home_team_id end as perd_id,
           case when m.gol_home > m.gol_away then f.home_team_id else f.away_team_id end as vinc_id,
           greatest(m.gol_home, m.gol_away) as presi, least(m.gol_home, m.gol_away) as fatti
      into v_m
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
    where f.league_id = v_g.league_id and f.season_id = v_g.season_id and f.giornata = v_g.giornata
      and abs(m.gol_home - m.gol_away) >= 3
    order by abs(m.gol_home - m.gol_away) desc, greatest(m.gol_home, m.gol_away) desc, m.id
    limit 1;
    if found then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
      values (v_g.league_id, 'bruttini:' || v_k, 'influencer', 'Calciatori Bruttini', 'calciatoribruttini', 'calciatoribruttini', v_m.perd_id, v_m.vinc_id,
        private.social_scegli('cb' || v_k, array[
          '📸 La difesa di ' || v_m.perd || ' stasera: 🚪🚪🚪 ' || v_m.presi || ' gol presi da ' || v_m.vinc || '. Qualcuno avvisi il mister.',
          '📸 ' || v_m.perd || ' ha provato una nuova tattica: lasciar passare tutti. ' || v_m.vinc || ' ringrazia e ne fa ' || v_m.presi || '.',
          '📸 Ultime notizie: la retroguardia di ' || v_m.perd || ' è ancora in cerca del pallone. ' || v_m.vinc || ' ' || v_m.presi || '-' || v_m.fatti || '.',
          '📸 ' || v_m.presi || ' gol presi. Il portiere di ' || v_m.perd || ' a fine partita ha chiesto il rimborso del biglietto.']),
        v_g.quando + interval '90 minutes')
      on conflict (league_id, chiave) do nothing
      returning id into v_post;
      v_n := v_n + 1;
      if v_post is not null then
        insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
        values (v_g.league_id, 'bruttini-tifoso:' || v_k, 'tifosi',
                (private.tifoso_finto('cbt' || v_k, v_m.perd)).nome, (private.tifoso_finto('cbt' || v_k, v_m.perd)).handle, v_m.perd_id, v_post,
                private.social_scegli('cbt' || v_k, array['ridete ridete, a fine anno vediamo 😤', 'non fa ridere. non oggi.', 'ok questa fa male ma è vera 💀', 'bloccato. bloccati tutti.']),
                v_g.quando + interval '97 minutes')
        on conflict (league_id, chiave) do nothing;
      end if;
    end if;
  end loop;

  return v_n;
end;
$function$;
