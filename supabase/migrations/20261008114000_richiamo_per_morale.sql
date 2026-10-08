-- Il richiamo al mister non dipende piu' solo dal minutaggio: parte quando il morale del giocatore scende sotto 30
-- (8 ottobre 2026, committente). Stesso calendario dei controlli (giornata 8, poi ogni 5), stessa conseguenza: al
-- controllo dopo, ancora sotto 30, chiede la cessione. Vale per tutti i giocatori delle squadre umane, non solo per
-- chi ha un minutaggio trattato. Funzione ricostruita dalla definizione live.
create or replace function private.controlla_minutaggio(p_league_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_ultima smallint;
  v_controllo smallint;
  v_g record;
  v_partite integer;
  v_minuti numeric;
  v_reale numeric;
  v_attesa numeric;
  v_soglia numeric;
  v_messaggi integer := 0;
  v_nome_gradino text;
  v_gradino text;
begin
  select l.id, l.stagione_corrente, l.giornate_totali, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione' and l.tattiche_attive;
  if not found then return 0; end if;

  select max(f.giornata) into v_ultima
  from public.fixtures f
  where f.season_id = v_lega.season_id and f.stato = 'simulata' and f.giornata <= v_lega.giornate_totali;
  if v_ultima is null or v_ultima < 8 then return 0; end if;

  v_controllo := (8 + ((v_ultima - 8) / 5) * 5)::smallint;
  insert into private.minutaggio_controlli (season_id, giornata)
  values (v_lega.season_id, v_controllo)
  on conflict do nothing;
  if not found then return 0; end if;

  for v_g in
    select pi.id, pi.team_id, pi.richiamo_stagione, pi.morale, t.user_id, p.nome
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.teams t on t.id = pi.team_id and t.attiva
    where pi.league_id = p_league_id
      and not pi.ritirato and not pi.ritiro_annunciato
      and pi.richiesta_cessione_stagione is null
      and t.user_id is not null and not coalesce(t.controllata_da_pc, false)
    order by pi.id
    for update of pi
  loop
    select ms.partite, ms.minuti into v_partite, v_minuti from private.minuti_stagione(v_g.id) ms;
    -- Con meno di 5 partite giocabili non c'e' abbastanza campione.
    if v_partite < 5 then continue; end if;

    -- Dall'8 ottobre 2026 il giocatore scrive quando il MORALE scende sotto 30 (non piu' solo per i minuti):
    -- il morale contiene gia' minutaggio, ingaggio e classifica. Al controllo dopo, se e' ancora sotto, chiede
    -- la cessione; se e' risalito, il richiamo si cancella.
    if v_g.morale < 30 then
      if v_g.richiamo_stagione = v_lega.stagione_corrente then
        update public.player_instances
        set richiesta_cessione_stagione = v_lega.stagione_corrente
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' chiede la cessione', 80),
          'Mister, la mia situazione non è cambiata: chiedo la cessione. Non rinnoverò il contratto.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'cessione_morale'));
      else
        update public.player_instances
        set richiamo_stagione = v_lega.stagione_corrente, richiamo_giornata = v_controllo
        where id = v_g.id;
        perform private.notifica(v_g.user_id, p_league_id, 'sistema',
          left(v_g.nome || ' non è soddisfatto', 80),
          'Salve mister, volevo dirle che non sono soddisfatto del mio impiego e credo di meritare di meglio. '
            || 'Le chiedo di prendere provvedimenti, altrimenti sarò costretto a richiedere la cessione.',
          jsonb_build_object('view', 'squad', 'player_instance_id', v_g.id, 'motivo', 'richiamo_morale'));
      end if;
      v_messaggi := v_messaggi + 1;
    elsif v_g.richiamo_stagione = v_lega.stagione_corrente then
      update public.player_instances
      set richiamo_stagione = null, richiamo_giornata = null
      where id = v_g.id;
    end if;
  end loop;

  return v_messaggi;
end;
$function$

;
