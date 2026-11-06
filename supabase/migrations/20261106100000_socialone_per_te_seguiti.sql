-- SocialOne: "Per te" premia i profili seguiti (richiesta del committente, 6/11/2026).
--
-- Prima seguire un profilo serviva solo alla scheda Seguiti. Ora in "Per te", subito dopo i post sulla
-- propria squadra degli ultimi 3 giorni, arrivano quelli dei giornali e degli influencer seguiti degli
-- ultimi 3 giorni; poi tutto il resto in ordine di tempo. Funzione ricostruita dalla definizione live.

CREATE OR REPLACE FUNCTION public.social_feed(p_league_id bigint, p_per_te boolean DEFAULT true, p_limite integer DEFAULT 40, p_offset integer DEFAULT 0, p_seguiti boolean DEFAULT false, p_profilo text DEFAULT NULL::text)
 RETURNS TABLE(id bigint, autore_tipo text, autore_nome text, autore_handle text, team_id bigint, team2_id bigint, player_instance_id bigint, in_risposta_a bigint, testo text, creato_il timestamp with time zone, n_mi_piace bigint, mio_mi_piace boolean, riguarda_me boolean, profilo text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_utente uuid := (select auth.uid());
  v_mia bigint;
begin
  if not (p_league_id = any (private.mie_leghe())) then return; end if;
  select t.id into v_mia from public.teams t where t.league_id = p_league_id and t.user_id = v_utente;

  return query
    with recursive radici as (
      select p.id as radice_id,
             row_number() over (
               order by case when p_per_te and v_mia is not null and (p.team_id = v_mia or p.team2_id = v_mia)
                                  and p.creato_il > now() - interval '3 days' then 0
                             when p_per_te and p.creato_il > now() - interval '3 days'
                                  and p.profilo in (select s.profilo from public.social_seguiti s
                                                     where s.user_id = v_utente and s.league_id = p_league_id) then 1
                             else 2 end,
                        p.creato_il desc, p.id desc) as ordine
        from public.social_posts p
       where p.league_id = p_league_id and p.in_risposta_a is null and p.creato_il <= now()
         and (p_profilo is null or p.profilo = p_profilo)
         and (not p_seguiti or p.profilo in (select s.profilo from public.social_seguiti s
                                              where s.user_id = v_utente and s.league_id = p_league_id))
       order by 2
       limit greatest(1, least(p_limite, 60)) offset greatest(0, p_offset)
    ), albero as (
      select r.radice_id, r.ordine, r.radice_id as post_id from radici r
      union all
      select a.radice_id, a.ordine, c.id
        from albero a join public.social_posts c on c.in_risposta_a = a.post_id and c.creato_il <= now()
    )
    select p.id, p.autore_tipo, p.autore_nome, p.autore_handle, p.team_id, p.team2_id, p.player_instance_id, p.in_risposta_a, p.testo, p.creato_il,
           (select count(*) from public.social_mi_piace l where l.post_id = p.id) + coalesce(p.mi_piace_fan, 0),
           exists (select 1 from public.social_mi_piace l where l.post_id = p.id and l.user_id = v_utente),
           coalesce(p.team_id = v_mia or p.team2_id = v_mia, false),
           p.profilo
      from albero a join public.social_posts p on p.id = a.post_id
     order by a.ordine, p.creato_il, p.id;
end;
$function$;
