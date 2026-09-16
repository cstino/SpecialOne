-- ============================================================
--  IL CAPITANO, E IL MORALE CHE TOCCA IL CAMPO
--
--  Fino a oggi il morale non entrava in partita. Lo diceva in chiaro la
--  migrazione che lo ha introdotto (20260805150000): "Il morale NON tocca il
--  rendimento in campo". Serviva ai rinnovi e alle richieste economiche.
--
--  QUANTO DEVE PESARE, e perche' non a occhio. FM-Arena ha misurato il morale
--  in Football Manager su 2.880 partite, normalizzate su una stagione da 38:
--  da "Quite Poor" a "Very Good" sono +3,8 punti. Nello stesso banco la
--  condizione fisica ne vale +15,6 e la coesione di squadra +6. Il morale e'
--  quindi la PIU' PICCOLA delle tre leve, circa un quarto della condizione.
--  Tarato a sensazione avrebbe schiacciato le tattiche, che valgono il doppio.
--  Il lato motore sta in engine/morale.js, tarato su quel numero: misurato
--  3,6 punti su 38 fra morale 45 e morale 95.
--
--  IL CAPITANO STA QUI, NON NEL MOTORE. Provato prima nel motore, dove attenua
--  il malcontento dei compagni: vale +0,68 punti su 38, cioe' sotto il rumore
--  di un banco da 20.000 partite. Non e' un errore di taratura, e' il posto
--  sbagliato. In Football Manager la fascia agisce sullo SPOGLIATOIO NEL
--  TEMPO — atmosfera, recupero del morale — non sui novanta minuti. Da noi il
--  morale si ricalcola a ogni quarto di stagione, ed e' li' che il capitano
--  pesa e si accumula.
--
--  CHI E' UN BUON CAPITANO: il suo morale e la sua freddezza
--  (mentality_composure). Non serve un attributo di leadership, che nei dati
--  FC 26 non esiste — era la ragione per cui la fascia era stata rimandata
--  (vedi 20260916210000, dove il capitano era stato escluso di proposito).
--
--  UN CAPITANO SCONTENTO FA DANNO: la qualita' va sotto zero, e il malcontento
--  dei compagni pesa di piu' invece che di meno.
--
--  QUESTA MIGRAZIONE E' INERTE. teams.capitano nasce NULL e niente lo assegna
--  in automatico: finche' resta NULL, forza_capitano e' 0, l'attenuazione e' 1
--  e applica_morale_checkpoint calcola esattamente quello che calcolava prima.
--  L'assegnazione automatica e l'interfaccia arrivano insieme al resto del
--  lavoro tattico, non adesso.
-- ============================================================

alter table public.teams
  add column if not exists capitano bigint references public.player_instances(id) on delete set null;

comment on column public.teams.capitano is
  'Chi porta la fascia. Incarico di squadra, non di giornata: in Football Manager il capitano agisce sullo spogliatoio nel tempo. Influenza applica_morale_checkpoint, non il motore di partita.';

-- ------------------------------------------------------------
--  Quanto un giocatore tiene su lo spogliatoio, da -1 a +1
--  Stessa formula di engine/morale.js — qualitaCapitano().
-- ------------------------------------------------------------
create or replace function private.qualita_capitano(p_id bigint)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(-1, least(1,
      ((pi.morale - 70)::numeric / 30) * 0.5
    + ((coalesce((private.attributi_effettivi(
          p.attributi,
          coalesce(pi.posizioni_override, p.posizioni),
          pi.overall_corrente - p.overall,
          pi.attributi_override
        )->>'mentality_composure')::numeric, 60) - 60) / 25) * 0.5
  ))
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_id and not pi.ritirato
$$;

