-- ============================================================
--  L'ANTEPRIMA DELLA SPECIALIZZAZIONE MOSTRAVA I DELTA GREZZI DEL
--  CATALOGO (+8/+5/+3), NON QUELLI VERI SCALATI SU ETA'/POTENZIALE.
--
--  Segnalato dall'utente il 2 settembre 2026 con uno screenshot: il
--  confronto "prima -> dopo" nel picker (SchedaGiocatore.tsx) calcola
--  dopo = prima + delta usando i delta che arrivano da
--  specializzazioni_disponibili(), che finora restituiva sempre il
--  catalogo statico — non quanto avrebbe reso DAVVERO per quel giocatore
--  specifico dopo private.fattore_allenamento (20260902070000).
--
--  Fix: specializzazioni_disponibili ora scala i delta con lo stesso
--  fattore che completa_specializzazioni() applichera' davvero al
--  completamento (calcolato sui valori CORRENTI di eta'/overall/
--  potenziale, come tutto il resto in questo sistema — mai una copia
--  congelata). Il client non cambia: gia' fa prima+delta per disegnare
--  la barra, quindi ora mostra da solo il numero vero, incluso lo zero
--  quando l'allenamento non rende nulla.
-- ============================================================

begin;

create or replace function public.specializzazioni_disponibili(p_instance_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_posizioni text[];
  v_eta smallint;
  v_overall smallint;
  v_potenziale smallint;
  v_fattore numeric;
  v_catalogo jsonb;
  v_risultato jsonb := '{}'::jsonb;
  v_chiave text;
  v_sub_chiave text;
  v_deltas_base jsonb;
  v_deltas_scalati jsonb;
begin
  select coalesce(pi.posizioni_override, p.posizioni), pi.eta_corrente, pi.overall_corrente, p.potential
  into v_posizioni, v_eta, v_overall, v_potenziale
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;

  if v_posizioni is null then
    return '{}'::jsonb;
  end if;

  v_catalogo := private.specializzazioni_ruolo(v_posizioni[1]);
  v_fattore := private.fattore_allenamento(v_eta, v_potenziale, v_overall);

  for v_chiave in select jsonb_object_keys(coalesce(v_catalogo, '{}'::jsonb)) loop
    v_deltas_base := v_catalogo -> v_chiave -> 'deltas';
    v_deltas_scalati := '{}'::jsonb;
    for v_sub_chiave in select jsonb_object_keys(v_deltas_base) loop
      v_deltas_scalati := v_deltas_scalati || jsonb_build_object(
        v_sub_chiave, round((v_deltas_base ->> v_sub_chiave)::numeric * v_fattore)::int
      );
    end loop;
    v_risultato := v_risultato || jsonb_build_object(
      v_chiave, jsonb_build_object('etichetta', v_catalogo -> v_chiave ->> 'etichetta', 'deltas', v_deltas_scalati)
    );
  end loop;

  return v_risultato;
end;
$$;

commit;
