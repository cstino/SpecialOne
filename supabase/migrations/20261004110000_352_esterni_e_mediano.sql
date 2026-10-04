-- ============================================================
--  3-5-2: esterni di centrocampo e mediano, non piu' quinti LWB/RWB
--  Decisione del committente, 4 ottobre 2026 (registro tattico, punto 42)
--
--  DA APPLICARE AL LANCIO DELLA SEASON 2, insieme alla distribuzione di
--  simula-giornata dal ramo feat/tattiche: il motore e l'app del ramo hanno
--  gia' il 3-5-2 nuovo, quelli di main ancora il vecchio.
--
--  Prima: GK CB CB CB LWB CM CM CM RWB ST ST (sul campo identico al 5-3-2).
--  Ora:   GK CB CB CB LM  CM CDM CM RM  ST ST
--  Stesso ordine degli slot: i titolari restano allo stesso indice. Cambiano
--  lo slot 5 (LWB -> LM), il 7 (il CM centrale -> CDM) e il 9 (RWB -> RM),
--  contando da 1 come gli array di Postgres.
--
--  Motore validato dopo la modifica (tools/validazione/simulate.js e
--  simulate-reale.js): nessuna metrica uscita dal target, il 3-5-2 resta
--  equilibrato nel torneo fra moduli (1,379 punti/partita, prima 1,383).
--
--  Dati convertiti (al 4 ottobre: 3 righe di familiarita' e 6 formazioni,
--  tutte con la disposizione standard):
--  - disposizioni: LWB/LB -> LM, RWB/RB -> RM, slot 7 -> CDM (CAM -> CM, che
--    il CDM non puo' diventare); la familiarita' segue lo schieramento, e se
--    due vecchie disposizioni finiscono nella stessa si tiene la piu' alta;
--  - ruoli degli slot 5 e 9: erano ruoli da terzino, non validi per un
--    esterno di centrocampo, quindi tornano senza ruolo. Lo slot 7 tiene il
--    suo: CM e CDM hanno gli stessi ruoli.
-- ============================================================

begin;

-- 1. Il modulo standard.
create or replace function private.disposizione_standard(p_modulo text)
 returns text[]
 language sql
 immutable parallel safe
 set search_path to ''
as $function$
  select case p_modulo
    when '4-3-3' then array['GK','LB','CB','CB','RB','CM','CM','CM','LW','ST','RW']::text[]
    when '4-3-3 offensivo' then array['GK','LB','CB','CB','RB','CM','CM','CAM','LW','ST','RW']::text[]
    when '4-3-3 difensivo' then array['GK','LB','CB','CB','RB','CM','CM','CDM','LW','ST','RW']::text[]
    when '4-4-2' then array['GK','LB','CB','CB','RB','LM','CM','CM','RM','ST','ST']::text[]
    when '4-2-3-1' then array['GK','LB','CB','CB','RB','CDM','CDM','CAM','LW','RW','ST']::text[]
    when '3-5-2' then array['GK','CB','CB','CB','LM','CM','CDM','CM','RM','ST','ST']::text[]
    when '3-4-3' then array['GK','CB','CB','CB','LM','CM','CM','RM','LW','ST','RW']::text[]
    when '5-3-2' then array['GK','LB','CB','CB','CB','RB','CM','CM','CM','ST','ST']::text[]
    when '4-2-4' then array['GK','LB','CB','CB','RB','CM','CM','LW','ST','ST','RW']::text[]
    else null::text[]
  end
$function$;

-- 2. La copia della tabella dentro lo svincolo (sceglie il sostituto in
--    formazione): si corregge la sola riga del 3-5-2 sulla definizione VIVA,
--    senza ribatterla a mano.
do $$
declare
  v_def text := pg_get_functiondef('public.svincola_giocatore_cassa_legacy'::regproc);
  v_vecchia text := $v$when '3-5-2' then array['GK','CB','CB','CB','LWB','CM','CM','CM','RWB','ST','ST']$v$;
  v_nuova text := $v$when '3-5-2' then array['GK','CB','CB','CB','LM','CM','CDM','CM','RM','ST','ST']$v$;
begin
  if position(v_vecchia in v_def) = 0 then
    raise exception 'svincola_giocatore_cassa_legacy: riga del 3-5-2 non trovata, controllare a mano.';
  end if;
  execute replace(v_def, v_vecchia, v_nuova);
end;
$$;

-- 3. Conversione di una disposizione del vecchio 3-5-2 (funzione di servizio,
--    tolta alla fine).
create function private.tmp_converti_352(p text[])
 returns text[]
 language sql
 immutable
 set search_path to ''
as $$
  select case when p is null then null else
    p[1:4]
    || array[case when p[5] in ('LWB','LB') then 'LM' else coalesce(p[5], 'LM') end]
    || array[p[6]]
    || array[case when p[7] = 'CAM' then 'CM' when p[7] in ('LM','RM') then 'CM' else 'CDM' end]
    || array[p[8]]
    || array[case when p[9] in ('RWB','RB') then 'RM' else coalesce(p[9], 'RM') end]
    || p[10:11]
  end
$$;

-- Familiarita': si ricalcola la chiave, tenendo il massimo se due righe
-- finiscono sulla stessa disposizione.
create temporary table tmp_xp_352 on commit drop as
  select team_id, league_id, modulo, private.tmp_converti_352(disposizione) as disposizione,
         max(partite_giocate) as partite_giocate, max(aggiornata_il) as aggiornata_il
  from public.formation_xp
  where modulo = '3-5-2'
  group by 1, 2, 3, 4;
delete from public.formation_xp where modulo = '3-5-2';
insert into public.formation_xp (team_id, league_id, modulo, disposizione, partite_giocate, aggiornata_il)
  select team_id, league_id, modulo, disposizione, partite_giocate, aggiornata_il from tmp_xp_352;

-- Formazioni (una disposizione nulla resta nulla: vuol dire "standard").
update public.lineups
set disposizione = private.tmp_converti_352(disposizione),
    ruoli = case when ruoli is null then null else ruoli[1:4] || array[null::text] || ruoli[6:8] || array[null::text] || ruoli[10:11] end
where modulo = '3-5-2';

update public.moduli_personalizzati
set disposizione = private.tmp_converti_352(disposizione),
    ruoli = case when ruoli is null then null else ruoli[1:4] || array[null::text] || ruoli[6:8] || array[null::text] || ruoli[10:11] end
where modulo = '3-5-2';

update public.schemi_squadra
set riserva_disposizione = private.tmp_converti_352(riserva_disposizione),
    riserva_ruoli = case when riserva_ruoli is null then null else riserva_ruoli[1:4] || array[null::text] || riserva_ruoli[6:8] || array[null::text] || riserva_ruoli[10:11] end
where riserva_modulo = '3-5-2';

drop function private.tmp_converti_352(text[]);

commit;
