-- Gli occhiali restano collegati finche' non li scolleghi dal telefono. Al collegamento gli occhiali registrano
-- la loro sessione (session_id del token); "Scollega occhiali" cancella quelle sessioni: entro un'ora al massimo
-- (scadenza del token in uso) gli occhiali tornano alla schermata del codice.
create table if not exists private.sessioni_occhiali (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  collegata_il timestamptz not null default now()
);

create or replace function public.registra_occhiali()
 returns void language plpgsql volatile security definer set search_path to ''
as $function$
declare v_sessione uuid := nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
begin
  if (select auth.uid()) is null or v_sessione is null then return; end if;
  insert into private.sessioni_occhiali (session_id, user_id) values (v_sessione, (select auth.uid()))
  on conflict (session_id) do nothing;
end;
$function$;
revoke all on function public.registra_occhiali() from public;
grant execute on function public.registra_occhiali() to authenticated;

create or replace function public.scollega_occhiali()
 returns integer language plpgsql volatile security definer set search_path to ''
as $function$
declare v_n integer;
begin
  if (select auth.uid()) is null then return 0; end if;
  delete from auth.sessions s using private.sessioni_occhiali o
  where o.user_id = (select auth.uid()) and s.id = o.session_id;
  get diagnostics v_n = row_count;
  delete from private.sessioni_occhiali where user_id = (select auth.uid());
  return v_n;
end;
$function$;
revoke all on function public.scollega_occhiali() from public;
grant execute on function public.scollega_occhiali() to authenticated;

create or replace function public.occhiali_collegati()
 returns integer language sql stable security definer set search_path to ''
as $function$
  select count(*)::int from private.sessioni_occhiali o join auth.sessions s on s.id = o.session_id
  where o.user_id = (select auth.uid());
$function$;
revoke all on function public.occhiali_collegati() from public;
grant execute on function public.occhiali_collegati() to authenticated;
