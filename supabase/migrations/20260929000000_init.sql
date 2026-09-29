-- =============================================================================
-- CCC 회계 관리 시스템 - 초기 스키마 / RLS
--
-- 권한 모델 요약
--   * 모든 테이블 RLS ON. anon 은 아무것도 못 한다.
--   * admin / member 모두 Postgres 롤은 `authenticated` 이므로, 역할 구분은 RLS
--     정책(private.is_admin())으로 한다.
--   * 컬럼 권한(GRANT UPDATE (col))은 "누구도 클라이언트에서 직접 바꾸면 안 되는
--     컬럼"을 막는 데 쓴다. (total_price, unit_price, paid_at, confirmed_by 등은
--     서버 함수/트리거만 쓴다.)
--   * 회원의 교재 신청/수정/취소는 SECURITY DEFINER RPC 로만 가능하다.
--     (주문 + 품목을 한 트랜잭션으로 쓰고, 가격은 서버가 교재 테이블에서 계산)
--   * 계정 생성/비밀번호 초기화는 Edge Function(service role)에서 한다.
-- =============================================================================

create schema if not exists private;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('member', 'admin');
create type public.order_status as enum ('requested', 'paid', 'cancelled');

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  student_id            text not null unique
                        check (student_id ~ '^[0-9A-Za-z]{4,20}$'),
  name                  text not null check (char_length(name) between 1 and 50),
  role                  public.user_role not null default 'member',
  must_change_password  boolean not null default true,
  created_at            timestamptz not null default now()
);

