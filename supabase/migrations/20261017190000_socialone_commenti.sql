-- SocialOne: i commenti degli allenatori (17 ottobre 2026). Il fumetto sotto ogni post apre un campo
-- per rispondere; il commento entra nella conversazione a filo, firmato col nome dell'allenatore e lo
-- stemma della squadra. Solo colore: nessun effetto su morale, pubblico o rivalita'.
-- Al massimo 280 caratteri e un commento ogni 20 secondi per utente.

begin;

create or replace function public.social_commenta(p_post_id bigint, p_testo text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_utente uuid := (select auth.uid());
  v_post public.social_posts;
  v_team public.teams;
  v_nome text;
  v_testo text := btrim(coalesce(p_testo, ''));
  v_id bigint;
begin
  if v_utente is null then raise exception using errcode = '42501', message = 'Accedi per commentare.'; end if;
  select * into v_post from public.social_posts where id = p_post_id;
  if not found then raise exception using errcode = 'P0002', message = 'Post non trovato.'; end if;
  select * into v_team from public.teams where league_id = v_post.league_id and user_id = v_utente;
  if not found then raise exception using errcode = '42501', message = 'Puoi commentare solo nelle tue leghe.'; end if;
  if char_length(v_testo) = 0 then raise exception using errcode = '22023', message = 'Scrivi qualcosa.'; end if;
  if char_length(v_testo) > 280 then raise exception using errcode = '22023', message = 'Al massimo 280 caratteri.'; end if;
  if exists (select 1 from public.social_posts sp where sp.league_id = v_post.league_id and sp.chiave like 'commento:' || v_team.id || ':%'
             and sp.creato_il > now() - interval '20 seconds') then
    raise exception using errcode = '22023', message = 'Aspetta qualche secondo prima di commentare di nuovo.';
  end if;

  select coalesce(nullif(btrim(pr.nome_allenatore), ''), v_team.nome) into v_nome
  from public.teams t left join public.profiles pr on pr.user_id = t.user_id where t.id = v_team.id;

  insert into public.social_posts (league_id, chiave, autore_tipo, autore_nome, team_id, in_risposta_a, testo)
  values (v_post.league_id, 'commento:' || v_team.id || ':' || gen_random_uuid(), 'allenatore', v_nome, v_team.id, p_post_id, v_testo)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.social_commenta(bigint, text) from public, anon;
grant execute on function public.social_commenta(bigint, text) to authenticated;

commit;
