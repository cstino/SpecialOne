-- SlotOne: due minigiochi (24/10/2026, committente) — "Scegli lo stemma" e "Calcio di rigore".
--
-- Si attivano con 3 o piu' simboli uguali ovunque sui rulli (come le coppe): simbolo 11 = pallone (rigori), 12 = stemma
-- d'oro (scegli lo stemma). Ognuno parte in media 1 giro su 200 (insieme: circa 1 su 100). Tetto 500 volte la puntata.
-- L'esito lo estrae il SERVER al momento dello scatto e resta segreto (casino_slot_bonus.segreto, nessuna policy per i
-- client): l'app disegna e basta, come in CrazyOne. I crediti si pagano alla fine del minigioco; se uno se ne va, dopo
-- 3 minuti il server gioca da solo le mosse rimaste a caso e paga (cron ogni minuto, e comunque al primo accesso).
--
-- Matematica (docs/slotone-minigiochi.md): per tenere il ritorno al 97% in crediti si aggiungono due simboli (peso 159 su
-- 6.638, tutti i pesi in scala x10) e la scala dei pagamenti passa da 1,033 a 1,0947 (senza album 1,024 -> 1,0537).
--   Scegli lo stemma: 9 scudi, se ne scoprono 3, premio = somma dei valori x puntata (valori 1,2,3,5,10,25,100,250 con pesi
--     38,30,15,8,5,3,0.8,0.15), tetto 500x. Valore atteso 12,77x.
--   Calcio di rigore: 5 tiri, il primo parato chiude. Probabilita' di gol 78%,68%,58%,48%,38%; premio per gol segnati
--     0..5 = 1,2,4,8,25,120 x puntata. Valore atteso 11,91x.
-- Verificato con una simulazione di 4.000.000 di giri: ritorno 97,13% (modello esatto 97,00%).

create table public.casino_slot_bonus (
  id bigint generated always as identity primary key,
  league_id bigint not null references public.leagues (id) on delete cascade,
  user_id uuid not null,
  team_id bigint not null references public.teams (id) on delete cascade,
  giro_id bigint references public.casino_giri (id) on delete set null,
  tipo text not null check (tipo in ('stemma', 'rigori')),
  puntata integer not null,
  segreto jsonb not null,                       -- stemma: {"valori":[9 valori]}; rigori: {"gol":[5 booleani]}
  mosse jsonb not null default '[]'::jsonb,     -- stemma: [{"i":3,"v":5}]; rigori: [{"zona":1,"gol":true,"portiere":0}]
  stato text not null default 'aperto' check (stato in ('aperto', 'finito')),
  premio bigint,                                -- crediti pagati alla chiusura
  creato_il timestamptz not null default now(),
  scade_il timestamptz not null default now() + interval '3 minutes',
  finito_il timestamptz
);
create index casino_slot_bonus_aperti_idx on public.casino_slot_bonus (league_id, user_id) where stato = 'aperto';
create index casino_slot_bonus_scadenza_idx on public.casino_slot_bonus (scade_il) where stato = 'aperto';
alter table public.casino_slot_bonus enable row level security;
grant select on public.casino_slot_bonus to anon;
grant select, insert, update, delete on public.casino_slot_bonus to authenticated, service_role;

-- Estrae e salva un bonus appena scattato. Restituisce l'id.
create or replace function private.casino_bonus_crea(p_league_id bigint, p_user uuid, p_team bigint, p_giro bigint, p_tipo text, p_puntata integer)
 returns bigint language plpgsql volatile security definer set search_path to ''
as $function$
declare
  v_segreto jsonb; v_id bigint;
  c_val constant int[] := array[1, 2, 3, 5, 10, 25, 100, 250];
  c_peso constant numeric[] := array[38, 30, 15, 8, 5, 3, 0.8, 0.15];
  c_pg constant numeric[] := array[0.78, 0.68, 0.58, 0.48, 0.38];
  v_tot numeric; v_r numeric; v_c numeric; i int; j int; v_valori int[] := '{}'; v_gol boolean[] := '{}';
begin
  if p_tipo = 'stemma' then
    select sum(x) into v_tot from unnest(c_peso) x;
    for i in 1..9 loop
      v_r := random() * v_tot; v_c := 0;
      for j in 1..8 loop v_c := v_c + c_peso[j]; if v_r < v_c then v_valori := v_valori || c_val[j]; exit; end if; end loop;
    end loop;
    v_segreto := jsonb_build_object('valori', to_jsonb(v_valori));
  else
    for i in 1..5 loop v_gol := v_gol || (random() < c_pg[i]); end loop;
    v_segreto := jsonb_build_object('gol', to_jsonb(v_gol));
  end if;
  insert into public.casino_slot_bonus (league_id, user_id, team_id, giro_id, tipo, puntata, segreto)
  values (p_league_id, p_user, p_team, p_giro, p_tipo, p_puntata, v_segreto) returning id into v_id;
  return v_id;
