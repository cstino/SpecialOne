-- Serie F (lega 63), Doomsday (squadra 306): nella Season 2 non aveva rinnovato nessuno, quindi alla chiusura
-- dell'off-season (8/11/2026, 12:00) i 25 giocatori in scadenza sono usciti e la rosa e' stata completata con
-- 20 svincolati da 0,5 M€. Decisione del committente (8/11/2026): i 25 tornano alla Doomsday come se li avesse
-- rinnovati per un anno nella Season 2, cioe' all'ingaggio che chiedevano allora (private.rinnovo_proposta con
-- l'eta' della Season 2 e l'overall di fine stagione, che all'apertura dell'off-season non cambia), contratto fino
-- alla Season 3. I 20 riempitivi tornano svincolati; Tsygankov, preso col draft OFF, resta.
-- Poi la scelta ON-Season 3 della Doomsday si ricolloca col nuovo monte ingaggi (64,5 M€), confrontato coi monti
-- delle altre squadre alla chiusura delle 12:00 (da allora alcune hanno rinnovato): fra M'ARPZZC FC (62,1 M€) e
-- Cocciaspigola (64,8 M€), cioe' 15ª. Le squadre dalla 2ª alla 15ª salgono di un posto, l'ordine delle altre resta.

begin;

create temp table doomsday_rientro on commit drop as
select pi.id, p.nome, pi.ingaggio as vecchio, r.richiesta
from (
  select unnest(titolari || panchina || tribuna) as id
  from private.lineups_archivio
  where team_id = 306 and stagione = 2 and giornata = 24 and not automatica
) a
join public.player_instances pi on pi.id = a.id
join public.players p on p.id = pi.player_id
cross join lateral private.rinnovo_proposta(pi.id, pi.overall_corrente, (pi.eta_corrente - 1)::smallint, pi.ingaggio,
                                            p.mentalita_bandiera, p.mentalita_economia) r
where pi.team_id is null and not pi.ritirato and pi.league_id = 63;

do $$
begin
  if (select count(*) from doomsday_rientro) <> 25 then
    raise exception 'attesi 25 giocatori liberi, trovati %', (select count(*) from doomsday_rientro);
  end if;
  if (select sum(richiesta) from doomsday_rientro) <> 61500000 then
    raise exception 'totale richieste inatteso: %', (select sum(richiesta) from doomsday_rientro);
  end if;
end $$;

-- 1) I 20 riempitivi tornano svincolati (rilascio normale, trigger compresi).
update public.player_instances
set team_id = null
where team_id = 306 and id between 8148 and 8167;

-- 2) I 25 rientrano senza i trigger del trasferimento: non e' un acquisto (niente registro trasferimenti, niente
--    spinta di morale da nuovo arrivo, niente arrivo nella Season 3). Campi messi a mano come dopo un rinnovo.
set local session_replication_role = replica;
update public.player_instances pi
set team_id = 306,
    ingaggio = d.richiesta,
    contratto_scadenza = 3,
    rinnovo_stagione = 2,
    rinnovo_tentativi = 0,
    arrivo_stagione = 2,
    peso_team_id = null,
    peso_stagione = null,
    sul_mercato = false,
    opzione_contratto = null,
    minutaggio_promesso = private.minutaggio_alla_firma(pi.league_id, pi.overall_corrente, pi.eta_corrente,
                                                        pi.player_id, pi.posizioni_override)
from doomsday_rientro d
where pi.id = d.id;
set local session_replication_role = origin;

-- Non sono piu' rilasci da mettere all'asta.
delete from private.rilasci_in_coda r
using public.player_instances pi
where r.league_id = 63 and pi.player_id = r.player_id and pi.id in (select id from doomsday_rientro);

-- Registro movimenti, come public.offri_rinnovo (importo negativo = spazio salariale consumato).
insert into public.transactions (league_id, team_id, tipo, importo, descrizione, saldo_dopo)
select 63, 306, 'rinnovo_in_stagione', coalesce(nullif(vecchio - richiesta, 0), 1),
       'Rinnovo d''ufficio (Season 2): ' || nome || ' — ' || round(richiesta / 1000000.0, 1) || ' M€ fino alla stagione 3', 0
from doomsday_rientro
order by richiesta desc;

-- 3) Scelta ON-Season 3: Doomsday dalla 1ª alla 15ª.
update public.scelte_draft
set posizione = posizione - 1, aggiornata_il = now()
where league_id = 63 and stagione = 3 and finestra = 'on' and posizione between 2 and 15;
update public.scelte_draft
set posizione = 15, aggiornata_il = now()
where league_id = 63 and stagione = 3 and finestra = 'on' and team_origine_id = 306;

do $$
declare
  v_rosa integer;
  v_monte bigint;
begin
  select count(*) into v_rosa from public.player_instances where team_id = 306 and not ritirato;
  v_monte := private.monte_ingaggi(306, 3::smallint);
  if v_rosa <> 26 or v_monte <> 64500000 then
    raise exception 'controllo finale fallito: rosa %, monte %', v_rosa, v_monte;
  end if;
  if (select count(distinct posizione) from public.scelte_draft
      where league_id = 63 and stagione = 3 and finestra = 'on') <> 28 then
    raise exception 'posizioni ON-Season 3 non uniche';
  end if;
end $$;

commit;
