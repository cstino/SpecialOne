-- Collegamento degli occhiali Ray-Ban Display: sugli occhiali i campi password non esistono, quindi il login
-- passa da un codice di 6 cifre creato dal telefono (valido 10 minuti, usabile una volta). La funzione
-- collega-occhiali (Edge Function) consuma il codice e restituisce un accesso per quell'utente.
create table if not exists private.codici_occhiali (
  codice text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  scade_il timestamptz not null
);

create or replace function public.crea_codice_occhiali()
 returns text language plpgsql volatile security definer set search_path to ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_codice text;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'Devi accedere prima di collegare gli occhiali.';
  end if;
  delete from private.codici_occhiali where user_id = v_user or scade_il < now();
  loop
    v_codice := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from private.codici_occhiali where codice = v_codice);
  end loop;
  insert into private.codici_occhiali (codice, user_id, scade_il) values (v_codice, v_user, now() + interval '10 minutes');
  return v_codice;
end;
$function$;
revoke all on function public.crea_codice_occhiali() from public;
grant execute on function public.crea_codice_occhiali() to authenticated;

-- Solo la Edge Function (chiave di servizio): consuma il codice e dice di quale utente era.
create or replace function public.usa_codice_occhiali(p_codice text)
 returns text language plpgsql volatile security definer set search_path to ''
as $function$
declare v_email text;
begin
  select u.email into v_email
  from private.codici_occhiali c join auth.users u on u.id = c.user_id
  where c.codice = trim(p_codice) and c.scade_il > now();
  delete from private.codici_occhiali where codice = trim(p_codice) or scade_il < now();
  return v_email;
end;
$function$;
revoke all on function public.usa_codice_occhiali(text) from public, anon, authenticated;
grant execute on function public.usa_codice_occhiali(text) to service_role;

-- Contro chi prova codici a caso: oltre 20 tentativi sbagliati in 10 minuti (in tutto) il collegamento si ferma
-- per qualche minuto. Con un gruppo di amici basta e avanza.
create table if not exists private.tentativi_occhiali (quando timestamptz not null default now());

create or replace function public.usa_codice_occhiali(p_codice text)
 returns text language plpgsql volatile security definer set search_path to ''
as $function$
declare v_email text;
begin
  delete from private.tentativi_occhiali where quando < now() - interval '10 minutes';
  if (select count(*) from private.tentativi_occhiali) >= 20 then
    return null;
  end if;
  select u.email into v_email
  from private.codici_occhiali c join auth.users u on u.id = c.user_id
  where c.codice = trim(p_codice) and c.scade_il > now();
  if v_email is null then
    insert into private.tentativi_occhiali default values;
  end if;
  delete from private.codici_occhiali where codice = trim(p_codice) or scade_il < now();
  return v_email;
end;
$function$;
revoke all on function public.usa_codice_occhiali(text) from public, anon, authenticated;
grant execute on function public.usa_codice_occhiali(text) to service_role;
