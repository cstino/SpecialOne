-- Stemma Jeffrey's Eleven per BackDoor Invaders (Serie F, team 303), scontornato dal logo mandato dal committente il 7/11/2026.
-- Funzione dalla definizione viva, con il preset nuovo in coda.
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
      'preset:b64',
      'preset:disonesti',
      'preset:real-paupiedad',
      'preset:marpzzc',
      'preset:riskmond',
      'preset:hage-no-justu',
      'preset:as-turbo',
      'preset:cocciaspigola',
      'preset:juventu-nazionale',
      'preset:fcno',
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
      'preset:yugioh',
      'preset:bucio-di-culo',
      'preset:arrosticini',
      'preset:sporting-genziana',
      'preset:middlesbronz',
      'preset:jeffreys-eleven'
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

update public.teams set stemma_url = 'preset:jeffreys-eleven' where id = 303 and nome = 'BackDoor Invaders';
