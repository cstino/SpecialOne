-- Tolto dalla galleria degli stemmi il logo usato da Gaza Strickers (preset:parenzo) e rinominate due squadre su richiesta
-- del committente (7 ottobre 2026). Gaza Strickers riparte dallo stemma predefinito e da un nome da definire.
-- Funzione ricostruita dalla definizione live.

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
      'preset:bigbrain',
      'preset:calvi',
      'preset:canna',
      'preset:cola',
      'preset:coord',
      'preset:cotoletta',
      'preset:down',
      'preset:eagle',
      'preset:eddaii',
      'preset:flat',
      'preset:generale',
      'preset:leoni',
      'preset:lions',
      'preset:lupo',
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

update public.teams set nome = 'Nome da definire', sigla = 'NOM', stemma_url = 'preset:1'
  where id = 303 and league_id = 63 and nome = 'Gaza Strickers';
update public.teams set nome = 'Salisburro', sigla = 'SAL'
  where id = 282 and league_id = 63 and nome = 'Lamadremortadelsionist';
