-- ============================================================
--  L'ALLENAMENTO NON RENDE PIU' A TUTTI ALLO STESSO MODO.
--
--  Segnalato dall'utente il 2 settembre 2026 con l'esempio di D. Ballard
--  (27 anni, overall 74, potenziale 78: poco margine, età già avanzata):
--  un giocatore vicino al proprio potenziale, specie se non più giovane,
--  non dovrebbe ottenere lo stesso guadagno pieno di un ventenne con
--  ampio margine di crescita.
--
--  Riusa la STESSA logica (fasce d'età, margine dal potenziale) già in
--  uso per la crescita/declino trimestrale
--  (public.applica_progressione_trimestrale, 20260808120000): non e' un
--  criterio nuovo inventato per la specializzazione, e' lo stesso principio
--  che governa gia' come i giocatori maturano in questo gioco.
--
--  private.fattore_allenamento(eta, potenziale, overall) restituisce un
--  moltiplicatore 0-1:
--    - fattore eta': 1.0 fino a 22 anni, poi 0.75 / 0.35 / 0.15 / 0.0
--      (stesse soglie 22/26/31/35 della progressione trimestrale)
--    - fattore margine: 0 se overall >= potenziale (nessun margine), sale
--      linearmente fino a 1.0 con un margine di 10+ punti
--  Il prodotto dei due scala TUTTI i delta della specializzazione (le tre
--  stat e, di conseguenza, il bonus overall che ne deriva) prima di
--  applicarli. Un giocatore giovane e con ampio margine ottiene il pieno
--  effetto di prima; uno come Ballard ottiene un guadagno molto ridotto,
--  a volte pari a zero: l'allenamento resta legittimo da avviare (e le
--  giornate/il costo Training restano gli stessi), ma non e' più un
--  beneficio garantito.
-- ============================================================

begin;

create or replace function private.fattore_allenamento(p_eta smallint, p_potenziale smallint, p_overall smallint)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select (
    case
      when p_eta <= 22 then 1.0
      when p_eta <= 26 then 0.75
      when p_eta <= 31 then 0.35
      when p_eta <= 35 then 0.15
      else 0.0
    end
  ) * least(1.0, greatest(0, p_potenziale - p_overall) / 10.0)
$$;
comment on function private.fattore_allenamento(smallint, smallint, smallint) is
  'Moltiplicatore 0-1 su quanto rende un allenamento di specializzazione: '
  'stesse fasce d''eta'' e stesso principio di margine dal potenziale gia'' '
  'usati da applica_progressione_trimestrale, non un criterio a se''.';

create or replace function private.completa_specializzazioni()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lega record;
  v_prossima integer;
  v_riga record;
  v_posizioni text[];
  v_deltas_base jsonb;
  v_deltas_scalati jsonb;
  v_fattore numeric;
  v_chiave text;
  v_base_attributi jsonb;
  v_override jsonb;
  v_bonus_overall integer;
  v_completati integer := 0;
