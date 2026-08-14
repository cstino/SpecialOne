-- ============================================================
--  SVINCOLO: conserva la formazione e sostituisce il giocatore
-- ============================================================
-- Lo svincolo non deve cancellare le scelte tattiche dell'allenatore. Per ogni
-- distinta futura coinvolta, un titolare viene sostituito dal migliore profilo
-- disponibile per lo slot; un panchinaro dal migliore giocatore libero. Un
-- eventuale giocatore promosso dalla tribuna viene rimosso da li', evitando
-- duplicati. La rosa minima di 21 garantisce sempre almeno un candidato.

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_giocatore public.players;
  v_rosa integer;
  v_portieri integer;
  v_prossima integer;
  v_formazione public.lineups;
  v_indice integer;
  v_slot text;
  v_sostituto bigint;
  v_formazioni_aggiornate integer := 0;
  v_stagioni_residue integer;
  v_buonuscita bigint := 0;
  v_nuovo_budget bigint;
  v_nota text := '';
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza from public.player_instances
  where id = p_instance_id and team_id = v_squadra.id for update;
  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;
  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000', message = 'Il mercato e'' chiuso: puoi svincolare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK') into v_rosa, v_portieri
  from public.player_instances pi join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id and pi.id <> v_istanza.id;
  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023', message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  select * into v_giocatore from public.players where id = v_istanza.player_id;
  v_stagioni_residue := greatest(0, v_istanza.contratto_scadenza - v_lega.stagione_corrente);
  if v_istanza.ritiro_annunciato then v_stagioni_residue := 0; end if;
  v_buonuscita := (v_stagioni_residue::bigint * v_istanza.ingaggio) / 2;
  if v_buonuscita > 0 and v_squadra.budget < v_buonuscita then
    raise exception using errcode = '55000', message = format(
      'Servono %s M€ di buonuscita per svincolare %s (%s stagioni residue sul contratto): budget insufficiente.',
      to_char(v_buonuscita / 1000000.0, 'FM999999990.0'), v_giocatore.nome, v_stagioni_residue
    );
  end if;

  select min(f.giornata) into v_prossima from public.fixtures f
  where f.league_id = v_lega.id and f.stato = 'programmata';

  if v_prossima is not null then
    for v_formazione in
      select * from public.lineups
      where league_id = v_lega.id
        and team_id = v_squadra.id
        and giornata >= v_prossima
        and (titolari && array[v_istanza.id]::bigint[] or panchina && array[v_istanza.id]::bigint[] or tribuna && array[v_istanza.id]::bigint[])
      for update
    loop
      v_sostituto := null;
      v_indice := array_position(v_formazione.titolari, v_istanza.id);

      if v_indice is not null then
        v_slot := (case v_formazione.modulo
          when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']
          when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']
          when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']
          when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']
          when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']
          when '3-5-2' then array['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST']
          when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']
          when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']
          when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']
        end)[v_indice];

        select pi.id into v_sostituto
        from public.player_instances pi join public.players p on p.id = pi.player_id
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by
          case
            when v_slot = any(p.posizioni) then 0
            when v_slot in ('CB','LB','RB','LWB','RWB') and p.posizioni && array['CB','LB','RB','LWB','RWB']::text[] then 1
            when v_slot in ('CDM','CM','CAM','LM','RM') and p.posizioni && array['CDM','CM','CAM','LM','RM']::text[] then 1
            when v_slot in ('LW','RW','ST','CF') and p.posizioni && array['LW','RW','ST','CF']::text[] then 1
            when v_slot = 'GK' or p.posizioni && array['GK']::text[] then 3
            else 2
          end,
          case when pi.infortunato_fino_a <= 0 then 0 else 1 end,
          pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set titolari = array_replace(titolari, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      elsif array_position(v_formazione.panchina, v_istanza.id) is not null then
        select pi.id into v_sostituto
        from public.player_instances pi
        where pi.league_id = v_lega.id and pi.team_id = v_squadra.id and pi.id <> v_istanza.id
          and not (pi.id = any(v_formazione.titolari || coalesce(v_formazione.panchina, '{}'::bigint[])))
        order by case when pi.infortunato_fino_a <= 0 then 0 else 1 end, pi.overall_corrente desc, pi.id
        limit 1;

        update public.lineups
        set panchina = array_replace(panchina, v_istanza.id, v_sostituto),
            tribuna = array_remove(tribuna, v_sostituto)
        where id = v_formazione.id;
        v_formazioni_aggiornate := v_formazioni_aggiornate + 1;

      else
        update public.lineups set tribuna = array_remove(tribuna, v_istanza.id) where id = v_formazione.id;
      end if;
    end loop;
  end if;

  if v_buonuscita > 0 then
    v_nuovo_budget := v_squadra.budget - v_buonuscita;
    update public.teams set budget = v_nuovo_budget where id = v_squadra.id;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (v_lega.id, v_squadra.id, 'svincolo_buonuscita', -v_buonuscita,
      'Buonuscita per svincolo anticipato: ' || v_giocatore.nome || ' (' || v_stagioni_residue || ' stagioni residue)', v_nuovo_budget);
  end if;

  update public.player_instances set team_id = null,
    ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
  where id = v_istanza.id returning * into v_istanza;
  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente) on conflict do nothing;
  end if;

  if v_formazioni_aggiornate > 0 then v_nota := ' Formazione aggiornata automaticamente con un sostituto.'; end if;
  perform private.notifica(
    v_utente, v_lega.id, 'mercato_esito', 'Giocatore svincolato',
    v_giocatore.nome || (case
      when v_istanza.ritiro_annunciato then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      when v_buonuscita > 0 then ' non fa piu'' parte della tua rosa. Buonuscita pagata: ' || to_char(v_buonuscita / 1000000.0, 'FM999999990.0') || ' M€.'
      else ' non fa piu'' parte della tua rosa.' end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id, 'buonuscita', v_buonuscita)
  );
  return v_istanza;
end;
$$;

revoke all on function public.svincola_giocatore(bigint) from public, anon;
grant execute on function public.svincola_giocatore(bigint) to authenticated;

comment on function public.svincola_giocatore(bigint) is
  'Svincola un proprio giocatore senza cancellare la formazione: sostituisce automaticamente titolari e panchinari nelle giornate future.';
