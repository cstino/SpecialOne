-- ============================================================
--  LA CHIUSURA DEL DRAFT NON DEVE DIPENDERE DALL'APERTURA DELLA OFF
--
--  Due difetti trovati alla prima prova in diretta su LegaBot, 13 settembre
--  2026, entrambi nel codice scritto poche ore prima.
--
--  1. IL FALLIMENTO DELL'APERTURA ANNULLAVA LA CHIUSURA.
--     avanza_draft_live chiudeva la finestra e apriva la OFF della stessa
--     stagione dentro un unico blocco BEGIN ... EXCEPTION. In PL/pgSQL un
--     blocco con gestore di eccezioni e' una sottotransazione: se qualcosa
--     solleva, TUTTO quello che il blocco aveva gia' fatto viene annullato.
--
--     svela_finestra_scelte(..., 'off') solleva in modo del tutto legittimo
--     — "le posizioni di questa finestra non sono ancora state assegnate",
--     perche' l'ordine di scelta della OFF dipende dalla classifica finale e a
--     meta' stagione non esiste ancora. Quel fallimento annullava pero' anche
--     l'update di risolta_il. Il giro dopo ritentava, falliva di nuovo, e la
--     finestra restava aperta all'infinito: su LegaBot l'ultima chiamata e'
--     avvenuta alle 11:24 e alle 11:26 la finestra risultava ancora in corso.
--
--     Ora la chiusura sta in private.chiudi_finestra_draft, e il tentativo di
--     aprire la OFF e' isolato in un blocco suo: puo' fallire quanto vuole
--     senza toccare la chiusura. Ci pensera' avanza_finestre_scelte ad aprirla
--     quando le posizioni esisteranno.
--
--     Stesso innesto nel ciclo di avanza_finestre_scelte, dove la risoluzione
--     dell'intera finestra correva lo stesso rischio: li' un fallimento
--     dell'apertura avrebbe annullato l'assegnazione di TUTTI i giocatori.
--
--  2. LA FINESTRA SI CHIUDEVA UN GIRO TROPPO TARDI.
--     Dopo l'ultima chiamata la funzione usciva, e solo al giro successivo si
--     accorgeva che non c'erano piu' scelte da fare. Per un minuto la pagina
--     del mercato a scelte continuava a mostrare come "ultima sessione" quella
--     precedente. Ora, se la chiamata appena fatta era l'ultima, la finestra si
--     chiude nello stesso giro.
-- ============================================================

