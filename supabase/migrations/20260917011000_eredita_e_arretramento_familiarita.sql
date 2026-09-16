-- ============================================================
--  EREDITA' E ARRETRAMENTO DELLE DUE BARRE
--
--  La barra DISPOSIZIONE ha memoria e si eredita. Uno schieramento mai giocato
--  non parte da zero: prende il piu' simile gia' praticato e lo scala.
--
--      quota = max(0, 1 - 1.6 * (1 - somiglianza))
--
--  Il fattore 1,6 rende una modifica percepibile senza renderla proibitiva.
--  Sull'esempio dell'utente — un 4-4-2 in cui i due CM diventano CDM, cioe' 9
--  slot su 11 identici, somiglianza 0,818 — la quota e' 0,71: da 5 partite si
--  riparte da 4, cioe' l'80% della barra. Costa qualcosa, non azzera.
--  Uno stravolgimento (5 slot cambiati su 11) scende invece al 20%.
--
--  La barra INDICAZIONI non ha memoria e non si azzera: arretra in proporzione
--  a quanto e' cambiato, sulla stessa formula. Gli elementi sono 23 — lo stile,
--  gli 11 ruoli e gli 11 compiti — quindi cambiare un solo compito costa nulla
--  (fattore 0,93, la barra resta piena) e cambiare tutti i compiti insieme la
--  porta al 20%. E' il "non fare troppe modifiche in una volta" di Football
--  Manager, reso numerico.
--
--  PERCHE' DUE MECCANICHE DIVERSE. Uno schieramento e' una cosa discreta a cui
--  si torna, ed e' giusto ritrovarlo come lo si era lasciato. Le indicazioni
--  sono un continuo in cui ci si sposta, e tenerne la memoria vorrebbe dire
--  indicizzare ogni combinazione di 23 elementi: una tabella che cresce senza
--  che nessuna riga venga mai riusata.
--
--  INERTE FINCHE' NESSUNO PERSONALIZZA. Con lineups.disposizione, ruoli e
--  compiti a NULL la disposizione e' quella standard del modulo e le
--  indicazioni non cambiano mai: i contatori avanzano di uno a partita, come
--  hanno sempre fatto.
-- ============================================================

-- Le partite che riempiono una barra. Specchio di CFG.FAM_PARTITE_PIENA in
-- engine/config.js: se cambia la', va cambiato qui.
create or replace function private.fam_partite_piena()
returns integer language sql immutable parallel safe set search_path = ''
as $$ select 5 $$;

revoke all on function private.fam_partite_piena() from public, anon, authenticated;

-- Quanto sopravvive di una barra, data la distanza fra vecchio e nuovo.
create or replace function private.resa_familiarita(p_distanza numeric)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select greatest(0, least(1, 1 - 1.6 * greatest(0, least(1, coalesce(p_distanza, 0)))))
$$;

revoke all on function private.resa_familiarita(numeric) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Fa avanzare le due barre dopo una partita
-- ------------------------------------------------------------
create or replace function private.avanza_familiarita(
  p_team_id   bigint,
  p_league_id bigint,
  p_modulo    text,
  p_stile     text,
  p_giornata  smallint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_disp      text[];
  v_ruoli     text[];
  v_compiti   text[];
  v_semina    smallint;
  v_prec      public.indicazioni_xp;
  v_distanza  numeric;
  v_diversi   integer;
begin
  select coalesce(l.disposizione, private.disposizione_standard(p_modulo)), l.ruoli, l.compiti
  into v_disp, v_ruoli, v_compiti
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
    insert into public.indicazioni_xp (team_id, league_id, partite_giocate, stile, ruoli, compiti)
    values (
      p_team_id, p_league_id,
      least(private.fam_partite_piena(),
            coalesce((select sx.partite_giocate from public.stile_xp sx
                      where sx.team_id = p_team_id and sx.stile = p_stile), 0))::smallint + 1,
      p_stile, v_ruoli, v_compiti);
    return;
  end if;

  -- Distanza su 23 elementi: lo stile, gli undici ruoli, gli undici compiti.
  -- Un elemento assente da entrambe le parti non e' un cambiamento.
  v_diversi := (case when coalesce(v_prec.stile, '') <> coalesce(p_stile, '') then 1 else 0 end)
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.ruoli[i], '') <> coalesce(v_ruoli[i], ''))
    + (select count(*) from generate_series(1, 11) i
       where coalesce(v_prec.compiti[i], '') <> coalesce(v_compiti[i], ''));
  v_distanza := v_diversi::numeric / 23;

  -- Stessa cura dell'eredita': si arretra la quota, non il conteggio grezzo.
  update public.indicazioni_xp
  set partite_giocate = least(32767, greatest(0,
        round(least(1.0, partite_giocate::numeric / private.fam_partite_piena())
              * private.resa_familiarita(v_distanza)
              * private.fam_partite_piena())::smallint + 1)),
      stile = p_stile, ruoli = v_ruoli, compiti = v_compiti, aggiornata_il = now()
  where team_id = p_team_id;
