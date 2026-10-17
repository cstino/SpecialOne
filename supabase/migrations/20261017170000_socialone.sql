-- ============================================================
--  SOCIALONE — il feed social della lega (docs/decisioni-conferenze-stampa.md §3)
--  Prova in LegaBot (interruttore leagues.conferenze_stampa).
--
--  Un post per ogni evento, generato da un cron ogni 5 minuti (private.social_genera),
--  una sola volta (unique league_id + chiave). Chi pubblica:
--    lega       risultati, scambi ufficiali ("HERE WE GO"), aste vinte
--    testata    la domanda fatta in conferenza stampa (testata reale)
--    allenatore la risposta data in conferenza
--    tifosi     il post generato dalla valutazione (esultano o protestano)
--    giocatore  chi segna dopo la partita; il capitano che risponde ai tifosi arrabbiati
--  Lo vede tutta la lega. L'utente vede per primi i post che riguardano la sua squadra.
--  Un solo "mi piace" per utente e post.
-- ============================================================

begin;

create table public.social_posts (
  id                 bigint generated always as identity primary key,
  league_id          bigint not null references public.leagues(id) on delete cascade,
  chiave             text not null,
  autore_tipo        text not null check (autore_tipo in ('lega', 'testata', 'allenatore', 'tifosi', 'giocatore')),
  autore_nome        text not null check (char_length(autore_nome) between 1 and 80),
  team_id            bigint references public.teams(id) on delete set null,
  team2_id           bigint references public.teams(id) on delete set null,
  player_instance_id bigint references public.player_instances(id) on delete set null,
  in_risposta_a      bigint references public.social_posts(id) on delete set null,
  testo              text not null check (char_length(testo) between 1 and 700),
  creato_il          timestamptz not null default now(),
  unique (league_id, chiave)
);
create index social_posts_lega_idx on public.social_posts (league_id, creato_il desc);
create index social_posts_team_idx on public.social_posts (team_id, creato_il desc);

create table public.social_mi_piace (
  post_id   bigint not null references public.social_posts(id) on delete cascade,
  user_id   uuid not null default auth.uid(),
  creato_il timestamptz not null default now(),
  primary key (post_id, user_id)
);

alter table public.social_posts enable row level security;
alter table public.social_mi_piace enable row level security;

-- Si legge solo nelle proprie leghe. Le scritture passano da funzioni (security definer).
create policy social_posts_lettura on public.social_posts
  for select to authenticated
  using (league_id = any ((select private.mie_leghe())::bigint[]));
create policy social_mi_piace_miei on public.social_mi_piace
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ------------------------------------------------------------
--  Per l'app: il feed
-- ------------------------------------------------------------
create or replace function public.social_feed(
  p_league_id bigint, p_per_te boolean default true, p_limite integer default 40, p_offset integer default 0)
