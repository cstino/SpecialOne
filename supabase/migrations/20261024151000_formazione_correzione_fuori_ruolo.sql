-- Formazioni: nessuna strada per mandare in campo un portiere fuori dai pali o un giocatore di movimento in porta
-- (24/10/2026, committente: "non devono poterlo piu' fare"). salva_formazione rifiuta gia' i casi estremi
-- (20261024150000); qui si chiudono le altre strade:
--   * formazioni salvate PRIMA della regola e riusate nelle giornate dopo (la simulazione eredita l'ultima salvata);
--   * formazioni diventate irregolari dopo il salvataggio (portiere titolare infortunato o squalificato, ruolo cambiato).
-- Un trigger su lineups corregge da solo ogni formazione di una partita ancora da giocare: in porta va il miglior
-- portiere disponibile (prima uno gia' titolare, poi la panchina, poi il resto della rosa), e un portiere fra i dieci di
-- movimento viene scambiato col miglior giocatore di movimento disponibile (prima la panchina). Le eccezioni sono le
-- stesse del salvataggio: nessun portiere disponibile, o meno di 10 giocatori di movimento disponibili.
-- La simulazione ripassa tutte le formazioni della giornata prima di giocare (correggi_formazioni_giornata) e usa la
-- versione corretta di quelle ereditate. La correzione non blocca mai: se qualcosa va storto la formazione resta com'e'.

create or replace function private.e_portiere(p_id bigint)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce((select 'GK' = any(coalesce(pi.posizioni_override, p.posizioni))
                     from public.player_instances pi join public.players p on p.id = pi.player_id where pi.id = p_id), false)
$function$;

create or replace function private.giocatore_disponibile(p_id bigint)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce((select not coalesce(pi.ritirato, false) and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0
                     from public.player_instances pi where pi.id = p_id), false)
$function$;

-- Restituisce titolari, panchina e tribuna senza i due casi vietati (o invariati se non c'e' niente da correggere).
create or replace function private.formazione_senza_fuori_ruolo(p_league_id bigint, p_team_id bigint, p_tit bigint[], p_pan bigint[], p_tri bigint[],
  out titolari bigint[], out panchina bigint[], out tribuna bigint[])
 language plpgsql stable security definer set search_path to ''
as $function$
declare v_scelto bigint; v_vecchio bigint; v_pos int; v_k int; v_mov_disp int;
begin
  titolari := p_tit; panchina := coalesce(p_pan, '{}'); tribuna := coalesce(p_tri, '{}');
  if titolari is null or cardinality(titolari) <> 11 then return; end if;

  -- 1. In porta un portiere disponibile, se ce n'e' uno.
  if not (private.e_portiere(titolari[1]) and private.giocatore_disponibile(titolari[1])) then
    select pi.id into v_scelto from public.player_instances pi join public.players p on p.id = pi.player_id
     where pi.league_id = p_league_id and pi.team_id = p_team_id and not coalesce(pi.ritirato, false)
       and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0
       and 'GK' = any(coalesce(pi.posizioni_override, p.posizioni)) and pi.id is distinct from titolari[1]
     order by case when pi.id = any(titolari) then 0 when pi.id = any(panchina) then 1 else 2 end, pi.overall_corrente desc nulls last, pi.id
     limit 1;
    if v_scelto is not null then
      v_vecchio := nullif(titolari[1], 0);
      v_pos := array_position(titolari, v_scelto);
      if v_pos is not null then
        -- era gia' titolare (fuori dai pali): scambio di posto
        titolari[v_pos] := coalesce(v_vecchio, 0); titolari[1] := v_scelto;
      else
        titolari[1] := v_scelto;
        panchina := array_remove(panchina, v_scelto); tribuna := array_remove(tribuna, v_scelto);
        -- chi stava in porta va dove stava il portiere (panchina se c'e' posto e se e' disponibile, altrimenti tribuna)
        if v_vecchio is not null then
          if private.giocatore_disponibile(v_vecchio) and cardinality(panchina) < 9 then panchina := panchina || v_vecchio;
          else tribuna := tribuna || v_vecchio; end if;
        end if;
      end if;
    end if;
  end if;

  -- 2. Niente portieri fra i dieci di movimento, se ci sono abbastanza giocatori di movimento disponibili.
  select count(*) into v_mov_disp from public.player_instances pi join public.players p on p.id = pi.player_id
   where pi.league_id = p_league_id and pi.team_id = p_team_id and not coalesce(pi.ritirato, false)
     and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0
     and not ('GK' = any(coalesce(pi.posizioni_override, p.posizioni)));
  if v_mov_disp >= 10 then
    for v_k in 2..11 loop
      continue when not private.e_portiere(titolari[v_k]);
      select pi.id into v_scelto from public.player_instances pi join public.players p on p.id = pi.player_id
       where pi.league_id = p_league_id and pi.team_id = p_team_id and not coalesce(pi.ritirato, false)
         and coalesce(pi.infortunato_fino_a, 0) <= 0 and coalesce(pi.squalificato_fino_a, 0) <= 0
         and not ('GK' = any(coalesce(pi.posizioni_override, p.posizioni))) and not (pi.id = any(titolari))
       order by case when pi.id = any(panchina) then 0 else 1 end, pi.overall_corrente desc nulls last, pi.id
       limit 1;
      exit when v_scelto is null;
      v_vecchio := titolari[v_k]; titolari[v_k] := v_scelto;
      v_pos := array_position(panchina, v_scelto);
      if v_pos is not null then panchina[v_pos] := v_vecchio;
      else tribuna := array_remove(tribuna, v_scelto) || v_vecchio; end if;
    end loop;
  end if;
end $function$;

-- Trigger: corregge le formazioni delle partite ancora da giocare.
create or replace function private.lineups_niente_fuori_ruolo()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare r record;
begin
  if not exists (select 1 from public.fixtures f where f.league_id = new.league_id and f.giornata = new.giornata
                    and f.stato = 'programmata' and new.team_id in (f.home_team_id, f.away_team_id)) then
    return new;
  end if;
  select * into r from private.formazione_senza_fuori_ruolo(new.league_id, new.team_id, new.titolari, new.panchina, new.tribuna);
  new.titolari := r.titolari; new.panchina := r.panchina; new.tribuna := r.tribuna;
  return new;
exception when others then
  return new;   -- la correzione non deve mai impedire di salvare o di simulare
end $function$;

drop trigger if exists lineups_niente_fuori_ruolo on public.lineups;
create trigger lineups_niente_fuori_ruolo before insert or update of titolari, panchina, tribuna on public.lineups
  for each row execute function private.lineups_niente_fuori_ruolo();

-- Ripasso prima della simulazione: riscrive (e quindi corregge) le formazioni gia' salvate per la giornata.
create or replace function public.correggi_formazioni_giornata(p_league_id bigint, p_giornata integer)
 returns integer language plpgsql volatile security definer set search_path to ''
as $function$
declare v_n integer;
begin
  update public.lineups set titolari = titolari where league_id = p_league_id and giornata = p_giornata;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;
revoke all on function public.correggi_formazioni_giornata(bigint, integer) from public, anon, authenticated;
grant execute on function public.correggi_formazioni_giornata(bigint, integer) to service_role;
