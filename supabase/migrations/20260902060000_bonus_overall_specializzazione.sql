-- ============================================================
--  L'OVERALL ORA REAGISCE ALLA SPECIALIZZAZIONE.
--
--  Segnalato dall'utente il 2 settembre 2026: non aveva senso che tre
--  stat vere migliorassero senza che l'overall si muovesse di un punto,
--  perche' l'overall di un giocatore è (nella realta' e nel dataset FC26
--  originale) un composto delle sue stat. Prima soluzione proposta (bonus
--  fisso tipo +2) scartata: avrebbe ignorato i dati che avevamo appena
--  arricchito con l'import completo (20260902050000_specializzazioni_
--  tre_stat.sql + normalizza.py).
--
--  Come funziona: EA non pubblica la formula esatta con cui calcola
--  l'overall dalle stat, ma la community l'ha ricostruita da tempo con
--  buona approssimazione (sofifa e affini) in due passaggi:
--    1) ogni sotto-attributo di dettaglio (finishing, short_passing,
--       standing_tackle, dribbling, stamina — gli unici 5 che il motore
--       usa, quindi gli unici toccati dalla specializzazione) contribuisce
--       per una frazione alla sua macro-categoria FIFA (SHO/PAS/DEF/DRI/PHY);
--    2) ogni macro-categoria pesa sull'overall in proporzione diversa a
--       seconda del macro-ruolo (un difensore pesa molto DEF, un
--       attaccante molto SHO).
--  Sono stime ragionevoli, non la formula segreta di EA: bastano per dare
--  un effetto coerente e proporzionato, non per riprodurla esattamente.
--
--  Il bonus e' quindi piccolo (spesso 1-2 punti): e' onesto cosi', un
--  allenamento mirato su un aspetto del gioco non deve valere quanto una
--  stagione intera di crescita. Un pavimento a 1 punto evita che finisca
--  arrotondato a zero (tornerebbe il problema di partenza).
--
--  Anti-abuso: il bonus scatta solo se la specializzazione_target e'
--  DIVERSA dalla precedente. Senza questo controllo, riavviare in loop lo
--  stesso allenamento sulla stessa specializzazione farebbe salire
--  l'overall all'infinito (gli attributi non rischiano: attributi_override
--  si ricalcola sempre da zero, ma l'overall e' cumulativo per necessita' —
--  convive con crescita stagionale e altri sistemi che lo toccano nel
--  tempo, quindi non puo' "resettarsi" come gli attributi).
-- ============================================================

begin;

create or replace function private.bonus_overall_specializzazione(p_macro_ruolo text, p_deltas jsonb)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  -- Peso di ciascuna macro-categoria FIFA sull'overall, per macro-ruolo
  -- (stima community, non la formula EA — vedi commento in testa al file).
  v_pesi_ruolo jsonb := case p_macro_ruolo
    when 'DEF' then '{"shooting":0.02,"passing":0.13,"dribbling":0.10,"defending":0.45,"physic":0.20,"pace":0.10}'::jsonb
    when 'ATT' then '{"shooting":0.35,"passing":0.10,"dribbling":0.22,"defending":0.02,"physic":0.13,"pace":0.18}'::jsonb
    else          '{"shooting":0.12,"passing":0.28,"dribbling":0.25,"defending":0.10,"physic":0.15,"pace":0.10}'::jsonb -- MID
  end;
  -- Quanto ciascun sotto-attributo trainabile contribuisce alla sua
  -- macro-categoria (idem, stima community).
  v_contributo constant jsonb := '{
    "finishing":       {"macro": "shooting",   "peso": 0.45},
    "short_passing":   {"macro": "passing",    "peso": 0.35},
    "standing_tackle": {"macro": "defending",  "peso": 0.30},
    "dribbling":       {"macro": "dribbling",  "peso": 0.40},
    "stamina":         {"macro": "physic",     "peso": 0.30}
  }'::jsonb;
  v_chiave text;
  v_macro text;
  v_peso_contributo numeric;
  v_totale numeric := 0;
begin
  for v_chiave in select jsonb_object_keys(p_deltas) loop
    v_macro := v_contributo -> v_chiave ->> 'macro';
    v_peso_contributo := (v_contributo -> v_chiave ->> 'peso')::numeric;
    if v_macro is not null then
      v_totale := v_totale
        + (p_deltas ->> v_chiave)::numeric * v_peso_contributo * coalesce((v_pesi_ruolo ->> v_macro)::numeric, 0);
    end if;
  end loop;
  return greatest(1, round(v_totale)::int);
end;
$$;
comment on function private.bonus_overall_specializzazione(text, jsonb) is
  'Quanto sale overall_corrente per una specializzazione completata: '
  'stima in due passaggi (sotto-attributo -> macro-categoria -> overall '
  'pesato per macro-ruolo), non la formula EA reale. Pavimento a 1 punto.';

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
  v_posizioni text[];
  v_deltas jsonb;
  v_chiave text;
  v_base_attributi jsonb;
  v_override jsonb;
  v_bonus_overall integer;
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
      v_posizioni := coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo);
      v_deltas := private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target -> 'deltas';
      v_base_attributi := v_riga.attributi_catalogo;
      v_override := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(coalesce(v_deltas, '{}'::jsonb)) loop
        v_override := v_override || jsonb_build_object(
          v_chiave, least(99, coalesce((v_base_attributi->>v_chiave)::int, 0) + (v_deltas->>v_chiave)::int)
        );
      end loop;

      -- Anti-abuso: il bonus overall scatta solo su un cambio VERO di
      -- specializzazione, mai riselezionando quella gia' attiva.
      v_bonus_overall := case
        when v_riga.specializzazione_precedente is distinct from v_riga.specializzazione_target
          then private.bonus_overall_specializzazione(private.macro_ruolo(v_posizioni), v_deltas)
        else 0
      end;

      update public.player_instances
      set attributi_override = v_override,
          specializzazione_attiva = v_riga.specializzazione_target,
          overall_corrente = least(99, overall_corrente + v_bonus_overall)
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        'Un giocatore ha completato l''allenamento: ora è specializzato come ' || v_riga.specializzazione_target
          || case when v_bonus_overall > 0 then format(' (overall +%s)', v_bonus_overall) else '' end || '.',
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