returns table (
  id bigint, autore_tipo text, autore_nome text, team_id bigint, team2_id bigint,
  player_instance_id bigint, in_risposta_a bigint, testo text, creato_il timestamptz,
  n_mi_piace bigint, mio_mi_piace boolean, riguarda_me boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_mia bigint;
begin
  if not (p_league_id = any (private.mie_leghe())) then return; end if;
  select t.id into v_mia from public.teams t where t.league_id = p_league_id and t.user_id = v_utente;

  return query
    select p.id, p.autore_tipo, p.autore_nome, p.team_id, p.team2_id, p.player_instance_id, p.in_risposta_a, p.testo, p.creato_il,
           (select count(*) from public.social_mi_piace l where l.post_id = p.id),
           exists (select 1 from public.social_mi_piace l where l.post_id = p.id and l.user_id = v_utente),
           coalesce(p.team_id = v_mia or p.team2_id = v_mia, false)
    from public.social_posts p
    where p.league_id = p_league_id
    order by case when p_per_te and v_mia is not null and (p.team_id = v_mia or p.team2_id = v_mia)
                       and p.creato_il > now() - interval '3 days' then 0 else 1 end,
             p.creato_il desc, p.id desc
    limit greatest(1, least(p_limite, 100)) offset greatest(0, p_offset);
end;
$$;
revoke all on function public.social_feed(bigint, boolean, integer, integer) from public, anon;
grant execute on function public.social_feed(bigint, boolean, integer, integer) to authenticated;

-- "Mi piace": se c'e' lo toglie, se non c'e' lo mette. Restituisce lo stato nuovo e il totale.
create or replace function public.social_mi_piace(p_post_id bigint)
returns table (mio boolean, totale bigint)
language plpgsql security definer set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_lega bigint;
begin
  select league_id into v_lega from public.social_posts where id = p_post_id;
  if v_lega is null or v_utente is null or not (v_lega = any (private.mie_leghe())) then
    raise exception using errcode = '42501', message = 'Post non disponibile.';
  end if;
  if exists (select 1 from public.social_mi_piace where post_id = p_post_id and user_id = v_utente) then
    delete from public.social_mi_piace where post_id = p_post_id and user_id = v_utente;
  else
    insert into public.social_mi_piace (post_id, user_id) values (p_post_id, v_utente);
  end if;
  return query select exists (select 1 from public.social_mi_piace where post_id = p_post_id and user_id = v_utente),
                      (select count(*) from public.social_mi_piace where post_id = p_post_id);
end;
$$;
revoke all on function public.social_mi_piace(bigint) from public, anon;
grant execute on function public.social_mi_piace(bigint) to authenticated;

-- ------------------------------------------------------------
--  Il generatore: un post per ogni evento, una sola volta
-- ------------------------------------------------------------
create or replace function private.social_scegli(p_chiave text, p_frasi text[])
returns text
language sql immutable set search_path = ''
as $$ select p_frasi[1 + (abs(hashtext(p_chiave)) % array_length(p_frasi, 1))] $$;

create or replace function private.social_genera()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_nuovi integer := 0;
  v_n integer;
begin
  -- 1. Risultati: l'account della lega (ultimi 3 giorni).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, testo, creato_il)
  select f.league_id, 'partita:' || m.id, 'lega', 'SpecialOne Lega', f.home_team_id, f.away_team_id,
         'FINALE · ' || th.nome || ' ' || m.gol_home || '-' || m.gol_away || ' ' || ta.nome || '. ' ||
         case
           when m.gol_home = 0 and m.gol_away = 0 then private.social_scegli('p' || m.id, array[
             'Tanta tattica e zero gol: le difese vincono la serata.', 'Nessuna rete, tanti rimpianti da una parte e dall''altra.'])
           when m.gol_home = m.gol_away then private.social_scegli('p' || m.id, array[
             'Pari e patta: un punto a testa, e qualcuno recrimina.', 'Si divide la posta, con gol da entrambe le parti.'])
           when abs(m.gol_home - m.gol_away) >= 4 then private.social_scegli('p' || m.id, array[
             'Goleada: ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' non lascia scampo.',
             'Serata da dimenticare per ' || case when m.gol_home > m.gol_away then ta.nome else th.nome end || '.'])
           when abs(m.gol_home - m.gol_away) = 1 then private.social_scegli('p' || m.id, array[
             case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' la spunta di misura.',
             'Tre punti sofferti per ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || '.'])
           else private.social_scegli('p' || m.id, array[
             case when m.gol_home > m.gol_away then th.nome else ta.nome end || ' porta a casa i tre punti con merito.',
             'Vittoria chiara per ' || case when m.gol_home > m.gol_away then th.nome else ta.nome end || '.'])
         end,
         m.simulata_il
  from public.matches m
  join public.fixtures f on f.id = m.fixture_id
  join public.leagues l on l.id = f.league_id and l.conferenze_stampa
  join public.teams th on th.id = f.home_team_id
  join public.teams ta on ta.id = f.away_team_id
  where m.simulata_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 2. Chi segna: il miglior marcatore di ogni squadra pubblica dopo la partita, col tono del suo
  --    carattere (uno per squadra e partita, per non coprire il resto del feed).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, testo, creato_il)
  select distinct on (ms.match_id, ms.team_id) f.league_id, 'gol:' || ms.match_id || ':' || ms.player_instance_id, 'giocatore', p.nome, ms.team_id, ms.player_instance_id,
         case
           when (case when ms.team_id = f.home_team_id then m.gol_home - m.gol_away else m.gol_away - m.gol_home end) < 0
             then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
               'Il gol non basta. Si lavora in settimana per rialzarci.', 'Una serata amara: segnare non serve se non si vince.'])
           when p.mentalita_bandiera >= greatest(p.mentalita_economia, p.mentalita_vittorie) then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta con questa maglia addosso: non esiste emozione più grande.' else 'Segnare per questa maglia non ha prezzo. Grazie a chi ci ha spinto!' end,
             'Questa maglia è tutta la mia vita. Grazie ai tifosi per ogni voce.'])
           when p.mentalita_economia >= p.mentalita_vittorie then private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta. Il lavoro paga, sempre.' else 'Un gol che fa bene. Il lavoro quotidiano paga.' end,
             'Contento del gol, ma ora si pensa alla prossima.'])
           else private.social_scegli('g' || ms.match_id || ms.player_instance_id, array[
             case when ms.gol >= 2 then 'Doppietta, ma conta solo vincere. Avanti verso gli obiettivi.' else 'Un gol per la squadra: l''obiettivo è vincere tutto.' end,
             'Si vince, si segna, si va avanti. Questo è il nostro livello.'])
         end,
         m.simulata_il + interval '1 second'
  from public.match_stats ms
  join public.matches m on m.id = ms.match_id
  join public.fixtures f on f.id = m.fixture_id
  join public.leagues l on l.id = f.league_id and l.conferenze_stampa
  join public.player_instances pi on pi.id = ms.player_instance_id
  join public.players p on p.id = pi.player_id
  where ms.gol >= 1 and m.simulata_il > now() - interval '3 days'
  order by ms.match_id, ms.team_id, ms.gol desc, ms.player_instance_id
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 3. Scambi ufficiali: "HERE WE GO".
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, team2_id, testo, creato_il)
  select tp.league_id, 'scambio:' || tp.id, 'lega', 'SpecialOne Lega', tp.da_team_id, tp.a_team_id,
         '‼️ HERE WE GO ‼️ Adesso è ufficiale lo scambio tra ' || td.nome || ' e ' || tt.nome || '. ' ||
         td.nome || ' cede ' || coalesce(nullif((
           select string_agg(p.nome, ', ') from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (tp.giocatori_offerti)), ''), 'solo scelte') ||
         '; ' || tt.nome || ' cede ' || coalesce(nullif((
           select string_agg(p.nome, ', ') from public.player_instances pi join public.players p on p.id = pi.player_id
           where pi.id = any (tp.giocatori_richiesti)), ''), 'solo scelte') || '.',
         tp.risolta_il
  from public.trade_proposals tp
  join public.leagues l on l.id = tp.league_id and l.conferenze_stampa
  join public.teams td on td.id = tp.da_team_id
  join public.teams tt on tt.id = tp.a_team_id
  where tp.stato = 'accettata' and tp.risolta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 4. Aste vinte (svincolati e UNDER).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select a.league_id, 'asta:' || a.id, 'lega', 'SpecialOne Lega', a.vincitore_team_id,
         t.nome || ' si aggiudica ' || p.nome || ' per ' || to_char(a.ingaggio_finale / 1000000.0, 'FM990.0') || ' M€.',
         a.risolta_il
  from public.free_agent_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > now() - interval '3 days' and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select a.league_id, 'under:' || a.id, 'lega', 'SpecialOne Lega', a.vincitore_team_id,
         'UNDER · ' || t.nome || ' porta in casa il giovane ' || p.nome || ' per ' || to_char(a.ingaggio_finale / 1000000.0, 'FM990.0') || ' M€.',
         a.risolta_il
  from public.under_auctions a
  join public.leagues l on l.id = a.league_id and l.conferenze_stampa
  join public.teams t on t.id = a.vincitore_team_id
  join public.players p on p.id = a.player_id
  where a.stato = 'assegnata' and a.risolta_il > now() - interval '3 days' and a.ingaggio_finale is not null
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 5. Conferenze stampa risposte: la domanda della testata, la risposta dell'allenatore
  --    (in risposta alla domanda) e il post dei tifosi (in risposta all'allenatore).
  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
  select d.league_id, 'conf-domanda:' || d.id, 'testata', d.giornalista, d.team_id, d.domanda, d.risposta_il - interval '2 seconds'
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  where d.voto is not null and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, in_risposta_a, testo, creato_il)
  select d.league_id, 'conf-risposta:' || d.id, 'allenatore',
         coalesce(nullif(btrim(pr.nome_allenatore), ''), t.nome), d.team_id,
         (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-domanda:' || d.id),
         d.risposta, d.risposta_il - interval '1 second'
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  join public.teams t on t.id = d.team_id
  left join public.profiles pr on pr.user_id = t.user_id
  where d.voto is not null and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, in_risposta_a, testo, creato_il)
  select d.league_id, 'conf-tifosi:' || d.id, 'tifosi', 'Tifosi ' || t.nome, d.team_id,
         (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-risposta:' || d.id),
         d.reazione_pubblico, d.risposta_il
  from public.conferenze_domande d
  join public.leagues l on l.id = d.league_id and l.conferenze_stampa
  join public.teams t on t.id = d.team_id
  where d.voto is not null and d.reazione_pubblico is not null and btrim(d.reazione_pubblico) <> ''
    and d.risposta_il > now() - interval '3 days'
  on conflict (league_id, chiave) do nothing;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  -- 6. Il capitano risponde ai tifosi arrabbiati (protesta forte: pubblico -2 o peggio).
  --    Un buon capitano calma i tifosi: da 0 a +3 punti di pubblico, una volta per protesta.
  with protesta as (
    select d.id as domanda_id, d.league_id, d.team_id, d.risposta_il,
           coalesce(t.capitano, private.capitano_automatico(t.id)) as cap_id,
           (select sp.id from public.social_posts sp where sp.league_id = d.league_id and sp.chiave = 'conf-tifosi:' || d.id) as post_tifosi
    from public.conferenze_domande d
    join public.leagues l on l.id = d.league_id and l.conferenze_stampa
    join public.teams t on t.id = d.team_id
    where d.voto is not null and coalesce(d.effetto_pubblico, 0) <= -8
      and d.risposta_il > now() - interval '3 days'
  ), inseriti as (
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, player_instance_id, in_risposta_a, testo, creato_il)
    select pr.league_id, 'conf-capitano:' || pr.domanda_id, 'giocatore', p.nome, pr.team_id, pi.id, pr.post_tifosi,
           private.social_scegli('cap' || pr.domanda_id, array[
             'Capisco la rabbia, ragazzi. Siamo i primi a volerci rialzare: restateci vicino.',
             'Avete ragione ad arrabbiarvi. Ci rimbocchiamo le maniche, lo promettiamo.',
             'Questa maglia pesa e sappiamo cosa dobbiamo a voi. Si riparte dal campo.']),
           pr.risposta_il + interval '5 seconds'
    from protesta pr
    join public.player_instances pi on pi.id = pr.cap_id and not pi.ritirato
    join public.players p on p.id = pi.player_id
    where pr.post_tifosi is not null
    on conflict (league_id, chiave) do nothing
    returning team_id, player_instance_id
  )
  update public.teams t
     set pubblico = least(100, t.pubblico + 3 * greatest(0, private.qualita_capitano(i.player_instance_id)))
    from inseriti i
   where t.id = i.team_id;
  get diagnostics v_n = row_count; v_nuovi := v_nuovi + v_n;

  return v_nuovi;
end;
$$;

select cron.schedule('social-genera', '*/5 * * * *', 'select private.social_genera();');

commit;
