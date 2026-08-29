begin;

-- ============================================================
--  NUOVI STEMMI PRESET
--
--  L'utente ha aggiunto sei nuovi stemmi in public/stemmi-squadra/ (con le
--  relative miniature in thumbs/, generate 320x320 come le altre) e li ha
--  registrati in src/lib/teamCrests.ts. Mancava solo questo lato: la
--  whitelist server-side che valida lo stemma scelto alla creazione lega o
--  all'ingresso — senza, la selezione sarebbe stata rifiutata nonostante
--  comparisse nel selettore.
-- ============================================================

create or replace function private.stemma_valido(p_stemma_url text, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
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
      p_stemma_url ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(webp|png)$'
      )
      and exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'team-crests'
          and o.name = p_stemma_url
          and o.owner_id = p_user_id::text
          and o.metadata ->> 'mimetype' in ('image/webp', 'image/png')
          and (o.metadata ->> 'size')::bigint <= 524288
      )
    );
$$;

commit;
