-- ============================================================
--  RPC PUBBLICA: CAPIENZA DELLA PROPRIA SQUADRA
--
--  budget_disponibile mostra ancora cassa (teams.budget), che passo 5 ha
--  reso irrilevante per gli scambi: non c'e' piu' conguaglio da coprire.
--  La pagina Scambi ha bisogno del numero che conta davvero sotto il
--  tetto salariale, e private.capienza_residua non e' raggiungibile dal
--  browser (revocata a authenticated). Wrapper minimo, stesso pattern di
--  budget_disponibile: legge la squadra dell'utente in questa lega.
-- ============================================================

create or replace function public.capienza_squadra(p_league_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_stagione smallint;
  v_monte bigint;
  v_tetto bigint;
  v_rosa integer;
begin
  select * into v_team from public.teams
  where league_id = p_league_id and user_id = (select auth.uid());
  if not found then
    raise exception using errcode = '42501', message = 'Non partecipi a questa lega.';
  end if;

  select tetto_ingaggi into v_tetto from public.leagues where id = p_league_id;
  v_stagione := private.stagione_contratto(p_league_id);
  v_monte := private.monte_ingaggi(v_team.id, v_stagione);
  select count(*) into v_rosa from public.player_instances where team_id = v_team.id;

  return jsonb_build_object(
    'stagione', v_stagione,
    'tetto', v_tetto,
    'monte', v_monte,
    'capienza', v_tetto - v_monte - private.ingaggi_impegnati_aste(v_team.id, null),
    'rosa', v_rosa,
    'slot_liberi', private.rosa_massima() - v_rosa
  );
end;
$$;

comment on function public.capienza_squadra(bigint) is
  'Tetto, monte ingaggi e capienza residua della propria squadra per la stagione corrente (o entrante, in off-season). Sostituisce budget_disponibile per le schermate dove il denaro non e'' piu'' la grandezza rilevante.';

revoke all on function public.capienza_squadra(bigint) from public, anon;
grant execute on function public.capienza_squadra(bigint) to authenticated;
