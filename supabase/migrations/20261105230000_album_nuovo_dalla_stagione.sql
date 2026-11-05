-- Le figurine nuove (rarita', card FUT, foto) partono con l'album della stagione successiva al lancio, non con
-- quello in corso (richiesta del committente, 5/11/2026). leagues.album_nuovo_dalla_stagione: Serie F 3, LegaBot 6,
-- leghe nuove 1. Negli album precedenti la bustina torna all'estrazione di prima e le rare/ultimate gia' uscite
-- oggi diventano le versioni di prima: rara -> normale, ultimate giocatore o conference -> ultrarara,
-- ultimate stemma -> normale (prima gli stemmi esistevano solo normali).

alter table public.leagues add column if not exists album_nuovo_dalla_stagione smallint not null default 1;
update public.leagues set album_nuovo_dalla_stagione = 3 where id = 63;
update public.leagues set album_nuovo_dalla_stagione = 6 where id = 62;

update public.album_possesso ap set
  normali = ap.normali + ap.rare + case when f.tipo = 'stemma' then ap.ultimate else 0 end,
  ultra = ap.ultra + case when f.tipo = 'stemma' then 0 else ap.ultimate end,
  rare = 0, ultimate = 0
from public.album_figurine f join public.leagues l on l.id = f.league_id
where f.id = ap.figurina_id and f.stagione < l.album_nuovo_dalla_stagione and (ap.rare > 0 or ap.ultimate > 0);

CREATE OR REPLACE FUNCTION private.album_sincronizza(p_league_id bigint)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_stag smallint;
  v_prima boolean;
  v_conf boolean;
begin
  select stagione_corrente, coalesce(conferenze_attive, false) into v_stag, v_conf from public.leagues where id = p_league_id;
  v_prima := not exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag);
  insert into public.album_figurine (league_id, stagione, tipo, team_id)
  select p_league_id, v_stag, 'stemma', t.id from public.teams t where t.league_id = p_league_id and t.attiva
  on conflict do nothing;
  insert into public.album_figurine (league_id, stagione, tipo, team_id, player_id, overall, aggiornamento, statistiche, posizioni)
  select p_league_id, v_stag, 'giocatore', pi.team_id, pi.player_id, pi.overall_corrente, not v_prima,
    private.album_statistiche(private.attributi_istanza(
      p.attributi, coalesce(pi.posizioni_override, p.posizioni), pi.overall_corrente, p.overall,
      pi.piano_scostamenti, pi.specializzazione_attiva, pi.piano_overall_rif)),
    coalesce(pi.posizioni_override, p.posizioni)
  from public.player_instances pi join public.teams t on t.id = pi.team_id and t.attiva
  join public.players p on p.id = pi.player_id
  where pi.league_id = p_league_id and not pi.ritirato
    -- Solo chi non ha ancora la figurina: le statistiche costano, e senza questo filtro ogni bustina le
    -- ricalcolava per tutta la lega (7,5 s a bustina in Serie F) per poi scartarle col conflitto.
    and not exists (select 1 from public.album_figurine af where af.league_id = p_league_id and af.stagione = v_stag
                    and af.tipo = 'giocatore' and af.team_id = pi.team_id and af.player_id = pi.player_id)
  on conflict do nothing;
  if v_conf then
    insert into public.album_figurine (league_id, stagione, tipo, conferenza)
    values (p_league_id, v_stag, 'conferenza', 'est'), (p_league_id, v_stag, 'conferenza', 'ovest')
    on conflict do nothing;
  end if;
  return v_stag;
end $function$;

