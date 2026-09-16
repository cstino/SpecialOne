-- ============================================================
--  CHI BATTE I PIAZZATI: automatico al salvataggio, modificabile a mano
--
--  Con angoli e punizioni nel motore (engine/piazzati.js), chi li batte conta
--  davvero: il migliore su quel gesto converte di piu'. Finora l'incaricato era
--  dedotto in partita prendendo il migliore in campo, e il proprietario non
--  poteva dire la sua.
--
--  COME DECISO CON L'UTENTE: quando si salva l'undici il sistema assegna da
--  solo i tre incarichi, e chi vuole li cambia. Chi non se ne occupa non deve
--  accorgersi che esistono.
--
--  Le tre scelte finiscono su lineups e non su teams perche' seguono la
--  FORMAZIONE, non la squadra: se il rigorista designato finisce in tribuna
--  alla giornata dopo, l'incarico deve tornare a qualcun altro da solo.
--
--  IL RIGORISTA usa la stessa formula del dischetto (engine/rigori.js): non
--  l'attributo "rigori" da solo, ma l'overall corretto per meta' dello scarto
--  con quell'attributo. Un fuoriclasse mediocre dagli undici metri resta
--  comunque una scelta ragionevole; uno specialista modesto lo supera.
--
--  IL CAPITANO NON C'E', ed e' voluto. Nei dati FC 26 non esiste un attributo
--  di leadership, e soprattutto non abbiamo ancora deciso cosa faccia. Una
--  fascia che non fa niente e' esattamente l'errore appena corretto sui rigori,
--  dove la scheda mostrava una statistica che il gioco ignorava. Arrivera' col
--  morale, dove avra' qualcosa da fare.
-- ============================================================

alter table public.lineups
  add column if not exists rigorista  bigint references public.player_instances(id) on delete set null,
  add column if not exists angoli     bigint references public.player_instances(id) on delete set null,
  add column if not exists punizioni  bigint references public.player_instances(id) on delete set null;

comment on column public.lineups.rigorista is
  'Chi tira i rigori. Assegnato in automatico al salvataggio, modificabile. Deve essere fra i titolari.';
comment on column public.lineups.angoli is
  'Chi batte gli angoli. Stesse regole del rigorista.';
comment on column public.lineups.punizioni is
  'Chi calcia le punizioni. Stesse regole del rigorista.';

-- ------------------------------------------------------------
--  I tre incaricati migliori fra un dato undici
--
--  Il portiere e' sempre escluso: para, non batte.
-- ------------------------------------------------------------
create or replace function private.incaricati_automatici(
  p_league_id bigint,
  p_titolari  bigint[]
)
returns table (rigorista bigint, angoli bigint, punizioni bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with giocatori as (
    select pi.id,
           private.attributi_effettivi(
             p.attributi,
             coalesce(pi.posizioni_override, p.posizioni),
             pi.overall_corrente - p.overall,
             pi.attributi_override) as a,
           pi.overall_corrente as ovr,
           coalesce(pi.posizioni_override, p.posizioni) as pos
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and pi.id = any(p_titolari)
  ), voti as (
    select id,
           -- Stessa formula del dischetto: overall corretto per meta' dello
           -- scarto con l'attributo rigori (CFG_RIGORI.PESO_SPECIALISTA = 0.5).
           ovr + (coalesce((a->>'mentality_penalties')::numeric, ovr) - ovr) * 0.5 as v_rigori,
           (coalesce((a->>'attacking_crossing')::numeric, 40)
            + coalesce((a->>'skill_curve')::numeric, 40)) / 2 as v_angoli,
           (coalesce((a->>'skill_fk_accuracy')::numeric, 40)
            + coalesce((a->>'power_long_shots')::numeric, 40)) / 2 as v_punizioni
    from giocatori
    where pos[1] <> 'GK'
  )
  select
    (select id from voti order by v_rigori desc, id limit 1),
    (select id from voti order by v_angoli desc, id limit 1),
    (select id from voti order by v_punizioni desc, id limit 1)
$$;

revoke all on function private.incaricati_automatici(bigint, bigint[]) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Riempie gli incarichi mancanti o non piu' validi
--
--  Un incarico resta al suo posto solo se quel giocatore e' ancora fra i
--  titolari. Altrimenti torna all'automatico: chi ha messo il rigorista in
--  tribuna non deve ritrovarsi senza.
-- ------------------------------------------------------------
create or replace function private.sistema_incaricati(p_team_id bigint, p_giornata smallint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_riga public.lineups;
  v_auto record;
begin
  select * into v_riga from public.lineups
  where team_id = p_team_id and giornata = p_giornata;
  if not found then return; end if;

  select * into v_auto from private.incaricati_automatici(v_riga.league_id, v_riga.titolari);

  update public.lineups set
    rigorista = case when rigorista = any(v_riga.titolari) then rigorista else v_auto.rigorista end,
    angoli    = case when angoli    = any(v_riga.titolari) then angoli    else v_auto.angoli end,
    punizioni = case when punizioni = any(v_riga.titolari) then punizioni else v_auto.punizioni end
  where team_id = p_team_id and giornata = p_giornata;
end;
$$;

revoke all on function private.sistema_incaricati(bigint, smallint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Il salvataggio della formazione li sistema
--  Definizione ripresa dal database, con una sola riga aggiunta in fondo.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salva_formazione(p_league_id bigint, p_giornata smallint, p_modulo text, p_titolari bigint[], p_panchina bigint[] DEFAULT '{}'::bigint[], p_tribuna bigint[] DEFAULT '{}'::bigint[], p_stile_gioco text DEFAULT 'equilibrato'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
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
    league_id, team_id, giornata, modulo, titolari, panchina, tribuna, stile_gioco, automatica, salvata_il
  ) values (
    p_league_id, v_team.id, p_giornata, p_modulo, p_titolari,
    coalesce(p_panchina, '{}'::bigint[]), coalesce(p_tribuna, '{}'::bigint[]), p_stile_gioco, false, now()
  )
  on conflict (team_id, giornata) do update set
    modulo = excluded.modulo,
    titolari = excluded.titolari,
    panchina = excluded.panchina,
    tribuna = excluded.tribuna,
    stile_gioco = excluded.stile_gioco,
    automatica = false,
    salvata_il = now();

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
    'titolari', p_titolari,
    'panchina', coalesce(p_panchina, '{}'::bigint[]),
    'tribuna', coalesce(p_tribuna, '{}'::bigint[])
  );
end;
$function$
;
