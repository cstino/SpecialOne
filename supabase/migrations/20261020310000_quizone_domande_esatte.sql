-- QuizOne: domande rese inequivocabili prima del lancio in Serie F.
-- Gol/assist/capocannoniere contati come li mostra l'app (classifica_giocatori_stagione: tutte le partite simulate della
-- stagione corrente, per giocatore, squadra attuale; prima un giocatore cambiato di squadra veniva diviso per squadra);
-- solo giocatori con nome non ambiguo; vittorie/gol subiti/attacco/difesa dicono "in campionato" (vengono dalla classifica,
-- che non conta i playoff); risultati solo di partite di campionato (niente supplementari/rigori); 4 risposte sempre diverse.
CREATE OR REPLACE FUNCTION private.quiz_genera(p_league_id bigint, p_ora timestamp with time zone)
 RETURNS quizzone_domande
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_stagione bigint; v_tipi text[] := array['gol','assist','punti','posizione','vittorie','subiti','risultato','capocannoniere','capolista','attacco','difesa'];
  v_recenti text[]; v_tipo text; v_tentativo int; r record; v_testo text; v_giusta text; v_sbagliate text[]; v_mix jsonb; d public.quizzone_domande;
  v_lega text; v_gruppo text; v_n int;
begin
  -- stessa stagione che mostra l'app (classifica_giocatori_stagione): quella corrente della lega, se e' in corso
  select s.id into v_stagione from public.seasons s join public.leagues l on l.id = s.league_id
   where l.id = p_league_id and s.numero = l.stagione_corrente and s.stato = 'in_corso';
  if v_stagione is null then return null; end if;
  select nome into v_lega from public.leagues where id = p_league_id;
  v_recenti := array(select tipo from public.quizzone_domande where league_id = p_league_id order by ora desc limit 4);
  for v_tentativo in 1..30 loop
    v_tipo := v_tipi[1 + floor(random() * array_length(v_tipi, 1))::int];
    continue when v_tipo = any(v_recenti) and v_tentativo < 25;
    v_testo := null;
    if v_tipo in ('gol', 'assist') then
      select p.nome as giocatore, t.nome as squadra, x.n into r
        from (select ms.player_instance_id, coalesce(pi.team_id, max(ms.team_id)) as team_id,
                     sum(case when v_tipo = 'gol' then ms.gol else ms.assist end)::int as n
                from public.match_stats ms join public.matches m on m.id = ms.match_id
                join public.fixtures f on f.id = m.fixture_id and f.season_id = v_stagione and f.stato = 'simulata'
                left join public.player_instances pi on pi.id = ms.player_instance_id
               where ms.league_id = p_league_id group by ms.player_instance_id, pi.team_id) x
        join public.player_instances pi on pi.id = x.player_instance_id join public.players p on p.id = pi.player_id join public.teams t on t.id = x.team_id
       where x.n >= 2
         and (select count(*) from public.player_instances pi2 join public.players p2 on p2.id = pi2.player_id where pi2.league_id = p_league_id and p2.nome = p.nome) = 1
       order by random() limit 1;
      if r.n is not null then
        v_testo := case v_tipo when 'gol' then format('Quanti gol ha segnato %s (%s) in questa stagione?', r.giocatore, r.squadra)
                               else format('Quanti assist ha fatto %s (%s) in questa stagione?', r.giocatore, r.squadra) end;
        v_giusta := r.n::text; v_sbagliate := private.quiz_numeri(r.n, 0);
      end if;
    elsif v_tipo in ('punti', 'vittorie', 'subiti') then
      select t.nome as squadra, s.punti, s.vittorie, s.gol_subiti into r from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null then
        v_testo := case v_tipo when 'punti' then format('Quanti punti ha in classifica %s?', r.squadra)
                               when 'vittorie' then format('Quante partite ha vinto %s in campionato?', r.squadra)
                               else format('Quanti gol ha subito %s in campionato?', r.squadra) end;
        v_n := case v_tipo when 'punti' then r.punti when 'vittorie' then r.vittorie else r.gol_subiti end;
        v_giusta := v_n::text; v_sbagliate := private.quiz_numeri(v_n, 0);
      end if;
    elsif v_tipo = 'posizione' then
      select t.nome as squadra, s.posizione, s.conferenza,
             (select count(*) from public.standings s2 where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza)::int as tot into r
        from public.standings s join public.teams t on t.id = s.team_id
       where s.season_id = v_stagione and s.posizione is not null and s.giocate > 0 order by random() limit 1;
      if r.squadra is not null and r.tot >= 4 then
        v_gruppo := case r.conferenza when 'est' then ' nella Conference Est' when 'ovest' then ' nella Conference Ovest' else '' end;
        v_testo := format('In che posizione è %s in classifica%s?', r.squadra, v_gruppo);
        v_giusta := r.posizione || 'º';
        v_sbagliate := array(select x || 'º' from (select r.posizione + dd as x from unnest(array[-3,-2,-1,1,2,3]) dd where r.posizione + dd between 1 and r.tot order by random() limit 3) s);
      end if;
    elsif v_tipo = 'risultato' then
      select th.nome as casa, ta.nome as ospite, f.giornata, m.gol_home as gh, m.gol_away as ga into r
        from public.matches m join public.fixtures f on f.id = m.fixture_id join public.teams th on th.id = f.home_team_id join public.teams ta on ta.id = f.away_team_id
       where m.league_id = p_league_id and f.season_id = v_stagione and f.stato = 'simulata' and f.bracket_tie_id is null
         and m.simulata_il < now() - interval '30 minutes' order by random() limit 1;
      if r.casa is not null then
        v_testo := format('Com''è finita %s - %s della giornata %s?', r.casa, r.ospite, r.giornata);
        v_giusta := r.gh || '-' || r.ga;
        v_sbagliate := array(select x from (select distinct x from unnest(array[r.ga || '-' || r.gh, (r.gh + 1) || '-' || r.ga, r.gh || '-' || (r.ga + 1),
                               greatest(r.gh - 1, 0) || '-' || r.ga, (r.gh + 1) || '-' || (r.ga + 1), r.gh || '-' || greatest(r.ga - 1, 0)]) x
                             where x <> r.gh || '-' || r.ga) s order by random() limit 3);
      end if;
    elsif v_tipo = 'capocannoniere' then
      with marcatori as (
        select p.nome, sum(ms.gol)::int as g from public.match_stats ms join public.matches m on m.id = ms.match_id
          join public.fixtures f on f.id = m.fixture_id and f.season_id = v_stagione and f.stato = 'simulata'
          join public.player_instances pi on pi.id = ms.player_instance_id join public.players p on p.id = pi.player_id
         where ms.league_id = p_league_id group by pi.id, p.nome having sum(ms.gol) > 0 order by g desc limit 6)
      select (select nome from marcatori order by g desc limit 1) as primo,
             (select count(*) from marcatori where g = (select max(g) from marcatori))::int as pari,
             (select array_agg(nome) from (select nome from marcatori order by g desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 and not (r.primo = any(r.altri)) and (select count(distinct x) from unnest(r.altri) x) = 3 then
        v_testo := format('Chi è il capocannoniere di %s in questa stagione?', v_lega);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo = 'capolista' then
      select s.conferenza, (select t.nome from public.standings s1 join public.teams t on t.id = s1.team_id where s1.season_id = v_stagione and s1.conferenza is not distinct from s.conferenza and s1.posizione = 1) as primo,
             (select array_agg(t.nome order by s2.posizione) from public.standings s2 join public.teams t on t.id = s2.team_id where s2.season_id = v_stagione and s2.conferenza is not distinct from s.conferenza and s2.posizione between 2 and 4) as altri into r
        from public.standings s where s.season_id = v_stagione and s.giocate > 0 order by random() limit 1;
      if r.primo is not null and array_length(r.altri, 1) = 3 then
        v_gruppo := case r.conferenza when 'est' then 'della Conference Est' when 'ovest' then 'della Conference Ovest' else 'in classifica' end;
        v_testo := format('Chi è prima %s in questo momento?', v_gruppo);
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    elsif v_tipo in ('attacco', 'difesa') then
      with ordine as (select t.nome, case when v_tipo = 'attacco' then s.gol_fatti else s.gol_subiti end as n from public.standings s join public.teams t on t.id = s.team_id
                       where s.season_id = v_stagione and s.giocate > 0 order by 2 desc limit 5)
      select (select nome from ordine order by n desc limit 1) as primo, (select count(*) from ordine where n = (select max(n) from ordine))::int as pari,
             (select array_agg(nome) from (select nome from ordine order by n desc offset 1 limit 3) x) as altri into r;
      if r.primo is not null and r.pari = 1 and array_length(r.altri, 1) = 3 then
        v_testo := case v_tipo when 'attacco' then format('Quale squadra ha segnato più gol in campionato in %s?', v_lega) else format('Quale squadra ha subito più gol in campionato in %s?', v_lega) end;
        v_giusta := r.primo; v_sbagliate := r.altri;
      end if;
    end if;
    if v_testo is not null and array_length(v_sbagliate, 1) = 3 and not (v_giusta = any(v_sbagliate)) and (select count(distinct x) from unnest(v_sbagliate) x) = 3 then
      v_mix := private.quiz_mescola(v_giusta, v_sbagliate);
      insert into public.quizzone_domande (league_id, ora, tipo, testo, risposte, corretta)
      values (p_league_id, p_ora, v_tipo, v_testo, v_mix -> 'risposte', (v_mix ->> 'corretta')::int)
      on conflict (league_id, ora) do nothing returning * into d;
      if d.id is null then select * into d from public.quizzone_domande where league_id = p_league_id and ora = p_ora; end if;
      return d;
    end if;
  end loop;
  return null;
end $function$;
