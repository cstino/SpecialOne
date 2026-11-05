-- Season 3, diario §10: gli sponsor.
-- * Extra campo > Sponsor: 3 offerte a breve termine e 3 a lungo termine da aziende reali (loghi in public/loghi-sponsor,
--   da Simple Icons). Un contratto attivo per colonna; completato o fallito, le offerte di quella colonna si rinnovano.
-- * Le offerte si costruiscono sulla situazione della squadra: obiettivi relativi (tifo, classifica, gol medi), solo se
--   possibili (derby in calendario, trasferta, Under 21 in rosa...), premio scalato sulla forza degli avversari.
-- * La verifica usa solo le partite gia' viste dall'allenatore (o giocate da piu' di 24 ore): niente spoiler.
-- * Rinuncia: le nuove offerte di quella colonna arrivano dopo 24 ore. Premi in crediti del casino'.
-- * Acceso nelle leghe con le conferenze stampa e la Season 3 (leagues.stadio_attivo).

create table public.sponsor_aziende (
  id smallint generated always as identity primary key,
  slug text not null unique,
  nome text not null,
  colore text not null,
  settore text not null check (settore in ('sport', 'energia', 'finanza', 'viaggi', 'auto', 'cibo', 'tech', 'media'))
);
alter table public.sponsor_aziende enable row level security;
create policy sponsor_aziende_lettura on public.sponsor_aziende for select using (true);
grant select on public.sponsor_aziende to anon;
grant select, insert, update, delete on public.sponsor_aziende to authenticated, service_role;

insert into public.sponsor_aziende (slug, nome, colore, settore) values
  ('adidas', 'Adidas', '#000000', 'sport'),
  ('puma', 'Puma', '#242B2F', 'sport'),
  ('nike', 'Nike', '#111111', 'sport'),
  ('newbalance', 'New Balance', '#CF0A2C', 'sport'),
  ('underarmour', 'Under Armour', '#1D1D1D', 'sport'),
  ('redbull', 'Red Bull', '#DB0A40', 'energia'),
  ('monster', 'Monster', '#6D4C9F', 'energia'),
  ('playstation', 'PlayStation', '#0070D1', 'energia'),
  ('nintendo', 'Nintendo', '#E60012', 'energia'),
  ('nvidia', 'NVIDIA', '#76B900', 'energia'),
  ('intel', 'Intel', '#0071C5', 'energia'),
  ('visa', 'Visa', '#1A1F71', 'finanza'),
  ('mastercard', 'MasterCard', '#EB001B', 'finanza'),
  ('paypal', 'PayPal', '#003087', 'finanza'),
  ('americanexpress', 'American Express', '#2E77BC', 'finanza'),
  ('revolut', 'Revolut', '#191C1F', 'finanza'),
  ('n26', 'N26', '#48AC98', 'finanza'),
  ('barclays', 'Barclays', '#00AEEF', 'finanza'),
  ('hsbc', 'HSBC', '#DB0011', 'finanza'),
  ('emirates', 'Emirates', '#D71921', 'viaggi'),
  ('qatarairways', 'Qatar Airways', '#5C0D34', 'viaggi'),
  ('ryanair', 'Ryanair', '#073590', 'viaggi'),
  ('lufthansa', 'Lufthansa', '#05164D', 'viaggi'),
  ('turkishairlines', 'Turkish Airlines', '#C70A0C', 'viaggi'),
  ('etihadairways', 'Etihad Airways', '#BD8B13', 'viaggi'),
  ('airfrance', 'Air France', '#002157', 'viaggi'),
  ('klm', 'KLM', '#00A1DE', 'viaggi'),
  ('dhl', 'DHL', '#FFCC00', 'viaggi'),
  ('ups', 'UPS', '#150400', 'viaggi'),
  ('fedex', 'FedEx', '#4D148C', 'viaggi'),
  ('fiat', 'Fiat', '#941711', 'auto'),
  ('audi', 'Audi', '#BB0A30', 'auto'),
  ('volkswagen', 'Volkswagen', '#151F5D', 'auto'),
  ('bmw', 'BMW', '#0066B1', 'auto'),
  ('toyota', 'Toyota', '#EB0A1E', 'auto'),
  ('alfaromeo', 'Alfa Romeo', '#981E32', 'auto'),
  ('jeep', 'Jeep', '#000000', 'auto'),
  ('ferrari', 'Ferrari', '#D40000', 'auto'),
  ('mercedes', 'Mercedes', '#242424', 'auto'),
  ('porsche', 'Porsche', '#B12B28', 'auto'),
  ('peugeot', 'Peugeot', '#000000', 'auto'),
  ('renault', 'Renault', '#FFCC33', 'auto'),
  ('skoda', 'ŠKODA', '#0E3A2F', 'auto'),
  ('hyundai', 'Hyundai', '#002C5E', 'auto'),
  ('kia', 'Kia', '#05141F', 'auto'),
  ('cocacola', 'Coca Cola', '#D00013', 'cibo'),
  ('mcdonalds', 'McDonald''s', '#FBC817', 'cibo'),
  ('starbucks', 'Starbucks', '#006241', 'cibo'),
  ('kfc', 'KFC', '#F40027', 'cibo'),
  ('burgerking', 'Burger King', '#D62300', 'cibo'),
  ('samsung', 'Samsung', '#1428A0', 'tech'),
  ('spotify', 'Spotify', '#1ED760', 'tech'),
  ('sony', 'Sony', '#FFFFFF', 'tech'),
  ('netflix', 'Netflix', '#E50914', 'tech'),
  ('tiktok', 'TikTok', '#000000', 'tech'),
  ('xiaomi', 'Xiaomi', '#FF6900', 'tech'),
  ('huawei', 'Huawei', '#FF0000', 'tech'),
  ('lg', 'LG', '#A50034', 'tech'),
  ('oppo', 'OPPO', '#2D683D', 'tech'),
  ('dazn', 'DAZN', '#F8F8F5', 'tech'),
  ('amazon', 'Amazon', '#FF9900', 'media'),
  ('zalando', 'Zalando', '#FF6900', 'media'),
  ('ebay', 'eBay', '#E53238', 'media'),
  ('uber', 'Uber', '#000000', 'media'),
  ('airbnb', 'Airbnb', '#FF5A5F', 'media'),
  ('ikea', 'IKEA', '#0058A3', 'media'),
  ('shell', 'Shell', '#FFD500', 'media');

create table public.sponsor_contratti (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  stagione smallint not null,
  categoria text not null check (categoria in ('breve', 'lungo')),
  tipo text not null,
  azienda_id smallint not null references public.sponsor_aziende(id),
  titolo text not null,
  descrizione text not null,
  parametri jsonb not null default '{}'::jsonb,
  partite smallint not null,
  premio integer not null check (premio > 0),
  effetto_tifo numeric not null default 0,
  -- offerta: prossima giornata quando e' stata proposta (scade quando la giornata si gioca)
  giornata_offerta smallint not null,
  fixture_ids bigint[],
  progresso jsonb not null default '{}'::jsonb,
  stato text not null default 'offerta' check (stato in ('offerta', 'scartata', 'attiva', 'completata', 'fallita', 'rinunciata')),
  creata_il timestamptz not null default now(),
  scelta_il timestamptz,
  chiusa_il timestamptz
);
create index sponsor_contratti_team_idx on public.sponsor_contratti (team_id, stato);
create unique index sponsor_un_attivo_per_categoria on public.sponsor_contratti (team_id, categoria) where stato = 'attiva';
alter table public.sponsor_contratti enable row level security;
-- Le offerte e i contratti sono della squadra: li vede solo chi la allena.
create policy sponsor_contratti_miei on public.sponsor_contratti for select to authenticated
  using ((select private.e_mia_squadra(team_id)));
grant select on public.sponsor_contratti to anon;
grant select, insert, update, delete on public.sponsor_contratti to authenticated, service_role;

-- Forza di una rosa: media dei 14 migliori overall disponibili (non ritirati, non in prestito).
create or replace function private.sponsor_forza(p_team_id bigint)
returns numeric
language sql
stable
set search_path to ''
as $$
  select coalesce(avg(o), 70) from (
    select pi.overall_corrente o from public.player_instances pi
    where pi.team_id = p_team_id and not pi.ritirato and pi.prestito_id is null
    order by pi.overall_corrente desc limit 14) x
$$;

-- Le prossime partite ancora da giocare della squadra, in ordine.
create or replace function private.sponsor_prossime(p_team_id bigint, p_n integer)
returns table (fixture_id bigint, giornata smallint, casa boolean, avversario bigint, playoff boolean)
language sql
stable
set search_path to ''
as $$
  select f.id, f.giornata::smallint, f.home_team_id = p_team_id,
         case when f.home_team_id = p_team_id then f.away_team_id else f.home_team_id end,
         f.bracket_tie_id is not null
  from public.fixtures f
  join public.teams t on t.id = p_team_id
  join public.leagues l on l.id = t.league_id
  join public.seasons s on s.id = f.season_id and s.league_id = l.id and s.numero = l.stagione_corrente
  where f.stato = 'programmata' and p_team_id in (f.home_team_id, f.away_team_id)
  order by f.giornata, f.id
  limit p_n
$$;

-- Moltiplicatore del premio: avversari piu' forti pagano di piu' (0,6 - 2,0), in trasferta un po' di piu'.
create or replace function private.sponsor_fattore(p_team_id bigint, p_avversari bigint[], p_trasferte integer default 0)
returns numeric
language sql
stable
set search_path to ''
as $$
  select greatest(0.6, least(2.0,
           (1 + (coalesce((select avg(private.sponsor_forza(a)) from unnest(p_avversari) a), private.sponsor_forza(p_team_id))
                 - private.sponsor_forza(p_team_id)) * 0.08)
           * (1 + 0.15 * p_trasferte / greatest(1, cardinality(p_avversari)))))
$$;

create or replace function private.sponsor_premio(p_base numeric, p_fattore numeric)
returns integer
language sql
immutable
set search_path to ''
as $$ select greatest(50, (round(p_base * p_fattore / 10) * 10)::integer) $$;

-- Gol fatti e subiti di media nelle ultime 6 partite giocate della stagione (1,4 se non ce ne sono).
create or replace function private.sponsor_medie(p_team_id bigint, out gf numeric, out gs numeric)
language sql
stable
set search_path to ''
as $$
  select coalesce(avg(case when f.home_team_id = p_team_id then m.gol_home else m.gol_away end), 1.4),
         coalesce(avg(case when f.home_team_id = p_team_id then m.gol_away else m.gol_home end), 1.4)
  from (select f.* from public.fixtures f
        join public.teams t on t.id = p_team_id
        join public.leagues l on l.id = t.league_id
        join public.seasons s on s.id = f.season_id and s.league_id = l.id and s.numero = l.stagione_corrente
        where f.stato = 'simulata' and p_team_id in (f.home_team_id, f.away_team_id)
        order by f.giornata desc limit 6) f
  join public.matches m on m.fixture_id = f.id
$$;

create or replace function private.sponsor_azienda(p_team_id bigint, p_settore text)
returns public.sponsor_aziende
language sql
volatile
set search_path to ''
as $$
  select a.* from public.sponsor_aziende a
  where a.settore = p_settore
  order by (exists (select 1 from public.sponsor_contratti c
                    where c.team_id = p_team_id and c.azienda_id = a.id and c.stato in ('offerta', 'attiva'))), random()
  limit 1
$$;

revoke all on function private.sponsor_forza(bigint) from public, anon, authenticated;
revoke all on function private.sponsor_prossime(bigint, integer) from public, anon, authenticated;
revoke all on function private.sponsor_fattore(bigint, bigint[], integer) from public, anon, authenticated;
revoke all on function private.sponsor_premio(numeric, numeric) from public, anon, authenticated;
revoke all on function private.sponsor_medie(bigint) from public, anon, authenticated;
revoke all on function private.sponsor_azienda(bigint, text) from public, anon, authenticated;

-- Le offerte di una colonna: tutte le richieste possibili adesso, poi 3 di tipo diverso a caso.
create or replace function private.sponsor_genera(p_team_id bigint, p_categoria text)
returns integer
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  v_team public.teams;
  v_lega public.leagues;
  v_prossima smallint;
  v_p record;
  v_n integer;
  v_casa integer;
  v_trasf integer;
  v_avv bigint[];
  v_medie record;
  v_target integer;
  v_pos integer;
  v_cap_ruolo text;
  v_derby integer;
  v_regolari integer;
  v_c jsonb := '[]'::jsonb;
  v_x jsonb;
  v_az public.sponsor_aziende;
  v_inseriti integer := 0;
begin
  select * into v_team from public.teams where id = p_team_id;
  select * into v_lega from public.leagues where id = v_team.league_id;
  v_prossima := private.prossima_giornata_lega(v_lega.id);
  select * into v_medie from private.sponsor_medie(p_team_id);

  if p_categoria = 'breve' then
    select * into v_p from private.sponsor_prossime(p_team_id, 1);
    if v_p.fixture_id is not null then
      v_x := jsonb_build_object('fattore', private.sponsor_fattore(p_team_id, array[v_p.avversario], (not v_p.casa)::int));
      v_c := v_c || jsonb_build_object('tipo', 'vinci_prossima', 'settore', 'sport', 'partite', 1, 'titolo', 'Vittoria',
        'descrizione', 'Vinci la prossima partita.', 'premio', private.sponsor_premio(300, (v_x->>'fattore')::numeric), 'parametri', '{}'::jsonb);
      v_c := v_c || jsonb_build_object('tipo', 'porta_inviolata', 'settore', 'finanza', 'partite', 1, 'titolo', 'Cassaforte',
        'descrizione', 'Non subire gol nella prossima partita.', 'premio', private.sponsor_premio(300, (v_x->>'fattore')::numeric), 'parametri', '{}'::jsonb);
      v_target := least(5, greatest(2, round(v_medie.gf * 1.3)::int));
      v_c := v_c || jsonb_build_object('tipo', 'segna_x', 'settore', 'energia', 'partite', 1, 'titolo', 'Pioggia di gol',
        'descrizione', 'Segna almeno ' || v_target || ' gol nella prossima partita.',
        'premio', private.sponsor_premio(120 * v_target, (v_x->>'fattore')::numeric), 'parametri', jsonb_build_object('gol', v_target));
      if exists (select 1 from public.player_instances pi where pi.team_id = p_team_id and not pi.ritirato and pi.prestito_id is null and pi.eta_corrente < 21) then
        v_c := v_c || jsonb_build_object('tipo', 'under21', 'settore', 'tech', 'partite', 1, 'titolo', 'Largo ai giovani',
          'descrizione', 'Schiera titolare almeno un Under 21 nella prossima partita.', 'premio', 200, 'parametri', '{}'::jsonb);
      end if;
    end if;
    -- Trasferta: una delle prossime 2 fuori casa.
    select array_agg(avversario) filter (where not casa), count(*) filter (where not casa) into v_avv, v_trasf
    from private.sponsor_prossime(p_team_id, 2);
    if v_trasf > 0 then
      v_c := v_c || jsonb_build_object('tipo', 'vinci_trasferta', 'settore', 'viaggi', 'partite', 2, 'titolo', 'In trasferta',
        'descrizione', 'Vinci una partita fuori casa entro le prossime 2.',
        'premio', private.sponsor_premio(450, private.sponsor_fattore(p_team_id, v_avv, 1)), 'parametri', '{}'::jsonb);
    end if;
    -- Derby entro le prossime 3.
    select min(rn) into v_derby from (
      select row_number() over () as rn, x.* from private.sponsor_prossime(p_team_id, 3) x) y
    where private.e_derby(v_lega.id, p_team_id, y.avversario);
    if v_derby is not null then
      v_c := v_c || jsonb_build_object('tipo', 'vinci_derby', 'settore', 'cibo', 'partite', v_derby, 'titolo', 'Derby',
        'descrizione', 'Vinci il prossimo derby.', 'premio', 600, 'parametri', '{}'::jsonb);
    end if;
    -- Gol del capitano (non portiere): piu' premio se e' un difensore o un centrocampista.
    if v_team.capitano is not null then
      select private.macro_ruolo(coalesce(pi.posizioni_override, p.posizioni)) into v_cap_ruolo
      from public.player_instances pi join public.players p on p.id = pi.player_id
      where pi.id = v_team.capitano and pi.prestito_id is null;
      if v_cap_ruolo is not null and v_cap_ruolo <> 'GK' then
        v_c := v_c || jsonb_build_object('tipo', 'gol_capitano', 'settore', 'auto', 'partite', 2, 'titolo', 'Fascia d''oro',
          'descrizione', 'Fai segnare il tuo capitano entro le prossime 2 partite.',
          'premio', case v_cap_ruolo when 'DEF' then 650 when 'MID' then 450 else 350 end,
          'parametri', jsonb_build_object('capitano', v_team.capitano));
      end if;
    end if;
    if v_lega.conferenze_stampa then
      v_c := v_c || jsonb_build_object('tipo', 'pubblicita', 'settore', 'cibo', 'partite', 2, 'titolo', 'Pubblicità occulta',
        'descrizione', 'Cita lo sponsor in una risposta in conferenza stampa entro le prossime 2 giornate. I tifosi storcono un po'' il naso.',
        'premio', 200, 'effetto_tifo', -1, 'parametri', jsonb_build_object('citazioni', 1));
      v_c := v_c || jsonb_build_object('tipo', 'testimonial', 'settore', 'media', 'partite', 2, 'titolo', 'Testimonial',
        'descrizione', 'Cita lo sponsor in 2 risposte diverse in conferenza stampa entro le prossime 2 giornate. Sa di marchetta: ai tifosi piace meno.',
        'premio', 350, 'effetto_tifo', -2, 'parametri', jsonb_build_object('citazioni', 2));
    end if;
  else
    -- Lungo termine: servono abbastanza partite davanti.
    select count(*), array_agg(avversario), count(*) filter (where casa) into v_n, v_avv, v_casa from private.sponsor_prossime(p_team_id, 5);
    if v_n = 5 then
      v_c := v_c || jsonb_build_object('tipo', 'vinci_3_su_5', 'settore', 'sport', 'partite', 5, 'titolo', 'Serie vincente',
        'descrizione', 'Vinci 3 delle prossime 5 partite.', 'premio', private.sponsor_premio(1000, private.sponsor_fattore(p_team_id, v_avv, 5 - v_casa)),
        'parametri', jsonb_build_object('vittorie', 3));
      v_c := v_c || jsonb_build_object('tipo', 'imbattuto', 'settore', 'finanza', 'partite', 5, 'titolo', 'Imbattibili',
        'descrizione', 'Non perdere nessuna delle prossime 5 partite.', 'premio', private.sponsor_premio(1200, private.sponsor_fattore(p_team_id, v_avv, 5 - v_casa)),
        'parametri', '{}'::jsonb);
    end if;
    select count(*), array_agg(avversario), count(*) filter (where casa), count(*) filter (where not playoff)
      into v_n, v_avv, v_casa, v_regolari from private.sponsor_prossime(p_team_id, 6);
    if v_n = 6 then
      v_target := greatest(6, ceil(v_medie.gf * 6 * 1.15)::int);
      v_c := v_c || jsonb_build_object('tipo', 'gol_fatti', 'settore', 'energia', 'partite', 6, 'titolo', 'Attacco atomico',
        'descrizione', 'Segna almeno ' || v_target || ' gol nelle prossime 6 partite.',
        'premio', private.sponsor_premio(1000, private.sponsor_fattore(p_team_id, v_avv, 6 - v_casa)), 'parametri', jsonb_build_object('gol', v_target));
      v_target := greatest(3, floor(v_medie.gs * 6 * 0.8)::int);
      v_c := v_c || jsonb_build_object('tipo', 'gol_subiti', 'settore', 'finanza', 'partite', 6, 'titolo', 'Muro',
        'descrizione', 'Subisci al massimo ' || v_target || ' gol nelle prossime 6 partite.',
        'premio', private.sponsor_premio(1000, private.sponsor_fattore(p_team_id, v_avv, 6 - v_casa)), 'parametri', jsonb_build_object('gol', v_target));
      v_c := v_c || jsonb_build_object('tipo', 'bomber', 'settore', 'energia', 'partite', 6, 'titolo', 'Bomber',
        'descrizione', 'Un tuo giocatore segna almeno 5 gol nelle prossime 6 partite.',
        'premio', private.sponsor_premio(900, private.sponsor_fattore(p_team_id, v_avv, 6 - v_casa)), 'parametri', jsonb_build_object('gol', 5));
      if v_casa >= 4 then
        v_c := v_c || jsonb_build_object('tipo', 'maglia', 'settore', 'auto', 'partite', 6, 'titolo', 'Sponsor di maglia',
          'descrizione', 'Vinci 4 partite in casa fra le prossime 6. Se ci riesci i tifosi apprezzano.',
          'premio', private.sponsor_premio(1500, private.sponsor_fattore(p_team_id, v_avv, 0)), 'effetto_tifo', 3,
          'parametri', jsonb_build_object('vittorie', 4));
      end if;
      -- Classifica: solo in stagione regolare, con 6 giornate davanti.
      if v_regolari = 6 then
        select st.posizione into v_pos from public.standings st
        join public.seasons s on s.id = st.season_id and s.league_id = v_lega.id and s.numero = v_lega.stagione_corrente
        where st.team_id = p_team_id;
        if v_pos = 1 then
          v_c := v_c || jsonb_build_object('tipo', 'classifica', 'settore', 'viaggi', 'partite', 6, 'titolo', 'In vetta',
            'descrizione', 'Sii ancora primo in classifica fra 6 giornate.', 'premio', 1200, 'parametri', jsonb_build_object('posizione', 1));
        elsif v_pos > 1 then
          v_target := greatest(1, v_pos - 3);
          v_c := v_c || jsonb_build_object('tipo', 'classifica', 'settore', 'viaggi', 'partite', 6, 'titolo', 'Scalata',
            'descrizione', 'Sali almeno al ' || v_target || 'º posto in classifica entro 6 giornate (ora sei ' || v_pos || 'º).',
            'premio', 400 * (v_pos - v_target), 'parametri', jsonb_build_object('posizione', v_target));
        end if;
      end if;
    end if;
    -- Tifo: dal valore di adesso + 15, solo se c'e' margine.
    select count(*) into v_n from private.sponsor_prossime(p_team_id, 8);
    if v_lega.conferenze_stampa and v_n = 8 and coalesce(v_team.pubblico, 100) < 85 then
      v_target := least(95, ceil(v_team.pubblico)::int + 15);
      v_c := v_c || jsonb_build_object('tipo', 'tifo', 'settore', 'media', 'partite', 8, 'titolo', 'Stadio pieno',
        'descrizione', 'Porta il tifo almeno a ' || v_target || ' entro 8 giornate (ora è ' || round(v_team.pubblico) || ').',
        'premio', 800, 'parametri', jsonb_build_object('tifo', v_target));
    end if;
  end if;

  for v_x in select e from jsonb_array_elements(v_c) e order by random() limit 3 loop
    v_az := private.sponsor_azienda(p_team_id, v_x->>'settore');
    insert into public.sponsor_contratti (league_id, team_id, stagione, categoria, tipo, azienda_id, titolo, descrizione,
      parametri, partite, premio, effetto_tifo, giornata_offerta)
    values (v_lega.id, p_team_id, v_lega.stagione_corrente, p_categoria, v_x->>'tipo', v_az.id, v_x->>'titolo', v_x->>'descrizione',
      v_x->'parametri', (v_x->>'partite')::smallint, (v_x->>'premio')::int, coalesce((v_x->>'effetto_tifo')::numeric, 0), v_prossima);
    v_inseriti := v_inseriti + 1;
  end loop;
  return v_inseriti;
end;
$$;
revoke all on function private.sponsor_genera(bigint, text) from public, anon, authenticated;

-- Testo normalizzato per cercare il nome dello sponsor nelle risposte ("Coca-Cola" = "coca cola" = "cocacola").
create or replace function private.sponsor_norm(p text)
returns text
language sql
immutable
set search_path to ''
as $$ select regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]', '', 'g') $$;
revoke all on function private.sponsor_norm(text) from public, anon, authenticated;

