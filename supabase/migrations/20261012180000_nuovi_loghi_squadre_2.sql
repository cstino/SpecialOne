-- Nuovi loghi delle squadre (secondo gruppo): preset in whitelist (funzione riscritta dalla definizione viva) e assegnazione.
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
      'preset:marpzzc',
      'preset:riskmond',
      'preset:hage-no-justu',
      'preset:as-turbo',
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

update public.teams set stemma_url = 'preset:marpzzc' where id in (277);
update public.teams set stemma_url = 'preset:riskmond' where id in (300);
update public.teams set stemma_url = 'preset:hage-no-justu' where id in (280);
update public.teams set stemma_url = 'preset:as-turbo' where id in (85, 275);
