-- =============================================================================
-- 이벤트 송금 대상은 관리자가 직접 지정한다.
--
--   * 이벤트 생성 시 회원 자동 등록을 제거한다.
--   * 회원 승인 시 진행 중 이벤트 자동 등록도 제거한다.
--     (대상을 직접 고른 이벤트에 새 회원이 끼어들지 않도록)
-- =============================================================================

drop trigger if exists events_enroll_members on public.events;
drop function if exists private.enroll_members_in_new_event();

drop trigger if exists profiles_enroll_in_events on public.profiles;
drop function if exists private.enroll_new_member_in_events();
