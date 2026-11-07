-- Serie F: budget del draft d'ingresso a 52M (era 48M) per le quattro squadre nuove (decisione del committente,
-- 7/11/2026), per compensare un pool di svincolati gia' scremato da due stagioni. budget_draft lo leggono solo le
-- funzioni del draft, e in questa off-season il draft lo fanno solo le squadre nuove: le altre non cambiano.
update public.leagues set budget_draft = 52000000 where id = 63;
