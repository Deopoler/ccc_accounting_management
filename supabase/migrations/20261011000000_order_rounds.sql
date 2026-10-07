-- =============================================================================
-- 교재 신청 회차를 캠퍼스별로 저장하고, 관리자가 마감 일시를 정한다.
--
--   * public.order_rounds: 캠퍼스별 회차. 회차는 빈틈없이 이어진다. (다음 회차 시작 = 이전 회차 마감)
--   * 이번 회차 = 마감이 지나지 않은 회차. 그보다 뒤 회차는 미리 만들지 않는다.
--     이번 회차가 마감되면 다음 회차를 마감 + 7일로 자동으로 만든다. (private.ensure_order_round)
--     → 관리자가 마감 일시를 바꾸면 그 요일 / 시각으로 매주 이어진다.
--   * 캠퍼스 관리자는 이번 회차의 마감 일시를 바꿀 수 있다. (admin_set_order_round_deadline)
--   * 캠퍼스 관리자는 신청을 같은 캠퍼스의 다른 회차로 옮길 수 있다. 신청 날짜와 상관없다.
--     (admin_move_textbook_order)
--   * textbook_orders.round_id 가 회차를 가리킨다. round_start(회차 시작 날짜)는
--     이전 앱 호환용으로 남기고 트리거가 round_id 에 맞춰 채운다.
--
--   기존 데이터
--     * 지금까지의 규칙(수요일 09:00 ~ 다음 수요일 09:00)대로 캠퍼스마다 첫 신청 회차부터
--       이번 회차까지 만들고, 기존 신청을 round_start 로 연결한다.
-- =============================================================================

create table public.order_rounds (
  id          uuid primary key default gen_random_uuid(),
  campus_id   uuid not null references public.campuses (id) on delete cascade,
  starts_at   timestamptz not null,
  deadline    timestamptz not null,
  created_at  timestamptz not null default now(),
  constraint order_rounds_deadline_after_start check (deadline > starts_at),
  constraint order_rounds_campus_starts_at_key unique (campus_id, starts_at),
  -- 신청이 같은 캠퍼스의 회차만 가리키도록 (textbook_orders 복합 FK)
  constraint order_rounds_id_campus_key unique (id, campus_id)
);

create index order_rounds_campus_deadline_idx on public.order_rounds (campus_id, deadline desc);

