-- SocialOne: quando un influencer parla di una squadra la tagga (@handle, come i tifosi) e l'allenatore riceve una
-- notifica quando il post diventa visibile (richiesta del committente, 8/11/2026). I post degli influencer nascono
-- alla simulazione con un orario futuro (22:40 -> 00:30), quindi la notifica non parte all'inserimento ma da un cron
-- ogni 5 minuti che guarda i post appena usciti.

-- Prima occorrenza del nome di ogni squadra della lega -> @handle. Nomi piu' lunghi prima, cosi' un nome contenuto
-- in un altro non lo spezza.
create or replace function private.social_tagga_squadre(p_league_id bigint, p_testo text)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_t record;
  v_testo text := p_testo;
  v_pos integer;
begin
  for v_t in
    select t.nome from public.teams t
     where t.league_id = p_league_id and char_length(t.nome) >= 3
     order by char_length(t.nome) desc
  loop
    v_pos := strpos(v_testo, v_t.nome);
    -- gia' taggata (testo gia' passato di qui): non si tagga una seconda volta
    if v_pos > 0 and strpos(v_testo, '@' || private.handle_squadra(v_t.nome)) = 0 then
      v_testo := overlay(v_testo placing '@' || private.handle_squadra(v_t.nome) from v_pos for char_length(v_t.nome));
    end if;
  end loop;
  return v_testo;
end $function$;

alter table public.social_posts add column if not exists menzioni_notificate boolean not null default true;
-- I nuovi post degli influencer nascono «da notificare»; tutti gli altri (e quelli vecchi) no.
create or replace function private.social_influencer_tag()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.autore_tipo = 'influencer' then
    new.testo := private.social_tagga_squadre(new.league_id, new.testo);
    new.menzioni_notificate := false;
  end if;
  return new;
end $function$;

drop trigger if exists social_posts_influencer_tag on public.social_posts;
create trigger social_posts_influencer_tag before insert on public.social_posts
  for each row execute function private.social_influencer_tag();

create or replace function private.social_notifica_menzioni()
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_p record;
  v_n integer := 0;
begin
  for v_p in
    select p.id, p.league_id, p.autore_nome, p.testo, p.team_id, p.team2_id
      from public.social_posts p
     where not p.menzioni_notificate and p.creato_il <= now()
     order by p.creato_il
     for update skip locked
  loop
    -- Post rimasti indietro (cron fermo): si chiudono senza notificare.
    if (select creato_il from public.social_posts where id = v_p.id) > now() - interval '6 hours' then
      perform private.notifica(t.user_id, v_p.league_id, 'sistema', v_p.autore_nome || ' ha parlato di te',
                               v_p.testo, jsonb_build_object('view', 'social', 'post_id', v_p.id))
        from public.teams t
       where t.league_id = v_p.league_id and t.user_id is not null
         -- taggata nel testo, oppure squadra del post (un giocatore citato per nome senza la sua squadra)
         and (v_p.testo ~* ('@' || private.handle_squadra(t.nome) || '([^a-z0-9_]|$)')
              or t.id in (v_p.team_id, v_p.team2_id));
      v_n := v_n + 1;
    end if;
    update public.social_posts set menzioni_notificate = true where id = v_p.id;
  end loop;
  return v_n;
end $function$;

select cron.unschedule('social-menzioni') where exists (select 1 from cron.job where jobname = 'social-menzioni');
select cron.schedule('social-menzioni', '*/5 * * * *', 'select private.social_notifica_menzioni();');

-- Post degli influencer della giornata di stasera: taggati; quelli non ancora usciti notificheranno all'uscita.
update public.social_posts
   set testo = private.social_tagga_squadre(league_id, testo),
       menzioni_notificate = creato_il <= now()
 where autore_tipo = 'influencer' and creato_il > now() - interval '3 hours'
   and testo !~ '@[a-z0-9_]+';
