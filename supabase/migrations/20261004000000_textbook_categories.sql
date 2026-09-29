-- =============================================================================
-- 교재 카테고리
--
--   * textbook_categories: 관리자가 만드는 교재 분류. sort_order 순으로 보여준다.
--   * textbooks.category_id: null 이면 "기타"로 보여준다.
--   * 교재가 속한 카테고리는 삭제할 수 없다. (on delete restrict)
--   * 조회는 승인된 사용자, 쓰기는 관리자만.
-- =============================================================================

create table public.textbook_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (char_length(btrim(name)) between 1 and 50),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.textbooks
  add column category_id uuid
    references public.textbook_categories (id) on delete restrict;

create index textbooks_category_id_idx on public.textbooks (category_id);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.textbook_categories enable row level security;

create policy "textbook_categories: approved select" on public.textbook_categories
  for select to authenticated using ((select private.is_approved_user()));
create policy "textbook_categories: admin insert" on public.textbook_categories
  for insert to authenticated with check ((select private.is_admin()));
create policy "textbook_categories: admin update" on public.textbook_categories
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "textbook_categories: admin delete" on public.textbook_categories
  for delete to authenticated using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- 권한 (Supabase 기본 권한을 회수하고 필요한 것만 부여)
-- -----------------------------------------------------------------------------
revoke all on public.textbook_categories from anon, authenticated;

grant select on public.textbook_categories to authenticated;
grant insert (name, sort_order), update (name, sort_order), delete
  on public.textbook_categories to authenticated;

grant insert (category_id), update (category_id) on public.textbooks to authenticated;
