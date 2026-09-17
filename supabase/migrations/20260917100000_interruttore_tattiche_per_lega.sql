-- ============================================================
--  UN INTERRUTTORE PER LEGA
--
--  Tutto il lavoro tattico (morale in campo, ruoli, compiti, schemi
--  personalizzati, capitano) e' stato scritto per essere inerte finche' nessuno
--  lo usa, e finora lo e' stato per costruzione: le colonne nascono NULL.
--
--  Da qui in poi non basta piu'. Il morale in particolare si applica a
--  CHIUNQUE, perche' ogni giocatore ne ha uno: appena l'Edge Function viene
--  distribuita, tutte le leghe lo sentirebbero. Vale poco di proposito (3,8
--  punti su 38, vedi il registro), ma "poco" non e' "niente" e non e' una
--  decisione da prendere con un deploy.
--
--  Serve quindi un interruttore esplicito, per lega, spento di default. Cosi'
--  si accende prima su LegaBot e si guarda cosa succede per qualche giornata,
--  senza toccare Serie F.
--
--  NON e' un flag "per sviluppatori" da togliere poi: resta. Una lega gia'
--  avviata puo' legittimamente non volere le tattiche a meta' stagione, e
--  l'amministratore deve poterlo decidere.
-- ============================================================

alter table public.leagues
  add column if not exists tattiche_attive boolean not null default false;

comment on column public.leagues.tattiche_attive is
  'Interruttore del sistema tattico: morale in campo, ruoli, compiti e schemi personalizzati. Spento di default. Le colonne restano scrivibili anche a interruttore spento — semplicemente il motore non le guarda.';

-- ------------------------------------------------------------
--  Accenderlo e spegnerlo
--
--  Solo l'amministratore della lega. Non e' una scelta di squadra: cambia le
--  regole per tutti, quindi non puo' deciderla un partecipante.
-- ------------------------------------------------------------
create or replace function public.imposta_tattiche_attive(p_league_id bigint, p_attive boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_lega public.leagues;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere.';
  end if;
  select * into v_lega from public.leagues where id = p_league_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Lega non trovata.';
  end if;
  if v_lega.admin_id <> v_user_id then
    raise exception using errcode = '42501', message = 'Solo l''amministratore della lega puo'' cambiare questa impostazione.';
  end if;

  update public.leagues set tattiche_attive = coalesce(p_attive, false) where id = p_league_id;
  return jsonb_build_object('league_id', p_league_id, 'tattiche_attive', coalesce(p_attive, false));
end;
$$;

revoke all on function public.imposta_tattiche_attive(bigint, boolean) from public, anon;
grant execute on function public.imposta_tattiche_attive(bigint, boolean) to authenticated;
