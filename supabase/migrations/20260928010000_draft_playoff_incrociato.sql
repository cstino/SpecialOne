-- ============================================================
--  DRAFT PLAYOFF: SEEDING INCROCIATO, COME IL TITLE PLAYOFF
--
--  Sostituisce l'accoppiamento per posizioni adiacenti di
--  docs/decisioni-draft-picks.md §1.2 (9a-10a, 11a-12a, ...). Ora l'ultima
--  in classifica gioca contro la prima del gruppo, la penultima contro la
--  seconda e cosi' via: con 16 squadre il Draft Playoff e' di 8 (9a-16a) e
--  gli scontri sono 16a-9a, 15a-10a, 14a-11a, 13a-12a.
--
--  crea_tabelloni ordina gia' il gruppo al contrario (seed 1 = ultima
--  assoluta) e chiama private.ordine_draft_playoff(M): basta far restituire
--  a quella funzione l'ordine incrociato, senza toccare crea_tabelloni.
--  Con M non potenza di 2 (es. 14 squadre -> M=6) i seed mancanti sono bye,
--  come nel Title Playoff: 14a e 13a saltano il primo turno.
-- ============================================================

create or replace function private.ordine_draft_playoff(p_squadre integer)
returns integer[]
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_squadre < 2 then
    raise exception using errcode = '22023', message = 'Servono almeno 2 squadre per un tabellone.';
  end if;
  return private.ordine_tabellone(private.posti_tabellone(p_squadre));
end;
$$;

comment on function private.ordine_draft_playoff(integer) is
  'Seeding del Draft Playoff: incrociato come il Title Playoff (seed 1 = ultima in classifica contro la prima del gruppo). Sostituisce l''accoppiamento adiacente di docs/decisioni-draft-picks.md §1.2.';

-- ------------------------------------------------------------
--  Tabelloni Draft gia' generati e ancora fermi al primo turno, senza
--  nessuna partita giocata: si riaccoppiano sul posto. Il tabellone e'
--  ricostruito dai seed gia' scritti (seed -> squadra), quindi non serve
--  ricalcolare la classifica.
--
--  Le partite si cancellano tutte e si ricreano: aggiornarle una alla volta
--  farebbe scattare verifica_fixture_unica (una squadra due volte nella
--  stessa giornata) a meta' lavoro. Sono al sicuro perche' non ancora
--  giocate: l'unica tabella che le referenzia e' matches, che nasce alla
--  simulazione.
-- ------------------------------------------------------------
do $$
declare
  v_b record;
  v_ordine integer[];
  v_squadra_di_seed jsonb;
  v_n integer;
  v_posti integer;
  v_i integer;
  v_sa integer; v_sb integer;
  v_alta bigint; v_bassa bigint;
  v_tie record;
begin
  for v_b in
    select b.id from public.brackets b
    where b.tipo = 'draft' and b.stato = 'in_corso'
      and not exists (select 1 from public.bracket_ties t where t.bracket_id = b.id and t.turno > 1)
      and not exists (
        select 1 from public.bracket_ties t join public.fixtures f on f.bracket_tie_id = t.id
        where t.bracket_id = b.id and f.stato <> 'programmata')
  loop
    select jsonb_object_agg(s, sq), count(*) into v_squadra_di_seed, v_n
    from (
      select t.alta_seed as s, t.alta_team_id as sq from public.bracket_ties t
        where t.bracket_id = v_b.id and t.alta_seed is not null
      union all
      select t.bassa_seed, t.bassa_team_id from public.bracket_ties t
        where t.bracket_id = v_b.id and t.bassa_seed is not null
    ) x;

    v_ordine := private.ordine_draft_playoff(v_n);
    v_posti := private.posti_tabellone(v_n);
    if v_posti <> v_n then
      raise exception 'Tabellone % con bye: riaccoppiamento non supportato qui.', v_b.id;
    end if;

    create temporary table _giornate_tie on commit drop as
      select t.id as tie_id, t.posizione, min(f.giornata) as giornata
      from public.bracket_ties t join public.fixtures f on f.bracket_tie_id = t.id
      where t.bracket_id = v_b.id and t.turno = 1
      group by t.id, t.posizione;

    delete from public.fixtures
      where bracket_tie_id in (select tie_id from _giornate_tie);

    for v_i in 1..(v_posti / 2) loop
      v_sa := v_ordine[v_i * 2 - 1];
      v_sb := v_ordine[v_i * 2];
      v_alta := (v_squadra_di_seed ->> v_sa::text)::bigint;
      v_bassa := (v_squadra_di_seed ->> v_sb::text)::bigint;

      select * into v_tie from _giornate_tie where posizione = v_i - 1;

      update public.bracket_ties
        set alta_team_id = v_alta, bassa_team_id = v_bassa, alta_seed = v_sa, bassa_seed = v_sb
        where id = v_tie.tie_id;

      perform private.crea_fixtures_tie(v_tie.tie_id, v_tie.giornata);
    end loop;

    drop table _giornate_tie;
  end loop;
end;
$$;
