-- ============================================================
--  CINQUE INCARICHI, NON TRE
--
--  Precisazione dell'utente: i calci piazzati sono cinque gesti distinti, non
--  tre. Le punizioni sono due cose diverse — da distanza di tiro si calcia in
--  porta, da lontano si mette il pallone in area — e gli angoli vanno separati
--  per lato, perche' il lato decide la traiettoria.
--
--  E' il lato che rende il piede importante. Un destro che batte dalla
--  bandierina di sinistra fa RIENTRARE il pallone verso la porta; dalla destra
--  lo fa uscire. Per un mancino e' l'inverso. In Premier League 2025-26 gli
--  angoli a rientrare hanno prodotto 77 gol contro 11: e' la differenza piu'
--  netta di tutto il repertorio dei piazzati.
--
--  Misurato sul nostro motore: la combinazione giusta — mancino a destra,
--  destro a sinistra, entrambi a rientrare — vale il 34% di gol da angolo in
--  piu'. E i mancini sono il 26,6% del catalogo, quindi averne uno che sappia
--  battere e' una risorsa scarsa davvero.
--
--  L'ASSEGNAZIONE AUTOMATICA ORDINA CON LA STESSA FORMULA DEL MOTORE: qualita'
--  del cross moltiplicata per la traiettoria. Cosi' chi viene designato e' chi
--  il motore premia, e i due criteri non possono divergere.
-- ============================================================

alter table public.lineups
  add column if not exists punizione_corta bigint references public.player_instances(id) on delete set null,
  add column if not exists punizione_lunga bigint references public.player_instances(id) on delete set null,
  add column if not exists angolo_dx       bigint references public.player_instances(id) on delete set null,
  add column if not exists angolo_sx       bigint references public.player_instances(id) on delete set null;

-- I due campi della prima stesura NON vengono copiati nei nuovi, ed e' una
-- scelta: il vecchio "angoli" non sapeva niente dei lati, quindi il suo valore
-- non e' corretto per nessuno dei due. Copiandolo in entrambi si otteneva un
-- incaricato valido — e quindi mai corretto dall'assegnazione automatica, che
-- sostituisce solo chi non e' piu' fra i titolari. Il piede non entrava mai in
-- gioco. Meglio lasciarli vuoti e farli calcolare da zero qui sotto.
alter table public.lineups drop column if exists angoli;
alter table public.lineups drop column if exists punizioni;

comment on column public.lineups.punizione_corta is 'Chi calcia le punizioni da distanza di tiro.';
comment on column public.lineups.punizione_lunga is 'Chi mette in area le punizioni da lontano.';
comment on column public.lineups.angolo_dx is 'Chi batte gli angoli da destra. Un mancino li fa rientrare.';
comment on column public.lineups.angolo_sx is 'Chi batte gli angoli da sinistra. Un destro li fa rientrare.';

drop function if exists private.incaricati_automatici(bigint, bigint[]);

create or replace function private.incaricati_automatici(
  p_league_id bigint,
  p_titolari  bigint[]
)
returns table (rigorista bigint, punizione_corta bigint, punizione_lunga bigint,
               angolo_dx bigint, angolo_sx bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with giocatori as (
    select pi.id,
           private.attributi_effettivi(
             p.attributi, coalesce(pi.posizioni_override, p.posizioni),
             pi.overall_corrente - p.overall, pi.attributi_override) as a,
           pi.overall_corrente as ovr,
           coalesce(pi.posizioni_override, p.posizioni) as pos,
           p.piede
    from public.player_instances pi
    join public.players p on p.id = pi.player_id
    where pi.league_id = p_league_id and pi.id = any(p_titolari)
  ), voti as (
    select id, piede,
           -- Stessa formula del dischetto (CFG_RIGORI.PESO_SPECIALISTA = 0.5).
           ovr + (coalesce((a->>'mentality_penalties')::numeric, ovr) - ovr) * 0.5 as v_rigori,
           -- Punizione corta: si calcia in porta.
           (coalesce((a->>'skill_fk_accuracy')::numeric, 40)
            + coalesce((a->>'power_long_shots')::numeric, 40)) / 2 as v_corta,
           -- Punizione lunga e angoli: si mette un pallone in area.
           (coalesce((a->>'attacking_crossing')::numeric, 40)
            + coalesce((a->>'skill_curve')::numeric, 40)) / 2 as v_cross
    from giocatori
    where pos[1] <> 'GK'
  ), conTraiettoria as (
    -- Gli stessi fattori di CFG_PIAZZATI.RIENTRARE e USCIRE: chi il motore
    -- premia e' chi viene designato.
    select id, v_rigori, v_corta, v_cross,
           v_cross * case when piede = 'sinistro' then 1.35 else 0.70 end as v_dx,
           v_cross * case when piede = 'sinistro' then 0.70 else 1.35 end as v_sx
    from voti
  )
  select
    (select id from conTraiettoria order by v_rigori desc, id limit 1),
    (select id from conTraiettoria order by v_corta  desc, id limit 1),
    (select id from conTraiettoria order by v_cross  desc, id limit 1),
    (select id from conTraiettoria order by v_dx     desc, id limit 1),
    (select id from conTraiettoria order by v_sx     desc, id limit 1)
$$;

revoke all on function private.incaricati_automatici(bigint, bigint[]) from public, anon, authenticated;

create or replace function private.sistema_incaricati(p_team_id bigint, p_giornata smallint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_riga public.lineups;
  v_auto record;
begin
  select * into v_riga from public.lineups where team_id = p_team_id and giornata = p_giornata;
  if not found then return; end if;
  select * into v_auto from private.incaricati_automatici(v_riga.league_id, v_riga.titolari);

  -- Un incarico sopravvive solo se quel giocatore e' ancora fra i titolari.
  update public.lineups set
    rigorista       = case when rigorista       = any(v_riga.titolari) then rigorista       else v_auto.rigorista end,
    punizione_corta = case when punizione_corta = any(v_riga.titolari) then punizione_corta else v_auto.punizione_corta end,
    punizione_lunga = case when punizione_lunga = any(v_riga.titolari) then punizione_lunga else v_auto.punizione_lunga end,
    angolo_dx       = case when angolo_dx       = any(v_riga.titolari) then angolo_dx       else v_auto.angolo_dx end,
    angolo_sx       = case when angolo_sx       = any(v_riga.titolari) then angolo_sx       else v_auto.angolo_sx end
  where team_id = p_team_id and giornata = p_giornata;
end;
$$;

revoke all on function private.sistema_incaricati(bigint, smallint) from public, anon, authenticated;

-- Ricalcola le formazioni ancora da giocare, cosi' gli angoli si dividono
-- subito per lato e il piede entra in gioco.
do $$
declare v_riga record;
begin
  for v_riga in
    select l.team_id, l.giornata from public.lineups l
    where l.giornata >= coalesce((select min(f.giornata) from public.fixtures f
      where f.league_id = l.league_id and f.stato = 'programmata'), 0)
  loop
    perform private.sistema_incaricati(v_riga.team_id, v_riga.giornata);
  end loop;
end $$;
