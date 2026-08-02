-- ============================================================
--  RIMOZIONE DEL MINIMO PORTIERI
--
--  Il vincolo utile resta la dimensione rosa 21-30. Il minimo portieri
--  era un'impostazione di lega, ma in off-season/mercato crea blocchi non
--  necessari: un allenatore puo' scegliere di restare senza portieri, con
--  le normali conseguenze tecniche nella formazione.
--
--  Manteniamo la colonna per compatibilita' con RPC e codice esistente:
--  portieri_minimi = 0 significa nessun vincolo.
-- ============================================================

alter table public.leagues
  drop constraint if exists leagues_portieri_minimi_check;

alter table public.leagues
  alter column portieri_minimi set default 0;

update public.leagues
set portieri_minimi = 0
where portieri_minimi <> 0;

alter table public.leagues
  add constraint leagues_portieri_minimi_check
  check (portieri_minimi = 0);

comment on column public.leagues.portieri_minimi is
  'Parametro storico non piu'' usato come vincolo di gioco. Deve restare a 0: la rosa e'' valida fra 21 e 30 giocatori senza minimo portieri.';

create or replace function public.crea_lega(
  p_nome_lega text,
  p_nome_squadra text,
  p_stemma_url text,
  p_n_squadre smallint,
  p_n_gironi smallint,
  p_budget_iniziale bigint,
  p_reroll_draft smallint,
  p_slot_rosa smallint,
  p_portieri_minimi smallint,
  p_campionati_attivi text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_league public.leagues;
  v_team public.teams;
  v_codice text;
  v_campionati_validi constant text[] := array[
    'Premier League', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1',
    'Eredivisie', 'Liga Portugal', 'Süper Lig', 'Saudi Pro League',
    'EFL Championship'
  ];
  v_tentativi smallint := 0;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di creare una lega.';
  end if;

  p_nome_lega := trim(p_nome_lega);
  p_nome_squadra := trim(p_nome_squadra);
  p_portieri_minimi := 0;

  if length(p_nome_lega) not between 3 and 60 then
    raise exception using errcode = '22023', message = 'Il nome della lega deve avere da 3 a 60 caratteri.';
  end if;
  if length(p_nome_squadra) not between 2 and 40 then
    raise exception using errcode = '22023', message = 'Il nome della squadra deve avere da 2 a 40 caratteri.';
  end if;
  if p_n_squadre not between 4 and 20
    or p_n_gironi not between 2 and 6
    or p_budget_iniziale not between 50000000 and 200000000
    or p_reroll_draft not between 0 and 30
    or p_slot_rosa not between private.rosa_minima() and private.rosa_massima() then
    raise exception using errcode = '22023', message = 'Una o più impostazioni della lega non sono valide.';
  end if;
  if coalesce(cardinality(p_campionati_attivi), 0) = 0
    or not (p_campionati_attivi <@ v_campionati_validi)
    or cardinality(p_campionati_attivi) <> cardinality(array(select distinct unnest(p_campionati_attivi))) then
    raise exception using errcode = '22023', message = 'Seleziona almeno un campionato valido, senza duplicati.';
  end if;
  if not private.stemma_valido(p_stemma_url, v_user_id) then
    raise exception using errcode = '22023', message = 'Lo stemma selezionato non è valido.';
  end if;

  loop
    v_tentativi := v_tentativi + 1;
    v_codice := private.genera_codice_invito();
    begin
      insert into public.leagues (
        nome, admin_id, codice_invito, n_squadre, n_gironi,
        budget_iniziale, reroll_draft, slot_rosa, portieri_minimi,
        campionati_attivi
      ) values (
        p_nome_lega, v_user_id, v_codice, p_n_squadre, p_n_gironi,
        p_budget_iniziale, p_reroll_draft, p_slot_rosa, p_portieri_minimi,
        p_campionati_attivi
      ) returning * into v_league;
      exit;
    exception when unique_violation then
      if v_tentativi >= 10 then
        raise exception 'Impossibile generare un codice invito univoco.';
      end if;
    end;
  end loop;

  insert into public.teams (
    league_id, user_id, nome, stemma_url, budget, reroll_rimasti
  ) values (
    v_league.id, v_user_id, p_nome_squadra, p_stemma_url,
    v_league.budget_iniziale, v_league.reroll_draft
  ) returning * into v_team;

  insert into public.transactions (
    league_id, team_id, tipo, importo, descrizione, saldo_dopo
  ) values (
    v_league.id, v_team.id, 'dotazione_iniziale', v_league.budget_iniziale,
    'Dotazione iniziale della lega', v_league.budget_iniziale
  );

  return jsonb_build_object(
    'league_id', v_league.id,
    'team_id', v_team.id,
    'codice_invito', v_league.codice_invito
  );
end;
$$;

revoke all on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) from public, anon, authenticated;
grant execute on function public.crea_lega(text, text, text, smallint, smallint, bigint, smallint, smallint, smallint, text[]) to authenticated;
