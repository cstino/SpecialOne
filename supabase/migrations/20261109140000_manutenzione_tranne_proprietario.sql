-- Manutenzione: il proprietario (login cr.96bc@gmail.com) non vede la riga di stato_app, quindi la sua app non entra
-- mai in manutenzione e puo' provare il gioco mentre gli altri vedono la pagina "Server in manutenzione"
-- (richiesta del committente, 9/11/2026). Nessun cambio all'app: senza la riga, useManutenzione legge "spenta".
drop policy if exists stato_app_lettura on public.stato_app;
create policy stato_app_lettura on public.stato_app for select to anon, authenticated
  using (coalesce(auth.jwt() ->> 'email', '') <> 'cr.96bc@gmail.com');