end $function$;

-- Moltiplicatore finale (in multipli della puntata) di un bonus, dalle mosse fatte.
create or replace function private.casino_bonus_molt(p_tipo text, p_mosse jsonb)
 returns integer language sql immutable set search_path to ''
as $function$
  select case when p_tipo = 'stemma'
    then least(500, coalesce((select sum((m ->> 'v')::int) from jsonb_array_elements(p_mosse) m), 0))
    else (array[1, 2, 4, 8, 25, 120])[1 + coalesce((select count(*) from jsonb_array_elements(p_mosse) m where (m ->> 'gol')::boolean), 0)::int]
  end
$function$;

-- Gioca a caso le mosse rimaste (usato alla scadenza) e chiude.
create or replace function private.casino_bonus_chiudi(p_id bigint, p_completa boolean default false)
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
declare
  b public.casino_slot_bonus; v_molt int; v_premio bigint; v_vinto_giro bigint; v_team_nome text; v_i int; v_zona int; v_gol boolean; v_disp int[];
begin
  -- stesso ordine di blocchi ovunque: prima il saldo, poi il bonus
  perform 1 from public.casino_saldi s join public.casino_slot_bonus x on x.league_id = s.league_id and x.user_id = s.user_id where x.id = p_id for update of s;
  select * into b from public.casino_slot_bonus where id = p_id for update;
  if b.id is null or b.stato <> 'aperto' then return; end if;
  if p_completa then
    if b.tipo = 'stemma' then
      v_disp := array(select i from generate_series(0, 8) i where not exists (select 1 from jsonb_array_elements(b.mosse) m where (m ->> 'i')::int = i) order by random());
      while jsonb_array_length(b.mosse) < 3 loop
        v_i := v_disp[1]; v_disp := v_disp[2:];
        b.mosse := b.mosse || jsonb_build_object('i', v_i, 'v', (b.segreto -> 'valori' ->> v_i)::int);
      end loop;
    else
      loop
        exit when jsonb_array_length(b.mosse) >= 5 or exists (select 1 from jsonb_array_elements(b.mosse) m where not (m ->> 'gol')::boolean);
        v_i := jsonb_array_length(b.mosse); v_zona := floor(random() * 3)::int; v_gol := (b.segreto -> 'gol' ->> v_i)::boolean;
        b.mosse := b.mosse || jsonb_build_object('zona', v_zona, 'gol', v_gol,
                     'portiere', case when v_gol then (v_zona + 1 + floor(random() * 2)::int) % 3 else v_zona end);
      end loop;
    end if;
  end if;
  v_molt := private.casino_bonus_molt(b.tipo, b.mosse);
  v_premio := v_molt::bigint * b.puntata;
  update public.casino_slot_bonus set mosse = b.mosse, stato = 'finito', premio = v_premio, finito_il = now() where id = b.id;
  select coalesce(g.vinto, 0) + v_premio into v_vinto_giro from (select 0) z left join public.casino_giri g on g.id = b.giro_id;
  update public.casino_saldi set crediti = crediti + v_premio, totale_vinto = totale_vinto + v_premio,
         max_vincita = greatest(max_vincita, v_vinto_giro), aggiornato_il = now()
   where league_id = b.league_id and user_id = b.user_id;
  -- la vincita del giro (classifica, miglior colpo) comprende anche il minigioco
  update public.casino_giri set vinto = vinto + v_premio where id = b.giro_id;
  -- il colpo grosso (almeno 100 volte la puntata) finisce su SocialOne, una sola volta per giro
  if v_vinto_giro >= 100 * b.puntata then
    select nome into v_team_nome from public.teams where id = b.team_id;
    insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, testo, creato_il)
    values (b.league_id, 'casino:' || b.giro_id, 'lega', 'BetOne Casinò', b.team_id,
            '🎰 COLPO GROSSO al casinò! ' || v_team_nome || ' vince ' || to_char(v_vinto_giro, 'FM999G999G999') || ' crediti con un solo giro 🤑', now())
    on conflict do nothing;
  end if;
end $function$;

-- Chiude (giocando a caso) i bonus scaduti di un utente, o di tutti se p_user e' null.
create or replace function private.casino_bonus_scaduti(p_league_id bigint, p_user uuid)
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
declare r record;
begin
  for r in select id from public.casino_slot_bonus
            where stato = 'aperto' and scade_il < now() and (p_user is null or (league_id = p_league_id and user_id = p_user)) order by id loop
    perform private.casino_bonus_chiudi(r.id, true);
  end loop;
