-- =============================================================================
-- 캠퍼스
--
--   권한 구조
--     * member        회원. 자기 캠퍼스의 교재 / 이벤트만 보고, 본인 신청 / 송금만 본다.
--     * campus_admin  캠퍼스 관리자. 자기 캠퍼스의 교재 / 회원 / 신청 / 이벤트 / 계좌를 관리하고,
--                     자기 캠퍼스 회원을 캠퍼스 관리자로 지정 / 해제할 수 있다.
--     * central_admin 총괄 관리자. 모든 캠퍼스를 관리하고 캠퍼스를 추가한다.
--                     총괄 관리자 지정 / 해제와 회원의 캠퍼스 이동은 총괄 관리자만 한다.
--
--   로그인 이메일 (= 아이디)
--     * KAIST: {학번}@ccc.local (기존 그대로)
--     * 다른 캠퍼스: {학번}@{캠퍼스 코드}.ccc.local
--     * 가입 트리거가 이메일 도메인으로 캠퍼스를 정한다. (클라이언트가 보낸 값을 믿지 않는다)
--     * 캠퍼스 코드 / 이메일 도메인은 바꿀 수 없다. (바뀌면 그 캠퍼스 회원이 로그인하지 못한다)
--
--   기존 데이터
--     * 모든 회원 / 교재 / 카테고리 / 이벤트 / 신청은 KAIST 캠퍼스로 옮긴다.
--     * 기존 관리자(admin)는 KAIST 캠퍼스 관리자(campus_admin)가 된다.
--     * 학번 20250133 은 총괄 관리자가 된다. (회원이 있는데 이 계정이 없으면 마이그레이션을 멈춘다)
--     * 송금 계좌(app_settings)는 KAIST 캠퍼스로 복사한다. app_settings 는 이전 앱 호환용으로 남긴다.
--
--   학번은 캠퍼스 안에서만 유일하다. (다른 학교 학번은 겹칠 수 있다)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 캠퍼스
-- -----------------------------------------------------------------------------
create table public.campuses (
  id              uuid primary key default gen_random_uuid(),
  -- 로그인 이메일 도메인에 쓰는 영문 코드. 바꿀 수 없다.
  code            text not null unique check (code ~ '^[a-z][a-z0-9]{1,19}$'),
  name            text not null unique check (char_length(btrim(name)) between 1 and 50),
  -- 로그인 이메일 도메인. 기본은 {code}.ccc.local, KAIST 만 ccc.local. 바꿀 수 없다.
  email_domain    text not null unique,
  bank_name       text not null default '' check (char_length(bank_name) <= 50),
  account_number  text not null default '' check (char_length(account_number) <= 50),
  account_holder  text not null default '' check (char_length(account_holder) <= 50),
  created_at      timestamptz not null default now()
);

insert into public.campuses (code, name, email_domain, bank_name, account_number, account_holder)
select 'kaist', 'KAIST', 'ccc.local',
  coalesce((select value from public.app_settings where key = 'bank_name'), ''),
  coalesce((select value from public.app_settings where key = 'account_number'), ''),
  coalesce((select value from public.app_settings where key = 'account_holder'), '');

-- 이메일 도메인은 코드로 정하고, 코드 / 도메인은 바꿀 수 없다.
create function private.guard_campus()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.email_domain := coalesce(new.email_domain, new.code || '.ccc.local');
  elsif new.code is distinct from old.code
     or new.email_domain is distinct from old.email_domain then
    raise exception '캠퍼스 코드는 바꿀 수 없습니다. (회원 로그인 아이디에 쓰입니다)';
  end if;
  return new;
end;
$$;

create trigger campuses_guard
  before insert or update on public.campuses
  for each row execute function private.guard_campus();

-- -----------------------------------------------------------------------------
-- 역할: admin → campus_admin, central_admin 추가
--   enum 값 추가는 같은 트랜잭션에서 바로 쓸 수 없으므로 새 타입으로 바꾼다.
-- -----------------------------------------------------------------------------
drop trigger profiles_keep_last_admin on public.profiles;
drop function private.keep_last_admin();

