-- ============================================================
--  POPUP DI SPIEGAZIONE ALLA PRIMA APERTURA DI UNA PAGINA
--  Deciso il 1 settembre 2026, in conversazione con l'utente.
--
--  Ogni pagina di gioco puo' mostrare un popup che spiega come funziona
--  la meccanica, con una casella "non mostrare più". La scelta segue
--  l'utente su ogni dispositivo (niente localStorage per lo stato di
--  gioco, vedi CLAUDE.md sez. 6): e' una tabella minima, letta e
--  scritta direttamente via RLS, senza bisogno di una RPC dedicata.
-- ============================================================

begin;

create table public.hint_visti (
  user_id uuid not null references auth.users(id) on delete cascade,
  hint_key text not null,
  visto_il timestamptz not null default now(),
  primary key (user_id, hint_key)
);

comment on table public.hint_visti is
  'Popup di spiegazione gia'' chiusi con "non mostrare più", per utente. hint_key identifica la pagina/meccanica (es. ''mercato-free-agent'').';

alter table public.hint_visti enable row level security;

create policy hint_visti_lettura on public.hint_visti
  for select using (user_id = (select auth.uid()));

create policy hint_visti_scrittura on public.hint_visti
  for insert with check (user_id = (select auth.uid()));

grant select, insert on public.hint_visti to authenticated;

commit;