CREATE OR REPLACE FUNCTION public.album_compra_bustina(p_league_id bigint, p_gratis boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_saldo public.casino_saldi;
  v_stag smallint;
  v_k int;
  v_r numeric;
  v_ver text;
  v_min smallint;
  v_fig public.album_figurine;
  v_nuova boolean;
  v_out jsonb := '[]'::jsonb;
  v_classica boolean;
  c_prezzo constant int := 250;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  if not private.album_attivo(p_league_id) then
    raise exception using errcode = '55000', message = 'L''album non è attivo in questa lega.';
  end if;
  v_saldo := private.casino_saldo(p_league_id, v_utente);
  -- Bustina gratis (vinta al casino'): non costa crediti.
  if p_gratis then
    if v_saldo.bustine_gratis < 1 then raise exception using errcode = '22023', message = 'Non hai bustine gratis.'; end if;
  elsif v_saldo.crediti < c_prezzo then raise exception using errcode = '22023', message = 'Crediti insufficienti: una bustina costa 250 crediti.'; end if;
  v_stag := private.album_sincronizza(p_league_id);
  v_classica := v_stag < (select album_nuovo_dalla_stagione from public.leagues where id = p_league_id);
  update public.casino_saldi set
    crediti = crediti - (case when p_gratis then 0 else c_prezzo end),
    bustine_gratis = bustine_gratis - (case when p_gratis then 1 else 0 end), aggiornato_il = now()
  where league_id = p_league_id and user_id = v_utente;

  for v_k in 1..3 loop
    v_fig := null;
    if v_classica then
      -- Album di una stagione cominciata prima delle rarita': estrazione di prima (bustina_250), 2% ultrarara,
      -- 10% stemma normale, il resto giocatore normale; le conference solo ultrarare.
      v_r := random();
      v_ver := case when v_r < 0.02 then 'ultra' else 'common' end;
      if v_r >= 0.02 and v_r < 0.12 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
      elsif v_r < 0.02 and exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
      end if;
    elsif random() < 0.05 then
      -- Stemma o conference, sempre ultimate. Le conference (dove esistono) sono un decimo di questo 5%.
      v_ver := 'ultimate';
      if exists (select 1 from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza') and random() < 0.10 then
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'conferenza' order by random() limit 1;
      else
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'stemma' order by random() limit 1;
      end if;
    end if;
    if v_fig.id is null and not v_classica then
      -- Giocatore: prima la rarita', poi il giocatore fra quelli che hanno quella versione (overall minimo).
      v_r := random();
      v_ver := case when v_r < 0.75 then 'common' when v_r < 0.93 then 'rare' when v_r < 0.99 then 'ultra' else 'ultimate' end;
      loop
        v_min := case v_ver when 'ultimate' then 83 when 'ultra' then 78 when 'rare' then 70 else 0 end;
        -- I piu' forti escono piu' di rado: peso = 100 - overall (minimo 5). Estrazione pesata con chiave esponenziale.
        select * into v_fig from public.album_figurine where league_id = p_league_id and stagione = v_stag and tipo = 'giocatore'
          and coalesce(overall, 0) >= v_min
        order by -ln(random()) / greatest(5, 100 - coalesce(overall, 70)) limit 1;
        exit when v_fig.id is not null or v_ver = 'common';
        v_ver := case v_ver when 'ultimate' then 'ultra' when 'ultra' then 'rare' else 'common' end;
      end loop;
    end if;
    if v_fig.id is null then continue; end if;
    select not exists (select 1 from public.album_possesso where user_id = v_utente and figurina_id = v_fig.id
                        and private.album_n(normali, rare, ultra, ultimate, v_ver) > 0) into v_nuova;
    insert into public.album_possesso (league_id, user_id, figurina_id, normali, rare, ultra, ultimate)
    values (p_league_id, v_utente, v_fig.id, (v_ver = 'common')::int, (v_ver = 'rare')::int, (v_ver = 'ultra')::int, (v_ver = 'ultimate')::int)
    on conflict (user_id, figurina_id) do update set
      normali = public.album_possesso.normali + (v_ver = 'common')::int,
      rare = public.album_possesso.rare + (v_ver = 'rare')::int,
      ultra = public.album_possesso.ultra + (v_ver = 'ultra')::int,
      ultimate = public.album_possesso.ultimate + (v_ver = 'ultimate')::int;
    v_out := v_out || jsonb_build_object('figurina_id', v_fig.id, 'tipo', v_fig.tipo, 'team_id', v_fig.team_id, 'player_id', v_fig.player_id,
      'conferenza', v_fig.conferenza, 'versione', v_ver, 'ultra', v_ver in ('ultra', 'ultimate'), 'nuova', v_nuova);
  end loop;

  insert into public.album_bustine (league_id, user_id, contenuto) values (p_league_id, v_utente, v_out);
  return jsonb_build_object('figurine', v_out, 'premi', private.album_controlla_premi(p_league_id, v_utente, v_stag),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente),
    'bustine_gratis', (select bustine_gratis from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;
