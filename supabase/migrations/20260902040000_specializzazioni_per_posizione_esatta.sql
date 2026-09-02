-- ============================================================
--  Le specializzazioni erano per MACRO-ruolo (DEF/MID/ATT), non per
--  posizione esatta: un CB puro si vedeva proporre "Terzino offensivo"
--  (dribbling/stamina), che ha senso per un terzino ma non per un
--  difensore centrale puro. Segnalato dall'utente il 2 settembre 2026.
--
--  private.specializzazioni_ruolo ora prende la posizione ESATTA
--  (p_posizioni_attuali[1]: CB, LB, RB, ...), non il macro-ruolo. Stessa
--  filosofia di prima (2-4 archetipi per posizione, +7/+4 su due
--  attributi reali, GK escluso perche' il motore legge un solo "gk"
--  aggregato): solo la granularita' cambia, da 3 macro-ruoli a 13
--  posizioni. Stessa firma (text -> jsonb): create or replace basta,
--  nessun drop necessario.
-- ============================================================

begin;

-- Il nome del parametro cambia (p_macro_ruolo -> p_posizione): create or
-- replace da solo rifiuta di rinominarlo, serve un drop esplicito prima.
drop function if exists private.specializzazioni_ruolo(text);

create function private.specializzazioni_ruolo(p_posizione text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_posizione
    when 'CB' then jsonb_build_object(
      'marcatore', jsonb_build_object('etichetta', 'Marcatore',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'libero', jsonb_build_object('etichetta', 'Libero',
        'deltas', jsonb_build_object('short_passing', 7, 'standing_tackle', 4))
    )
    when 'LB' then jsonb_build_object(
      'terzino_difensivo', jsonb_build_object('etichetta', 'Terzino difensivo',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'terzino_offensivo', jsonb_build_object('etichetta', 'Terzino offensivo',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'regista_basso', jsonb_build_object('etichetta', 'Regista basso',
        'deltas', jsonb_build_object('short_passing', 7, 'standing_tackle', 4))
    )
    when 'RB' then jsonb_build_object(
      'terzino_difensivo', jsonb_build_object('etichetta', 'Terzino difensivo',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'terzino_offensivo', jsonb_build_object('etichetta', 'Terzino offensivo',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'regista_basso', jsonb_build_object('etichetta', 'Regista basso',
        'deltas', jsonb_build_object('short_passing', 7, 'standing_tackle', 4))
    )
    when 'LWB' then jsonb_build_object(
      'corsia_offensiva', jsonb_build_object('etichetta', 'Corsia offensiva',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'corsia_equilibrata', jsonb_build_object('etichetta', 'Corsia equilibrata',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4))
    )
    when 'RWB' then jsonb_build_object(
      'corsia_offensiva', jsonb_build_object('etichetta', 'Corsia offensiva',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'corsia_equilibrata', jsonb_build_object('etichetta', 'Corsia equilibrata',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4))
    )
    when 'CDM' then jsonb_build_object(
      'schermo_difensivo', jsonb_build_object('etichetta', 'Schermo difensivo',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'regista_arretrato', jsonb_build_object('etichetta', 'Regista arretrato',
        'deltas', jsonb_build_object('short_passing', 7, 'standing_tackle', 4))
    )
    when 'CM' then jsonb_build_object(
      'regista', jsonb_build_object('etichetta', 'Regista',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'box_to_box', jsonb_build_object('etichetta', 'Box-to-box',
        'deltas', jsonb_build_object('stamina', 7, 'standing_tackle', 4)),
      'recupera_palloni', jsonb_build_object('etichetta', 'Recupera palloni',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4)),
      'mezzala_inserimento', jsonb_build_object('etichetta', 'Mezz''ala d''inserimento',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    when 'CAM' then jsonb_build_object(
      'rifinitore', jsonb_build_object('etichetta', 'Rifinitore',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'mezzala_inserimento', jsonb_build_object('etichetta', 'Mezz''ala d''inserimento',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    when 'LM' then jsonb_build_object(
      'ala_di_fascia', jsonb_build_object('etichetta', 'Ala di fascia',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'mezzala_di_fascia', jsonb_build_object('etichetta', 'Mezzala di fascia',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4))
    )
    when 'RM' then jsonb_build_object(
      'ala_di_fascia', jsonb_build_object('etichetta', 'Ala di fascia',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'mezzala_di_fascia', jsonb_build_object('etichetta', 'Mezzala di fascia',
        'deltas', jsonb_build_object('standing_tackle', 7, 'stamina', 4))
    )
    when 'LW' then jsonb_build_object(
      'ala_rapida', jsonb_build_object('etichetta', 'Ala rapida',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'rifinitore_esterno', jsonb_build_object('etichetta', 'Rifinitore esterno',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'ala_realizzatrice', jsonb_build_object('etichetta', 'Ala realizzatrice',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    when 'RW' then jsonb_build_object(
      'ala_rapida', jsonb_build_object('etichetta', 'Ala rapida',
        'deltas', jsonb_build_object('dribbling', 7, 'stamina', 4)),
      'rifinitore_esterno', jsonb_build_object('etichetta', 'Rifinitore esterno',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'ala_realizzatrice', jsonb_build_object('etichetta', 'Ala realizzatrice',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    when 'ST' then jsonb_build_object(
      'rapace_area', jsonb_build_object('etichetta', 'Rapace d''area',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4)),
      'bomber_fisico', jsonb_build_object('etichetta', 'Bomber fisico',
        'deltas', jsonb_build_object('stamina', 7, 'finishing', 4)),
      'falso_nueve', jsonb_build_object('etichetta', 'Falso nueve',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4))
    )
    when 'CF' then jsonb_build_object(
      'falso_nueve', jsonb_build_object('etichetta', 'Falso nueve',
        'deltas', jsonb_build_object('short_passing', 7, 'dribbling', 4)),
      'rapace_area', jsonb_build_object('etichetta', 'Rapace d''area',
        'deltas', jsonb_build_object('finishing', 7, 'dribbling', 4))
    )
    else '{}'::jsonb
  end
$$;
comment on function private.specializzazioni_ruolo(text) is
  'Catalogo delle specializzazioni per POSIZIONE ESATTA (CB, LB, RB, ...), '
  'non per macro-ruolo: un CB e un LB hanno archetipi diversi. GK escluso '
  '(else vuoto): il motore legge un solo "gk" aggregato.';

-- public.specializzazioni_disponibili: passa la posizione esatta, non piu'
-- il macro-ruolo.
create or replace function public.specializzazioni_disponibili(p_instance_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.specializzazioni_ruolo((coalesce(pi.posizioni_override, p.posizioni))[1])
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;
$$;

-- avvia_specializzazione: stessa cosa, e il controllo "e' il portiere?" ora
-- guarda direttamente la posizione invece di passare da macro_ruolo.
create or replace function public.avvia_specializzazione(p_instance_id bigint, p_specializzazione text)
returns public.specializzazioni_giocatore
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_istanza public.player_instances;
  v_squadra public.teams;
  v_lega public.leagues;
  v_posizioni_attuali text[];
  v_catalogo jsonb;
  v_livello smallint;
  v_riduzione numeric;
  v_durata integer;
  v_prossima integer;
  v_allenamento public.specializzazioni_giocatore;
begin
  if v_utente is null then
    raise exception using errcode = '42501', message = 'Devi accedere per gestire il training.';
  end if;

  select * into v_istanza from public.player_instances where id = p_instance_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Giocatore inesistente.';
  end if;

  select * into v_squadra from public.teams where id = v_istanza.team_id and user_id = v_utente;
  if not found then
    raise exception using errcode = '42501', message = 'Questo giocatore non appartiene alla tua squadra.';
  end if;

  select * into v_lega from public.leagues where id = v_istanza.league_id;
  if v_lega.stato <> 'stagione' then
    raise exception using errcode = '55000', message = 'Puoi avviare un allenamento solo durante la stagione.';
  end if;

  perform 1 from public.player_instances where id = p_instance_id for update;

  if exists (
    select 1 from public.specializzazioni_giocatore
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000', message = 'Questo giocatore ha già un allenamento in corso.';
  end if;
  if exists (
    select 1 from public.cambi_ruolo
    where player_instance_id = p_instance_id and completato_il is null
  ) then
    raise exception using errcode = '55000',
      message = 'Questo giocatore sta gia'' cambiando ruolo: non puo'' anche allenare una specializzazione insieme.';
  end if;

  select coalesce(pi.posizioni_override, p.posizioni) into v_posizioni_attuali
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni_attuali[1]);
  if v_posizioni_attuali[1] = 'GK' or not (v_catalogo ? p_specializzazione) then
    raise exception using errcode = '22023',
      message = case when v_posizioni_attuali[1] = 'GK'
        then 'Il portiere non ha specializzazioni: il motore riassume le sue qualità in un unico valore.'
        else 'Specializzazione non valida per questo ruolo.' end;
  end if;

  select livello_training into v_livello from public.team_risorse where team_id = v_squadra.id;
  v_riduzione := coalesce(
    (private.effetti_ramo('training', coalesce(v_livello, 0::smallint))->>'riduzione_tempi_ruolo_pct')::numeric, 0);

  v_durata := greatest(3, round(10 * (1 - v_riduzione / 100.0)));

  select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
  from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

  insert into public.specializzazioni_giocatore (
    league_id, team_id, player_instance_id, specializzazione_precedente, specializzazione_target,
    avviato_giornata, completa_giornata
  ) values (
    v_lega.id, v_squadra.id, p_instance_id, v_istanza.specializzazione_attiva, p_specializzazione,
    v_prossima, v_prossima + v_durata
  ) returning * into v_allenamento;

  return v_allenamento;
end;
$$;

-- private.completa_specializzazioni: idem, posizione esatta invece di macro.
create or replace function private.completa_specializzazioni()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_riga record;
  v_deltas jsonb;
  v_chiave text;
  v_base_attributi jsonb;
  v_override jsonb;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_riga in
      select s.*, pi.posizioni_override, p.posizioni as posizioni_catalogo, p.attributi as attributi_catalogo
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_deltas := private.specializzazioni_ruolo((coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo))[1])
        -> v_riga.specializzazione_target -> 'deltas';
      v_base_attributi := v_riga.attributi_catalogo;
      v_override := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(coalesce(v_deltas, '{}'::jsonb)) loop
        v_override := v_override || jsonb_build_object(
          v_chiave, least(99, coalesce((v_base_attributi->>v_chiave)::int, 0) + (v_deltas->>v_chiave)::int)
        );
      end loop;

      update public.player_instances
      set attributi_override = v_override, specializzazione_attiva = v_riga.specializzazione_target
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        'Un giocatore ha completato l''allenamento: ora è specializzato come ' || v_riga.specializzazione_target || '.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;

commit;