create type public.user_role_v2 as enum ('member', 'campus_admin', 'central_admin');

alter table public.profiles alter column role drop default;
alter table public.profiles
  alter column role type public.user_role_v2
  using (case role::text when 'admin' then 'campus_admin' else role::text end)::public.user_role_v2;
alter table public.profiles alter column role set default 'member';

drop type public.user_role;
alter type public.user_role_v2 rename to user_role;

-- -----------------------------------------------------------------------------
-- 캠퍼스 컬럼 (기존 데이터는 모두 KAIST)
-- -----------------------------------------------------------------------------
alter table public.profiles add column campus_id uuid references public.campuses (id) on delete restrict;
alter table public.textbooks add column campus_id uuid references public.campuses (id) on delete restrict;
alter table public.textbook_categories add column campus_id uuid references public.campuses (id) on delete restrict;
alter table public.events add column campus_id uuid references public.campuses (id) on delete restrict;
alter table public.textbook_orders add column campus_id uuid references public.campuses (id) on delete restrict;

update public.profiles set campus_id = (select id from public.campuses where code = 'kaist');
update public.textbooks set campus_id = (select id from public.campuses where code = 'kaist');
update public.textbook_categories set campus_id = (select id from public.campuses where code = 'kaist');
update public.events set campus_id = (select id from public.campuses where code = 'kaist');
update public.textbook_orders set campus_id = (select id from public.campuses where code = 'kaist');

alter table public.profiles alter column campus_id set not null;
alter table public.textbooks alter column campus_id set not null;
alter table public.textbook_categories alter column campus_id set not null;
alter table public.events alter column campus_id set not null;
alter table public.textbook_orders alter column campus_id set not null;

create index profiles_campus_id_idx on public.profiles (campus_id);
create index textbooks_campus_id_idx on public.textbooks (campus_id);
create index events_campus_id_idx on public.events (campus_id);
create index textbook_orders_campus_id_idx on public.textbook_orders (campus_id);

-- 학번 / 카테고리 이름은 캠퍼스 안에서만 유일
alter table public.profiles drop constraint profiles_student_id_key;
alter table public.profiles add constraint profiles_campus_student_id_key unique (campus_id, student_id);

alter table public.textbook_categories drop constraint textbook_categories_name_key;
alter table public.textbook_categories add constraint textbook_categories_campus_name_key unique (campus_id, name);

-- 교재는 같은 캠퍼스의 카테고리에만 넣을 수 있다. (category_id 가 null 이면 검사하지 않는다)
alter table public.textbook_categories
  add constraint textbook_categories_id_campus_key unique (id, campus_id);
alter table public.textbooks drop constraint textbooks_category_id_fkey;
alter table public.textbooks
  add constraint textbooks_category_campus_fkey
    foreign key (category_id, campus_id)
    references public.textbook_categories (id, campus_id) on delete restrict;

-- -----------------------------------------------------------------------------
-- 총괄 관리자 지정 (새 "마지막 관리자" 규칙이 생기기 전에 한다)
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from public.profiles) then
    update public.profiles
    set role = 'central_admin', is_approved = true
    where student_id = '20250133'
      and campus_id = (select id from public.campuses where code = 'kaist');
    if not found then
      raise exception '총괄 관리자로 지정할 학번 20250133 계정이 없습니다. 먼저 가입시켜 주세요.';
    end if;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 권한 헬퍼 (RLS 에서 사용. 행마다 다시 계산하지 않도록 정책에서는 (select ...) 로 감싼다)
-- -----------------------------------------------------------------------------

-- 승인된 사용자의 캠퍼스. 승인 전이면 null.
create function private.my_campus_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select campus_id from public.profiles
  where id = (select auth.uid()) and is_approved;
$$;

