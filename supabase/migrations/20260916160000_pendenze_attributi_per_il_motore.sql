-- ============================================================
--  LE PENDENZE DEGLI ATTRIBUTI, LEGGIBILI DALL'EDGE FUNCTION
--
--  private.pendenze_attributi (20260916140000) dice quanto ogni attributo
--  cresce per punto di overall, per reparto. La simulazione notturna deve
--  leggerla per far crescere anche i cinque attributi che il motore usa —
--  stamina, finishing, short_passing, standing_tackle, dribbling — che finora
--  restavano quelli dell'importazione.
--
--  PostgREST non espone lo schema private, quindi serve un varco pubblico.
--  Stesso schema gia' usato per moltiplicatori_infortuni_squadre: una funzione
--  security definer, tolta a chiunque non sia il ruolo di servizio. Un
--  partecipante non ha motivo di leggere la tabella delle pendenze, e da qui
--  non la legge.
-- ============================================================

create or replace function public.pendenze_attributi()
returns table (reparto text, attributo text, pendenza numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select p.reparto, p.attributo, p.pendenza from private.pendenze_attributi p
$$;

revoke all on function public.pendenze_attributi() from public, anon, authenticated;
grant execute on function public.pendenze_attributi() to service_role;
