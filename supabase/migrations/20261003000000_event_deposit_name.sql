-- =============================================================================
-- 이벤트 입금자명
--
--   * events.deposit_name: 회원이 송금할 때 쓸 입금자명 형식.
--     `{이름}`, `{학번}` 자리표시자를 쓸 수 있다. 빈 문자열이면 회원 이름.
--     예) '{이름}MT' → '홍길동MT'
--   * 관리자만 수정할 수 있다. (기존 RLS: events 쓰기는 admin 만)
-- =============================================================================

alter table public.events
  add column deposit_name text not null default ''
    check (char_length(deposit_name) <= 50);

grant insert (deposit_name), update (deposit_name) on public.events to authenticated;