-- 승인된 캠퍼스 관리자가 관리하는 캠퍼스. 캠퍼스 관리자가 아니면 null.
create function private.admin_campus_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select campus_id from public.profiles
  where id = (select auth.uid()) and is_approved and role = 'campus_admin';
$$;

create function private.is_central_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_approved and role = 'central_admin'
  );
$$;

-- 서버 함수 안에서 쓰는 캠퍼스 관리 권한 검사.
create function private.can_admin_campus(p_campus_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_central_admin() or p_campus_id = private.admin_campus_id();
$$;

-- -----------------------------------------------------------------------------
-- 회원 정보 변경 규칙
-- -----------------------------------------------------------------------------

-- 총괄 관리자 권한 / 캠퍼스 이동은 총괄 관리자만. (서비스 롤 / SQL Editor 는 auth.uid() 가 없어 통과)
create function private.guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
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

create trigger profiles_guard_update
  before update on public.profiles
  for each row execute function private.guard_profile_update();

-- 마지막 총괄 관리자는 해제할 수 없다.
-- 캠퍼스의 마지막 캠퍼스 관리자는 해제할 수 없다. (총괄 관리자는 예외: 캠퍼스 정리 / 교체)
create function private.keep_last_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'central_admin' and old.is_approved
     and (new.role <> 'central_admin' or not new.is_approved)
     and not exists (
       select 1 from public.profiles
       where role = 'central_admin' and is_approved and id <> old.id
     ) then
    raise exception '마지막 총괄 관리자의 권한은 해제할 수 없습니다.';
  end if;

  if old.role = 'campus_admin' and old.is_approved
     and (new.role <> 'campus_admin' or not new.is_approved
          or new.campus_id is distinct from old.campus_id)
     and not private.is_central_admin()
     and not exists (
       select 1 from public.profiles
       where role = 'campus_admin' and is_approved
         and campus_id = old.campus_id and id <> old.id
     ) then
    raise exception '캠퍼스의 마지막 관리자 권한은 해제할 수 없습니다.';
  end if;
  return new;
end;
$$;

create trigger profiles_keep_last_admin
  before update of role, is_approved, campus_id on public.profiles
  for each row execute function private.keep_last_admin();

-- -----------------------------------------------------------------------------
-- 가입: 이메일 도메인으로 캠퍼스를 정한다.
-- -----------------------------------------------------------------------------
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_campus_id uuid;
  v_name text;
begin
  if v_email !~ '^[0-9a-z]{4,20}@([a-z0-9]+\.)?ccc\.local$' then
    raise exception '학번 형식의 계정만 가입할 수 있습니다.';
  end if;

  select id into v_campus_id from public.campuses
  where email_domain = split_part(v_email, '@', 2);
  if v_campus_id is null then
    raise exception '존재하지 않는 캠퍼스입니다.';
  end if;

  v_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'name', '')), '');
  if v_name is not null and char_length(v_name) > 50 then
    raise exception '이름이 너무 깁니다.';
  end if;

  insert into public.profiles (id, campus_id, student_id, name)
  values (new.id, v_campus_id, split_part(v_email, '@', 1),
          coalesce(v_name, split_part(v_email, '@', 1)));
  return new;
end;
$$;

