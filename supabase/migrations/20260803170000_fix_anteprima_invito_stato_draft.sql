-- ============================================================
--  FIX: anteprima_invito bloccava l'ingresso su una lega gia' in draft
--
--  `20260803160000_draft_indipendente_dall_ingresso.sql` ha allargato il
--  cancello di `entra_in_lega` per accettare anche `stato = 'draft'`, oltre
--  a 'setup', dato che ora una lega parte in draft dal momento in cui
--  l'admin la crea. Mancava `anteprima_invito`: e' un controllo separato,
--  non condiviso, chiamato PRIMA di entra_in_lega — appena l'utente preme
--  "Continua" sul codice, prima ancora di scegliere nome e stemma squadra.
--  Aveva lo stesso identico check ma non era stato toccato, quindi ogni
--  amico che provava a entrare in una lega gia' in draft veniva respinto
--  al primissimo passo con "Questa lega non accetta nuovi partecipanti",
--  senza mai arrivare a entra_in_lega.
-- ============================================================

create or replace function public.anteprima_invito(p_codice text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_partecipanti integer;
  v_stemmi text[];
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di entrare in una lega.';
  end if;

  p_codice := upper(trim(p_codice));
  if p_codice !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception using errcode = '22023', message = 'Il codice invito deve contenere 6 caratteri.';
  end if;

  select * into v_league
  from public.leagues
  where codice_invito = p_codice;

  if not found then
    raise exception using errcode = 'P0002', message = 'Codice invito non trovato.';
  end if;
  -- Stesso cancello di entra_in_lega: 'setup' (leghe pre-esistenti), 'draft'
  -- (il caso normale ora), o off-season a stagione avviata.
  if not (v_league.stato in ('setup', 'draft') or (v_league.stato = 'stagione' and v_league.fase_carriera = 'offseason')) then
    raise exception using errcode = '55000', message = 'Questa lega non accetta nuovi partecipanti.';
  end if;
  if exists (
    select 1 from public.teams
    where league_id = v_league.id and user_id = v_user_id
  ) then
    raise exception using errcode = '23505', message = 'Hai gia'' una squadra in questa lega.';
  end if;

  select count(*)::integer, coalesce(array_agg(stemma_url order by id), array[]::text[])
  into v_partecipanti, v_stemmi
  from public.teams
  where league_id = v_league.id and attiva;

  if v_partecipanti >= v_league.n_squadre then
    raise exception using errcode = '54000', message = 'La lega ha gia'' raggiunto il numero massimo di squadre.';
  end if;

  return jsonb_build_object(
    'league_id', v_league.id,
    'nome_lega', v_league.nome,
    'fase_carriera', v_league.fase_carriera,
    'posti_disponibili', v_league.n_squadre - v_partecipanti,
    'stemmi_usati', v_stemmi
  );
end;
$$;

revoke all on function public.anteprima_invito(text) from public, anon, authenticated;
grant execute on function public.anteprima_invito(text) to authenticated;