revoke all on function private.qualita_capitano(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Chi meriterebbe la fascia in una rosa
--  A parita', il piu' anziano: l'esperienza fa da spareggio, come nel motore.
-- ------------------------------------------------------------
create or replace function private.capitano_automatico(p_team_id bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select pi.id
  from public.player_instances pi
  where pi.team_id = p_team_id and not pi.ritirato
  order by private.qualita_capitano(pi.id) desc nulls last, pi.eta_corrente desc, pi.id
  limit 1
$$;

revoke all on function private.capitano_automatico(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Rimette a posto la fascia se il capitano non c'e' piu'
--
--  Serve perche' uno scambio non cancella la riga, le cambia team_id: la
--  chiave esterna con "on delete set null" non se ne accorge, e la squadra
--  resterebbe col capitano di un'altra rosa.
-- ------------------------------------------------------------
create or replace function private.sistema_capitano(p_team_id bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.teams t set capitano = null
  where t.id = p_team_id
    and t.capitano is not null
    and not exists (
      select 1 from public.player_instances pi
      where pi.id = t.capitano and pi.team_id = p_team_id and not pi.ritirato
    );
end;
$$;

revoke all on function private.sistema_capitano(bigint) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Scegliere il capitano
--
--  Solo un giocatore della propria rosa, e solo il proprietario della squadra.
--  NULL toglie la fascia.
-- ------------------------------------------------------------
create or replace function public.scegli_capitano(p_league_id bigint, p_player_instance_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di scegliere il capitano.';
  end if;

  select * into v_team from public.teams
  where league_id = p_league_id and user_id = v_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.';
  end if;

  if p_player_instance_id is not null and not exists (
    select 1 from public.player_instances
    where id = p_player_instance_id and team_id = v_team.id and not ritirato
  ) then
    raise exception using errcode = '42501', message = 'Quel giocatore non e'' nella tua rosa.';
  end if;

  update public.teams set capitano = p_player_instance_id where id = v_team.id;

  return jsonb_build_object('team_id', v_team.id, 'capitano', p_player_instance_id);
end;
$$;

revoke all on function public.scegli_capitano(bigint, bigint) from public, anon;
grant execute on function public.scegli_capitano(bigint, bigint) to authenticated;

-- ------------------------------------------------------------
--  Il checkpoint del morale tiene conto della fascia
--  Definizione ripresa dal database vivo, con le sole righe del capitano
--  aggiunte. Con capitano NULL il risultato e' identico a prima.
-- ------------------------------------------------------------
create or replace function public.applica_morale_checkpoint(
  p_league_id bigint,
  p_giornata smallint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$

declare
  v_lega record;
  v_stagione_id bigint;
  v_step smallint;
  v_soglia smallint;
  v_applicato smallint := null;
  v_aggiornati integer := 0;
  v_giocatore record;
  v_delta_min numeric;
  v_delta_eco numeric;
  v_delta_vit numeric;
  v_positivi numeric;
  v_negativi numeric;
  v_attenuazione numeric;
  v_att_capitano numeric;
  v_nuovo smallint;
begin
  select l.id, l.giornate_totali, l.n_squadre, s.id as season_id
  into v_lega
  from public.leagues l
  join public.seasons s
    on s.league_id = l.id and s.numero = l.stagione_corrente and s.stato = 'in_corso'
  where l.id = p_league_id and l.stato = 'stagione';

  if not found then
    return jsonb_build_object('checkpoint_applicato', null, 'giocatori_aggiornati', 0);
  end if;

  v_stagione_id := v_lega.season_id;

  -- Stessa scansione della progressione overall: si recupera al massimo un
  -- checkpoint arretrato per giornata, senza saltarne nessuno.
  for v_step in select generate_series(1, 4)::smallint loop
    v_soglia := ceil(v_lega.giornate_totali::numeric * v_step / 4.0)::smallint;
    if p_giornata < v_soglia then
      continue;
    end if;

    insert into public.season_morale_checkpoints(season_id, league_id, checkpoint, giornata)
    values (v_stagione_id, p_league_id, v_step, v_soglia)
    on conflict (season_id, checkpoint) do nothing;

    if not found then
      continue;
    end if;

    v_applicato := v_step;

    for v_giocatore in
      select
        pi.id,
        pi.morale,
        pi.ingaggio,
        pi.overall_corrente,
        pi.eta_corrente,
        pi.team_id,
        -- Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
        -- un capitano, o se il capitano e' quello che si sta valutando: chi
        -- porta la fascia non consola se stesso.
        case when t.capitano is null or t.capitano = pi.id then 0
             else private.qualita_capitano(t.capitano) end as forza_capitano,
        p.mentalita_bandiera,
        p.mentalita_economia,
        p.mentalita_vittorie,
        -- media overall della propria rosa: e' il metro con cui il giocatore
        -- giudica quanto dovrebbe giocare
        (select avg(x.overall_corrente)
           from public.player_instances x
          where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
        -- quota di minuti effettivamente giocati sulle giornate disputate
        coalesce((select sum(ms.minuti)::numeric
                    from public.match_stats ms
                   where ms.player_instance_id = pi.id), 0) as minuti_giocati,
        greatest(1, (select count(*)
                       from public.fixtures f
                      where f.season_id = v_stagione_id and f.stato = 'simulata'
                        and (f.home_team_id = pi.team_id or f.away_team_id = pi.team_id))) as giornate_disputate,
        coalesce((select st.posizione
                    from public.standings st
                   where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      v_delta_min := greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente))
        ) * 30
      ));

      -- 2. Economia, pesata dal ramo: 33 (media) pesa 1,0; 66 pesa 2,0.
      v_delta_eco := greatest(-10, least(6,
        ((v_giocatore.ingaggio::numeric
          / greatest(1, private.ingaggio_teorico(v_giocatore.overall_corrente, v_giocatore.eta_corrente))) - 1) * 20
      )) * (v_giocatore.mentalita_economia / 33.0);

      -- 3. Vittorie: posizione normalizzata, 0 = primo, 1 = ultimo.
      v_delta_vit := (0.5 - ((v_giocatore.posizione - 1)::numeric / greatest(1, v_lega.n_squadre - 1)))
        * 16 * (v_giocatore.mentalita_vittorie / 33.0);

      -- 4. Bandiera: non e' un contributo a se', attenua le insoddisfazioni.
      --    Un bandiera 60 assorbe il 30% del malcontento.
      v_attenuazione := 1 - (v_giocatore.mentalita_bandiera / 200.0);

      -- 5. Il capitano. In Football Manager la fascia agisce sullo spogliatoio
      --    nel tempo, non sui novanta minuti: e' qui che deve pesare, non nel
      --    motore. Un trascinatore assorbe fino al 30% del malcontento dei
      --    compagni; un capitano scontento lo peggiora, perche' la qualita' va
      --    anche sotto zero. Si moltiplica con l'attenuazione da bandiera
      --    invece di sommarsi: sono due modi diversi di reggere lo stesso colpo,
      --    e sommandoli un bandiera capitano sarebbe diventato immune.
      v_att_capitano := 1 - (v_giocatore.forza_capitano * 0.30);

      v_positivi := greatest(0, v_delta_min) + greatest(0, v_delta_eco) + greatest(0, v_delta_vit);
      v_negativi := (least(0, v_delta_min) + least(0, v_delta_eco) + least(0, v_delta_vit))
                    * v_attenuazione * v_att_capitano;

      v_nuovo := greatest(0, least(100, round(v_giocatore.morale + v_positivi + v_negativi)))::smallint;

      update public.player_instances set morale = v_nuovo where id = v_giocatore.id;
      v_aggiornati := v_aggiornati + 1;
    end loop;

    exit;
  end loop;

  return jsonb_build_object('checkpoint_applicato', v_applicato, 'giocatori_aggiornati', v_aggiornati);
end;

$function$;

revoke all on function public.applica_morale_checkpoint(bigint, smallint) from public, anon, authenticated;
grant execute on function public.applica_morale_checkpoint(bigint, smallint) to service_role;

comment on function public.applica_morale_checkpoint(bigint, smallint) is
  'Ricalcola il morale della lega al quarto di stagione raggiunto (design 11.3). Idempotente per (stagione, checkpoint). Da settembre 2026 tiene conto del capitano: chi porta la fascia attenua il malcontento dei compagni, o lo peggiora se e'' lui il primo scontento.';