-- 로그인 / 가입 화면에서 캠퍼스를 고르기 위한 목록. 로그인 전에도 호출한다.
-- 계좌 등 다른 정보는 돌려주지 않는다.
create function public.list_campuses()
returns table (id uuid, code text, name text, email_domain text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.code, c.name, c.email_domain
  from public.campuses c
  order by c.name;
$$;

-- -----------------------------------------------------------------------------
-- 교재 신청: 신청은 회원의 캠퍼스로, 교재는 같은 캠퍼스 것만.
-- -----------------------------------------------------------------------------
create or replace function private.replace_order_items(p_order_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid;
  v_count int;
  v_distinct int;
  v_null int;
  v_bad_qty int;
  v_unavailable int;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception '신청할 교재를 선택해 주세요.';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception '한 번에 신청할 수 있는 교재 종류를 초과했습니다.';
  end if;

  select campus_id into v_campus_id from public.textbook_orders where id = p_order_id;

  select
    count(*),
    count(distinct i.textbook_id),
    count(*) filter (where i.textbook_id is null),
    count(*) filter (where i.quantity is null or i.quantity not between 1 and 99),
    count(*) filter (where t.id is null)
  into v_count, v_distinct, v_null, v_bad_qty, v_unavailable
  from jsonb_to_recordset(p_items) as i (textbook_id uuid, quantity int)
  left join public.textbooks t
    on t.id = i.textbook_id and t.is_active and t.campus_id = v_campus_id;

  if v_null > 0 or v_count <> v_distinct then
    raise exception '신청 교재 목록이 올바르지 않습니다.';
  end if;
  if v_bad_qty > 0 then
    raise exception '수량은 1~99권 사이여야 합니다.';
  end if;
  if v_unavailable > 0 then
    raise exception '신청할 수 없는 교재가 포함되어 있습니다.';
  end if;

  delete from public.textbook_order_items where order_id = p_order_id;

  insert into public.textbook_order_items (order_id, textbook_id, quantity, unit_price)
  select p_order_id, i.textbook_id, i.quantity, t.price
  from jsonb_to_recordset(p_items) as i (textbook_id uuid, quantity int)
  join public.textbooks t on t.id = i.textbook_id;

  update public.textbook_orders o
  set total_price = coalesce((
    select sum(oi.quantity * oi.unit_price)
    from public.textbook_order_items oi
    where oi.order_id = p_order_id
  ), 0)
  where o.id = p_order_id;
end;
$$;

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

  insert into public.textbook_orders (user_id, campus_id, round_start)
  values (auth.uid(), private.my_campus_id(), public.current_order_round())
  returning id into v_order_id;

  perform private.replace_order_items(v_order_id, p_items);
  return v_order_id;
end;
$$;

-- 관리자 수령 처리: 자기 캠퍼스(총괄 관리자는 전체) 신청만.
create or replace function public.admin_set_textbook_received(p_order_id uuid, p_received boolean)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
begin
  if not private.is_central_admin() and private.admin_campus_id() is null then
    raise exception '관리자만 수령 처리할 수 있습니다.';
  end if;
  if p_received is null then
    raise exception '수령 여부를 지정해 주세요.';
  end if;

  select * into v_order from public.textbook_orders
  where id = p_order_id
  for update;

  if not found or not private.can_admin_campus(v_order.campus_id) then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;

  if not p_received then
    if v_order.received_at is not null then
      update public.textbook_orders
      set received_at = null, received_by = null
      where id = p_order_id;
    end if;
    return null;
  end if;

  if v_order.status = 'cancelled' then
    raise exception '취소된 신청은 수령 처리할 수 없습니다.';
  end if;
  if not v_order.is_shipped then
    raise exception '배송되지 않은 신청은 수령 처리할 수 없습니다. 먼저 배송 처리해 주세요.';
  end if;
  if v_order.received_at is not null then
    return v_order.received_at;
  end if;

  update public.textbook_orders
  set received_at = now(), received_by = auth.uid()
  where id = p_order_id;
  return now();
end;
$$;

-- 송금 대상은 이벤트와 같은 캠퍼스 회원만.
create function private.check_event_payment_campus()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select campus_id from public.events where id = new.event_id)
     is distinct from (select campus_id from public.profiles where id = new.user_id) then
    raise exception '이벤트와 같은 캠퍼스의 회원만 송금 대상으로 지정할 수 있습니다.';
  end if;
  return new;
end;
$$;

create trigger event_payments_check_campus
  before insert or update of event_id, user_id on public.event_payments
  for each row execute function private.check_event_payment_campus();

-- -----------------------------------------------------------------------------
-- RLS: 모든 정책을 캠퍼스 기준으로 다시 만든다.
-- -----------------------------------------------------------------------------
alter table public.campuses enable row level security;

drop policy "profiles: select own or admin" on public.profiles;
drop policy "profiles: admin update" on public.profiles;
drop policy "textbooks: approved select" on public.textbooks;
drop policy "textbooks: admin insert" on public.textbooks;
drop policy "textbooks: admin update" on public.textbooks;
drop policy "textbooks: admin delete" on public.textbooks;
drop policy "textbook_categories: approved select" on public.textbook_categories;
drop policy "textbook_categories: admin insert" on public.textbook_categories;
drop policy "textbook_categories: admin update" on public.textbook_categories;
drop policy "textbook_categories: admin delete" on public.textbook_categories;
drop policy "orders: select own or admin" on public.textbook_orders;
drop policy "orders: admin update" on public.textbook_orders;
drop policy "orders: admin delete" on public.textbook_orders;
drop policy "order_items: select own or admin" on public.textbook_order_items;
drop policy "events: approved select" on public.events;
drop policy "events: admin insert" on public.events;
drop policy "events: admin update" on public.events;
drop policy "events: admin delete" on public.events;
drop policy "event_payments: select own or admin" on public.event_payments;
drop policy "event_payments: admin insert" on public.event_payments;
drop policy "event_payments: admin update" on public.event_payments;
drop policy "event_payments: admin delete" on public.event_payments;
drop policy "app_settings: approved select" on public.app_settings;
drop policy "app_settings: admin insert" on public.app_settings;
drop policy "app_settings: admin update" on public.app_settings;

-- 전역 "관리자" 개념은 없어졌다. 캠퍼스 기준 헬퍼만 쓴다. (정책이 모두 지워진 뒤에 지운다)
drop function private.is_admin();

-- campuses: 회원은 자기 캠퍼스만. 추가 / 삭제는 총괄 관리자, 수정은 그 캠퍼스 관리자도.
create policy "campuses: select own campus or central" on public.campuses
  for select to authenticated
  using (id = (select private.my_campus_id()) or (select private.is_central_admin()));
create policy "campuses: central insert" on public.campuses
  for insert to authenticated
  with check ((select private.is_central_admin()));
create policy "campuses: campus admin update" on public.campuses
  for update to authenticated
  using ((select private.is_central_admin()) or id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or id = (select private.admin_campus_id()));
create policy "campuses: central delete" on public.campuses
  for delete to authenticated
  using ((select private.is_central_admin()));

-- profiles: 본인, 또는 그 캠퍼스 관리자 / 총괄 관리자.
create policy "profiles: select own or campus admin" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_central_admin())
    or campus_id = (select private.admin_campus_id())
  );