create table public.textbooks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 200),
  price       integer not null check (price >= 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table public.textbook_orders (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,
  -- 신청 회차의 시작일(수요일, KST). 회차는 매주 화요일 24:00(KST)에 마감된다.
  round_start  date not null,
  status       public.order_status not null default 'requested',
  total_price  integer not null default 0 check (total_price >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint textbook_orders_user_id_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade
);
create index textbook_orders_user_id_idx on public.textbook_orders (user_id);
create index textbook_orders_round_start_idx on public.textbook_orders (round_start);

create table public.textbook_order_items (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.textbook_orders (id) on delete cascade,
  textbook_id  uuid not null references public.textbooks (id) on delete restrict,
  quantity     integer not null check (quantity between 1 and 99),
  unit_price   integer not null check (unit_price >= 0), -- 신청 시점 가격
  unique (order_id, textbook_id)
);
create index textbook_order_items_textbook_id_idx
  on public.textbook_order_items (textbook_id);

create table public.events (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (char_length(title) between 1 and 200),
  amount       integer not null check (amount >= 0),
  due_date     date,
  description  text not null default '',
  created_at   timestamptz not null default now()
);

create table public.event_payments (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events (id) on delete cascade,
  user_id       uuid not null,
  is_paid       boolean not null default false,
  paid_at       timestamptz,
  confirmed_by  uuid,
  unique (event_id, user_id),
  constraint event_payments_user_id_fkey
    foreign key (user_id) references public.profiles (id) on delete cascade,
  constraint event_payments_confirmed_by_fkey
    foreign key (confirmed_by) references public.profiles (id) on delete set null
);
create index event_payments_user_id_idx on public.event_payments (user_id);

create table public.app_settings (
  key         text primary key,
  value       text not null default '',
  updated_at  timestamptz not null default now()
);

insert into public.app_settings (key, value) values
  ('bank_name', ''),
  ('account_number', ''),
  ('account_holder', '');

-- -----------------------------------------------------------------------------
-- Helper functions
-- -----------------------------------------------------------------------------

-- 현재 로그인 사용자가 관리자인지. RLS 정책에서 사용한다.
-- SECURITY DEFINER: profiles 의 RLS 를 거치지 않고 조회해야 재귀가 생기지 않는다.
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- 현재 교재 신청 회차의 시작일(수요일, KST).
-- 매주 화요일 24:00(= 수요일 00:00, KST)에 새 회차가 시작된다.
create function public.current_order_round()
returns date
language sql
stable
set search_path = ''
as $$
  select d - ((extract(isodow from d)::int - 3 + 7) % 7)
  from (select (now() at time zone 'Asia/Seoul')::date as d) t;
$$;

-- 회차 시작일 → 마감 시각(다음 수요일 00:00 KST = 화요일 24:00).
create function public.order_round_deadline(p_round_start date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select ((p_round_start + 7)::timestamp at time zone 'Asia/Seoul');
$$;

-- 클라이언트 표시용: 현재 회차와 마감 시각.
create function public.get_order_round()
returns table (round_start date, deadline timestamptz)
language sql
stable
set search_path = ''
as $$
  select r, public.order_round_deadline(r)
  from (select public.current_order_round() as r) t;
$$;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger textbook_orders_set_updated_at
  before update on public.textbook_orders
  for each row execute function private.set_updated_at();

create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function private.set_updated_at();

-- 송금 확인 시각/확인자는 서버에서만 기록한다.
create function private.stamp_event_payment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.is_paid is distinct from old.is_paid then
    if new.is_paid then
      new.paid_at := now();
      new.confirmed_by := auth.uid();
    else
      new.paid_at := null;
      new.confirmed_by := null;
    end if;
  else
    new.paid_at := old.paid_at;
    new.confirmed_by := old.confirmed_by;
  end if;
  return new;
end;
$$;

create trigger event_payments_stamp
  before insert or update on public.event_payments
  for each row execute function private.stamp_event_payment();

-- 이벤트 생성 시 모든 회원을 송금 대상으로 등록한다.
create function private.enroll_members_in_new_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.event_payments (event_id, user_id)
  select new.id, p.id from public.profiles p where p.role = 'member'
  on conflict (event_id, user_id) do nothing;
  return new;
end;
$$;

create trigger events_enroll_members
  after insert on public.events
  for each row execute function private.enroll_members_in_new_event();

-- 새 회원은 아직 마감되지 않은(또는 마감일 없는) 이벤트의 송금 대상으로 등록한다.
create function private.enroll_new_member_in_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role = 'member' then
    insert into public.event_payments (event_id, user_id)
    select e.id, new.id from public.events e
    where e.due_date is null
       or e.due_date >= (now() at time zone 'Asia/Seoul')::date
    on conflict (event_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger profiles_enroll_in_events
  after insert on public.profiles
  for each row execute function private.enroll_new_member_in_events();

-- 마지막 관리자를 일반 회원으로 바꾸지 못하게 막는다.
create function private.keep_last_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'admin' and new.role <> 'admin' and not exists (
    select 1 from public.profiles where role = 'admin' and id <> old.id
  ) then
    raise exception '마지막 관리자의 권한은 해제할 수 없습니다.';
  end if;
  return new;
end;
$$;

create trigger profiles_keep_last_admin
  before update of role on public.profiles
  for each row execute function private.keep_last_admin();

-- 비밀번호가 실제로 바뀌면 "첫 로그인 비밀번호 변경 필요" 플래그를 해제한다.
-- 클라이언트가 플래그를 직접 바꿀 수 없으므로 강제 변경을 건너뛸 수 없다.
-- (관리자 초기화 Edge Function 은 비밀번호 변경 후 플래그를 다시 true 로 설정한다.)
create function private.clear_must_change_password()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set must_change_password = false where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_password_changed
  after update of encrypted_password on auth.users
  for each row
  when (old.encrypted_password is distinct from new.encrypted_password)
  execute function private.clear_must_change_password();

-- -----------------------------------------------------------------------------
-- 교재 신청 RPC (회원용)
-- -----------------------------------------------------------------------------

-- p_items: [{"textbook_id": "<uuid>", "quantity": 1}, ...]
-- 주문 품목을 검증 후 교체하고 합계를 다시 계산한다. 가격은 교재 테이블 기준.
create function private.replace_order_items(p_order_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
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

  select
    count(*),
    count(distinct i.textbook_id),
    count(*) filter (where i.textbook_id is null),
    count(*) filter (where i.quantity is null or i.quantity not between 1 and 99),
    count(*) filter (where t.id is null)
  into v_count, v_distinct, v_null, v_bad_qty, v_unavailable
  from jsonb_to_recordset(p_items) as i (textbook_id uuid, quantity int)
  left join public.textbooks t on t.id = i.textbook_id and t.is_active;

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

-- 본인 주문을 잠그고 회원이 수정/취소 가능한 상태인지 확인한다.
create function private.lock_own_editable_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
begin
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

create function public.place_textbook_order(p_items jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  if auth.uid() is null
     or not exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception '로그인이 필요합니다.';
  end if;

  insert into public.textbook_orders (user_id, round_start)
  values (auth.uid(), public.current_order_round())
  returning id into v_order_id;

  perform private.replace_order_items(v_order_id, p_items);
  return v_order_id;
end;
$$;

create function public.update_textbook_order(p_order_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.lock_own_editable_order(p_order_id);
  perform private.replace_order_items(p_order_id, p_items);
end;
$$;

create function public.cancel_textbook_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.lock_own_editable_order(p_order_id);
  update public.textbook_orders set status = 'cancelled' where id = p_order_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------

-- 이벤트별 송금 요약. security_invoker 이므로 조회자의 RLS 가 그대로 적용된다.
create view public.event_payment_summaries
with (security_invoker = true)
as
select
  e.id as event_id,
  count(p.id)::int as target_count,
  (count(p.id) filter (where p.is_paid))::int as paid_count,
  ((count(p.id) filter (where p.is_paid)) * e.amount)::bigint as collected_amount
from public.events e
left join public.event_payments p on p.event_id = e.id
group by e.id;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.textbooks enable row level security;
alter table public.textbook_orders enable row level security;
alter table public.textbook_order_items enable row level security;
alter table public.events enable row level security;
alter table public.event_payments enable row level security;
alter table public.app_settings enable row level security;

-- profiles: 본인 또는 관리자만 조회, 수정은 관리자만. 생성/삭제는 Edge Function(service role).
create policy "profiles: select own or admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));
create policy "profiles: admin update" on public.profiles
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- textbooks: 로그인 사용자는 모두 조회, 쓰기는 관리자.
create policy "textbooks: authenticated select" on public.textbooks
  for select to authenticated using (true);
create policy "textbooks: admin insert" on public.textbooks
  for insert to authenticated with check ((select private.is_admin()));
create policy "textbooks: admin update" on public.textbooks
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "textbooks: admin delete" on public.textbooks
  for delete to authenticated using ((select private.is_admin()));

-- textbook_orders: 본인 것만 조회. 직접 쓰기는 관리자만(상태 변경/삭제).
-- 회원의 신청/수정/취소는 RPC(place/update/cancel_textbook_order)로만 한다.
create policy "orders: select own or admin" on public.textbook_orders
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy "orders: admin update" on public.textbook_orders
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "orders: admin delete" on public.textbook_orders
  for delete to authenticated using ((select private.is_admin()));

-- textbook_order_items: 본인 주문의 품목만 조회. 쓰기는 RPC 로만.
create policy "order_items: select own or admin" on public.textbook_order_items
  for select to authenticated
  using (
    (select private.is_admin())
    or exists (
      select 1 from public.textbook_orders o
      where o.id = order_id and o.user_id = (select auth.uid())
    )
  );

-- events: 로그인 사용자는 모두 조회, 쓰기는 관리자.
create policy "events: authenticated select" on public.events
  for select to authenticated using (true);
create policy "events: admin insert" on public.events
  for insert to authenticated with check ((select private.is_admin()));
create policy "events: admin update" on public.events
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "events: admin delete" on public.events
  for delete to authenticated using ((select private.is_admin()));

-- event_payments: 본인 것만 조회, 쓰기는 관리자.
create policy "event_payments: select own or admin" on public.event_payments
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy "event_payments: admin insert" on public.event_payments
  for insert to authenticated with check ((select private.is_admin()));
create policy "event_payments: admin update" on public.event_payments
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "event_payments: admin delete" on public.event_payments
  for delete to authenticated using ((select private.is_admin()));

-- app_settings: 로그인 사용자는 조회(송금 계좌 안내), 쓰기는 관리자.
create policy "app_settings: authenticated select" on public.app_settings
  for select to authenticated using (true);
create policy "app_settings: admin insert" on public.app_settings
  for insert to authenticated with check ((select private.is_admin()));
create policy "app_settings: admin update" on public.app_settings
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- 테이블 / 컬럼 권한
--   RLS 가 "어떤 행"을, GRANT 가 "어떤 컬럼"을 제어한다.
--   여기서 GRANT 하지 않은 컬럼은 관리자도 클라이언트에서 수정할 수 없다.
-- -----------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

grant select on
  public.profiles,
  public.textbooks,
  public.textbook_orders,
  public.textbook_order_items,
  public.events,
  public.event_payments,
  public.app_settings,
  public.event_payment_summaries
to authenticated;

-- profiles: id / student_id / created_at 은 변경 불가
grant update (name, role, must_change_password) on public.profiles to authenticated;

grant insert (title, price, is_active), update (title, price, is_active), delete
  on public.textbooks to authenticated;

-- textbook_orders: 상태만 변경 가능 (user_id, round_start, total_price 는 서버 전용)
grant update (status), delete on public.textbook_orders to authenticated;

grant insert (title, amount, due_date, description),
      update (title, amount, due_date, description),
      delete
  on public.events to authenticated;

-- event_payments: is_paid 만 변경 가능 (paid_at, confirmed_by 는 트리거가 기록)
grant insert (event_id, user_id), update (is_paid), delete
  on public.event_payments to authenticated;

grant insert (key, value), update (value) on public.app_settings to authenticated;

-- -----------------------------------------------------------------------------
-- 함수 실행 권한 (Postgres 기본값은 PUBLIC 실행 허용이므로 명시적으로 회수)
-- -----------------------------------------------------------------------------
revoke all on schema private from public;
grant usage on schema private to authenticated;

revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;

revoke execute on function
  public.current_order_round(),
  public.order_round_deadline(date),
  public.get_order_round(),
  public.place_textbook_order(jsonb),
  public.update_textbook_order(uuid, jsonb),
  public.cancel_textbook_order(uuid)
from public, anon;

grant execute on function
  public.current_order_round(),
  public.order_round_deadline(date),
  public.get_order_round(),
  public.place_textbook_order(jsonb),
  public.update_textbook_order(uuid, jsonb),
  public.cancel_textbook_order(uuid)
to authenticated;
