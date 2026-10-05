-- ============================================================
--  STEMMI: SOLO PREDEFINITI (5 ottobre 2026)
--  Il committente ha tolto la possibilita' di caricare immagini personali.
--    - private.stemma_valido accetta i predefiniti, oppure lo stemma
--      personalizzato che l'utente ha GIA' su una sua squadra (cosi' chi ne ha
--      uno lo conserva, ad esempio cambiando solo il nome);
--    - tolta la policy che permetteva di caricare file nel bucket team-crests
--      (restano lettura e cancellazione del proprio, che serve a ripulire il
--      vecchio file quando si passa a un predefinito).
--  Il nuovo logo del Salisburro (senza stella) era stato caricato a mano, senza
--  proprietario: gli si assegna, altrimenti il vecchio controllo lo avrebbe
--  rifiutato.
-- ============================================================

update storage.objects
set owner_id = '2a32c025-49a4-4f38-9e5a-c2fd80232e2d'
where bucket_id = 'team-crests'
  and name = '2a32c025-49a4-4f38-9e5a-c2fd80232e2d/16e0c10c-beb5-46a5-86fd-d914545909cc.png'
  and owner_id is null;

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
      'preset:parenzo',
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

drop policy if exists team_crests_upload_proprio on storage.objects;

notify pgrst, 'reload schema';