-- ------------------------------------------------------------
--  Chiudere una finestra: due cose distinte, e la seconda non puo' far
--  fallire la prima.
-- ------------------------------------------------------------
create or replace function private.chiudi_finestra_draft(
  p_league_id bigint,
  p_stagione  smallint,
  p_finestra  text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.finestre_scelte set risolta_il = now()
  where league_id = p_league_id and stagione = p_stagione and finestra = p_finestra
    and risolta_il is null;

  -- L'apertura della OFF segue la chiusura della ON, ma e' un'operazione a
  -- se': dipende dall'ordine di scelta, che puo' non esistere ancora. Blocco
  -- separato apposta, cosi' un suo fallimento non annulla la chiusura qui
  -- sopra. Non e' un errore da segnalare all'utente: e' lo stato normale di
  -- una OFF a meta' stagione.
  if p_finestra = 'on' then
    begin
      if not exists (
        select 1 from public.finestre_scelte
        where league_id = p_league_id and stagione = p_stagione and finestra = 'off'
      ) then
        perform private.svela_finestra_scelte(p_league_id, p_stagione, 'off');
      end if;
    exception when others then
      raise warning 'mercato a scelte: OFF di lega % stagione % non ancora apribile: % (%)',
        p_league_id, p_stagione, sqlerrm, sqlstate;
    end;
  end if;
end;
$$;

revoke all on function private.chiudi_finestra_draft(bigint, smallint, text) from public, anon, authenticated;

-- ------------------------------------------------------------
--  Il draft in diretta: chiude subito e in sicurezza
-- ------------------------------------------------------------
create or replace function private.avanza_draft_live()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_f          record;
  v_chiamate   integer;
  v_prossima   bigint;
  v_dovuta_il  timestamptz;
  v_fatte      integer := 0;
  v_membro     record;
begin
  for v_f in
    select f.*
    from public.finestre_scelte f
    where f.risolta_il is null
      and f.finestra = 'on'
      and f.passo_secondi > 0
      and f.estrazione_il is not null
      and f.estrazione_il <= now()
    order by f.league_id, f.stagione
    for update
  loop
    begin
      -- Avvio. date_trunc al minuto aggancia le chiamate al minuto tondo: il
      -- cron gira al minuto, quindi ogni scelta cade con pochi secondi di
      -- ritardo invece di accumulare la latenza di un giro.
      if v_f.avviata_il is null then
        v_f.avviata_il := date_trunc('minute', now());
        update public.finestre_scelte set avviata_il = v_f.avviata_il
        where league_id = v_f.league_id and stagione = v_f.stagione and finestra = v_f.finestra;

        -- La diretta non serve a niente se nessuno sa che e' iniziata.
        for v_membro in
          select t.user_id from public.teams t
          where t.league_id = v_f.league_id and t.user_id is not null and t.attiva
        loop
          perform private.notifica(
            v_membro.user_id, v_f.league_id, 'mercato_esito',
            'On-Season Draft: si parte',
            'Le chiamate arrivano una ogni minuto. Apri l''app per seguirle in diretta.',
            jsonb_build_object('draft_live', true, 'stagione', v_f.stagione)
          );
        end loop;
      end if;

      select count(*) into v_chiamate
      from public.scelte_draft sd
      where sd.league_id = v_f.league_id and sd.stagione = v_f.stagione
        and sd.finestra = v_f.finestra and sd.stato in ('usata', 'vuota');

      select sd.id into v_prossima
      from public.scelte_draft sd
      where sd.league_id = v_f.league_id and sd.stagione = v_f.stagione
        and sd.finestra = v_f.finestra and sd.stato = 'determinata'
      order by sd.posizione
      limit 1;

      if v_prossima is null then
        perform private.chiudi_finestra_draft(v_f.league_id, v_f.stagione, v_f.finestra);
        continue;
      end if;

      v_dovuta_il := v_f.avviata_il + make_interval(secs => (v_chiamate * v_f.passo_secondi)::integer);
      if now() < v_dovuta_il then
        continue;  -- il turno di questa squadra non e' ancora arrivato
      end if;

      perform private.risolvi_una_scelta(v_prossima);
      v_fatte := v_fatte + 1;

      -- Se quella appena chiamata era l'ultima, la finestra si chiude adesso e
      -- non al giro dopo: per quel minuto di scarto la pagina del mercato
      -- continuava a indicare come ultima sessione conclusa quella precedente.
      if not exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = v_f.league_id and sd.stagione = v_f.stagione
          and sd.finestra = v_f.finestra and sd.stato = 'determinata'
      ) then
        perform private.chiudi_finestra_draft(v_f.league_id, v_f.stagione, v_f.finestra);
      end if;

    exception when others then
      raise warning 'draft live: lega % stagione %: % (%)',
        v_f.league_id, v_f.stagione, sqlerrm, sqlstate;
    end;
  end loop;

  return v_fatte;
end;
$$;

revoke all on function private.avanza_draft_live() from public, anon, authenticated;

-- ------------------------------------------------------------
--  Stesso innesto nel ciclo da 5 minuti.
--  Definizione ripresa dal database e modificata nel solo punto necessario.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.avanza_finestre_scelte()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lega record;
  v_giornata_mezza integer;
  v_data_mezza timestamptz;
  v_finestra record;
  v_risolte integer := 0;