-- 회차 시작 날짜(KST) → 시작 시각 (그날 09:00 KST). 기존 주간 규칙용.
create function private.order_round_start_at(p_round_start date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (p_round_start::timestamp + interval '9 hours') at time zone 'Asia/Seoul';
$$;

-- -----------------------------------------------------------------------------
-- 기존 데이터: 캠퍼스마다 (첫 신청 회차 또는 이번 회차) ~ 이번 회차를 주간 규칙으로 만든다.
-- -----------------------------------------------------------------------------
insert into public.order_rounds (campus_id, starts_at, deadline)
select c.id,
       private.order_round_start_at(d::date),
       private.order_round_start_at(d::date + 7)
from public.campuses c
cross join lateral generate_series(
  least(
    coalesce(
      (select min(private.order_round_for(private.order_round_start_at(o.round_start)))
       from public.textbook_orders o where o.campus_id = c.id),
      private.order_round_for(now())
    ),
    private.order_round_for(now())
  )::timestamp,
  private.order_round_for(now())::timestamp,
  interval '7 days'
) as d;

alter table public.textbook_orders add column round_id uuid;

-- 기존 신청의 updated_at 은 그대로 둔다.
alter table public.textbook_orders disable trigger textbook_orders_set_updated_at;

update public.textbook_orders o
set round_id = r.id
from public.order_rounds r
where r.campus_id = o.campus_id
  and r.starts_at <= private.order_round_start_at(o.round_start)
  and r.deadline > private.order_round_start_at(o.round_start);

alter table public.textbook_orders enable trigger textbook_orders_set_updated_at;

alter table public.textbook_orders
  alter column round_id set not null,
  add constraint textbook_orders_round_campus_fkey
    foreign key (round_id, campus_id)
    references public.order_rounds (id, campus_id) on delete restrict;

create index textbook_orders_round_id_idx on public.textbook_orders (round_id);

comment on column public.textbook_orders.round_start is
  '이전 앱 호환용. 회차(round_id)의 시작 날짜(KST)를 트리거가 채운다.';

-- round_start 는 round_id 에 맞춰 서버가 채운다.
create function private.sync_order_round_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select (r.starts_at at time zone 'Asia/Seoul')::date into new.round_start
  from public.order_rounds r
  where r.id = new.round_id;
  return new;
end;
$$;

create trigger textbook_orders_sync_round_start
  before insert or update of round_id on public.textbook_orders
  for each row execute function private.sync_order_round_start();

-- -----------------------------------------------------------------------------
-- 이번 회차
-- -----------------------------------------------------------------------------

-- 캠퍼스의 이번 회차(마감 전 회차)를 돌려준다. 없으면 만든다.
--   * 회차가 하나도 없으면 주간 규칙(수요일 09:00 KST)으로 첫 회차를 만든다.
--   * 마지막 회차가 마감됐으면 마감 + 7일 회차를 이어서 만든다. (오래 비었으면 그 사이 회차도)
create function private.ensure_order_round(p_campus_id uuid)
returns public.order_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.order_rounds;
begin
  select * into v_round from public.order_rounds
  where campus_id = p_campus_id
  order by deadline desc
  limit 1;

  if found and v_round.deadline > now() then
    return v_round;
  end if;

  -- 동시에 여러 요청이 같은 회차를 만들지 않도록 캠퍼스 단위로 잠근다.
  perform 1 from public.campuses where id = p_campus_id for update;
  if not found then
    raise exception '캠퍼스를 찾을 수 없습니다.';
  end if;

  select * into v_round from public.order_rounds
  where campus_id = p_campus_id
  order by deadline desc
  limit 1;

  if not found then
    insert into public.order_rounds (campus_id, starts_at, deadline)
    values (
      p_campus_id,
      private.order_round_start_at(private.order_round_for(now())),
      private.order_round_start_at(private.order_round_for(now()) + 7)
    )
    returning * into v_round;
  end if;

  while v_round.deadline <= now() loop
    insert into public.order_rounds (campus_id, starts_at, deadline)
    values (p_campus_id, v_round.deadline, v_round.deadline + interval '7 days')
    returning * into v_round;
  end loop;

  return v_round;
end;
$$;

-- 이번 회차. p_campus_id 가 없으면 본인 캠퍼스.
-- 다른 캠퍼스는 그 캠퍼스 관리자 / 총괄 관리자만 조회할 수 있다.
-- 승인 전이라 캠퍼스가 없으면 빈 결과. (round_start 는 이전 앱 호환용)
drop function public.get_order_round();

create function public.get_order_round(p_campus_id uuid default null)
returns table (id uuid, round_start date, starts_at timestamptz, deadline timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid := coalesce(p_campus_id, private.my_campus_id());
  v_round public.order_rounds;
begin
  if v_campus_id is null then
    return;
  end if;
  if v_campus_id is distinct from private.my_campus_id()
     and private.can_admin_campus(v_campus_id) is not true then
    raise exception '회차 정보를 볼 권한이 없습니다.';
  end if;

  v_round := private.ensure_order_round(v_campus_id);
  return query select
    v_round.id,
    (v_round.starts_at at time zone 'Asia/Seoul')::date,
    v_round.starts_at,
    v_round.deadline;
end;
$$;

-- -----------------------------------------------------------------------------
-- 신청 / 회원 수정: 캠퍼스의 이번 회차 기준
-- -----------------------------------------------------------------------------
create or replace function public.place_textbook_order(p_items jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid;
  v_order_id uuid;
begin
  if auth.uid() is null or not private.is_approved_user() then
    raise exception '승인된 회원만 신청할 수 있습니다.';
  end if;

  v_campus_id := private.my_campus_id();
  insert into public.textbook_orders (user_id, campus_id, round_id)
  values (auth.uid(), v_campus_id, (private.ensure_order_round(v_campus_id)).id)
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
  if v_order.is_shipped then
    raise exception '배송된 신청은 변경할 수 없습니다.';
  end if;
  if v_order.round_id <> (private.ensure_order_round(v_order.campus_id)).id then
    raise exception '신청이 마감된 회차는 변경할 수 없습니다.';
  end if;
end;
$$;

-- 이제 쓰지 않는다. (주간 규칙 계산은 private.order_round_for 만 남긴다)
drop function public.current_order_round();
drop function public.order_round_deadline(date);

-- -----------------------------------------------------------------------------
-- 관리자: 마감 일시 변경 / 신청 회차 이동
-- -----------------------------------------------------------------------------

-- 캠퍼스 관리자가 아니면 null 이 아니라 false. (`if not ...` 검사가 null 로 통과되지 않게)
create or replace function private.can_admin_campus(p_campus_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_central_admin()
    or coalesce(p_campus_id = private.admin_campus_id(), false);
$$;

-- 이번 회차의 마감 일시를 바꾼다. 다음 회차부터는 이 마감에서 7일씩 이어진다.
create function public.admin_set_order_round_deadline(p_round_id uuid, p_deadline timestamptz)
returns public.order_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.order_rounds;
begin
  if p_deadline is null then
    raise exception '마감 일시를 지정해 주세요.';
  end if;

  select * into v_round from public.order_rounds
  where id = p_round_id
  for update;

  if not found or private.can_admin_campus(v_round.campus_id) is not true then
    raise exception '회차를 찾을 수 없습니다.';
  end if;
  if v_round.deadline <= now() then
    raise exception '이미 마감된 회차는 바꿀 수 없습니다.';
  end if;
  if p_deadline <= now() then
    raise exception '마감 일시는 지금보다 뒤여야 합니다.';
  end if;
  if p_deadline <= v_round.starts_at then
    raise exception '마감 일시는 회차 시작보다 뒤여야 합니다.';
  end if;
  if p_deadline > now() + interval '1 year' then
    raise exception '마감 일시는 1년 안이어야 합니다.';
  end if;

  update public.order_rounds
  set deadline = p_deadline
  where id = p_round_id
  returning * into v_round;
  return v_round;
end;
$$;

-- 신청을 같은 캠퍼스의 다른 회차로 옮긴다. 신청 날짜와 상관없이 어느 회차로든 옮길 수 있다.
create function public.admin_move_textbook_order(p_order_id uuid, p_round_id uuid)
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

  if not found or private.can_admin_campus(v_order.campus_id) is not true then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;
  if not exists (
    select 1 from public.order_rounds
    where id = p_round_id and campus_id = v_order.campus_id
  ) then
    raise exception '같은 캠퍼스의 회차로만 옮길 수 있습니다.';
  end if;

  update public.textbook_orders
  set round_id = p_round_id
  where id = p_order_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS / 권한
-- -----------------------------------------------------------------------------
alter table public.order_rounds enable row level security;

-- 같은 캠퍼스 사용자(신청 내역의 회차 표시)와 총괄 관리자만 조회. 쓰기는 RPC 로만.
create policy "order_rounds: campus select" on public.order_rounds
  for select to authenticated
  using (campus_id = (select private.my_campus_id()) or (select private.is_central_admin()));

revoke all on public.order_rounds from anon, authenticated;
grant select on public.order_rounds to authenticated;

revoke execute on function
  private.order_round_start_at(date),
  private.sync_order_round_start(),
  private.ensure_order_round(uuid)
from public, anon, authenticated;

revoke execute on function
  public.get_order_round(uuid),
  public.admin_set_order_round_deadline(uuid, timestamptz),
  public.admin_move_textbook_order(uuid, uuid)
from public, anon;

grant execute on function
  public.get_order_round(uuid),
  public.admin_set_order_round_deadline(uuid, timestamptz),
  public.admin_move_textbook_order(uuid, uuid)
to authenticated;
