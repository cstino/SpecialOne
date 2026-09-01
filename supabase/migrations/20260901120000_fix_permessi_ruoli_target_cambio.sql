-- ============================================================
--  FIX: ruoli_target_cambio falliva con "permission denied for
--  function macro_ruolo".
--
--  La funzione pubblica non era security definer, quindi girava con i
--  permessi dell'utente autenticato invece che del proprietario: non
--  puo' chiamare private.macro_ruolo (ne' private.ruoli_target_cambio,
--  private.ruoli_validi), che non hanno l'EXECUTE concesso al ruolo
--  authenticated — per disegno, gli helper in private si chiamano solo
--  passando da un wrapper public security definer, mai direttamente.
-- ============================================================

begin;

create or replace function public.ruoli_target_cambio(p_instance_id bigint)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select private.ruoli_target_cambio(coalesce(pi.posizioni_override, p.posizioni))
  from public.player_instances pi
  join public.players p on p.id = pi.player_id
  where pi.id = p_instance_id;
$$;

grant execute on function public.ruoli_target_cambio(bigint) to authenticated;

commit;