create policy "profiles: campus admin update" on public.profiles
  for update to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));

-- 캠퍼스 공용 데이터(교재 / 카테고리 / 이벤트): 같은 캠퍼스의 승인된 사용자만 조회,
-- 쓰기는 그 캠퍼스 관리자 / 총괄 관리자.
create policy "textbooks: campus select" on public.textbooks
  for select to authenticated
  using (campus_id = (select private.my_campus_id()) or (select private.is_central_admin()));
create policy "textbooks: campus admin insert" on public.textbooks
  for insert to authenticated
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "textbooks: campus admin update" on public.textbooks
  for update to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "textbooks: campus admin delete" on public.textbooks
  for delete to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));

create policy "textbook_categories: campus select" on public.textbook_categories
  for select to authenticated
  using (campus_id = (select private.my_campus_id()) or (select private.is_central_admin()));
create policy "textbook_categories: campus admin insert" on public.textbook_categories
  for insert to authenticated
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "textbook_categories: campus admin update" on public.textbook_categories
  for update to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "textbook_categories: campus admin delete" on public.textbook_categories
  for delete to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));

create policy "events: campus select" on public.events
  for select to authenticated
  using (campus_id = (select private.my_campus_id()) or (select private.is_central_admin()));
create policy "events: campus admin insert" on public.events
  for insert to authenticated
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "events: campus admin update" on public.events
  for update to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "events: campus admin delete" on public.events
  for delete to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));

