-- ============================================================
--  NOME SQUADRA: MASSIMO 22 CARATTERI, SOLO LETTERE, NUMERI, SPAZI E APOSTROFO
--  Richiesta del committente il 5 ottobre 2026: niente caratteri speciali
--  (@, ª, !, &, ...) ne' emoji; l'apostrofo (' e ’) e' ammesso.
--
--  Lettere: latine con accenti (A-Z, a-z, U+00C0-U+017E salvo × e ÷), cosi'
--  restano validi nomi come "Pérez" o "M’ARPZZC". Spazi iniziali, finali e
--  doppi vengono ripuliti prima del controllo.
--
--  Si applica agli inserimenti e a ogni cambio di nome (trigger, non CHECK:
--  un CHECK scatterebbe a ogni UPDATE della riga e bloccherebbe, ad esempio,
--  la sigla o le stelle di chi ha ancora un nome vecchio). I nomi gia'
--  esistenti non vengono toccati: valgono finche' il proprietario non li
--  cambia.
-- ============================================================

create or replace function private.valida_nome_squadra()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.nome is not distinct from old.nome then
    return new;
  end if;

  new.nome := regexp_replace(btrim(new.nome), '\s+', ' ', 'g');

  if char_length(new.nome) not between 2 and 22 then
    raise exception using errcode = '22023',
      message = 'Il nome della squadra deve avere da 2 a 22 caratteri, spazi compresi.';
  end if;
  if new.nome !~ '^[A-Za-zÀ-ÖØ-öø-ÿĀ-ž0-9 ''’]+$' then
    raise exception using errcode = '22023',
      message = 'Nel nome della squadra sono ammessi solo lettere, numeri, spazi e apostrofo: niente simboli ed emoji.';
  end if;
  return new;
end;
$$;

drop trigger if exists teams_valida_nome on public.teams;
create trigger teams_valida_nome
  before insert or update of nome on public.teams
  for each row execute function private.valida_nome_squadra();
