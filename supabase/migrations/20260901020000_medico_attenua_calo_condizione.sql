-- ============================================================
--  REPARTO MEDICO: EFFETTO VERO SUL RECUPERO POST-PARTITA
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Collega l'effetto descritto in 20260901010000: attenua quanto della
--  condizione persa in una giornata NON viene riassorbito dal recupero
--  post-partita gia' presente nel motore (REC_GIOCATO/PANCHINA/TRIBUNA
--  in engine/config.js). Il motore stesso resta invariato: qui si
--  interviene DOPO che ha gia' calcolato il suo valore, esattamente
--  nel punto in cui quel valore diventa definitivo sul database.
--
--  aggiorna_condizione_rosa e' il punto giusto: riceve da
--  simula-giornata il valore "grezzo" del motore (post recupero
--  built-in) e lo scrive su player_instances. La riga di
--  player_instances PRIMA di questo update e' esattamente "prima":
--  l'edge function l'ha letta a inizio richiesta e non l'ha piu'
--  toccata nel frattempo, quindi non serve passarla come parametro.
--
--  Formula, solo quando c'e' davvero un calo (grezzo < prima):
--    finale = prima - (prima - grezzo) * (1 - riduzione_medico% / 100)
--  Altrimenti (nessun calo: giocatore uscito, in panchina/tribuna, o
--  appena rientrato da un infortunio con condizione forzata a 65) il
--  valore resta quello del motore: il reparto medico attenua le
--  perdite, non gonfia i recuperi che gia' avvengono da soli.
--
--  Non serve validazione con tools/validazione/simulate.js: l'engine
--  non cambia, cambia solo il valore scritto dopo che l'engine ha gia'
--  calcolato il suo (stessa nota di 20260901010000).
-- ============================================================

create or replace function public.aggiorna_condizione_rosa(p_league_id bigint, p_valori jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aggiornati integer;
begin
  if jsonb_typeof(p_valori) <> 'array' then
    raise exception using errcode = '22023', message = 'Payload condizione non valido.';
  end if;

  with valori as (
    select *
    from jsonb_to_recordset(p_valori) as x(
      id                 bigint,
      condizione         smallint,
      infortunato_fino_a smallint
    )
  ), riduzioni as (
    select
      v.id,
      v.condizione as grezza,
      v.infortunato_fino_a,
      pi.condizione as prima,
      coalesce((
        select (private.effetti_ramo('medico', tr.livello_medico)->>'riduzione_calo_residuo_pct')::numeric
        from public.team_risorse tr
        where tr.team_id = pi.team_id
      ), 0) as riduzione_pct
    from valori v
    join public.player_instances pi on pi.id = v.id and pi.league_id = p_league_id
  )
  update public.player_instances pi
  set condizione = least(100, greatest(0, round(
        case when r.grezza < r.prima
          then r.prima - (r.prima - r.grezza) * (1 - r.riduzione_pct / 100.0)
          else r.grezza
        end
      )::int)),
      infortunato_fino_a = greatest(0, r.infortunato_fino_a)
  from riduzioni r
  where pi.id = r.id;

  get diagnostics v_aggiornati = row_count;
  return v_aggiornati;
end;
$$;