-- 신청: 본인 것, 또는 그 캠퍼스 관리자 / 총괄 관리자. 회원의 쓰기는 RPC 로만.
create policy "orders: select own or campus admin" on public.textbook_orders
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_central_admin())
    or campus_id = (select private.admin_campus_id())
  );
create policy "orders: campus admin update" on public.textbook_orders
  for update to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()))
  with check ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));
create policy "orders: campus admin delete" on public.textbook_orders
  for delete to authenticated
  using ((select private.is_central_admin()) or campus_id = (select private.admin_campus_id()));

create policy "order_items: select own or campus admin" on public.textbook_order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.textbook_orders o
      where o.id = order_id
        and (
          o.user_id = (select auth.uid())
          or (select private.is_central_admin())
          or o.campus_id = (select private.admin_campus_id())
        )
    )
  );

-- 송금: 본인 것, 또는 이벤트 캠퍼스의 관리자 / 총괄 관리자.
create policy "event_payments: select own or campus admin" on public.event_payments
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  );
create policy "event_payments: campus admin insert" on public.event_payments
  for insert to authenticated
  with check (
    (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  );
create policy "event_payments: campus admin update" on public.event_payments
  for update to authenticated
  using (
    (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  )
  with check (
    (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  );
create policy "event_payments: campus admin delete" on public.event_payments
  for delete to authenticated
  using (
    (select private.is_central_admin())
    or exists (
      select 1 from public.events e
      where e.id = event_id and e.campus_id = (select private.admin_campus_id())
    )
  );

-- app_settings: 이전 앱 호환용 (계좌는 campuses 로 옮겼다). 쓰기는 총괄 관리자만.
create policy "app_settings: approved select" on public.app_settings
  for select to authenticated using ((select private.is_approved_user()));
create policy "app_settings: central insert" on public.app_settings
  for insert to authenticated with check ((select private.is_central_admin()));
create policy "app_settings: central update" on public.app_settings
  for update to authenticated
  using ((select private.is_central_admin())) with check ((select private.is_central_admin()));

-- -----------------------------------------------------------------------------
-- 테이블 / 컬럼 권한
-- -----------------------------------------------------------------------------
revoke all on public.campuses from anon, authenticated;
grant select on public.campuses to authenticated;
-- code 는 추가할 때만, email_domain 은 트리거가 정한다.
grant insert (code, name, bank_name, account_number, account_holder),
      update (name, bank_name, account_number, account_holder),
      delete
  on public.campuses to authenticated;

-- 캠퍼스 이동은 총괄 관리자만 (트리거가 강제)
grant update (campus_id) on public.profiles to authenticated;

-- 교재 / 카테고리 / 이벤트는 만들 때 캠퍼스를 정하고, 이후 다른 캠퍼스로 옮길 수 없다.
grant insert (campus_id) on public.textbooks to authenticated;
grant insert (campus_id) on public.textbook_categories to authenticated;
grant insert (campus_id) on public.events to authenticated;

-- -----------------------------------------------------------------------------
-- 함수 실행 권한
-- -----------------------------------------------------------------------------
revoke execute on function
  private.guard_campus(),
  private.guard_profile_update(),
  private.keep_last_admin(),
  private.check_event_payment_campus(),
  private.can_admin_campus(uuid)
from public, anon, authenticated;

-- RLS 정책이 호출하므로 authenticated 에 필요하다. (본인 정보만 돌려준다)
revoke execute on function
  private.my_campus_id(),
  private.admin_campus_id(),
  private.is_central_admin()
from public, anon;
grant execute on function
  private.my_campus_id(),
  private.admin_campus_id(),
  private.is_central_admin()
to authenticated;

revoke execute on function public.list_campuses() from public;
grant execute on function public.list_campuses() to anon, authenticated;
