-- Per ora il collegamento degli occhiali e' solo per il proprietario del gioco (account amministratore).
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
  if (select email from auth.users where id = v_user) <> 'cr.96bc@gmail.com' then
    raise exception using errcode = '42501', message = 'Il collegamento degli occhiali non e'' disponibile.';
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
