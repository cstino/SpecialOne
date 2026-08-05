-- ============================================================
--  ECONOMIA: mod_eta invertito, premio ai giovani (design §5.1)
--
--  Decisione dell'utente, 5 agosto 2026: la scala precedente (16-20 a 0,35,
--  picco 1,00 a 27-30) rendeva un giovane gia' forte un affare enorme
--  rispetto a un adulto di pari overall attuale — e la progressione verso
--  il potenziale (design §6.2/§10.2, attiva a checkpoint trimestrali) lo
--  fa anche crescere GRATIS per anni sotto lo stesso contratto scontato.
--  Non e' un difetto del motore (non e' engine/, e' economia pura), ma un
--  eccesso della formula: un doppio vantaggio invece di uno solo.
--
--  Filosofia ribaltata: chi e' giovane E gia' forte oggi costa PIU' del
--  prime, non meno — paga il potenziale, non solo l'overall attuale. Il
--  picco si sposta da 27-30 a 24-26 (esperienza consolidata, prima del
--  premio-potenziale e prima del calo). Gli over 30 restano scontati verso
--  fine carriera, coerente col resto del gioco (rinnovi §10.4, ritiro §10.3).
--
--  Solo il case della fascia d'eta' cambia: base(overall), floor 0,5M,
--  arrotondamento a 0,1M restano identici. Stessa firma, nessun chiamante
--  da toccare (private.ingaggio_teorico e' definita una sola volta in
--  20260731133110_draft_rpc.sql e richiamata ovunque per nome).
-- ============================================================

create or replace function private.ingaggio_teorico(
  p_overall smallint,
  p_eta smallint
)
returns bigint
language sql
immutable
parallel safe
set search_path = ''
as $$
  select greatest(
    500000::numeric,
    round((
      case
        when p_overall <= 65 then 0.5
        when p_overall <= 70 then 0.8
        when p_overall <= 74 then 1.2
        when p_overall <= 77 then 2.0
        when p_overall <= 80 then 3.2
        when p_overall <= 83 then 5.0
        when p_overall <= 85 then 7.5
        when p_overall <= 87 then 10.0
        when p_overall <= 89 then 13.0
        else 17.0
      end
      * case
        when p_eta between 16 and 20 then 1.25
        when p_eta between 21 and 23 then 1.10
        when p_eta between 24 and 26 then 1.00
        when p_eta between 27 and 30 then 0.95
        when p_eta between 31 and 32 then 0.80
        when p_eta between 33 and 34 then 0.60
        else 0.40
      end
      * 10
    )) * 100000
  )::bigint;
$$;