end $function$;

select cron.schedule('casino_slot_bonus', '* * * * *', 'select private.casino_bonus_scaduti(null, null);');

-- Stato del bonus aperto (quello che il giocatore puo' vedere: mai il segreto).
create or replace function private.casino_bonus_json(p_id bigint)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select jsonb_build_object(
    'id', b.id, 'tipo', b.tipo, 'puntata', b.puntata, 'finito', b.stato = 'finito',
    'scade', floor(extract(epoch from b.scade_il) * 1000),
    'mosse', b.mosse,
    'molt', private.casino_bonus_molt(b.tipo, b.mosse),
    'premio', b.premio,
    -- a bonus chiuso si vede anche il resto della tavola (gli scudi non scelti)
    'tavola', case when b.tipo = 'stemma' and b.stato = 'finito' then b.segreto -> 'valori' end)
  from public.casino_slot_bonus b where b.id = p_id
$function$;

-- Il bonus aperto dell'utente nella lega (o l'ultimo appena chiuso, se p_id lo indica).
create or replace function public.casino_slot_bonus_stato(p_league_id bigint)
 returns jsonb language plpgsql volatile security definer set search_path to ''
as $function$
declare v_utente uuid := (select auth.uid()); v_id bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  perform private.casino_saldo(p_league_id, v_utente);
  perform private.casino_bonus_scaduti(p_league_id, v_utente);
  select id into v_id from public.casino_slot_bonus where league_id = p_league_id and user_id = v_utente and stato = 'aperto' order by id limit 1;
  return jsonb_build_object('bonus', case when v_id is not null then private.casino_bonus_json(v_id) end,
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;

-- Una mossa: stemma = indice dello scudo (0..8); rigori = zona del tiro (0 sinistra, 1 centro, 2 destra).
create or replace function public.casino_slot_bonus_gioca(p_league_id bigint, p_bonus_id bigint, p_mossa integer)
 returns jsonb language plpgsql volatile security definer set search_path to ''
as $function$
declare
  v_utente uuid := (select auth.uid()); b public.casino_slot_bonus; v_n int; v_gol boolean; v_fine boolean := false;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Devi accedere.'; end if;
  perform private.casino_saldo(p_league_id, v_utente);          -- blocca il saldo (stesso ordine di tutti)
  select * into b from public.casino_slot_bonus where id = p_bonus_id and league_id = p_league_id and user_id = v_utente for update;
  if b.id is null then raise exception using errcode = '42501', message = 'Minigioco non trovato.'; end if;
  if b.stato <> 'aperto' then raise exception using errcode = '55000', message = 'Questo minigioco è già finito.'; end if;
  if now() > b.scade_il then
    perform private.casino_bonus_chiudi(b.id, true);
    return jsonb_build_object('bonus', private.casino_bonus_json(b.id), 'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
  end if;
  v_n := jsonb_array_length(b.mosse);
  if b.tipo = 'stemma' then
    if p_mossa is null or p_mossa not between 0 and 8 then raise exception using errcode = '22023', message = 'Scudo non valido.'; end if;
    if exists (select 1 from jsonb_array_elements(b.mosse) m where (m ->> 'i')::int = p_mossa) then raise exception using errcode = '22023', message = 'Hai già scelto questo scudo.'; end if;
    update public.casino_slot_bonus set mosse = b.mosse || jsonb_build_object('i', p_mossa, 'v', (b.segreto -> 'valori' ->> p_mossa)::int) where id = b.id;
    v_fine := v_n + 1 >= 3;
  else
    if p_mossa is null or p_mossa not between 0 and 2 then raise exception using errcode = '22023', message = 'Zona non valida.'; end if;
    v_gol := (b.segreto -> 'gol' ->> v_n)::boolean;
    update public.casino_slot_bonus set mosse = b.mosse || jsonb_build_object('zona', p_mossa, 'gol', v_gol,
        'portiere', case when v_gol then (p_mossa + 1 + floor(random() * 2)::int) % 3 else p_mossa end) where id = b.id;
    v_fine := (not v_gol) or v_n + 1 >= 5;
  end if;
  if v_fine then perform private.casino_bonus_chiudi(b.id); end if;
  return jsonb_build_object('bonus', private.casino_bonus_json(b.id),
    'crediti', (select crediti from public.casino_saldi where league_id = p_league_id and user_id = v_utente));
end $function$;

revoke all on function public.casino_slot_bonus_stato(bigint), public.casino_slot_bonus_gioca(bigint, bigint, integer) from public, anon;
grant execute on function public.casino_slot_bonus_stato(bigint), public.casino_slot_bonus_gioca(bigint, bigint, integer) to authenticated;
