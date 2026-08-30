begin;

-- ============================================================
--  popola_pool_svincolati: se richiamata su una lega gia' oltre la
--  stagione 1 (non capita mai a crea_lega, ma e' esattamente cosa
--  successe nel backfill una tantum del 30 agosto 2026 su LegaBot, gia'
--  alla stagione 2), l'eta' andrebbe seminata coerente con quante
--  stagioni sono gia' passate — altrimenti diverge dal ritiro, che
--  ormai legge l'eta' vera da questa tabella invece di ricalcolarla
--  (v. 20260830130000_finalizza_offseason_pool_evoluto.sql). L'overall
--  resta il valore di importazione: non c'e' un modo onesto di
--  ricostruire retroattivamente quante stagioni di progressione
--  avrebbe maturato, solo l'eta' e' deterministica (un anno a stagione).
-- ============================================================

create or replace function private.popola_pool_svincolati(p_league_id bigint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega public.leagues;
  v_creati integer;
begin
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;

  insert into public.free_agent_progression (league_id, player_id, overall_corrente, eta_corrente)
  select p_league_id, p.id, p.overall,
         least(45, p.eta + greatest(0, v_lega.stagione_corrente - 1))::smallint
  from public.players p
  where (p.elite_globale or p.campionato = any(v_lega.campionati_attivi))
    and not exists (
      select 1 from public.player_instances pi
      where pi.league_id = p_league_id and pi.player_id = p.id
    )
  on conflict (league_id, player_id) do nothing;

  get diagnostics v_creati = row_count;
  return v_creati;
end;
$$;

commit;
