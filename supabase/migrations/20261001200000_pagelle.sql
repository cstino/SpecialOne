-- ============================================================
--  PAGELLE — il voto di ogni giocatore in ogni partita
--
--  Registro tattico, punto 31. Il voto (1-10, stile SofaScore) nasce dalle
--  azioni riuscite e sbagliate di ognuno: lo calcola engine/pagelle.js nella
--  Edge Function, dopo la partita e con un seme suo, e lo scrive qui.
--
--  Tabella a parte e non una colonna di match_stats: match_stats la scrive
--  registra_risultato_partita, che e' grande e viene toccata spesso su main;
--  le pagelle si aggiungono senza cambiarla.
--
--  voto NULL = "senza voto" (meno di 15 minuti in campo). Il migliore in campo
--  e' il voto piu' alto della partita: si salva come flag per non ricalcolarlo
--  in ogni pagina.
-- ============================================================

create table public.pagelle (
  id                 bigint generated always as identity primary key,
  match_id           bigint not null references public.matches(id) on delete cascade,
  league_id          bigint not null references public.leagues(id) on delete cascade,
  team_id            bigint not null references public.teams(id) on delete cascade,
  player_instance_id bigint not null references public.player_instances(id) on delete cascade,
  voto               numeric(3,1) check (voto is null or voto between 1 and 10),
  migliore_in_campo  boolean not null default false,
  -- Le azioni da cui nasce il voto (passaggi, interventi, dribbling, parate...):
  -- servono a spiegarlo nella pagina partita.
  dettaglio          jsonb,
  unique (match_id, player_instance_id)
);

create index pagelle_giocatore on public.pagelle (league_id, player_instance_id);

comment on table public.pagelle is
  'Voto 1-10 di ogni giocatore in ogni partita, calcolato da engine/pagelle.js. NULL = meno di 15 minuti.';

alter table public.pagelle enable row level security;

-- Stessa regola di match_stats: le vedono i membri della lega. Una pagella
-- esiste solo dopo la partita, quindi non anticipa niente.
create policy pagelle_lettura on public.pagelle
  for select to authenticated
  using ((select private.e_membro(pagelle.league_id)));

revoke all on public.pagelle from anon, authenticated;
grant select on public.pagelle to authenticated;
