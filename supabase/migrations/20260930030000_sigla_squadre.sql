-- ============================================================
--  SIGLA DELLE SQUADRE (3 lettere, unica nella lega)
--
--  Serve dove il nome intero non ci sta (intestazione del reveal su
--  telefono) al posto dei puntini. Si calcola da sola, nessuno la sceglie:
--    1. lettere del nome in maiuscolo, accenti tolti, senza prefissi di
--       forma societaria (FC, AC, AS, SS, US, ASD, SSD) quando il nome ha
--       anche altre parole: "FC Rocazz" -> ROC, non FCR;
--    2. la sigla e' la prima lettera piu' le due successive (COC);
--    3. se nella lega e' gia' presa, si prova la prima lettera con ogni altra
--       coppia di lettere del nome, in ordine (Cocciaspigola -> COI);
--    4. ultima riserva: prime due lettere + una cifra.
--  Chi c'era prima tiene la sigla "naturale". Si ricalcola se la squadra
--  cambia nome. Il vincolo unique e' la garanzia vera; la funzione evita
--  solo di sbatterci contro.
-- ============================================================

alter table public.teams add column if not exists sigla text;

create or replace function private.lettere_sigla(p_nome text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_parole text[];
  v_tenute text[] := '{}';
  v_parola text;
begin
  v_parole := regexp_split_to_array(
    upper(translate(coalesce(p_nome, ''),
      'àáâãäåèéêëìíîïòóôõöùúûüñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÑÇ',
      'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC')),
    '[^A-Z0-9]+');
  foreach v_parola in array v_parole loop
    v_parola := regexp_replace(v_parola, '[^A-Z]', '', 'g');
    if v_parola <> '' then v_tenute := v_tenute || v_parola; end if;
  end loop;
  if cardinality(v_tenute) > 1 then
    v_tenute := array(select p from unnest(v_tenute) p
                      where p not in ('FC', 'AC', 'AS', 'SS', 'US', 'ASD', 'SSD'));
    if cardinality(v_tenute) = 0 then
      v_tenute := regexp_split_to_array(regexp_replace(upper(p_nome), '[^A-Z]+', ' ', 'g'), ' ');
    end if;
  end if;
  -- rpad tronca oltre la lunghezza data: si usa solo per allungare i nomi corti.
  return case when length(array_to_string(v_tenute, '')) < 3 then rpad(array_to_string(v_tenute, ''), 3, 'X') else array_to_string(v_tenute, '') end;
end;
$$;

create or replace function private.genera_sigla(p_league_id bigint, p_nome text, p_team_id bigint)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_l text := private.lettere_sigla(p_nome);
  v_n integer := length(v_l);
  v_i integer;
  v_j integer;
  v_c text;
begin
  for v_i in 2..v_n - 1 loop
    for v_j in v_i + 1..v_n loop
      v_c := substr(v_l, 1, 1) || substr(v_l, v_i, 1) || substr(v_l, v_j, 1);
      if not exists (select 1 from public.teams t
                     where t.league_id = p_league_id and t.sigla = v_c
                       and t.id is distinct from p_team_id) then
        return v_c;
      end if;
    end loop;
  end loop;
  for v_i in 2..9 loop
    v_c := substr(v_l, 1, 2) || v_i::text;
    if not exists (select 1 from public.teams t
                   where t.league_id = p_league_id and t.sigla = v_c
                     and t.id is distinct from p_team_id) then
      return v_c;
    end if;
  end loop;
  raise exception 'Nessuna sigla libera per %', p_nome;
end;
$$;

create or replace function private.imposta_sigla_squadra()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.nome is distinct from old.nome or new.sigla is null then
    new.sigla := private.genera_sigla(new.league_id, new.nome, new.id);
  end if;
  return new;
end;
$$;

-- Le squadre esistenti, dalla piu' vecchia: chi c'era prima tiene la sigla
-- naturale.
do $$
declare
  v_t record;
begin
  update public.teams set sigla = null;
  for v_t in select id, league_id, nome from public.teams order by league_id, creata_il, id loop
    update public.teams set sigla = private.genera_sigla(v_t.league_id, v_t.nome, v_t.id) where id = v_t.id;
  end loop;
end;
$$;

alter table public.teams alter column sigla set not null;
alter table public.teams add constraint teams_sigla_unica_per_lega unique (league_id, sigla);

drop trigger if exists teams_sigla on public.teams;
create trigger teams_sigla
  before insert or update of nome, sigla on public.teams
  for each row execute function private.imposta_sigla_squadra();

comment on column public.teams.sigla is
  'Sigla di 3 caratteri, unica nella lega, calcolata da private.genera_sigla (trigger teams_sigla). Si usa dove il nome intero non ci sta.';