-- Verifica dei contratti attivi della squadra, solo sulle partite che l'allenatore ha gia' visto.
create or replace function private.sponsor_valuta(p_team_id bigint, p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  v_c record;
  v_esito text;
  v_prog jsonb;
  v_giocate integer; v_viste integer; v_totali integer;
  v_vinte integer; v_perse integer; v_gf integer; v_gs integer;
  v_x integer;
  v_ultima timestamptz;
  v_lega public.leagues;
begin
  for v_c in
    select c.*, a.nome as azienda from public.sponsor_contratti c join public.sponsor_aziende a on a.id = c.azienda_id
    where c.team_id = p_team_id and c.stato = 'attiva' for update of c
  loop
    v_esito := null;
    v_prog := '{}'::jsonb;
    if v_c.tipo in ('pubblicita', 'testimonial') then
      select count(*) into v_x from public.conferenze_domande d
      where d.team_id = p_team_id and d.risposta_il >= v_c.scelta_il
        and position(private.sponsor_norm(v_c.azienda) in private.sponsor_norm(d.risposta)) > 0;
      v_prog := jsonb_build_object('fatto', v_x, 'di', (v_c.parametri->>'citazioni')::int);
      if v_x >= (v_c.parametri->>'citazioni')::int then
        v_esito := 'completata';
      else
        -- Tempo fino al giorno dopo l'ultima partita della finestra (c'e' la sala stampa post partita).
        select max(m.simulata_il) into v_ultima from public.matches m where m.fixture_id = any(v_c.fixture_ids);
        if (select count(*) from public.fixtures f where f.id = any(v_c.fixture_ids) and f.stato = 'simulata') = cardinality(v_c.fixture_ids)
           and now() > v_ultima + interval '30 hours' then
          v_esito := 'fallita';
        end if;
      end if;
    else
      with w as (
        select f.id, f.home_team_id = p_team_id as casa, m.id as match_id, m.simulata_il,
               case when f.home_team_id = p_team_id then m.gol_home else m.gol_away end as gf,
               case when f.home_team_id = p_team_id then m.gol_away else m.gol_home end as gs,
               case when f.home_team_id = p_team_id then m.rigori_home else m.rigori_away end as rf,
               case when f.home_team_id = p_team_id then m.rigori_away else m.rigori_home end as rs,
               case when f.home_team_id = p_team_id then m.titolari_home else m.titolari_away end as titolari,
               (m.id is not null and (exists (select 1 from public.match_reveals r where r.match_id = m.id and r.user_id = p_user)
                                      or m.simulata_il < now() - interval '24 hours')) as vista
        from public.fixtures f left join public.matches m on m.fixture_id = f.id
        where f.id = any(v_c.fixture_ids)
      )
      select count(*) filter (where match_id is not null), count(*) filter (where vista), count(*),
             count(*) filter (where vista and (gf > gs or (gf = gs and rf is not null and rf > rs))),
             count(*) filter (where vista and (gf < gs or (gf = gs and rf is not null and rf < rs))),
             coalesce(sum(gf) filter (where vista), 0), coalesce(sum(gs) filter (where vista), 0)
        into v_giocate, v_viste, v_totali, v_vinte, v_perse, v_gf, v_gs
      from w;
      -- Una partita giocata ma non ancora vista: si aspetta, per non svelare il risultato.
      if v_giocate > v_viste then continue; end if;

      if v_c.tipo in ('vinci_prossima', 'vinci_3_su_5') then
        v_x := case when v_c.tipo = 'vinci_prossima' then 1 else (v_c.parametri->>'vittorie')::int end;
        v_prog := jsonb_build_object('fatto', v_vinte, 'di', v_x);
        v_esito := case when v_vinte >= v_x then 'completata' when v_vinte + (v_totali - v_viste) < v_x then 'fallita' end;
      elsif v_c.tipo = 'porta_inviolata' then
        v_esito := case when v_viste = v_totali then case when v_gs = 0 then 'completata' else 'fallita' end end;
      elsif v_c.tipo = 'segna_x' then
        v_prog := jsonb_build_object('fatto', v_gf, 'di', (v_c.parametri->>'gol')::int);
        v_esito := case when v_gf >= (v_c.parametri->>'gol')::int then 'completata' when v_viste = v_totali then 'fallita' end;
      elsif v_c.tipo = 'under21' then
        if v_viste = v_totali then
          v_esito := case when exists (
            select 1 from public.fixtures f join public.matches m on m.fixture_id = f.id
            cross join lateral unnest(case when f.home_team_id = p_team_id then m.titolari_home else m.titolari_away end) t(id)
            join public.player_instances pi on pi.id = t.id
            where f.id = any(v_c.fixture_ids) and pi.eta_corrente < 21) then 'completata' else 'fallita' end;
        end if;
      elsif v_c.tipo = 'vinci_trasferta' then
        select count(*) into v_x from public.fixtures f join public.matches m on m.fixture_id = f.id
        where f.id = any(v_c.fixture_ids) and f.away_team_id = p_team_id
          and (m.gol_away > m.gol_home or (m.gol_away = m.gol_home and m.rigori_away > m.rigori_home));
        v_esito := case when v_x > 0 then 'completata' when v_viste = v_totali then 'fallita' end;
      elsif v_c.tipo = 'vinci_derby' then
        -- La finestra finisce col derby: conta l'ultima partita.
        if v_viste = v_totali then
          select case when (case when f.home_team_id = p_team_id then m.gol_home - m.gol_away else m.gol_away - m.gol_home end) > 0
                        or (m.gol_home = m.gol_away and coalesce(case when f.home_team_id = p_team_id then m.rigori_home - m.rigori_away else m.rigori_away - m.rigori_home end, 0) > 0)
                      then 'completata' else 'fallita' end into v_esito
          from public.fixtures f join public.matches m on m.fixture_id = f.id
          where f.id = v_c.fixture_ids[cardinality(v_c.fixture_ids)];
        end if;
      elsif v_c.tipo = 'gol_capitano' then
        select coalesce(sum(ms.gol), 0) into v_x from public.match_stats ms join public.matches m on m.id = ms.match_id
        where m.fixture_id = any(v_c.fixture_ids) and ms.player_instance_id = (v_c.parametri->>'capitano')::bigint;
        v_esito := case when v_x > 0 then 'completata' when v_viste = v_totali then 'fallita' end;
      elsif v_c.tipo = 'imbattuto' then
        v_prog := jsonb_build_object('fatto', v_viste - v_perse, 'di', v_totali);
        v_esito := case when v_perse > 0 then 'fallita' when v_viste = v_totali then 'completata' end;
      elsif v_c.tipo = 'gol_fatti' then
        v_prog := jsonb_build_object('fatto', v_gf, 'di', (v_c.parametri->>'gol')::int);
        v_esito := case when v_gf >= (v_c.parametri->>'gol')::int then 'completata' when v_viste = v_totali then 'fallita' end;
      elsif v_c.tipo = 'gol_subiti' then
        v_prog := jsonb_build_object('fatto', v_gs, 'di', (v_c.parametri->>'gol')::int);
        v_esito := case when v_gs > (v_c.parametri->>'gol')::int then 'fallita' when v_viste = v_totali then 'completata' end;
      elsif v_c.tipo = 'bomber' then
        select coalesce(max(g), 0) into v_x from (
          select sum(ms.gol) g from public.match_stats ms join public.matches m on m.id = ms.match_id
          where m.fixture_id = any(v_c.fixture_ids) and ms.team_id = p_team_id group by ms.player_instance_id) x;
        v_prog := jsonb_build_object('fatto', v_x, 'di', 5);
        v_esito := case when v_x >= 5 then 'completata' when v_viste = v_totali then 'fallita' end;
      elsif v_c.tipo = 'maglia' then
        select count(*) into v_x from public.fixtures f join public.matches m on m.fixture_id = f.id
        where f.id = any(v_c.fixture_ids) and f.home_team_id = p_team_id
          and (m.gol_home > m.gol_away or (m.gol_home = m.gol_away and m.rigori_home > m.rigori_away));
        v_prog := jsonb_build_object('fatto', v_x, 'di', 4);
        v_esito := case when v_x >= 4 then 'completata'
                        when v_x + (select count(*) from public.fixtures f where f.id = any(v_c.fixture_ids) and f.home_team_id = p_team_id and f.stato <> 'simulata') < 4 then 'fallita' end;
      elsif v_c.tipo = 'classifica' then
        if v_viste = v_totali then
          select case when st.posizione <= (v_c.parametri->>'posizione')::int then 'completata' else 'fallita' end into v_esito
          from public.standings st
          join public.seasons s on s.id = st.season_id
          join public.leagues l on l.id = s.league_id and s.numero = l.stagione_corrente
          where st.team_id = p_team_id;
        end if;
      elsif v_c.tipo = 'tifo' then
        select pubblico into v_x from public.teams where id = p_team_id;
        v_prog := jsonb_build_object('fatto', v_x, 'di', (v_c.parametri->>'tifo')::int);
        v_esito := case when v_x >= (v_c.parametri->>'tifo')::int then 'completata' when v_viste = v_totali then 'fallita' end;
      end if;
    end if;

    if v_esito is null then
      update public.sponsor_contratti set progresso = v_prog where id = v_c.id;
      continue;
    end if;
    update public.sponsor_contratti set stato = v_esito, progresso = v_prog, chiusa_il = now() where id = v_c.id;
    if v_esito = 'completata' then
      perform private.casino_saldo(v_c.league_id, p_user);
      update public.casino_saldi set crediti = crediti + v_c.premio, aggiornato_il = now()
      where league_id = v_c.league_id and user_id = p_user;
      if v_c.effetto_tifo <> 0 then
        update public.teams set pubblico = greatest(0, least(100, pubblico + v_c.effetto_tifo)) where id = p_team_id;
      end if;
      perform private.notifica(p_user, v_c.league_id, 'sistema', left(v_c.azienda || ': obiettivo raggiunto', 80),
        v_c.titolo || ' completato: +' || v_c.premio || ' crediti.', jsonb_build_object('view', 'sponsor'));
    end if;
  end loop;
end;
$$;
revoke all on function private.sponsor_valuta(bigint, uuid) from public, anon, authenticated;

create or replace function private.sponsor_attivi(p_league_id bigint)
returns boolean
language sql
stable
set search_path to ''
as $$
  select exists (select 1 from public.leagues l where l.id = p_league_id and l.conferenze_stampa and l.stadio_attivo
                 and l.stato = 'stagione' and l.fase_carriera = 'normale')
$$;
revoke all on function private.sponsor_attivi(bigint) from public, anon, authenticated;

-- La pagina Sponsor: valuta i contratti, rinnova le offerte scadute e restituisce tutto.
create or replace function public.sponsor_stato(p_league_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_team public.teams;
  v_prossima smallint;
  v_cat text;
  v_attivi boolean := private.sponsor_attivi(p_league_id);
begin
  select * into v_team from public.teams where league_id = p_league_id and user_id = v_utente and attiva;
  if v_team.id is null then raise exception using errcode = '42501', message = 'Non hai una squadra in questa lega.'; end if;
  perform pg_advisory_xact_lock(hashtext('sponsor'), v_team.id::int);
  perform private.sponsor_valuta(v_team.id, v_utente);
  if v_attivi then
    v_prossima := private.prossima_giornata_lega(p_league_id);
    -- Le offerte valgono fino alla prossima giornata: poi si rifanno sulla situazione nuova.
    update public.sponsor_contratti set stato = 'scartata', chiusa_il = now()
    where team_id = v_team.id and stato = 'offerta' and giornata_offerta < v_prossima;
    foreach v_cat in array array['breve', 'lungo'] loop
      if not exists (select 1 from public.sponsor_contratti where team_id = v_team.id and categoria = v_cat and stato in ('offerta', 'attiva'))
         and not exists (select 1 from public.sponsor_contratti where team_id = v_team.id and categoria = v_cat and stato = 'rinunciata'
                           and chiusa_il > now() - interval '24 hours') then
        perform private.sponsor_genera(v_team.id, v_cat);
      end if;
    end loop;
  end if;
  return jsonb_build_object(
    'attivi', v_attivi,
    'contratti', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'categoria', c.categoria, 'tipo', c.tipo, 'titolo', c.titolo, 'descrizione', c.descrizione,
        'premio', c.premio, 'effetto_tifo', c.effetto_tifo, 'partite', c.partite, 'stato', c.stato, 'progresso', c.progresso,
        'scelta_il', c.scelta_il, 'chiusa_il', c.chiusa_il,
        'azienda', jsonb_build_object('nome', a.nome, 'slug', a.slug, 'colore', a.colore))
        order by c.id desc)
      from public.sponsor_contratti c join public.sponsor_aziende a on a.id = c.azienda_id
      where c.team_id = v_team.id and (c.stato in ('offerta', 'attiva') or (c.stato in ('completata', 'fallita', 'rinunciata') and c.chiusa_il > now() - interval '14 days'))), '[]'::jsonb),
    'pausa', (select jsonb_object_agg(c.categoria, c.chiusa_il + interval '24 hours') from public.sponsor_contratti c
              where c.team_id = v_team.id and c.stato = 'rinunciata' and c.chiusa_il > now() - interval '24 hours'),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end;
