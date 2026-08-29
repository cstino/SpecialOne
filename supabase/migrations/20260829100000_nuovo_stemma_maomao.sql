begin;

-- Aggiunge "maomao" agli stemmi preset (miniatura generata, registrato in
-- src/lib/teamCrests.ts): senza questo, la whitelist server-side lo
-- rifiuterebbe nonostante comparisse nel selettore.

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
