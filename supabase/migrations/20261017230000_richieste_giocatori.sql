-- ============================================================
--  RICHIESTE DEI GIOCATORI (docs/decisioni-conferenze-stampa.md §2e)
--  Prova in LegaBot (interruttore leagues.conferenze_stampa). Deciso il 17 ottobre 2026.
--
--  Durante l'anno un giocatore scrive al mister con una richiesta personale. L'allenatore
--  risponde a testo libero e l'AI valuta l'effetto sul morale di QUEL giocatore (solo suo).
--  Tipi: titolare (schierami nella prossima partita), spazio (piu' minuti), riposo (sono stanco).
--  Se nella risposta c'e' una promessa esplicita, a fine partita si verifica sui dati:
--    mantenuta  +8 di morale al giocatore
--    tradita    -20, e il giocatore si sfoga su SocialOne (post pubblico)
--    decaduta   se era infortunato o squalificato: nessuna conseguenza
--  Una richiesta senza risposta scade senza effetti.
-- ============================================================

begin;

create table public.richieste_giocatori (
  id                 bigint generated always as identity primary key,
  league_id          bigint not null references public.leagues(id) on delete cascade,
  team_id            bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  tipo               text not null check (tipo in ('titolare', 'spazio', 'riposo')),
  testo              text not null check (char_length(testo) between 1 and 400),
  giornata_target    smallint not null,
  creata_il          timestamptz not null default now(),
  scade_il           timestamptz not null default private.scadenza_conferenza(now()),
  stato              text not null default 'aperta'
                     check (stato in ('aperta', 'risposta', 'promessa', 'mantenuta', 'tradita', 'decaduta', 'scaduta')),
  risposta           text check (risposta is null or char_length(risposta) between 1 and 1200),
  risposta_il        timestamptz,
  voto               numeric(2,1) check (voto is null or voto between -3 and 3),
  reazione           text,
  effetto_morale     numeric(4,1),
  esito_morale       numeric(4,1),
  valutazione        jsonb,
  unique (team_id, giornata_target)
);
create index richieste_giocatori_team_idx on public.richieste_giocatori (team_id, creata_il desc);
create index richieste_giocatori_giocatore_idx on public.richieste_giocatori (player_instance_id, creata_il desc);

alter table public.richieste_giocatori enable row level security;
create policy richieste_giocatori_lettura on public.richieste_giocatori
  for select to authenticated
  using (exists (select 1 from public.teams t where t.id = team_id and t.user_id = (select auth.uid())));

-- ------------------------------------------------------------
--  Generazione: una richiesta al massimo per squadra e giornata, da fatti veri
-- ------------------------------------------------------------
create or replace function private.genera_richieste_giocatori()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_t record;
  v_next smallint;
  v_riposo jsonb;
  v_titolare jsonb;
  v_spazio jsonb;
  v_scelte text[];
  v_tipo text;
  v_p jsonb;
  v_seed text;
  v_testo text;
  v_n integer := 0;
begin
  for v_t in
    select t.id as team_id, t.league_id, t.user_id
    from public.teams t
    join public.leagues l on l.id = t.league_id and l.conferenze_stampa and l.stato = 'stagione' and l.fase_carriera = 'normale'
    where t.attiva and t.user_id is not null and not t.controllata_da_pc
  loop
    select min(f.giornata) into v_next from public.fixtures f
    where f.league_id = v_t.league_id and f.stato = 'programmata' and v_t.team_id in (f.home_team_id, f.away_team_id);
    continue when v_next is null;
    continue when exists (select 1 from public.richieste_giocatori r where r.team_id = v_t.team_id and r.giornata_target = v_next);
    -- Solo dopo una simulazione recente (le richieste nascono a ridosso delle partite)...
    continue when not exists (select 1 from public.matches m where m.league_id = v_t.league_id and m.simulata_il > now() - interval '20 hours');
    -- ...e non ogni giornata: circa 6 su 10.
    continue when abs(hashtext(v_t.team_id || ':' || v_next)) % 100 >= 60;

    with rosa as (
      select pi.id, p.nome, pi.overall_corrente, pi.morale, pi.condizione, ms.partite,
             case when coalesce(ms.partite, 0) > 0 then ms.minuti / (90.0 * ms.partite) end as pct,
             pi.id = any(coalesce((select l2.titolari from public.lineups l2 where l2.team_id = v_t.team_id
                                   order by l2.giornata desc, l2.salvata_il desc limit 1), '{}'::bigint[])) as titolare,
             row_number() over (order by pi.overall_corrente desc) as pos
      from public.player_instances pi
      join public.players p on p.id = pi.player_id
      left join lateral private.minuti_stagione(pi.id) ms on true
      where pi.team_id = v_t.team_id and not pi.ritirato and pi.infortunato_fino_a <= 0 and pi.squalificato_fino_a <= 0
        and not exists (select 1 from public.richieste_giocatori r where r.player_instance_id = pi.id and r.creata_il > now() - interval '6 days')
    )
    select
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where r.titolare and r.condizione < 55 order by r.condizione limit 1),
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where not r.titolare and r.partite >= 3 and r.pct < 0.45 and r.morale < 80 and r.pos <= 16
        order by r.overall_corrente desc limit 1),
      (select jsonb_build_object('id', r.id, 'nome', r.nome) from rosa r where r.partite >= 3 and r.pct < 0.30 and r.morale < 65 order by r.pct, r.id limit 1)
    into v_riposo, v_titolare, v_spazio;

    v_scelte := array[]::text[];
    if v_riposo is not null then v_scelte := array_append(v_scelte, 'riposo'); end if;
    if v_titolare is not null then v_scelte := array_append(v_scelte, 'titolare'); end if;
    if v_spazio is not null then v_scelte := array_append(v_scelte, 'spazio'); end if;
    continue when array_length(v_scelte, 1) is null;
    v_tipo := v_scelte[1 + abs(hashtext('tipo' || v_t.team_id || ':' || v_next)) % array_length(v_scelte, 1)];
    v_p := case v_tipo when 'riposo' then v_riposo when 'titolare' then v_titolare else v_spazio end;
    v_seed := 'rg' || v_t.team_id || ':' || v_next;
    v_testo := case v_tipo
      when 'titolare' then private.social_scegli(v_seed, array[
        'Ehi mister, mi sono allenato bene ultimamente. Volevo dunque chiederle se nella prossima partita potesse schierarmi tra i titolari.',
        'Mister, sento di essere in forma e di meritare una chance dall''inizio. Mi farebbe giocare nella prossima partita da titolare?',
        'Buongiorno mister, in settimana ho dato tutto negli allenamenti. Le chiedo la possibilità di partire titolare alla prossima.',
        'Mister, so che la concorrenza è forte, ma mi sento pronto. Posso avere una maglia da titolare nella prossima partita?'])
      when 'spazio' then private.social_scegli(v_seed, array[
        'Mister, vorrei sentirmi più parte del progetto. Le chiedo di darmi più spazio nelle prossime partite.',
        'Ehi mister, gioco troppo poco e non è quello che mi aspettavo. Possiamo parlare di un maggiore impiego nelle prossime gare?',
        'Mister, so di poter dare di più alla squadra. Mi darebbe più minuti nelle prossime partite?',
        'Buongiorno mister, sento di avere più da offrire di quanto stia facendo vedere. Le chiedo più spazio nelle prossime partite.'])
      else private.social_scegli(v_seed, array[
        'Mister, sento le gambe pesanti dopo gli ultimi impegni. Se possibile, vorrei riposare nella prossima partita.',
        'Ehi mister, sono stanco e non vorrei rischiare l''infortunio. Mi lascerebbe a riposo la prossima?',
        'Mister, il fisico mi sta presentando il conto. Posso riposare nella prossima partita, così torno al meglio?',
        'Buongiorno mister, non sono al meglio della condizione. Le chiedo di farmi tirare il fiato nella prossima partita.'])
    end;

    insert into public.richieste_giocatori (league_id, team_id, player_instance_id, tipo, testo, giornata_target)
    values (v_t.league_id, v_t.team_id, (v_p->>'id')::bigint, v_tipo, v_testo, v_next)
    on conflict (team_id, giornata_target) do nothing;
    if found then
      perform private.notifica(v_t.user_id, v_t.league_id, 'sistema', 'Richiesta di ' || (v_p->>'nome'),
        'Mister, ' || (v_p->>'nome') || ' vuole parlarle. Apri la home per rispondere.', jsonb_build_object('richiesta', true));
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