begin
  for v_lega in select id, giornate_totali from public.leagues where stato = 'stagione' loop
    select coalesce(min(f.giornata), v_lega.giornate_totali + 1) into v_prossima
    from public.fixtures f where f.league_id = v_lega.id and f.stato = 'programmata';

    for v_riga in
      select s.*, pi.posizioni_override, pi.eta_corrente, pi.overall_corrente,
        p.posizioni as posizioni_catalogo, p.attributi as attributi_catalogo, p.potential
      from public.specializzazioni_giocatore s
      join public.player_instances pi on pi.id = s.player_instance_id
      join public.players p on p.id = pi.player_id
      where s.league_id = v_lega.id and s.completato_il is null and s.completa_giornata <= v_prossima
      order by s.id
      for update of s
    loop
      v_posizioni := coalesce(v_riga.posizioni_override, v_riga.posizioni_catalogo);
      v_deltas_base := private.specializzazioni_ruolo(v_posizioni[1]) -> v_riga.specializzazione_target -> 'deltas';
      v_fattore := private.fattore_allenamento(v_riga.eta_corrente, v_riga.potential, v_riga.overall_corrente);

      v_deltas_scalati := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(coalesce(v_deltas_base, '{}'::jsonb)) loop
        v_deltas_scalati := v_deltas_scalati || jsonb_build_object(
          v_chiave, round((v_deltas_base->>v_chiave)::numeric * v_fattore)::int
        );
      end loop;

      v_base_attributi := v_riga.attributi_catalogo;
      v_override := '{}'::jsonb;
      for v_chiave in select jsonb_object_keys(v_deltas_scalati) loop
        v_override := v_override || jsonb_build_object(
          v_chiave, least(99, coalesce((v_base_attributi->>v_chiave)::int, 0) + (v_deltas_scalati->>v_chiave)::int)
        );
      end loop;

      -- Anti-abuso invariato: il bonus overall scatta solo su un cambio
      -- VERO di specializzazione. Niente pavimento a 1 punto ora: se il
      -- fattore e' quasi zero (poco margine, eta' avanzata), zero e'
      -- l'esito corretto, non un difetto da correggere.
      v_bonus_overall := case
        when v_riga.specializzazione_precedente is distinct from v_riga.specializzazione_target
          then private.bonus_overall_specializzazione(private.macro_ruolo(v_posizioni), v_deltas_scalati)
        else 0
      end;

      update public.player_instances
      set attributi_override = v_override,
          specializzazione_attiva = v_riga.specializzazione_target,
          overall_corrente = least(99, overall_corrente + v_bonus_overall)
      where id = v_riga.player_instance_id;

      update public.specializzazioni_giocatore set completato_il = now() where id = v_riga.id;

      perform private.notifica(
        t.user_id, v_lega.id, 'sistema', 'Allenamento completato',
        'Un giocatore ha completato l''allenamento: ora è specializzato come ' || v_riga.specializzazione_target
          || case when v_bonus_overall > 0 then format(' (overall +%s)', v_bonus_overall) else '' end || '.',
        jsonb_build_object('view', 'team', 'player_instance_id', v_riga.player_instance_id)
      )
      from public.teams t where t.id = v_riga.team_id;

      v_completati := v_completati + 1;
    end loop;
  end loop;
  return v_completati;
end;
$$;

-- private.bonus_overall_specializzazione non ha piu' bisogno del pavimento
-- a 1 punto: i delta in ingresso sono ora gia' scalati per eta'/margine, e
-- un esito a zero e' un risultato legittimo, non un caso da correggere.
create or replace function private.bonus_overall_specializzazione(p_macro_ruolo text, p_deltas jsonb)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_pesi_ruolo jsonb := case p_macro_ruolo
    when 'DEF' then '{"shooting":0.02,"passing":0.13,"dribbling":0.10,"defending":0.45,"physic":0.20,"pace":0.10}'::jsonb
    when 'ATT' then '{"shooting":0.35,"passing":0.10,"dribbling":0.22,"defending":0.02,"physic":0.13,"pace":0.18}'::jsonb
    else          '{"shooting":0.12,"passing":0.28,"dribbling":0.25,"defending":0.10,"physic":0.15,"pace":0.10}'::jsonb -- MID
  end;
  v_contributo constant jsonb := '{
    "finishing":       {"macro": "shooting",   "peso": 0.45},
    "short_passing":   {"macro": "passing",    "peso": 0.35},
    "standing_tackle": {"macro": "defending",  "peso": 0.30},
    "dribbling":       {"macro": "dribbling",  "peso": 0.40},
    "stamina":         {"macro": "physic",     "peso": 0.30}
  }'::jsonb;
  v_chiave text;
  v_macro text;
  v_peso_contributo numeric;
  v_totale numeric := 0;
begin
  for v_chiave in select jsonb_object_keys(p_deltas) loop
    v_macro := v_contributo -> v_chiave ->> 'macro';
    v_peso_contributo := (v_contributo -> v_chiave ->> 'peso')::numeric;
    if v_macro is not null then
      v_totale := v_totale
        + (p_deltas ->> v_chiave)::numeric * v_peso_contributo * coalesce((v_pesi_ruolo ->> v_macro)::numeric, 0);
    end if;
  end loop;
  return round(v_totale)::int;
end;
$$;

commit;
