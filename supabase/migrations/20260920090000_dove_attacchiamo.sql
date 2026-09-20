-- ============================================================
--  DOVE ATTACCHIAMO
--
--  Il sistema delle corsie (engine/corsie.js) e' scritto e misurato da giorni
--  ma non e' mai stato collegato, perche' gli manca la meta' che lo rende una
--  scelta: la squadra sa leggere dove l'avversario e' scoperto, ma nessuno
--  poteva dirle dove andare a cercare.
--
--  Misurato contro un avversario che tiene il terzino sinistro dentro — centro
--  rinforzato, fascia scoperta:
--
--      A non concentra        39,8% di vittorie
--      A attacca a sinistra   39,8%
--      A attacca al centro    37,4%   (il suo lato forte)
--      A attacca a destra     46,0%   (il buco)
--
--  Otto punti e sei fra leggere bene e leggere male, dentro la forbice di
--  Football Manager. NULL resta una scelta legittima: non concentrare vale
--  quanto concentrare dalla parte sbagliata, e chi non entra nella schermata
--  non e' penalizzato.
--
--  E' un'INDICAZIONE, non una disposizione: entra nella barra indicazioni come
--  ventiquattresimo elemento accanto allo stile, agli undici ruoli e agli
--  undici compiti. Cambiare dove si attacca costa quanto cambiare un compito.
--
--  SEGRETA COME LA FORMAZIONE. Sta su lineups, quindi e' gia' coperta da
--  private.lineup_visibile: l'avversario non puo' sapere dove lo attaccherai
--  prima che la giornata sia simulata. Era il requisito principale e non ha
--  richiesto una riga in piu'.
--
--  Le due definizioni sono riprese dal database vivo.
-- ============================================================

alter table public.lineups
  add column if not exists focus_corsia text
  check (focus_corsia is null or focus_corsia in ('SX','CEN','DX'));

comment on column public.lineups.focus_corsia is
  'Dove la squadra concentra l''attacco: SX, CEN, DX. NULL = da nessuna parte in particolare, che e'' una scelta legittima.';

alter table public.indicazioni_xp
  add column if not exists focus_corsia text;

CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text, p_disposizione text[] DEFAULT NULL::text[], p_ruoli text[] DEFAULT NULL::text[], p_compiti text[] DEFAULT NULL::text[], p_focus_corsia text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_i integer;
  v_std text[];
  v_schema text[];
  v_league public.leagues;
  v_team public.teams;
  v_all bigint[];
  v_convocati bigint[];
  v_rosa_count integer;
  v_unique_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di salvare la formazione.';
  end if;

  select * into v_league from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_league.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'La stagione non e'' ancora iniziata.';
  end if;
  -- Playoff e playout vivono a giornate OLTRE la stagione regolare (con 16
  -- squadre: regolare fino alla 30, playoff 31 e 32), quindi il confronto
  -- con giornate_totali da solo rendeva impossibile schierare la formazione
  -- proprio nelle partite decisive. Si accetta anche una giornata piu' alta,
  -- purche' esista davvero come turno di questa stagione.
  if p_giornata < 1 or (
    p_giornata > v_league.giornate_totali
    and not exists (
      select 1
      from public.fixtures f
      join public.seasons s on s.id = f.season_id
      where s.league_id = p_league_id
        and s.numero = v_league.stagione_corrente
        and f.giornata = p_giornata
    )
  ) then
    raise exception using errcode = '22023', message = 'Giornata non valida per questa lega.';
  end if;
  if not (p_modulo = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_gioco = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;
  -- Schema personalizzato: gli undici slot davvero schierati. NULL = lo
  -- schieramento standard del modulo, cioe' il comportamento di sempre.
  -- Ogni posizione puo' solo salire o scendere di una linea sulla propria
  -- corsia (private.spostamenti_slot), quindi da qui non puo' uscire uno
  -- schieramento che il motore non sa valutare.
  -- A interruttore spento lo schema personalizzato non si scrive nemmeno.
  -- Non e' pignoleria: la familiarita' e' indicizzata SULLO SCHIERAMENTO
  -- (formation_xp.disposizione), quindi salvare una variante che il motore
  -- ignora creerebbe un contatore per una forma mai davvero giocata, e la
  -- barra racconterebbe una storia falsa. Chi salva senza saperlo non riceve
  -- un errore: gli si ignorano i tre campi, come se non li avesse mandati.
  if not (select l.tattiche_attive from public.leagues l where l.id = p_league_id) then
    p_disposizione := null;
    p_ruoli := null;
    p_compiti := null;
    p_focus_corsia := null;
  end if;

  -- Dove si attacca. NULL = da nessuna parte in particolare, ed e' una scelta
  -- come le altre: concentrare su una corsia paga se l'avversario la' e'
  -- scoperto e costa se e' il suo lato forte (engine/corsie.js).
  if p_focus_corsia is not null and p_focus_corsia not in ('SX','CEN','DX') then
    raise exception using errcode = '22023', message = 'Corsia non valida.';
  end if;

  if p_disposizione is not null then
    if cardinality(p_disposizione) <> 11 then
      raise exception using errcode = '22023', message = 'Lo schema deve avere esattamente 11 posizioni.';
    end if;
    v_std := private.disposizione_standard(p_modulo);
    if v_std is null then
      raise exception using errcode = '22023', message = 'Modulo sconosciuto.';
    end if;
    for v_i in 1..11 loop
      if not (p_disposizione[v_i] = any(private.spostamenti_slot(v_std[v_i]))) then
        raise exception using errcode = '22023',
          message = format('La posizione %s non puo'' diventare %s.', v_std[v_i], p_disposizione[v_i]);
      end if;
    end loop;
  end if;

  v_schema := coalesce(p_disposizione, private.disposizione_standard(p_modulo));

  if p_ruoli is not null then
    if cardinality(p_ruoli) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 ruoli, uno per posizione.';
    end if;
    for v_i in 1..11 loop
      if p_ruoli[v_i] is not null and not (p_ruoli[v_i] = any(private.ruoli_slot(v_schema[v_i]))) then
        raise exception using errcode = '22023',
          message = format('Il ruolo %s non esiste per la posizione %s.', p_ruoli[v_i], v_schema[v_i]);
      end if;
    end loop;
  end if;

  if p_compiti is not null then
    if cardinality(p_compiti) <> 11 then
      raise exception using errcode = '22023', message = 'Servono 11 compiti, uno per posizione.';
    end if;
    if exists (select 1 from unnest(p_compiti) c where c is not null and c not in ('difesa','equilibrio','attacco')) then
      raise exception using errcode = '22023', message = 'Compito non valido.';
    end if;
  end if;

  if coalesce(cardinality(p_titolari), 0) <> 11 then
    raise exception using errcode = '22023', message = 'Servono esattamente 11 titolari.';
  end if;
  if coalesce(cardinality(p_panchina), 0) > 9 then
    raise exception using errcode = '22023', message = 'La panchina puo'' contenere al massimo 9 giocatori.';
  end if;
  if p_titolari[1] is null then
    raise exception using errcode = '22023', message = 'Il primo slot deve contenere il portiere, anche se di movimento.';
  end if;
  if array_position(p_titolari, null) is not null
     or array_position(p_panchina, null) is not null
     or array_position(p_tribuna, null) is not null then
    raise exception using errcode = '22023', message = 'La formazione contiene uno slot vuoto non valido.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  v_all := p_titolari || coalesce(p_panchina, '{}'::bigint[]) || coalesce(p_tribuna, '{}'::bigint[]);
  v_unique_count := (select count(distinct id)::integer from unnest(v_all) as u(id));
  if v_unique_count <> cardinality(v_all) then
    raise exception using errcode = '22023', message = 'Lo stesso giocatore compare piu'' volte nella formazione.';
  end if;

  select count(*) into v_rosa_count
  from public.player_instances
  where league_id = p_league_id and team_id = v_team.id and id = any(v_all);
  if v_rosa_count <> cardinality(v_all) then
    raise exception using errcode = '42501', message = 'La formazione contiene un giocatore fuori dalla tua rosa.';
  end if;

  v_convocati := p_titolari || coalesce(p_panchina, '{}'::bigint[]);
  if exists (
    select 1 from public.player_instances
    where league_id = p_league_id and team_id = v_team.id
      and id = any(v_convocati) and infortunato_fino_a > 0
  ) then
    raise exception using errcode = '22023', message = 'Un giocatore infortunato non puo'' essere titolare o andare in panchina. Spostalo in tribuna.';
  end if;

  insert into public.lineups (
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il,
    disposizione, ruoli, compiti, focus_corsia
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now(),
    p_disposizione, p_ruoli, p_compiti, p_focus_corsia
  )
  on conflict (team_id, giornata) do update set
    modulo = excluded.modulo,
    titolari = excluded.titolari,
    panchina = excluded.panchina,
    tribuna = excluded.tribuna,
    stile_gioco = excluded.stile_gioco,
    automatica = false,
    salvata_il = now(),
    disposizione = excluded.disposizione,
    ruoli = excluded.ruoli,
    compiti = excluded.compiti,
    focus_corsia = excluded.focus_corsia;

  -- Chi batte piazzati e rigori: assegnato in automatico, e ricontrollato a
  -- ogni salvataggio. Un incarico sopravvive solo se quel giocatore e' ancora
  -- fra i titolari; altrimenti passa al migliore disponibile. Chi vuole lo
  -- cambia dopo, dalla stessa pagina.
  perform private.sistema_incaricati(v_team.id, p_giornata);

  return jsonb_build_object(
    'league_id', p_league_id,
    'team_id', v_team.id,
    'giornata', p_giornata,
    'modulo', p_modulo,
    'stile_gioco', p_stile_gioco,
    'disposizione', p_disposizione,
    'ruoli', p_ruoli,
    'compiti', p_compiti,
    'focus_corsia', p_focus_corsia,
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.avanza_familiarita(p_team_id bigint, p_league_id bigint, p_modulo text, p_stile text, p_giornata smallint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_disp      text[];
  v_ruoli     text[];
  v_compiti   text[];
  v_semina    smallint;
  v_prec      public.indicazioni_xp;
  v_distanza  numeric;
  v_diversi   integer;
  v_focus     text;
begin
  select coalesce(l.disposizione, private.disposizione_standard(p_modulo)), l.ruoli, l.compiti, l.focus_corsia
  into v_disp, v_ruoli, v_compiti, v_focus
  from public.lineups l
  where l.team_id = p_team_id and l.giornata = p_giornata;

  if v_disp is null then
    v_disp := private.disposizione_standard(p_modulo);
  end if;
  if v_disp is null then
    return; -- modulo sconosciuto: non si inventa una barra
  end if;

  -- ----- barra DISPOSIZIONE -----
  -- Se questo schieramento non e' mai stato giocato, eredita dal piu' simile.
  if not exists (
    select 1 from public.formation_xp
    where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp
  ) then
    -- Si eredita dalla QUOTA, non dal conteggio grezzo. Il contatore cresce
    -- senza limite — una squadra puo' avere 21 partite col suo 4-4-2 — e
    -- moltiplicare quello per 0,71 darebbe ancora 15, cioe' una barra piena:
    -- l'eredita' non morderebbe mai per chi gioca da tempo lo stesso modulo,
    -- che e' esattamente chi dovrebbe sentirla.
    select coalesce(max(round(
             least(1.0, fx.partite_giocate::numeric / private.fam_partite_piena())
             * private.resa_familiarita(1 - private.similarita_disposizione(fx.disposizione, v_disp))
             * private.fam_partite_piena()
           )), 0)
    into v_semina
    from public.formation_xp fx
    where fx.team_id = p_team_id;

    insert into public.formation_xp (team_id, league_id, modulo, disposizione, partite_giocate)
    values (p_team_id, p_league_id, p_modulo, v_disp, greatest(0, coalesce(v_semina, 0)))
    on conflict (team_id, modulo, disposizione) do nothing;
  end if;

  update public.formation_xp
  set partite_giocate = partite_giocate + 1, aggiornata_il = now()
  where team_id = p_team_id and modulo = p_modulo and disposizione = v_disp;

  -- ----- barra INDICAZIONI -----
  select * into v_prec from public.indicazioni_xp where team_id = p_team_id;

  if not found then
    -- Prima riga per questa squadra. NON parte da zero: la barra indicazioni
    -- assorbe quello che prima era la familiarita' con lo STILE, e azzerarla
    -- qui vorrebbe dire che alla prima giornata dopo questa migrazione ogni
    -- squadra della lega perde meta' della sua familiarita' senza aver
    -- cambiato niente.
    insert into public.indicazioni_xp (team_id, league_id, partite_giocate, stile, ruoli, compiti, focus_corsia)
    values (
      p_team_id, p_league_id,
      least(private.fam_partite_piena(),
            coalesce((select sx.partite_giocate from public.stile_xp sx
                      where sx.team_id = p_team_id and sx.stile = p_stile), 0))::smallint + 1,
      p_stile, v_ruoli, v_compiti, v_focus);
    return;
  end if;

  -- Distanza su 23 elementi: lo stile, gli undici ruoli, gli undici compiti.
  -- Un elemento assente da entrambe le parti non e' un cambiamento.
  v_diversi := (case when coalesce(v_prec.stile, '') <> coalesce(p_stile, '') then 1 else 0 end)
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.ruoli[i], '') <> coalesce(v_ruoli[i], ''))
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.compiti[i], '') <> coalesce(v_compiti[i], ''))
    -- Ventiquattresimo elemento: dove si attacca. E' un'indicazione come le
    -- altre, quindi cambiarla costa familiarita' come cambiare un compito.
    + (case when coalesce(v_prec.focus_corsia, '') <> coalesce(v_focus, '') then 1 else 0 end);
  v_distanza := v_diversi::numeric / 24;

  -- Stessa cura dell'eredita': si arretra la quota, non il conteggio grezzo.
  update public.indicazioni_xp
  set partite_giocate = least(32767, greatest(0,
        round(least(1.0, partite_giocate::numeric / private.fam_partite_piena())
              * private.resa_familiarita(v_distanza)
              * private.fam_partite_piena())::smallint + 1)),
      stile = p_stile, ruoli = v_ruoli, compiti = v_compiti, focus_corsia = v_focus, aggiornata_il = now()
  where team_id = p_team_id;
end;
$function$;

-- ------------------------------------------------------------
--  Via la firma a dieci parametri
--
--  Stessa trappola della volta scorsa: aggiungere un parametro con un default
--  non sostituisce la funzione, ne crea una seconda. Con entrambe presenti
--  PostgREST sceglie in base ai nomi degli argomenti, e il frontend che non
--  manda p_focus_corsia continuerebbe a chiamare quella vecchia — che lo
--  ignora. Sarebbe stato un bug silenzioso, come gia' successo.
-- ------------------------------------------------------------
drop function if exists public.salva_formazione(bigint, smallint, text, bigint[], bigint[], bigint[], text, text[], text[], text[]);
