-- Pagelle del mercato (Corriere dello Sport, SocialOne): citavano un solo nome per squadra (il miglior overall in
-- entrata o in uscita) e mai le scelte di draft. Segnalazione dell'8/11/2026 sullo scambio Riskmond-Mafiester
-- (Gueye, Provedel e 2 scelte per Raya: il post parlava solo di Provedel). Ora ogni riga dice cosa entra e cosa esce,
-- scelte comprese. Voti e semi delle frasi invariati. stampa_scambio ricostruita dalla definizione live.

-- Elenco leggibile dei pezzi: «A, B e 2 scelte di draft»; null se non c'e' niente.
create or replace function private.stampa_elenco(p_giocatori bigint[], p_vivaio bigint[], p_scelte bigint[])
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select regexp_replace(nullif(private.descrizione_cessione(p_giocatori, p_vivaio, p_scelte), 'niente'), ', ([^,]*)$', ' e \1')
$function$;

create or replace function private.stampa_pagella_riga(p_nome text, p_voto numeric, p_in text, p_out text, p_seme text)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p_nome || ' ' || private.voto_testo(p_voto) || ' — ' || case
    when p_in is null then 'Cessione secca: fuori ' || coalesce(p_out, 'nessuno') || ' senza contropartita.'
    when p_out is null then 'Rinforzo a costo zero: dentro ' || p_in || ' senza cedere nessuno.'
    else private.social_scegli(p_seme, case
      when p_voto >= 7.5 then array['Colpo da applausi: dentro ' || p_in || ', fuori solo ' || p_out || '.',
                                    'Operazione da prima pagina: ' || p_in || ' in cambio di ' || p_out || '. Affare vinto.']
      when p_voto >= 6.5 then array['Buon affare: ' || p_in || ' in cambio di ' || p_out || ', il conto torna.',
                                    'Mossa intelligente: dare ' || p_out || ' per avere ' || p_in || ' conviene.']
      when p_voto >= 6 then array['Operazione equilibrata: ' || p_in || ' per ' || p_out || ', senza squilli.',
                                  'Scambio alla pari: ' || p_in || ' per ' || p_out || ', né vinto né perso.']
      when p_voto >= 5 then array['Qualche dubbio: dare ' || p_out || ' per ' || p_in || ' pesa più di quanto sembri.',
                                  'Affare che non convince fino in fondo: per avere ' || p_in || ' si rinuncia a ' || p_out || '.']
      else array['Bocciati: per avere solo ' || p_in || ' si rinuncia a ' || p_out || '. Troppo poco.',
                 'Mercato da dimenticare: rinunciare a ' || p_out || ' per ' || p_in || ' farà rumore.'] end)
  end
$function$;

create or replace function private.stampa_pagelle_testo(p_tp public.trade_proposals, p_voto_da numeric, p_voto_a numeric)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select '📝 PAGELLE DEL MERCATO' || chr(10) || chr(10)
    || private.stampa_pagella_riga((select nome from public.teams where id = p_tp.da_team_id), p_voto_da,
         private.stampa_elenco(p_tp.giocatori_richiesti, p_tp.vivaio_richiesti, p_tp.scelte_richieste),
         private.stampa_elenco(p_tp.giocatori_offerti, p_tp.vivaio_offerti, p_tp.scelte_offerte), 'pd' || p_tp.id)
    || chr(10)
    || private.stampa_pagella_riga((select nome from public.teams where id = p_tp.a_team_id), p_voto_a,
         private.stampa_elenco(p_tp.giocatori_offerti, p_tp.vivaio_offerti, p_tp.scelte_offerte),
         private.stampa_elenco(p_tp.giocatori_richiesti, p_tp.vivaio_richiesti, p_tp.scelte_richieste), 'pa' || p_tp.id)
$function$;

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
    values (v_tp.league_id, 'stampa-scambio:' || v_k, 'testata', 'La Gazzetta dello Sport', 'gazzetta', 'gazzetta',
            v_dest.id, v_orig.id, v_top.pi_id, left(v_testo, 700), v_tp.risolta_il + interval '3 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;

  -- 2. Le pagelle del Corriere dello Sport.
  v_testo := private.stampa_pagelle_testo(v_tp, v_voto_da, v_voto_a);
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, profilo, team_id, team2_id, testo, creato_il)
  values (v_tp.league_id, 'pagelle-scambio:' || v_k, 'testata', 'Corriere dello Sport', 'corrieredellosport', 'corrieredellosport',
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
                'il @corrieredellosport non ci capisce niente di calcio, come sempre',
                'ok il ' || private.voto_testo(v_voto_basso) || ' ma ne riparliamo a fine stagione. salvate il post 📌']),
              v_tp.risolta_il + interval '32 minutes')
      on conflict (league_id, chiave) do nothing;
    elsif v_voto_alto >= 7 then
      insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, autore_handle, team_id, in_risposta_a, testo, creato_il)
      values (v_tp.league_id, 'pagelle-tifoso:' || v_k, 'tifosi',
              (private.tifoso_finto('pg' || v_k, v_alto.nome)).nome, (private.tifoso_finto('pg' || v_k, v_alto.nome)).handle, v_alto.id, v_post,
              private.social_scegli('pgt' || v_k, array[
                'pure il @corrieredellosport lo dice. mercato da paura @' || private.handle_squadra(v_alto.nome) || ' 🔥',
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
    v_insider := case when abs(hashtext('chi' || v_k)) % 2 = 0 then 'fabrizioromano' else 'dimarzio' end;
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
            case v_insider when 'fabrizioromano' then 'Fabrizio Romano' else 'Gianluca Di Marzio' end, v_insider, v_insider,
            v_dest.id, v_orig.id, v_top.pi_id,
            case v_insider when 'fabrizioromano' then '🚨 ' else 'ESCLUSIVA | ' end || v_testo, v_tp.risolta_il + interval '70 minutes')
    on conflict (league_id, chiave) do nothing;
    v_n := v_n + 1;
  end if;
  return v_n;
end;
$function$;

-- Pagella gia' pubblicata dello scambio 1002 (Serie F): stesso voto (4,5 e 7,5), testo completo.
update public.social_posts
   set testo = private.stampa_pagelle_testo((select tp from public.trade_proposals tp where tp.id = 1002), 4.5, 7.5)
 where league_id = 63 and chiave = 'pagelle-scambio:1002';
