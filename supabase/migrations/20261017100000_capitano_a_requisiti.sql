-- ============================================================
--  CAPITANO A REQUISITI — prova in LegaBot (interruttore leagues.conferenze_stampa)
--  Deciso il 17 ottobre 2026 con il committente (docs/decisioni-conferenze-stampa.md).
--
--  Un capitano completo ha quattro requisiti, un punto ciascuno (idoneita 0-4):
--    1. bandiera come ramo principale della mentalita' (basta questo, sì/no);
--    2. esperienza: piu' di 25 anni;
--    3. anzianita': fra i 5 giocatori della rosa che sono da piu' tempo nel club;
--    4. centrale nel progetto: titolare per il minutaggio (gradino "titolare").
--  L'idoneita' decide quanto il capitano attenua il malcontento dei compagni
--  (private.qualita_capitano, usata dal ricalcolo del morale); se e' lui lo
--  scontento (morale < 50) la sua qualita' scende e puo' peggiorarlo, come prima.
--  Nelle altre leghe resta la formula di sempre (morale + freddezza).
--
--  Cambiare capitano costa: l'ex capitano prende un colpo al morale
--  (-12, piu' 0,12 per ogni punto di bandiera: da -12 a -24).
--
--  Anzianita': quasi tutti arrivano dal draft e arrivo_stagione e' vuoto, quindi a
--  parita' vince il piu' anziano d'eta' (poi l'id). Diventa un criterio vero stagione
--  dopo stagione, man mano che arrivano nuovi acquisti.
-- ============================================================

begin;

-- Il dettaglio dei quattro requisiti per ogni giocatore di una squadra.
create or replace function private.requisiti_capitano(p_team_id bigint)
returns table (player_instance_id bigint, bandiera boolean, esperienza boolean, anzianita boolean, titolare boolean, punti smallint)
language sql stable security definer set search_path = ''
as $$
  with rosa as (
    select pi.id, pi.eta_corrente, p.mentalita_bandiera, p.mentalita_economia, p.mentalita_vittorie,
           row_number() over (
             order by coalesce(pi.arrivo_stagione, case when pi.giornata_acquisizione is not null then l.stagione_corrente else 0 end),
                      coalesce(pi.giornata_acquisizione, 0), pi.eta_corrente desc, pi.id
           ) as ordine_anzianita
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    join public.leagues l on l.id = pi.league_id
    where pi.team_id = p_team_id and not pi.ritirato
  )
  select r.id,
         r.mentalita_bandiera >= greatest(r.mentalita_economia, r.mentalita_vittorie),
         r.eta_corrente > 25,
         r.ordine_anzianita <= 5,
         private.gradino_effettivo(r.id) = 'titolare',
         ((r.mentalita_bandiera >= greatest(r.mentalita_economia, r.mentalita_vittorie))::int
          + (r.eta_corrente > 25)::int + (r.ordine_anzianita <= 5)::int
          + (private.gradino_effettivo(r.id) = 'titolare')::int)::smallint
  from rosa r
$$;

-- La qualita' del capitano, da -1 a 1.
create or replace function private.qualita_capitano(p_id bigint)
returns numeric
language sql stable security definer set search_path = ''
as $$
  select case when l.conferenze_stampa then
      greatest(-1, least(1,
        (select rc.punti from private.requisiti_capitano(pi.team_id) rc where rc.player_instance_id = pi.id) / 4.0
        - greatest(0, (50 - pi.morale)::numeric / 50)))
    else
      greatest(-1, least(1,
        ((pi.morale - 70)::numeric / 30) * 0.5
      + ((coalesce((private.attributi_effettivi(
            p.attributi,
            coalesce(pi.posizioni_override, p.posizioni),
            pi.overall_corrente - p.overall,
            pi.attributi_override
          )->>'mentality_composure')::numeric, 60) - 60) / 25) * 0.5
      ))
    end
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  join public.leagues l on l.id = pi.league_id
  where pi.id = p_id and not pi.ritirato
$$;

-- Per l'app: i candidati della propria squadra, con i quattro requisiti e chi porta la fascia.
create or replace function public.candidati_capitano(p_league_id bigint)
returns table (player_instance_id bigint, bandiera boolean, esperienza boolean, anzianita boolean, titolare boolean, punti smallint, designato boolean, capitano_effettivo boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_team public.teams;
  v_effettivo bigint;
begin
  select * into v_team from public.teams where league_id = p_league_id and user_id = (select auth.uid());
  if not found then return; end if;
  v_effettivo := coalesce(v_team.capitano, private.capitano_automatico(v_team.id));
  return query
    select rc.player_instance_id, rc.bandiera, rc.esperienza, rc.anzianita, rc.titolare, rc.punti,
           rc.player_instance_id = v_team.capitano, rc.player_instance_id = v_effettivo
    from private.requisiti_capitano(v_team.id) rc;
end;
$$;
revoke all on function public.candidati_capitano(bigint) from public, anon;
grant execute on function public.candidati_capitano(bigint) to authenticated;

-- Il ricalcolo del morale: capitano effettivo (designato o piu' idoneo).
CREATE OR REPLACE FUNCTION public.applica_morale_checkpoint(p_league_id bigint, p_giornata smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

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
        -- Capitano effettivo: quello designato oppure, nelle leghe con il capitano a requisiti
        -- (conferenze_stampa), il piu' idoneo. Quanto la fascia tiene su lo spogliatoio. Zero se la squadra non ha
        -- un capitano, o se il capitano e' quello che si sta valutando: chi
        -- porta la fascia non consola se stesso.
        case when coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) is null or coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end) = pi.id then 0
             when not l.tattiche_attive then 0
             else private.qualita_capitano(coalesce(t.capitano, case when l.conferenze_stampa then private.capitano_automatico(t.id) end)) end as forza_capitano,
        p.mentalita_bandiera,
        p.mentalita_economia,
        p.mentalita_vittorie,
        pi.minutaggio_promesso,
        l.tattiche_attive as tattiche,
        -- media overall della propria rosa: e' il metro con cui il giocatore
        -- giudica quanto dovrebbe giocare
        (select avg(x.overall_corrente)
           from public.player_instances x
          where x.team_id = pi.team_id and not x.ritirato) as media_rosa,
        -- quota di minuti effettivamente giocati sulle giornate disputate
        coalesce((select ms.minuti from private.minuti_stagione(pi.id) ms), 0) as minuti_giocati,
        coalesce((select ms.partite from private.minuti_stagione(pi.id) ms), 0) as giornate_disputate,
        coalesce((select st.posizione
                    from public.standings st
                   where st.season_id = v_stagione_id and st.team_id = pi.team_id), 1) as posizione
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      join public.teams t on t.id = pi.team_id and t.attiva
      join public.leagues l on l.id = pi.league_id
      where pi.league_id = p_league_id and not pi.ritirato
      order by pi.id
      for update of pi
    loop
      -- 1. Minutaggio. Asimmetrico di proposito: giocare meno del previsto
      --    delude piu' di quanto giocare tanto gratifichi.
      -- Dall'arrivo in squadra, solo stagione corrente, senza le partite da
      -- assente; con meno di 3 partite giocabili la voce non pesa.
      v_delta_min := case when v_giocatore.giornate_disputate < 3 then 0 else greatest(-12, least(8,
        ((v_giocatore.minuti_giocati / (90.0 * v_giocatore.giornate_disputate))
          - case when v_giocatore.tattiche
              then private.quota_minutaggio(private.gradino_effettivo(v_giocatore.id))
              else private.quota_partite_attesa(v_giocatore.overall_corrente, coalesce(v_giocatore.media_rosa, v_giocatore.overall_corrente)) end
        ) * 30
      )) end;

      -- Promessa trattata e non mantenuta: pesa il 50% in piu'
      -- (docs/decisioni-minutaggio.md, punto 4).
      if v_giocatore.tattiche and v_giocatore.minutaggio_promesso is not null and v_delta_min < 0 then
        v_delta_min := greatest(-18, v_delta_min * 1.5);
      end if;

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

-- La nomina: con il costo per l'ex capitano.
CREATE OR REPLACE FUNCTION public.scegli_capitano(p_league_id bigint, p_player_instance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_team public.teams;
  v_ex record;
  v_ex_id bigint;
  v_colpo integer := 0;
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

  -- Togliere la fascia a chi la porta costa (lega con il capitano a requisiti): l'ex capitano
  -- prende un colpo al morale, piu' forte se e' un bandiera (per lui la fascia e' tutto).
  -- Vale anche se si torna al capitano automatico. Cambiare da "nessuno" non costa.
  if v_team.capitano is not null and v_team.capitano is distinct from p_player_instance_id
     and (select l.conferenze_stampa from public.leagues l where l.id = v_team.league_id) then
    select pi.id, pi.morale, p.nome, p.mentalita_bandiera into v_ex
    from public.player_instances pi join public.players p on p.id = pi.player_id
    where pi.id = v_team.capitano and pi.team_id = v_team.id and not pi.ritirato;
    if found then
      v_ex_id := v_ex.id;
      v_colpo := 12 + round(v_ex.mentalita_bandiera * 0.12);
      update public.player_instances set morale = greatest(0, morale - v_colpo)::smallint where id = v_ex.id;
      perform private.notifica(v_user_id, v_team.league_id, 'sistema', 'Fascia di capitano',
        v_ex.nome || ' ha perso la fascia e ne risente: morale -' || v_colpo || '.',
        jsonb_build_object('player_instance_id', v_ex.id));
    end if;
  end if;

  update public.teams set capitano = p_player_instance_id where id = v_team.id;

  return jsonb_build_object('team_id', v_team.id, 'capitano', p_player_instance_id, 'colpo_morale', v_colpo, 'ex_capitano', v_ex_id);
end;
$function$;

commit;
