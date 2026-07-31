-- Il FOR numerico dichiara internamente la variabile di iterazione.
-- Rimuoviamo la dichiarazione duplicata segnalata da plpgsql_check.
create or replace function private.genera_codice_invito()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_codice text := '';
begin
  v_bytes := extensions.gen_random_bytes(6);
  for i in 0..5 loop
    v_codice := v_codice || substr(
      v_alfabeto,
      (get_byte(v_bytes, i) % length(v_alfabeto)) + 1,
      1
    );
  end loop;
  return v_codice;
end;
$$;

revoke all on function private.genera_codice_invito() from public, anon, authenticated;
grant execute on function private.genera_codice_invito() to service_role;
