-- Nuovi loghi delle squadre: preset aggiunti alla whitelist (funzione riscritta dalla definizione viva) e assegnati alle squadre proprietarie.
CREATE OR REPLACE FUNCTION private.stemma_valido(p_stemma_url text, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    p_stemma_url = any (array[
      'preset:1',
      'preset:alci',
      'preset:aliens',
      'preset:aquile',
      'preset:arpzzc',
      'preset:aviator',
      'preset:balor-dito',
      'preset:cola-zero',
      'preset:doomsday-fc',
      'preset:fel-lazio',
      'preset:ho-chi-minh-city',
      'preset:maudit-printemps',
      'preset:pro-secco',
      'preset:scernobil-united',
      'preset:weed-athletic',
      'preset:bigbrain',
      'preset:calvi',
      'preset:canna',
      'preset:cola',
      'preset:coord',
      'preset:cotoletta',
      'preset:detroit-pigeons',
      'preset:down',
      'preset:eagle',
      'preset:eddaii',
      'preset:flat',
      'preset:generale',
      'preset:leoni',
      'preset:lions',
      'preset:lupo',
      'preset:mafiester-city',
      'preset:maomao',
      'preset:massoni',
      'preset:mcdonald',
      'preset:musk',
      'preset:musso',
      'preset:onepiece',
      'preset:paninissimi',
      'preset:piramidi',
      'preset:rocca',
      'preset:rosa',
      'preset:siga',
      'preset:skull',
      'preset:slot',
      'preset:sushi',
      'preset:torres',
      'preset:totti',
      'preset:trump',
      'preset:trump-portatore',
      'preset:twins',
      'preset:wolves',
      'preset:yugioh'
    ]::text[])
    or (
      -- Stemma personalizzato: solo se e' gia' lo stemma di una squadra di questo utente
      -- (chi ne aveva uno lo conserva, ma non se ne caricano di nuovi).
      p_stemma_url ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(webp|png)$'
      )
      and exists (
        select 1 from public.teams t
        where t.user_id = p_user_id and t.stemma_url = p_stemma_url
      )
    );
$function$;

update public.teams set stemma_url = 'preset:ho-chi-minh-city' where id in (302);
update public.teams set stemma_url = 'preset:scernobil-united' where id in (288);
update public.teams set stemma_url = 'preset:fel-lazio' where id in (286, 89);
update public.teams set stemma_url = 'preset:maudit-printemps' where id in (285);
update public.teams set stemma_url = 'preset:doomsday-fc' where id in (306);
update public.teams set stemma_url = 'preset:pro-secco' where id in (299);
update public.teams set stemma_url = 'preset:weed-athletic' where id in (301);
update public.teams set stemma_url = 'preset:cola-zero' where id in (305);
update public.teams set stemma_url = 'preset:balor-dito' where id in (84, 279);