end;
$$;

revoke all on function private.avanza_familiarita(bigint, bigint, text, text, smallint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Gli undici slot, i ruoli e i compiti della formazione
-- ------------------------------------------------------------
alter table public.lineups
  add column if not exists disposizione text[],
  add column if not exists ruoli text[],
  add column if not exists compiti text[];

comment on column public.lineups.disposizione is
  'Gli undici slot davvero schierati. NULL = lo schieramento standard del modulo. E'' qui che vivono gli schemi personalizzati.';
comment on column public.lineups.ruoli is
  'Un ruolo per slot (engine/ruoli.js). NULL o elemento NULL = ruolo naturale dello slot.';
comment on column public.lineups.compiti is
  'Un compito per slot: difesa, equilibrio, attacco. NULL = equilibrio.';

-- ------------------------------------------------------------
--  registra_risultato_partita fa avanzare le due barre
--  Definizione ripresa integralmente dal database vivo (pg_get_functiondef),
--  con il solo blocco formation_xp sostituito dalla chiamata a
--  private.avanza_familiarita. Firma, default e attributi sono quelli veri.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registra_risultato_partita(p_fixture_id bigint, p_seed bigint, p_modulo_home text, p_modulo_away text, p_stile_home text, p_stile_away text, p_gol_home smallint, p_gol_away smallint, p_blocchi jsonb, p_stats_squadra jsonb, p_player_stats jsonb, p_titolari_home bigint[] DEFAULT '{}'::bigint[], p_titolari_away bigint[] DEFAULT '{}'::bigint[], p_gol_home_90 smallint DEFAULT NULL::smallint, p_gol_away_90 smallint DEFAULT NULL::smallint, p_rigori_home smallint DEFAULT NULL::smallint, p_rigori_away smallint DEFAULT NULL::smallint, p_rigori_serie jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_fixture public.fixtures;
  v_match public.matches;
  v_season public.seasons;
begin
  select * into v_fixture
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Fixture non trovata.';
  end if;

  select * into v_match
  from public.matches
  where fixture_id = p_fixture_id;

  if found then
    return jsonb_build_object(
      'match_id', v_match.id,
      'fixture_id', v_match.fixture_id,
      'gia_simulata', true,
      'gol_home', v_match.gol_home,
      'gol_away', v_match.gol_away
    );
  end if;

  select * into v_season
  from public.seasons
  where id = v_fixture.season_id
    and league_id = v_fixture.league_id;

  if not found or v_season.stato <> 'in_corso' then
    raise exception using errcode = '55000', message = 'La stagione non e'' in corso.';
  end if;
  if v_fixture.stato not in ('programmata', 'in_corso') then
    raise exception using errcode = '55000', message = 'La fixture non puo'' essere simulata.';
  end if;
  if p_seed not between 1 and 4294967295 then
    raise exception using errcode = '22023', message = 'Seed non valido.';
  end if;
  if p_gol_home < 0 or p_gol_away < 0 then
    raise exception using errcode = '22023', message = 'Il risultato contiene gol negativi.';
  end if;
  if jsonb_typeof(p_blocchi) <> 'array'
     or jsonb_typeof(p_stats_squadra) <> 'object'
     or jsonb_typeof(p_player_stats) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload statistiche non valido.';
  end if;
  if not (p_modulo_home = any(private.moduli_validi()))
     or not (p_modulo_away = any(private.moduli_validi())) then
    raise exception using errcode = '22023', message = 'Modulo non valido.';
  end if;
  if not (p_stile_home = any(private.stili_validi()))
     or not (p_stile_away = any(private.stili_validi())) then
    raise exception using errcode = '22023', message = 'Stile di gioco non valido.';
  end if;

  if not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.home_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_home
      and l.stile_gioco = p_stile_home
  ) or not exists (
    select 1 from public.lineups l
    where l.league_id = v_fixture.league_id
      and l.team_id = v_fixture.away_team_id
      and l.giornata = v_fixture.giornata
      and l.modulo = p_modulo_away
      and l.stile_gioco = p_stile_away
  ) then
    raise exception using errcode = '55000', message = 'Manca una formazione valida per questa partita.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_player_stats) as x(
      player_instance_id bigint,
      team_id bigint,
      minuti smallint,
      gol smallint,
      assist smallint,
      tiri smallint,
      tiri_porta smallint,
      passaggi_tentati smallint,
      passaggi_riusciti smallint,
      contrasti_vinti smallint,
      contrasti_persi smallint,
      dribbling smallint
    )
    left join public.player_instances pi
      on pi.id = x.player_instance_id
     and pi.league_id = v_fixture.league_id
     and pi.team_id = x.team_id
    where pi.id is null
       or x.team_id not in (v_fixture.home_team_id, v_fixture.away_team_id)
  ) then
    raise exception using errcode = '42501', message = 'Le statistiche contengono un giocatore fuori dalle squadre della partita.';
  end if;

  insert into public.matches (
    fixture_id,
    league_id,
    gol_home,
    gol_away,
    modulo_home,
    modulo_away,
    stile_home,
    stile_away,
    seed,
    blocchi,
    stats_squadra,
    titolari_home,
    titolari_away,
    gol_home_90,
    gol_away_90,
    rigori_home,
    rigori_away,
    rigori_serie
  ) values (
    p_fixture_id,
    v_fixture.league_id,
    p_gol_home,
    p_gol_away,
    p_modulo_home,
    p_modulo_away,
    p_stile_home,
    p_stile_away,
    p_seed,
    p_blocchi,
    p_stats_squadra,
    coalesce(p_titolari_home, '{}'::bigint[]),
    coalesce(p_titolari_away, '{}'::bigint[]),
    p_gol_home_90,
    p_gol_away_90,
    p_rigori_home,
    p_rigori_away,
    p_rigori_serie
  )
  returning * into v_match;

  insert into public.match_stats (
    match_id,
    league_id,
    team_id,
    player_instance_id,
    minuti,
    gol,
    assist,
    tiri,
    tiri_porta,
    passaggi_tentati,
    passaggi_riusciti,
    contrasti_vinti,
    contrasti_persi,
    dribbling
  )
  select
    v_match.id,
    v_fixture.league_id,
    x.team_id,
    x.player_instance_id,
    x.minuti,
    x.gol,
    x.assist,
    x.tiri,
    x.tiri_porta,
    x.passaggi_tentati,
    x.passaggi_riusciti,
    x.contrasti_vinti,
    x.contrasti_persi,
    x.dribbling
  from jsonb_to_recordset(p_player_stats) as x(
    player_instance_id bigint,
    team_id bigint,
    minuti smallint,
    gol smallint,
    assist smallint,
    tiri smallint,
    tiri_porta smallint,
    passaggi_tentati smallint,
    passaggi_riusciti smallint,
    contrasti_vinti smallint,
    contrasti_persi smallint,
    dribbling smallint
  );

  -- Le partite di playoff/playout non entrano in classifica (design §10.7):
  -- la stagione regolare e' gia' chiusa e la sua classifica e' congelata.
  if v_fixture.bracket_tie_id is null then
  update public.standings
  set
    vittorie = vittorie + case
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 1
      else 0 end,
    pareggi = pareggi + case when p_gol_home = p_gol_away then 1 else 0 end,
    sconfitte = sconfitte + case
      when team_id = v_fixture.home_team_id and p_gol_home < p_gol_away then 1
      when team_id = v_fixture.away_team_id and p_gol_away < p_gol_home then 1
      else 0 end,
    punti = punti + case
      when p_gol_home = p_gol_away then 1
      when team_id = v_fixture.home_team_id and p_gol_home > p_gol_away then 3
      when team_id = v_fixture.away_team_id and p_gol_away > p_gol_home then 3
      else 0 end,
    gol_fatti = gol_fatti + case when team_id = v_fixture.home_team_id then p_gol_home else p_gol_away end,
    gol_subiti = gol_subiti + case when team_id = v_fixture.home_team_id then p_gol_away else p_gol_home end,
    aggiornata_il = now()
  where season_id = v_fixture.season_id
    and team_id in (v_fixture.home_team_id, v_fixture.away_team_id);
  end if;

  -- Le due barre di familiarita' (vedi 20260917010000). Lo schieramento e le
  -- indicazioni si leggono dalla formazione di giornata invece di arrivare per
  -- parametro: questa funzione ne ha gia' diciotto.
  perform private.avanza_familiarita(
    v_fixture.home_team_id, v_fixture.league_id, p_modulo_home, p_stile_home, v_fixture.giornata);
  perform private.avanza_familiarita(
    v_fixture.away_team_id, v_fixture.league_id, p_modulo_away, p_stile_away, v_fixture.giornata);

  insert into public.stile_xp (team_id, league_id, stile, partite_giocate)
  values
    (v_fixture.home_team_id, v_fixture.league_id, p_stile_home, 1),
    (v_fixture.away_team_id, v_fixture.league_id, p_stile_away, 1)
  on conflict (team_id, stile) do update set
    partite_giocate = public.stile_xp.partite_giocate + 1,
    aggiornata_il = now();

  update public.fixtures
  set stato = 'simulata'
  where id = p_fixture_id;

  -- La posizione e' ricalcolata dopo ogni risultato. Gli scontri diretti
  -- considerano soltanto le avversarie a pari punti nella classifica attuale.
  if v_fixture.bracket_tie_id is null then
  update public.standings
  set posizione = null
  where season_id = v_fixture.season_id;

  with h2h as (
    select
      st.team_id,
      coalesce(sum(case
        when f.home_team_id = st.team_id and m.gol_home > m.gol_away then 3
        when f.away_team_id = st.team_id and m.gol_away > m.gol_home then 3
        when m.gol_home = m.gol_away then 1
        else 0
      end), 0)::integer as punti_diretti
    from public.standings st
    left join public.fixtures f
      on f.season_id = st.season_id
     and (f.home_team_id = st.team_id or f.away_team_id = st.team_id)
    left join public.matches m on m.fixture_id = f.id
    left join public.standings opponent
      on opponent.season_id = st.season_id
     and opponent.team_id = case
       when f.home_team_id = st.team_id then f.away_team_id
       else f.home_team_id
     end
     and opponent.punti = st.punti
    where st.season_id = v_fixture.season_id
      and opponent.team_id is not null
    group by st.team_id
  ), ranking as (
    select
      st.team_id,
      row_number() over (
        order by st.punti desc,
                 coalesce(h2h.punti_diretti, 0) desc,
                 st.differenza_reti desc,
                 st.gol_fatti desc,
                 st.team_id
      )::smallint as posizione
    from public.standings st
    left join h2h on h2h.team_id = st.team_id
    where st.season_id = v_fixture.season_id
  )
  update public.standings st
  set posizione = ranking.posizione
  from ranking
  where st.season_id = v_fixture.season_id
    and st.team_id = ranking.team_id;
  end if;

  -- Un accoppiamento si risolve appena entrambe le sue mani sono giocate:
  -- da li' nasce il turno successivo, e alla fine i premi del playout.
  if v_fixture.bracket_tie_id is not null then
    perform private.risolvi_tie(v_fixture.bracket_tie_id);
  end if;

  if not exists (
    select 1 from public.fixtures
    where season_id = v_fixture.season_id
      and stato = 'programmata'
  ) then
    -- Finita la stagione regolare non si chiude subito: se la lega ha almeno
    -- 8 squadre nascono playoff e playout, con le loro fixtures (design
    -- §10.7). La stagione finisce davvero solo quando anche quelle sono state
    -- giocate, e a quel punto qui non si crea piu' nulla.
    if not exists (select 1 from public.brackets where season_id = v_fixture.season_id) then
      perform private.crea_tabelloni(v_fixture.season_id);
    end if;

    if not exists (
      select 1 from public.fixtures
      where season_id = v_fixture.season_id
        and stato = 'programmata'
    ) then
      update public.seasons
      set stato = 'conclusa', data_fine = (now() at time zone 'Europe/Rome')::date
      where id = v_fixture.season_id;
      update public.leagues
      set stato = 'conclusa'
      where id = v_fixture.league_id;
    end if;
  end if;

  return jsonb_build_object(
    'match_id', v_match.id,
    'fixture_id', v_match.fixture_id,
    'gia_simulata', false,
    'gol_home', v_match.gol_home,
    'gol_away', v_match.gol_away
  );
end;
$function$;


-- ------------------------------------------------------------
--  Semina iniziale della barra INDICAZIONI
--
--  Prima di questa migrazione la seconda componente della familiarita' era lo
--  STILE di gioco. La barra indicazioni lo assorbe, quindi eredita il suo
--  contatore: senza, ogni squadra gia' avviata si ritroverebbe a meta' barra
--  dall'oggi al domani senza aver toccato niente.
--
--  Si prende lo stile dell'ultima formazione salvata, che e' quello con cui la
--  squadra sta effettivamente giocando.
-- ------------------------------------------------------------
insert into public.indicazioni_xp (team_id, league_id, partite_giocate, stile, ruoli, compiti)
select t.id, t.league_id,
       least(private.fam_partite_piena(), coalesce(sx.partite_giocate, 0))::smallint,
       ul.stile_gioco, ul.ruoli, ul.compiti
from public.teams t
join lateral (
  select l.stile_gioco, l.ruoli, l.compiti
  from public.lineups l
  where l.team_id = t.id
  order by l.giornata desc
  limit 1
) ul on true
left join public.stile_xp sx on sx.team_id = t.id and sx.stile = ul.stile_gioco
on conflict (team_id) do nothing;
