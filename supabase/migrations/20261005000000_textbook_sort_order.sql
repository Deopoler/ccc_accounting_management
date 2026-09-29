-- =============================================================================
-- 교재 순서
--
--   * textbooks.sort_order: 카테고리 안에서의 표시 순서 (작을수록 위).
--   * 기존 교재는 카테고리별 이름순으로 번호를 매긴다.
--   * 관리자만 수정할 수 있다. (기존 RLS: textbooks 쓰기는 admin 만)
-- =============================================================================

alter table public.textbooks
  add column sort_order integer not null default 0;

update public.textbooks t
set sort_order = r.rn
from (
  select id, (row_number() over (partition by category_id order by title) - 1)::int as rn
  from public.textbooks
) r
where r.id = t.id;

grant insert (sort_order), update (sort_order) on public.textbooks to authenticated;