$$;
revoke all on function public.sponsor_stato(bigint) from public;
grant execute on function public.sponsor_stato(bigint) to authenticated, service_role;

create or replace function public.sponsor_scegli(p_contratto_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  v_c public.sponsor_contratti;
  v_ids bigint[];
begin
  select * into v_c from public.sponsor_contratti where id = p_contratto_id for update;
  if v_c.id is null or not (select private.e_mia_squadra(v_c.team_id)) then
    raise exception using errcode = '42501', message = 'Offerta non trovata.';
  end if;
  if v_c.stato <> 'offerta' then raise exception using errcode = '55000', message = 'Questa offerta non è più disponibile.'; end if;
  if not private.sponsor_attivi(v_c.league_id) then raise exception using errcode = '55000', message = 'Gli sponsor non sono attivi adesso.'; end if;
  if v_c.giornata_offerta < private.prossima_giornata_lega(v_c.league_id) then
    raise exception using errcode = '55000', message = 'L''offerta è scaduta: riapri la pagina per vedere quelle nuove.';
  end if;
  if exists (select 1 from public.sponsor_contratti where team_id = v_c.team_id and categoria = v_c.categoria and stato = 'attiva') then
    raise exception using errcode = '55000', message = 'Hai già un contratto attivo in questa categoria.';
  end if;
  select array_agg(fixture_id order by giornata, fixture_id) into v_ids from private.sponsor_prossime(v_c.team_id, v_c.partite);
  if coalesce(cardinality(v_ids), 0) < v_c.partite then
    raise exception using errcode = '55000', message = 'Non ci sono abbastanza partite davanti per questo contratto.';
  end if;
  update public.sponsor_contratti set stato = 'attiva', scelta_il = now(), fixture_ids = v_ids where id = v_c.id;
  update public.sponsor_contratti set stato = 'scartata', chiusa_il = now()
  where team_id = v_c.team_id and categoria = v_c.categoria and stato = 'offerta';
  return jsonb_build_object('id', v_c.id);
end;
$$;
revoke all on function public.sponsor_scegli(bigint) from public;
grant execute on function public.sponsor_scegli(bigint) to authenticated, service_role;

create or replace function public.sponsor_rinuncia(p_contratto_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare v_c public.sponsor_contratti;
begin
  select * into v_c from public.sponsor_contratti where id = p_contratto_id for update;
  if v_c.id is null or not (select private.e_mia_squadra(v_c.team_id)) then
    raise exception using errcode = '42501', message = 'Contratto non trovato.';
  end if;
  if v_c.stato <> 'attiva' then raise exception using errcode = '55000', message = 'Questo contratto non è attivo.'; end if;
  update public.sponsor_contratti set stato = 'rinunciata', chiusa_il = now() where id = v_c.id;
  return jsonb_build_object('id', v_c.id);
end;
$$;
revoke all on function public.sponsor_rinuncia(bigint) from public;
grant execute on function public.sponsor_rinuncia(bigint) to authenticated, service_role;
