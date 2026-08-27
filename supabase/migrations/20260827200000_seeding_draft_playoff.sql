-- ============================================================
--  PLAYOFF A DOPPIO TABELLONE — passo 2a: seeding del Draft Playoff
--  docs/decisioni-draft-picks.md §1.2
--
--  Solo la funzione di seeding, isolata e testabile da sola. Non ancora
--  collegata a crea_tabelloni/avanza_bracket (che oggi generano il vecchio
--  Playoff/Playout, gia' live): il collegamento — Title Playoff al posto
--  di Playoff con soglia 8 fissa, Draft Playoff al posto di Playout con
--  QUESTA funzione al posto del seeding incrociato, niente piu' premio in
--  denaro — e' il prossimo passo.
-- ============================================================

-- ------------------------------------------------------------
--  A differenza di private.ordine_tabellone (seeding incrociato, usato dal
--  Title Playoff e dal vecchio Playout), il Draft Playoff accoppia le
--  squadre ADIACENTI in classifica: 9a-10a, 11a-12a, non 9a-12a e 10a-11a.
--  Le due peggiori (seed 1 e 2 nella numerazione qui sotto, cioe' le
--  ultime due assolute) passano direttamente alle semifinali.
--
--  Convenzione: il seed 1 e' la squadra CHE HA PIU' BISOGNO di un buon
--  piazzamento nel tabellone, cioe' l'ultima assoluta — stessa inversione
--  gia' usata per il vecchio Playout (docs/design.md §10.7): chi ha fatto
--  peggio ha il tabellone piu' comodo.
--
--  Ritorna un array di lunghezza posti (potenza di 2 >= p_squadre): gli
--  elementi si accoppiano a due a due nell'ORDINE in cui compaiono
--  (posizione 1-2, 3-4, ...). Zero significa bye: l'altro elemento della
--  coppia passa senza giocare. Verificato per M=6 (il caso reale di Real
--  Fampionato, 14 squadre): produce esattamente 1-0, 3-4, 2-0, 5-6, cioe'
--  bye a seed1, 3a vs 4a, bye a seed2, 5a vs 6a — con avanza_bracket
--  (che accoppia le tie consecutive del turno precedente) questo produce
--  seed1 vs vinc.(3-4) e seed2 vs vinc.(5-6) in semifinale, esattamente
--  come da §1.2: bye-peggiore vs vincitrice del match "centrale", bye-
--  seconda-peggiore vs vincitrice del match "esterno".
--
--  Per M diverso da 6 (leghe con un numero di squadre diverso da 14) la
--  regola si generalizza per estensione naturale — non e' stata
--  confermata dall'utente al di fuori del caso M=6, vedi
--  docs/decisioni-draft-picks.md §6.
-- ------------------------------------------------------------

create or replace function private.ordine_draft_playoff(p_squadre integer)
returns integer[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_posti integer := private.posti_tabellone(p_squadre);
  v_bye integer := v_posti - p_squadre;
  v_seed_bye integer := 1;
  v_seed_pari integer := v_bye + 1;
  v_risultato integer[] := array[]::integer[];
  v_bye_emessi integer := 0;
  v_pari_emessi integer := 0;
  v_totale_coppie integer := v_posti / 2;
begin
  if p_squadre < 2 then
    raise exception using errcode = '22023', message = 'Servono almeno 2 squadre per un tabellone.';
  end if;

  while v_bye_emessi + v_pari_emessi < v_totale_coppie loop
    if v_bye_emessi < v_bye then
      v_risultato := v_risultato || v_seed_bye || 0;
      v_seed_bye := v_seed_bye + 1;
      v_bye_emessi := v_bye_emessi + 1;
    end if;
    if v_pari_emessi * 2 < (p_squadre - v_bye) and v_bye_emessi + v_pari_emessi < v_totale_coppie then
      v_risultato := v_risultato || v_seed_pari || (v_seed_pari + 1);
      v_seed_pari := v_seed_pari + 2;
      v_pari_emessi := v_pari_emessi + 1;
    end if;
  end loop;

  return v_risultato;
end;
$$;

comment on function private.ordine_draft_playoff(integer) is
  'Seeding ad accoppiamento adiacente per il Draft Playoff (docs/decisioni-draft-picks.md §1.2): bye alle 2 squadre col seed peggiore, il resto appaiato in ordine. Diverso da private.ordine_tabellone (seeding incrociato).';
