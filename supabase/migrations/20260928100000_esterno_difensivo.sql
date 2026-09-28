-- ============================================================
--  "Esterno di rientro" diventa "Esterno difensivo"
--
--  Richiesta del committente (28 settembre 2026, registro tattico punto 27):
--  il nome non gli piaceva. Cambia anche la chiave, cosi' codice e schermo
--  dicono la stessa cosa. Nessuna formazione salvata usa ruoli (verificato
--  in produzione lo stesso giorno: zero righe di lineups con ruoli non nulli),
--  quindi non c'e' niente da convertire.
--
--  Copia di RUOLI in engine/ruoli.js: se cambia la', va rigenerata qui.
-- ============================================================

create or replace function private.ruoli_slot(p_slot text)
returns text[] language sql immutable parallel safe set search_path = ''
as $$
  select case p_slot
    when 'GK' then array[]::text[]
    when 'CB' then array['centrale','centrale_marcatore','centrale_impostatore']::text[]
    when 'LB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'RB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'LWB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'RWB' then array['terzino','terzino_offensivo','terzino_interno','terzino_bloccato']::text[]
    when 'CDM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'CM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'CAM' then array['mediano','regista','mezzala','incursore','schermo']::text[]
    when 'LM' then array['esterno','ala_pura','esterno_a_rientrare','esterno_difensivo']::text[]
    when 'RM' then array['esterno','ala_pura','esterno_a_rientrare','esterno_difensivo']::text[]
    when 'LW' then array['esterno','ala_pura','esterno_a_rientrare','esterno_difensivo']::text[]
    when 'RW' then array['esterno','ala_pura','esterno_a_rientrare','esterno_difensivo']::text[]
    when 'ST' then array['punta','finalizzatore','punta_di_manovra']::text[]
    when 'CF' then array['punta','finalizzatore','punta_di_manovra']::text[]
    else '{}'::text[]
  end
$$;

revoke all on function private.ruoli_slot(text) from public, anon, authenticated;
grant execute on function private.ruoli_slot(text) to authenticated;
