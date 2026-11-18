-- =============================================================================
-- 회원 비활성화 (소프트 삭제)
--
--   * 회원을 삭제하면 행을 지우지 않고 profiles.deactivated_at / deactivated_by 를 기록한다.
--     (프로필을 물리 삭제하면 textbook_orders / event_payments 가 CASCADE 삭제되므로 금지)
--   * Edge Function(admin-members)이 profiles.deactivated_at 설정과 auth.users 로그인 차단(ban)을
--     함께 처리한다. 클라이언트에 deactivated_at / deactivated_by 수정 권한은 주지 않는다.
--   * 비활성화된 계정은 아직 만료되지 않은 JWT 가 있더라도 본인 프로필 조회(비활성 안내용) 외에는
--     어떤 데이터도 읽거나 쓸 수 없다 (fail-closed).
--   * 관리자는 비활성화된 회원의 기존 교재 신청 / 이벤트 송금 기록을 그대로 조회·처리할 수 있다.
--   * 비활성화된 회원은 새 이벤트 송금 대상으로 추가할 수 없고, 푸시 구독은 즉시 정리된다.
-- =============================================================================

alter table public.profiles
  add column deactivated_at timestamptz,
  add column deactivated_by uuid,
  add constraint profiles_deactivated_by_fkey
    foreign key (deactivated_by) references public.profiles (id) on delete set null,
  add constraint profiles_deactivated_requires_approved
    check (deactivated_at is null or is_approved),
  add constraint profiles_deactivated_by_requires_deactivated
    check (deactivated_by is null or deactivated_at is not null);

-- -----------------------------------------------------------------------------
-- 권한 헬퍼: 비활성화된 계정은 승인된 사용자 / 관리자로 보지 않는다.
-- -----------------------------------------------------------------------------

create or replace function private.is_approved_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_approved and deactivated_at is null
  );
$$;

create or replace function private.my_campus_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select campus_id from public.profiles
  where id = (select auth.uid()) and is_approved and deactivated_at is null;
$$;

create or replace function private.admin_campus_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select campus_id from public.profiles
  where id = (select auth.uid())
    and is_approved
    and deactivated_at is null
    and role = 'campus_admin';
$$;

create or replace function private.is_central_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and is_approved
      and deactivated_at is null
      and role = 'central_admin'
  );
$$;

-- -----------------------------------------------------------------------------
-- 회원 정보 보호 / 마지막 관리자 규칙 / 비활성화 정리 트리거
-- -----------------------------------------------------------------------------

create or replace function private.guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.deactivated_at is not null and new.deactivated_at is not null then
    raise exception '비활성화된 회원의 정보는 변경할 수 없습니다. 먼저 복구해 주세요.';
  end if;
  if auth.uid() is null or private.is_central_admin() then
    return new;
  end if;
  if old.role = 'central_admin' then
    raise exception '총괄 관리자 정보는 총괄 관리자만 바꿀 수 있습니다.';
  end if;
  if new.role = 'central_admin' then
    raise exception '총괄 관리자 지정은 총괄 관리자만 할 수 있습니다.';
  end if;
  if new.campus_id is distinct from old.campus_id then
    raise exception '회원의 캠퍼스는 총괄 관리자만 바꿀 수 있습니다.';
  end if;
  return new;
end;
$$;

create or replace function private.keep_last_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'central_admin' and old.is_approved and old.deactivated_at is null
     and (new.role <> 'central_admin' or not new.is_approved or new.deactivated_at is not null)
     and not exists (
       select 1 from public.profiles
       where role = 'central_admin' and is_approved and deactivated_at is null and id <> old.id
     ) then
    raise exception '마지막 총괄 관리자의 권한은 해제할 수 없습니다.';
  end if;

  if old.role = 'campus_admin' and old.is_approved and old.deactivated_at is null
     and (new.role <> 'campus_admin' or not new.is_approved or new.deactivated_at is not null
          or new.campus_id is distinct from old.campus_id)
     and (new.deactivated_at is not null or not private.is_central_admin())
     and not exists (
       select 1 from public.profiles
       where role = 'campus_admin' and is_approved and deactivated_at is null
         and campus_id = old.campus_id and id <> old.id
     ) then
    raise exception '캠퍼스의 마지막 관리자 권한은 해제할 수 없습니다.';
  end if;
  return new;
end;
$$;

drop trigger profiles_keep_last_admin on public.profiles;
create trigger profiles_keep_last_admin
  before update of role, is_approved, campus_id, deactivated_at on public.profiles
  for each row execute function private.keep_last_admin();

create function private.cleanup_deactivated_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.push_subscriptions where user_id = new.id;
  return new;
end;
$$;

create trigger profiles_cleanup_deactivated
  after update of deactivated_at on public.profiles
  for each row
  when (old.deactivated_at is null and new.deactivated_at is not null)
  execute function private.cleanup_deactivated_profile();

-- -----------------------------------------------------------------------------
-- 이벤트 송금 대상: 같은 캠퍼스의 활성 회원만 추가 가능
-- -----------------------------------------------------------------------------

create or replace function private.check_event_payment_campus()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  select * into v_profile from public.profiles where id = new.user_id;
  if v_profile.id is null
     or (select campus_id from public.events where id = new.event_id)
        is distinct from v_profile.campus_id then
    raise exception '이벤트와 같은 캠퍼스의 회원만 송금 대상으로 지정할 수 있습니다.';
  end if;
  if v_profile.deactivated_at is not null then
    raise exception '비활성화된 회원은 송금 대상으로 지정할 수 없습니다.';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 푸시 구독 저장: 활성 승인 회원만
-- -----------------------------------------------------------------------------

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_approved_user() then
    raise exception '승인된 회원만 알림을 받을 수 있습니다.';
  end if;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        created_at = now();
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS: 비활성화된 계정은 본인 주문 / 송금 / 구독도 조회할 수 없다 (관리자는 조회 가능)
-- -----------------------------------------------------------------------------

drop policy "orders: select own or campus admin" on public.textbook_orders;
create policy "orders: select own or campus admin" on public.textbook_orders
  for select to authenticated
  using (
    (user_id = (select auth.uid()) and (select private.is_approved_user()))
    or (select private.is_central_admin())
    or campus_id = (select private.admin_campus_id())
  );

drop policy "order_items: select own or campus admin" on public.textbook_order_items;
create policy "order_items: select own or campus admin" on public.textbook_order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.textbook_orders o
      where o.id = order_id
        and (
          (o.user_id = (select auth.uid()) and (select private.is_approved_user()))
          or (select private.is_central_admin())
          or o.campus_id = (select private.admin_campus_id())
        )
    )
  );

drop policy "event_payments: select own or campus admin" on public.event_payments;
create policy "event_payments: select own or campus admin" on public.event_payments
  for select to authenticated
  using (
    (user_id = (select auth.uid()) and (select private.is_approved_user()))
    or (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  );

drop policy "push_subscriptions: own select" on public.push_subscriptions;
create policy "push_subscriptions: own select" on public.push_subscriptions
  for select to authenticated
  using (user_id = (select auth.uid()) and (select private.is_approved_user()));

revoke execute on function private.cleanup_deactivated_profile() from public, anon, authenticated;
