-- ============================================================
--  NUOVI STEMMI PRESET
--
--  I preset disegnati iniziali vengono sostituiti dagli asset scelti per
--  il gioco. Gli upload personali continuano a essere validati su Storage.
-- ============================================================

update public.teams
set stemma_url = 'preset:1'
where stemma_url = any (array[
  'preset:scudo',
  'preset:diagonale',
  'preset:torre',
  'preset:stella',
  'preset:quartieri',
  'preset:corona'
]::text[]);

create or replace function private.stemma_valido(
  p_stemma_url text,
  p_user_id uuid
)
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
      'preset:aviator',
      'preset:bigbrain',
      'preset:calvi',
      'preset:canna',
      'preset:cola',
      'preset:coord',
      'preset:cotoletta',
      'preset:eagle',
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
      'preset:parenzo',
      'preset:piramidi',
      'preset:rocca',
      'preset:rosa',
      'preset:skull',
      'preset:slot',
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

comment on function private.stemma_valido(text, uuid) is
  'Accetta i preset inclusi nell''app o un PNG/WebP caricato dal proprietario nel bucket team-crests.';

revoke all on function private.stemma_valido(text, uuid) from public, anon, authenticated;
grant execute on function private.stemma_valido(text, uuid) to service_role;
