-- =============================================================================
-- 자유 가입 + 관리자 승인
--
--   * 회원이 앱에서 직접 가입한다 (supabase.auth.signUp, 이메일 = {학번}@ccc.local).
--   * auth.users insert 트리거가 profiles 를 "승인 대기"(is_approved = false)로 만든다.
--     - 학번은 클라이언트가 보낸 값이 아니라 가입 이메일에서 추출한다.
--     - role 은 항상 member. (user_metadata 는 사용자가 조작할 수 있으므로 이름만 사용)
--   * 승인 전에는 본인 프로필 외에 아무 데이터도 조회/신청할 수 없다. (RLS / RPC)
--   * 승인되면 진행 중인 이벤트의 송금 대상으로 자동 등록된다.
-- =============================================================================

alter table public.profiles
  add column is_approved boolean not null default false;

-- 기존 계정(초기 관리자 등)은 승인 처리
update public.profiles set is_approved = true;

-- 직접 가입한 회원은 본인이 비밀번호를 정하므로 변경 강제가 필요 없다.
-- (관리자 비밀번호 초기화 시에만 true 로 설정된다)
alter table public.profiles alter column must_change_password set default false;

-- -----------------------------------------------------------------------------
-- 권한 헬퍼
-- -----------------------------------------------------------------------------

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and is_approved
  );
$$;

-- 승인된 사용자(회원 또는 관리자)인지.
create function private.is_approved_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_approved
  );
$$;

revoke execute on function private.is_approved_user() from public, anon;
grant execute on function private.is_approved_user() to authenticated;

-- -----------------------------------------------------------------------------
-- 가입 트리거
-- -----------------------------------------------------------------------------

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_student_id text;
  v_name text;
begin
  if v_email !~ '^[0-9a-z]{4,20}@ccc\.local$' then
    raise exception '학번 형식의 계정만 가입할 수 있습니다.';
  end if;
  v_student_id := split_part(v_email, '@', 1);
  v_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'name', '')), '');
  if v_name is not null and char_length(v_name) > 50 then
    raise exception '이름이 너무 깁니다.';
  end if;

  insert into public.profiles (id, student_id, name)
  values (new.id, v_student_id, coalesce(v_name, v_student_id));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- 로그인 아이디(= 이메일 = 학번)는 바꿀 수 없다. 남의 학번을 선점하는 것을 막는다.
create function private.prevent_email_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '계정 학번(이메일)은 변경할 수 없습니다.';
end;
$$;

create trigger prevent_email_change
  before update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function private.prevent_email_change();

-- -----------------------------------------------------------------------------
-- 이벤트 자동 등록: 승인된 회원만
-- -----------------------------------------------------------------------------

create or replace function private.enroll_members_in_new_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.event_payments (event_id, user_id)
  select new.id, p.id from public.profiles p
  where p.role = 'member' and p.is_approved
  on conflict (event_id, user_id) do nothing;
  return new;
end;
$$;

create or replace function private.enroll_new_member_in_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'member' and new.is_approved then
    insert into public.event_payments (event_id, user_id)
    select e.id, new.id from public.events e
    where e.due_date is null
       or e.due_date >= (now() at time zone 'Asia/Seoul')::date
    on conflict (event_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

-- 가입(insert) 시점이 아니라 승인 시점에 등록한다.
drop trigger profiles_enroll_in_events on public.profiles;
create trigger profiles_enroll_in_events
  after insert or update of is_approved on public.profiles
  for each row
  when (new.is_approved)
  execute function private.enroll_new_member_in_events();

-- 마지막 (승인된) 관리자를 강등 / 승인 해제하지 못하게 한다.
create or replace function private.keep_last_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'admin' and old.is_approved
     and (new.role <> 'admin' or not new.is_approved)
     and not exists (
       select 1 from public.profiles
       where role = 'admin' and is_approved and id <> old.id
     ) then
    raise exception '마지막 관리자의 권한은 해제할 수 없습니다.';
  end if;
  return new;
end;
$$;

drop trigger profiles_keep_last_admin on public.profiles;
create trigger profiles_keep_last_admin
  before update of role, is_approved on public.profiles
  for each row execute function private.keep_last_admin();

-- -----------------------------------------------------------------------------
-- RLS: 공용 데이터는 승인된 사용자만 조회
-- -----------------------------------------------------------------------------

drop policy "textbooks: authenticated select" on public.textbooks;
create policy "textbooks: approved select" on public.textbooks
  for select to authenticated using ((select private.is_approved_user()));

drop policy "events: authenticated select" on public.events;
create policy "events: approved select" on public.events
  for select to authenticated using ((select private.is_approved_user()));

drop policy "app_settings: authenticated select" on public.app_settings;
create policy "app_settings: approved select" on public.app_settings
  for select to authenticated using ((select private.is_approved_user()));

-- 관리자가 가입 승인 (RLS: 관리자만 profiles update 가능)
grant update (is_approved) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- 교재 신청 RPC: 승인된 사용자만
-- -----------------------------------------------------------------------------

create or replace function public.place_textbook_order(p_items jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  if auth.uid() is null or not private.is_approved_user() then
    raise exception '승인된 회원만 신청할 수 있습니다.';
  end if;

  insert into public.textbook_orders (user_id, round_start)
  values (auth.uid(), public.current_order_round())
  returning id into v_order_id;

  perform private.replace_order_items(v_order_id, p_items);
  return v_order_id;
end;
$$;

create or replace function private.lock_own_editable_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
begin
  if not private.is_approved_user() then
    raise exception '승인된 회원만 신청을 변경할 수 있습니다.';
  end if;

  select * into v_order from public.textbook_orders
  where id = p_order_id
  for update;

  if not found or v_order.user_id is distinct from auth.uid() then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;
  if v_order.status <> 'requested' then
    raise exception '입금확인되었거나 취소된 신청은 변경할 수 없습니다.';
  end if;
  if v_order.round_start <> public.current_order_round() then
    raise exception '신청이 마감된 회차는 변경할 수 없습니다.';
  end if;
end;
$$;

revoke execute on function
  private.handle_new_auth_user(),
  private.prevent_email_change()
from public, anon, authenticated;