begin
  -- Passaggio di recupero: leghe la cui stagione corrente e' iniziata
  -- PRIMA che questa automazione esistesse (es. LegaBot, stagione 2 gia'
  -- in corso al momento di questa migrazione). inizializza_stagione fa lo
  -- stesso lavoro alla nascita di ogni stagione successiva; qui si
  -- recupera solo chi e' rimasto indietro, ed e' innocuo ripeterlo:
  -- svela_finestra_scelte non ritocca una finestra gia' svelata.
  for v_lega in
    select l.id as league_id, l.stagione_corrente, s.id as season_id, s.giornate_totali
    from public.leagues l
    join public.seasons s on s.league_id = l.id and s.numero = l.stagione_corrente
    where l.stato = 'stagione' and l.fase_carriera = 'normale' and l.stagione_corrente >= 2
      and exists (
        select 1 from public.scelte_draft sd
        where sd.league_id = l.id and sd.stagione = l.stagione_corrente
          and sd.finestra = 'on' and sd.stato = 'determinata'
      )
      and not exists (
        select 1 from public.finestre_scelte f
        where f.league_id = l.id and f.stagione = l.stagione_corrente and f.finestra = 'on'
      )
  loop
    begin
      v_giornata_mezza := v_lega.giornate_totali / 2;
      select f.data_sim into v_data_mezza
      from public.fixtures f
      where f.season_id = v_lega.season_id and f.giornata = v_giornata_mezza and f.bracket_tie_id is null
      limit 1;
      if v_data_mezza is not null then
        perform private.svela_finestra_scelte(
          v_lega.league_id, v_lega.stagione_corrente, 'on', private.alle_13_roma(v_data_mezza)
        );
      end if;
    exception when others then
      raise warning 'mercato a scelte: recupero apertura ON-Season fallito per lega % stagione %: % (%)',
        v_lega.league_id, v_lega.stagione_corrente, sqlerrm, sqlstate;
    end;
  end loop;

  -- Preferenze PC su tutte le finestre ancora aperte, non solo quelle in
  -- scadenza: cosi' una squadra PC non resta "in attesa" per giorni.
  for v_finestra in
    select league_id, stagione, finestra from public.finestre_scelte where risolta_il is null
  loop
    begin
      perform private.preferenze_squadre_pc(v_finestra.league_id, v_finestra.stagione, v_finestra.finestra);
    exception when others then
      raise warning 'mercato a scelte: preferenze PC fallite per lega % stagione % finestra %: % (%)',
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, sqlerrm, sqlstate;
    end;
  end loop;

  -- Una finestra non deve sopravvivere alla propria stagione: se la lega e'
  -- gia' passata a quella dopo, la sua scadenza originale non ha piu' senso.
  --
  -- Il 9 settembre 2026 questo blocco la RISOLVEVA all'istante. Sbagliato, e
  -- si e' visto subito: la stessa esecuzione apriva la finestra OFF di
  -- recupero con due giorni di respiro, e il giro successivo (5 minuti dopo)
  -- la ritrovava "di stagione arretrata" e la chiudeva. In LegaBot le sette
  -- squadre PC hanno preso il loro giocatore — le preferenze PC sono
  -- generate in automatico — e l'unica squadra umana ha perso la scelta con
  -- zero preferenze, senza aver mai avuto la possibilita' di comporre la
  -- lista.
  --
  -- Ora la scadenza viene solo AVVICINATA a 48 ore da adesso, e la
  -- risoluzione resta al percorso normale piu' sotto. Cosi' nessuno perde
  -- una scelta per un cambio di calendario, e il promemoria delle 24 ore
  -- (private.promemoria_scelte_draft) fa in tempo a suonare. La condizione
  -- "> now() + 48 ore" rende l'aggiornamento una tantum: appena avvicinata,
  -- la finestra non rientra piu' nel filtro.
  update public.finestre_scelte f
  set estrazione_il = now() + interval '48 hours'
  from public.leagues l
  where l.id = f.league_id
    and f.risolta_il is null
    and f.estrazione_il is not null
    and f.stagione < l.stagione_corrente
    and f.estrazione_il > now() + interval '48 hours';

  -- Anche le finestre 'off', non piu' solo le 'on'. Prima l'unico modo di
  -- risolvere una OFF-Season era il pulsante dell'admin
  -- (admin_forza_estrazione_scelte): scaduta la sua ora restava aperta per
  -- sempre. Difetto preesistente, emerso guardando questo ciclo il 10
  -- settembre 2026. L'apertura della OFF resta legata alla chiusura della
  -- ON della stessa stagione, come prima.
  -- Il draft a passi (private.avanza_draft_live, ogni minuto) chiama una
  -- scelta alla volta perche' la lega la veda in diretta. Questo ciclo gira
  -- ogni 5 minuti e risolverebbe tutto in un colpo, bruciando la diretta:
  -- quindi salta le finestre ON affidate al draft live finche' e' nei tempi.
  --
  -- Resta pero' la RETE DI SICUREZZA, ed e' il motivo per cui la condizione e'
  -- scritta cosi'. Se il draft live non partisse o si piantasse, dopo il tempo
  -- che gli serve piu' dieci passi di grazia questo ciclo riprende il comando e
  -- risolve ugualmente la finestra. Nessuno perde una scelta perche' una
  -- macchina nuova si e' rotta: al peggio il draft avviene in ritardo e tutto
  -- insieme, come prima di oggi. L'ancora e' coalesce(avviata_il,
  -- estrazione_il): se il draft live non e' mai partito si misura dall'ora di
  -- estrazione, altrimenti il termine non scadrebbe mai.
  for v_finestra in
    select f.league_id, f.stagione, f.finestra
    from public.finestre_scelte f
    where f.risolta_il is null
      and f.estrazione_il is not null and f.estrazione_il <= now()
      and not (
        f.finestra = 'on'
        and f.passo_secondi > 0
        and now() < coalesce(f.avviata_il, f.estrazione_il) + make_interval(secs =>
              f.passo_secondi * (10 + (
                select count(*) from public.scelte_draft sd
                where sd.league_id = f.league_id and sd.stagione = f.stagione
                  and sd.finestra = f.finestra
                  and sd.stato in ('determinata', 'usata', 'vuota')))::integer)
      )
    order by f.league_id, f.stagione, f.finestra
  loop
    begin
      -- v_finestra.finestra, non 'on' fisso. Era il difetto: il ciclo
      -- selezionava anche le finestre OFF scadute — il commento sopra lo dice
      -- da giorni — ma poi chiedeva sempre di risolvere la ON della stessa
      -- stagione. Quella era gia' risolta, risolvi_finestra_scelte usciva
      -- subito restituendo 0, e la OFF restava aperta per sempre.
      --
      -- Trovato il 13 settembre 2026 guardando perche' la OFF-Season 3 di
      -- LegaBot fosse ferma dal giorno prima con le preferenze gia' compilate:
      -- la schermata del mercato mostrava un countdown a 00:00:00 e le
      -- preferenze congelate, senza che l'estrazione arrivasse mai.
      perform private.risolvi_finestra_scelte(
        v_finestra.league_id, v_finestra.stagione, v_finestra.finestra, true);
      v_risolte := v_risolte + 1;

      -- L'apertura della OFF segue la chiusura della ON della stessa stagione,
      -- ma va tentata in un blocco SUO. Un BEGIN ... EXCEPTION in PL/pgSQL e'
      -- una sottotransazione: finche' questa chiamata stava nello stesso blocco
      -- della riga sopra, un suo fallimento avrebbe annullato l'intera
      -- risoluzione della finestra, cioe' l'assegnazione di tutti i giocatori.
      -- E fallire e' normale: l'ordine di scelta della OFF dipende dalla
      -- classifica finale, che a meta' stagione non esiste ancora.
      if v_finestra.finestra = 'on' then
        begin
          if not exists (
            select 1 from public.finestre_scelte
            where league_id = v_finestra.league_id and stagione = v_finestra.stagione and finestra = 'off'
          ) then
            perform private.svela_finestra_scelte(v_finestra.league_id, v_finestra.stagione, 'off');
          end if;
        exception when others then
          raise warning 'mercato a scelte: OFF di lega % stagione % non ancora apribile: % (%)',
            v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
        end;
      end if;
    exception when others then
      raise warning 'mercato a scelte: risoluzione ON-Season fallita per lega % stagione %: % (%)',
        v_finestra.league_id, v_finestra.stagione, sqlerrm, sqlstate;
    end;
  end loop;
  return v_risolte;
end;
$function$
;