-- ------------------------------------------------------------
--  L'effetto della risposta sul morale di quel giocatore (voto -3..+1,5, 1 punto = 3 di morale)
-- ------------------------------------------------------------
create or replace function public.applica_richiesta(p_id bigint, p_voto numeric, p_promessa boolean, p_reazione text, p_valutazione jsonb)
returns numeric
language plpgsql security definer set search_path = ''
as $$
declare
  v_r public.richieste_giocatori;
  v_morale smallint;
  v_voto numeric := greatest(-3, least(1.5, coalesce(p_voto, 0)));
  v_esatto numeric;
  v_nuovo smallint;
begin
  select * into v_r from public.richieste_giocatori where id = p_id;
  if not found then raise exception 'Richiesta % inesistente.', p_id; end if;
  select morale into v_morale from public.player_instances where id = v_r.player_instance_id for update;
  v_esatto := v_morale + v_voto * 3 * case when v_voto > 0 then greatest(0.35, least(1, (100 - v_morale) / 50.0))
                                           else greatest(0.35, least(1, v_morale / 50.0)) end;
  v_nuovo := greatest(0, least(100, floor(v_esatto) + case when random() < v_esatto - floor(v_esatto) then 1 else 0 end))::smallint;
  update public.player_instances set morale = v_nuovo where id = v_r.player_instance_id;
  update public.richieste_giocatori
     set stato = case when p_promessa then 'promessa' else 'risposta' end,
         voto = v_voto, reazione = left(p_reazione, 200), effetto_morale = v_nuovo - v_morale, valutazione = p_valutazione
   where id = p_id;
  return (v_nuovo - v_morale)::numeric;
