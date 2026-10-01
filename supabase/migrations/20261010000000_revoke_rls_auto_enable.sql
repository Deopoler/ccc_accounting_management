-- =============================================================================
-- public.rls_auto_enable() 실행 권한 회수
--
--   Supabase 가 프로젝트 생성 시 만드는 이벤트 트리거 함수다. (새 테이블에 RLS 자동 적용)
--   public 스키마에 있어 anon / authenticated 가 /rest/v1/rpc 로 보이므로 권한을 뺀다.
--   이벤트 트리거는 권한과 관계없이 그대로 동작한다.
--   함수가 없는 DB(로컬 / 테스트)도 있으므로 있을 때만 처리한다.
-- =============================================================================

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$$;
