-- ============================================================
--  BUONUSCITA PER LO SVINCOLO ANTICIPATO (design §5.4/§9.5)
--
--  Segnalato dall'utente: svincola_giocatore era completamente gratuito,
--  indipendentemente da quante stagioni restavano sul contratto. Si poteva
--  firmare un rinnovo a 4 stagioni e disfarsene dopo la prima senza mai
--  pagare le altre tre — un vero e proprio exploit economico, non solo una
--  stranezza. Il monte ingaggi (§5.4) viene addebitato per intero solo
--  stagione per stagione, quindi la squadra non ha mai davvero "promesso"
--  soldi oltre l'anno in corso in senso contabile, ma in senso di gioco
--  il contratto pluriennale deve costare qualcosa a romperlo prima, altrimenti
--  non è mai una promessa, è sempre un'opzione gratuita.
--
--  Formula scelta dall'utente: buonuscita = meta' (arrotondata per difetto)
--  dell'ingaggio delle stagioni residue DOPO quella in corso. Esempio
--  dell'utente: contratto di 4 stagioni a 2 M€, svincolato durante la prima
--  stagione -> restano 3 stagioni non pagate (6 M€) -> buonuscita 3 M€.
--
--  Nessuna buonuscita (comportamento invariato) quando:
--  - il contratto scade a fine di questa stagione o e' gia' scaduto
--    (contratto_scadenza <= stagione_corrente): non c'e' nessun impegno
--    futuro da comprare, era gia' l'ultimo anno;
--  - il giocatore ha gia' annunciato il ritiro: esce comunque a fine
--    stagione per conto suo (§10.3), quindi la squadra non sta comprando
--    nessuna liberta' che non avrebbe avuto gratis fra pochi mesi.
--
--  Se il budget non copre la buonuscita, lo svincolo viene rifiutato: il
--  budget non puo' mai andare sotto zero (§5.5), stessa regola di sempre.
-- ============================================================

create or replace function public.svincola_giocatore(p_instance_id bigint)
returns public.player_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente      uuid := (select auth.uid());
  v_istanza     public.player_instances;
  v_squadra     public.teams;
  v_lega        public.leagues;
  v_giocatore   public.players;
  v_rosa        integer;
  v_portieri    integer;
  v_prossima    integer;
  v_form_tolte  integer := 0;
  v_nota        text := '';
  v_stagioni_residue integer;
  v_buonuscita  bigint := 0;
  v_nuovo_budget bigint;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per svincolare un giocatore.';
  end if;

  select * into v_istanza
  from public.player_instances
  where id = p_instance_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra
  from public.teams
  where id = v_istanza.team_id
    and user_id = v_utente;

  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  perform 1 from public.teams where id = v_squadra.id for update;
  select * into v_istanza
  from public.player_instances
  where id = p_instance_id
    and team_id = v_squadra.id
  for update;

  if not found then
    raise exception using errcode = '55000', message = 'Il giocatore non e'' piu'' nella tua rosa.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi svincolare giocatori solo durante la stagione.';
  end if;

  if not private.mercato_aperto_lega(v_lega.id) then
    raise exception using errcode = '55000',
      message = 'Il mercato e'' chiuso: puoi svincolare dalle 23:30 alle 21:00, o quando l''admin lo apre.';
  end if;

  select count(*), count(*) filter (where p.posizioni[1] = 'GK')
    into v_rosa, v_portieri
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.team_id = v_squadra.id
    and pi.id <> v_istanza.id;

  if v_rosa < private.rosa_minima() then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto i 21 giocatori in rosa.';
  end if;
  if v_portieri < v_lega.portieri_minimi then
    raise exception using errcode = '22023',
      message = 'Non puoi scendere sotto il minimo di portieri della lega.';
  end if;

  select * into v_giocatore from public.players where id = v_istanza.player_id;

  -- Buonuscita: meta' (per difetto) dell'ingaggio delle stagioni residue
  -- dopo quella in corso. Zero se e' l'ultimo anno di contratto o se ha
  -- gia' annunciato il ritiro.
  v_stagioni_residue := greatest(0, v_istanza.contratto_scadenza - v_lega.stagione_corrente);
  if v_istanza.ritiro_annunciato then
    v_stagioni_residue := 0;
  end if;
  v_buonuscita := (v_stagioni_residue::bigint * v_istanza.ingaggio) / 2;

  if v_buonuscita > 0 and v_squadra.budget < v_buonuscita then
    raise exception using errcode = '55000',
      message = format(
        'Servono %s M€ di buonuscita per svincolare %s (%s stagioni residue sul contratto): budget insufficiente.',
        to_char(v_buonuscita / 1000000.0, 'FM999999990.0'), v_giocatore.nome, v_stagioni_residue
      );
  end if;

  select min(f.giornata) into v_prossima
  from public.fixtures f
  where f.league_id = v_lega.id
    and f.stato = 'programmata';

  if v_prossima is not null then
    delete from public.lineups
    where league_id = v_lega.id
      and team_id = v_squadra.id
      and giornata >= v_prossima
      and (
        titolari && array[v_istanza.id]::bigint[]
        or panchina && array[v_istanza.id]::bigint[]
        or tribuna && array[v_istanza.id]::bigint[]
      );
    get diagnostics v_form_tolte = row_count;
  end if;

  if v_buonuscita > 0 then
    v_nuovo_budget := v_squadra.budget - v_buonuscita;
    update public.teams set budget = v_nuovo_budget where id = v_squadra.id;
    insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
    values (
      v_lega.id, v_squadra.id, 'svincolo_buonuscita', -v_buonuscita,
      'Buonuscita per svincolo anticipato: ' || v_giocatore.nome || ' (' || v_stagioni_residue || ' stagioni residue)',
      v_nuovo_budget
    );
  end if;

  update public.player_instances
  set team_id = null,
      ritirato = case when v_istanza.ritiro_annunciato then true else ritirato end
  where id = v_istanza.id
  returning * into v_istanza;

  if v_istanza.ritiro_annunciato then
    insert into public.retired_players(league_id, player_id, stagione)
    values (v_lega.id, v_istanza.player_id, v_lega.stagione_corrente)
    on conflict do nothing;
  end if;

  if v_form_tolte > 0 then
    v_nota := ' La formazione delle prossime giornate va salvata di nuovo.';
  end if;

  perform private.notifica(
    v_utente,
    v_lega.id,
    'mercato_esito',
    'Giocatore svincolato',
    v_giocatore.nome || (case
      when v_istanza.ritiro_annunciato then ' aveva gia'' annunciato il ritiro: la carriera termina qui, non torna disponibile.'
      when v_buonuscita > 0 then ' non fa piu'' parte della tua rosa. Buonuscita pagata: ' || to_char(v_buonuscita / 1000000.0, 'FM999999990.0') || ' M€.'
      else ' non fa piu'' parte della tua rosa.'
    end) || v_nota,
    jsonb_build_object('player_instance_id', v_istanza.id, 'player_id', v_istanza.player_id, 'buonuscita', v_buonuscita)
  );

  return v_istanza;
end;
$$;

revoke all on function public.svincola_giocatore(bigint) from public, anon;
grant execute on function public.svincola_giocatore(bigint) to authenticated;
