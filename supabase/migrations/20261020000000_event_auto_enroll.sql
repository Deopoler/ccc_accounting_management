-- =============================================================================
-- 이벤트: 새로 가입한 회원 자동 송금 대상 추가
--
--   * events.auto_enroll_new_members: 켜 두면 가입이 승인된 회원이 송금 대상(event_payments)에
--     자동으로 추가된다. 기본값은 꺼짐(관리자가 대상을 직접 고른다).
--   * 이벤트 생성/수정은 관리자만 할 수 있다. (기존 RLS: 캠퍼스 관리자 / 총괄 관리자)
--   * 대상 이벤트: 설정이 켜져 있고, 회원과 같은 캠퍼스이며, 마감 전(마감일 없음 포함)인 이벤트.
--   * 새로 승인되는 순간에만 등록한다. (insert 시 승인됨, 또는 is_approved false -> true)
--     - 설정을 켠다고 기존 회원이 추가되지 않는다.
--     - 비활성화 회원 복구는 is_approved 변경이 아니므로 등록하지 않는다.
--   * 역할은 가리지 않는다. 직접 대상을 고를 때 관리자 계정도 고를 수 있는 것과 같다.
-- =============================================================================

alter table public.events
  add column auto_enroll_new_members boolean not null default false;

grant insert (auto_enroll_new_members), update (auto_enroll_new_members)
  on public.events to authenticated;

create function private.enroll_approved_member_in_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- check_event_payment_campus 가 거부하지 않도록 같은 캠퍼스의 활성 회원만 넣는다.
  if new.deactivated_at is not null then
    return new;
  end if;

  insert into public.event_payments (event_id, user_id)
  select e.id, new.id
  from public.events e
  where e.auto_enroll_new_members
    and e.campus_id = new.campus_id
    and (e.due_date is null or e.due_date >= (now() at time zone 'Asia/Seoul')::date)
  on conflict (event_id, user_id) do nothing;
  return new;
end;
$$;

-- insert 트리거의 WHEN 에서는 OLD 를 쓸 수 없어 insert / update 를 나눈다.
create trigger profiles_enroll_on_insert
  after insert on public.profiles
  for each row
  when (new.is_approved)
  execute function private.enroll_approved_member_in_events();

create trigger profiles_enroll_on_approve
  after update of is_approved on public.profiles
  for each row
  when (not old.is_approved and new.is_approved)
  execute function private.enroll_approved_member_in_events();

revoke execute on function private.enroll_approved_member_in_events()
  from public, anon, authenticated;
