-- ============================================================
--  FASCIA DI POTENZIALE: NON CENTRATA SUL VALORE VERO, E MAI
--  INVIATA AL CLIENT COME NUMERO GREZZO.
--
--  Segnalato dall'utente il 2 settembre 2026: TeamProfile.tsx calcolava
--  meta/alta come g.potential -/+ ampiezza/2, quindi il valore vero era
--  sempre la MEDIA esatta dei due estremi mostrati — bastava fare
--  (min+max)/2 per scoprirlo, la fascia non nascondeva nulla.
--
--  Due problemi distinti, entrambi da chiudere:
--
--  1) La fascia va spostata rispetto al valore vero (esempio dell'utente:
--     potenziale 80 -> fascia 68-83, non 72-88 o 73-88 centrate). Risolto
--     con private.fascia_potenziale: offset pseudo-casuale ma STABILE per
--     prospetto (seed sull'id, non su random() ricalcolato a ogni load —
--     altrimenti due utenti che guardano la stessa cantera, visibile a
--     tutta la lega, vedrebbero fasce diverse), fra il 20% e l'80%
--     dell'ampiezza cosi' il valore vero non cade mai proprio su un
--     estremo mostrato (che equivarrebbe comunque a rivelarlo).
--
--  2) Piu' a monte: TeamProfile.tsx e Under.tsx selezionavano
--     `potential` direttamente da public.players, che ha RLS aperta a
--     tutti gli utenti autenticati (corretta per il catalogo FC26, dove
--     potential non e' mai stato un segreto). Per i prospetti vivaio pero'
--     lo e': il numero vero arrivava comunque nel payload di rete, apribile
--     da chiunque con gli strumenti sviluppatore, a prescindere da come
--     veniva *mostrato* in pagina. Le nuove RPC restituiscono solo
--     potenziale_min/potenziale_max: il valore vero non lascia mai il
--     server per queste due schermate.
-- ============================================================

begin;

-- Offset deterministico sull'id del giocatore (hashtext, non random()):
-- stessa fascia per chiunque la guardi, stabile a ogni reload.
create function private.fascia_potenziale(p_id bigint, p_potential smallint, p_ampiezza smallint)
returns smallint[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p_ampiezza <= 0 then array[p_potential, p_potential]::smallint[]
    else (
      select array[v_min, v_min + p_ampiezza]::smallint[]
      from (
        select greatest(40, least(99 - p_ampiezza, round(
          p_potential - (0.2 + (abs(hashtext(p_id::text)) % 1000) / 1000.0 * 0.6) * p_ampiezza
        )))::int as v_min
      ) x
    )
  end
$$;

comment on function private.fascia_potenziale(bigint, smallint, smallint) is
  'Fascia mostrata per un potenziale nascosto: contiene sempre il valore vero, '
  'ma non centrata (altrimenti (min+max)/2 lo rivelerebbe). Seed sull''id, non '
  'su random(): la stessa fascia deve comparire a chiunque nella lega la guardi.';

-- Sostituisce, lato client, la select diretta di players(...,potential,...)
-- nella cantera di una squadra (TeamProfile "Prospetti in cantera"):
-- l'ampiezza dipende dal livello VIVAIO della squadra proprietaria, non di
-- chi guarda (stessa logica gia' in uso, solo spostata sul server).
create function public.fascia_potenziale_giocatori(p_player_ids bigint[], p_team_id bigint)
returns table (player_id bigint, potenziale_min smallint, potenziale_max smallint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_league_id bigint;
  v_ampiezza smallint;
begin
  select league_id into v_league_id from public.teams where id = p_team_id;
  if v_league_id is null or not (select private.e_membro(v_league_id)) then
    raise exception using errcode = '42501', message = 'Non fai parte di questa lega.';
  end if;

  select (private.effetti_ramo('vivaio', coalesce(r.livello_vivaio, 0)::smallint)->>'ampiezza_range')::smallint
  into v_ampiezza
  from public.team_risorse r where r.team_id = p_team_id;
  v_ampiezza := coalesce(v_ampiezza, 15);

  return query
  select p.id, f[1], f[2]
  from public.players p
  cross join lateral (select private.fascia_potenziale(p.id, p.potential, v_ampiezza) as f) x
  where p.id = any(p_player_ids);
end;
$$;

comment on function public.fascia_potenziale_giocatori(bigint[], bigint) is
  'Fasce di potenziale per una lista di giocatori (vivaio), calcolate secondo '
  'il livello VIVAIO di p_team_id. Non restituisce mai il potenziale vero.';

grant execute on function public.fascia_potenziale_giocatori(bigint[], bigint) to authenticated;

commit;
