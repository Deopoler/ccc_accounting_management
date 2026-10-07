-- =============================================================================
-- 신청을 다음 회차로도 옮길 수 있게 한다.
--
--   * 관리자는 이번 회차 다음 회차를 미리 만들 수 있다. (admin_create_next_order_round)
--     다음 회차 = 이번 회차 마감 ~ 마감 + 7일. 한 번에 하나만 미리 만든다.
--   * 이번 회차 = 지금이 시작 ~ 마감 사이인 회차. (다음 회차가 있어도 이번 회차를 돌려준다)
--   * 이번 회차 마감을 바꾸면 다음 회차도 그 마감에서 시작해 7일 뒤 마감되도록 맞춘다.
--   * 회원은 마감 전 회차(이번 / 다음 회차)의 신청을 수정 / 취소할 수 있다.
-- =============================================================================

-- 캠퍼스의 이번 회차(시작 <= 지금 < 마감)를 돌려준다. 없으면 만든다.
create or replace function private.ensure_order_round(p_campus_id uuid)
returns public.order_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.order_rounds;
begin
  select * into v_round from public.order_rounds
  where campus_id = p_campus_id and starts_at <= now() and deadline > now();
  if found then
    return v_round;
  end if;

  -- 동시에 여러 요청이 같은 회차를 만들지 않도록 캠퍼스 단위로 잠근다.
  perform 1 from public.campuses where id = p_campus_id for update;
  if not found then
    raise exception '캠퍼스를 찾을 수 없습니다.';
  end if;

  -- 이번 회차가 없으면 미리 만든 회차도 없다. (회차는 빈틈없이 이어지므로) 마지막 회차부터 잇는다.
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

-- 이번 회차 다음 회차. 없으면 만든다. (이미 있으면 그대로 돌려준다)
create function public.admin_create_next_order_round(p_campus_id uuid)
returns public.order_rounds
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.order_rounds;
  v_next public.order_rounds;
begin
  if private.can_admin_campus(p_campus_id) is not true then
    raise exception '회차를 만들 권한이 없습니다.';
  end if;

  v_current := private.ensure_order_round(p_campus_id);

  insert into public.order_rounds (campus_id, starts_at, deadline)
  values (p_campus_id, v_current.deadline, v_current.deadline + interval '7 days')
  on conflict (campus_id, starts_at) do nothing;

  select * into v_next from public.order_rounds
  where campus_id = p_campus_id and starts_at = v_current.deadline;
  return v_next;
end;
$$;

-- 이번 회차의 마감 일시를 바꾼다. 미리 만든 다음 회차는 새 마감 ~ 새 마감 + 7일로 맞춘다.
create or replace function public.admin_set_order_round_deadline(p_round_id uuid, p_deadline timestamptz)
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
  if v_round.starts_at > now() then
    raise exception '다음 회차의 마감은 그 회차가 시작된 뒤에 바꿀 수 있습니다.';
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

  -- 다음 회차를 먼저 옮겨야 (campus_id, starts_at) 가 겹치지 않는다.
  update public.order_rounds
  set starts_at = p_deadline, deadline = p_deadline + interval '7 days'
  where campus_id = v_round.campus_id and starts_at = v_round.deadline;

  update public.order_rounds
  set deadline = p_deadline
  where id = p_round_id
  returning * into v_round;
  return v_round;
end;
$$;

-- 회원 수정 / 취소: 마감 전 회차(이번 / 다음 회차)의 신청만.
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
  if (select deadline from public.order_rounds where id = v_order.round_id) <= now() then
    raise exception '신청이 마감된 회차는 변경할 수 없습니다.';
  end if;
end;
$$;

revoke execute on function public.admin_create_next_order_round(uuid) from public, anon;
grant execute on function public.admin_create_next_order_round(uuid) to authenticated;