end;
$$;
revoke all on function public.applica_richiesta(bigint, numeric, boolean, text, jsonb) from public, anon, authenticated;
grant execute on function public.applica_richiesta(bigint, numeric, boolean, text, jsonb) to service_role;

-- ------------------------------------------------------------
--  Scadenze e verifica delle promesse a fine partita
-- ------------------------------------------------------------
create or replace function private.verifica_richieste()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_r record;
  v_m record;
  v_in_campo boolean;
  v_minuti numeric;
  v_casa boolean;
  v_manca boolean;
  v_ok boolean;
  v_nome text;
  v_user uuid;
  v_n integer := 0;
begin
  update public.richieste_giocatori set stato = 'scaduta' where stato = 'aperta' and scade_il < now();

  for v_r in
    select r.* from public.richieste_giocatori r
    join public.leagues l on l.id = r.league_id and l.conferenze_stampa
    where r.stato = 'promessa'
  loop
    select m.id, m.titolari_home, m.titolari_away, f.home_team_id into v_m
    from public.matches m join public.fixtures f on f.id = m.fixture_id
    where f.league_id = v_r.league_id and f.giornata = v_r.giornata_target and v_r.team_id in (f.home_team_id, f.away_team_id)
      and f.season_id in (select s.id from public.seasons s join public.leagues l2 on l2.id = s.league_id and s.numero = l2.stagione_corrente where s.league_id = v_r.league_id)
    order by m.id desc limit 1;
    continue when v_m.id is null;

    v_casa := v_m.home_team_id = v_r.team_id;
    v_in_campo := v_r.player_instance_id = any(case when v_casa then v_m.titolari_home else v_m.titolari_away end);
    select coalesce(sum(ms.minuti), 0) into v_minuti from public.match_stats ms where ms.match_id = v_m.id and ms.player_instance_id = v_r.player_instance_id;
    select p.nome, t.user_id,
           (pi.infortunato_fino_a > 0 or pi.squalificato_fino_a > 0) and not v_in_campo and v_minuti = 0
      into v_nome, v_user, v_manca
    from public.player_instances pi join public.players p on p.id = pi.player_id join public.teams t on t.id = v_r.team_id
    where pi.id = v_r.player_instance_id;

    if v_manca then
      update public.richieste_giocatori set stato = 'decaduta', esito_morale = 0 where id = v_r.id;
      continue;
    end if;

    v_ok := case v_r.tipo when 'titolare' then v_in_campo when 'spazio' then v_minuti >= 30 else not v_in_campo end;
    update public.player_instances set morale = greatest(0, least(100, morale + case when v_ok then 8 else -20 end)) where id = v_r.player_instance_id;
    update public.richieste_giocatori set stato = case when v_ok then 'mantenuta' else 'tradita' end,
           esito_morale = case when v_ok then 8 else -20 end where id = v_r.id;

    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
    values (v_r.league_id, 'promessa:' || v_r.id, 'giocatore', v_nome, v_r.team_id, v_r.player_instance_id,
      case when v_ok then private.social_scegli('pm' || v_r.id, array[
             'Grazie mister per la fiducia: la parola data conta. Stasera ho dato tutto. 💪',
             'Il mister ha mantenuto la promessa e io ho cercato di ripagarlo in campo. Grazie.',
             'Quando un allenatore mantiene la parola, si vede. Grazie mister.'])
      else case v_r.tipo
        when 'titolare' then private.social_scegli('pt' || v_r.id, array[
             'Mi era stato promesso un posto da titolare. Parole al vento... 😒',
             'Promessa tradita: dovevo giocare dall''inizio e sono rimasto fuori. Mi sento preso in giro.',
             'Ci avevo creduto. Mi hanno detto "giochi tu" e poi niente. Che amarezza.'])
        when 'spazio' then private.social_scegli('ps' || v_r.id, array[
             'Mi avevano promesso più spazio. Ancora una volta niente. Basta promesse, servono i fatti.',
             'Più minuti, mi era stato detto. Sono ancora qui ad aspettare. Che delusione.'])
        else private.social_scegli('pr' || v_r.id, array[
             'Mi avevano detto che avrei riposato e invece sono sceso in campo comunque, stanco morto. Così non va.',
             'Ho chiesto di tirare il fiato, mi era stato promesso. E invece eccomi qui a giocare. Mah.'])
      end end,
      (select coalesce(m2.simulata_il, now()) from public.matches m2 where m2.id = v_m.id) + interval '2 minutes')
    on conflict (league_id, chiave) do nothing;

    perform private.notifica(v_user, v_r.league_id, 'sistema',
      case when v_ok then 'Promessa mantenuta' else 'Promessa non mantenuta' end,
      case when v_ok then v_nome || ' ha apprezzato che tu abbia mantenuto la parola: morale +8.'
           else v_nome || ' si sente tradito: morale -20, e si è sfogato sui social.' end,
      jsonb_build_object('player_instance_id', v_r.player_instance_id));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Il cron (richieste-giocatori, ogni 5 minuti) si attiva con la migrazione successiva, a funzione e schermata pronte.

commit;
