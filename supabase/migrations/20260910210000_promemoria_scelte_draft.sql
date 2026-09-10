-- ============================================================
--  PROMEMORIA 24 ORE PRIMA DELLA CHIUSURA DI UNA FINESTRA DRAFT
--
--  Richiesta dell'utente il 10 settembre 2026: "24h prima della scadenza
--  arriva una notifica/reminder a tutte le squadre, ricordando di impostare
--  le preferenze per il draft".
--
--  Perche' serve davvero: private.risolvi_finestra_scelte scorre le
--  preferenze in ordine e, se nessuna e' utilizzabile (o non ce n'e'
--  nessuna), marca la scelta 'vuota' e la squadra resta a mani vuote. E'
--  esattamente cio' che e' successo alla 1a scelta dei Cocacolers nella
--  ON-Season 3 di LegaBot, recuperata il 9 settembre: una sola preferenza
--  espressa, quel giocatore gia' in rosa altrove, scelta persa. Un
--  promemoria vale quindi un giocatore, non e' cortesia.
--
--  A CHI ARRIVA, e perche' non "a tutte le squadre" alla lettera.
--  Va solo a chi possiede almeno una scelta 'determinata' in quella
--  finestra per cui NON ha ancora espresso nessuna preferenza. Le altre
--  squadre non hanno niente da fare: avvisare chi non ha scelte in quella
--  finestra (succede: le scelte si scambiano, e nella ON-Season 3 di
--  LegaBot erano 8 su 16 squadre) sarebbe un avviso senza azione possibile,
--  cioe' rumore che insegna a ignorare le notifiche. Chi ha gia' composto
--  la lista non viene disturbato: ha gia' fatto la sua scelta, anche se
--  corta.
--
--  ANTI-DOPPIONE: la finestra dura 24 ore e il cron gira ogni 15 minuti,
--  quindi senza guardia partirebbero ~96 avvisi a testa. Si controlla se
--  esiste gia' una notifica per quella esatta (lega, stagione, finestra),
--  con le stesse chiavi in 'dati' — stesso schema di
--  private.promemoria_formazione_22, che usa dati->>'giornata'.
--
--  Il tipo e' 'mercato_asta' e non uno nuovo: notifications_tipo_check
--  ammette solo otto valori, e le scelte draft sono un mercato a busta
--  chiusa come le aste (stessa icona a martelletto, gia' corretta). Un tipo
--  nuovo avrebbe richiesto di toccare vincolo, TipoNotifica e mappa delle
--  icone per un guadagno solo estetico.
--  Il campo dati.view = 'scelte' accende il pallino sulla voce Draft del
--  menu, come gia' fanno 'risorse' e 'team' (vedi GameNav.tsx).
-- ============================================================

begin;

create or replace function private.promemoria_scelte_draft()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finestra record;
  v_team record;
  v_ore integer;
  v_inviate integer := 0;
begin
  for v_finestra in
    select f.league_id, f.stagione, f.finestra, f.estrazione_il
    from public.finestre_scelte f
    join public.leagues l on l.id = f.league_id
    where f.risolta_il is null
      and f.estrazione_il is not null
      and f.estrazione_il > now()
      and f.estrazione_il <= now() + interval '24 hours'
    order by f.league_id, f.stagione, f.finestra
  loop
    v_ore := greatest(1, ceil(extract(epoch from (v_finestra.estrazione_il - now())) / 3600.0)::integer);

    for v_team in
      select distinct t.id as team_id, t.user_id
      from public.scelte_draft sd
      join public.teams t on t.id = sd.team_proprietario_id and t.attiva
      where sd.league_id = v_finestra.league_id
        and sd.stagione  = v_finestra.stagione
        and sd.finestra  = v_finestra.finestra
        and sd.stato     = 'determinata'
        and t.user_id is not null
        -- solo chi non ha ancora messo NIENTE in lista su quella scelta
        and not exists (
          select 1 from public.scelte_preferenze pr where pr.scelta_id = sd.id
        )
    loop
      if exists (
        select 1 from public.notifications n
        where n.user_id   = v_team.user_id
          and n.league_id = v_finestra.league_id
          and n.tipo      = 'mercato_asta'
          and n.dati ->> 'promemoria' = 'scelte'
          and n.dati ->> 'stagione'   = v_finestra.stagione::text
          and n.dati ->> 'finestra'   = v_finestra.finestra
      ) then
        continue;
      end if;

      perform private.notifica(
        v_team.user_id, v_finestra.league_id, 'mercato_asta',
        'Draft: meno di 24 ore',
        'Non hai ancora indicato nessuna preferenza per la tua scelta ('
          || upper(v_finestra.finestra) || '-Season, chiude fra ' || v_ore
          || (case when v_ore = 1 then ' ora' else ' ore' end)
          || '). Senza una lista la scelta va a vuoto e il giocatore lo perdi.',
        jsonb_build_object(
          'view', 'scelte',
          'promemoria', 'scelte',
          'stagione', v_finestra.stagione,
          'finestra', v_finestra.finestra
        )
      );
      v_inviate := v_inviate + 1;
    end loop;
  end loop;

  return v_inviate;
end;
$$;

revoke all on function private.promemoria_scelte_draft() from public, anon, authenticated;

comment on function private.promemoria_scelte_draft() is
  'Avvisa chi non ha ancora composto la lista di preferenze per una finestra draft '
  'che chiude entro 24 ore. Idempotente: una sola notifica per (utente, lega, stagione, finestra).';

-- Ogni 15 minuti, come gli altri promemoria: il controllo vero sulla
-- finestra temporale sta dentro la funzione, non nella schedule (stesso
-- principio del fuso orario gia' documentato in 20260901130000).
select cron.schedule(
  'promemoria-scelte-draft',
  '*/15 * * * *',
  $cron$select private.promemoria_scelte_draft();$cron$
);

commit;
