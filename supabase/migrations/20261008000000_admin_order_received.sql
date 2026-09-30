-- =============================================================================
-- 관리자 수령 처리
--
--   * 관리자도 배송된 신청의 수령을 체크/해제할 수 있다. (RPC admin_set_textbook_received)
--   * textbook_orders.received_by: 수령을 체크한 사람 (회원 본인 또는 관리자).
--     이 마이그레이션 전의 수령 기록은 모두 회원 본인이 한 것이므로 user_id 로 채운다.
--   * received_at / received_by 는 여전히 클라이언트에 컬럼 권한이 없다. (RPC 로만 기록)
--   * 배송을 해제하면 수령 기록(시각, 확인자)을 함께 지운다.
-- =============================================================================

alter table public.textbook_orders
  add column received_by uuid,
  add constraint textbook_orders_received_by_fkey
    foreign key (received_by) references public.profiles (id) on delete set null,
  add constraint textbook_orders_received_by_requires_received
    check (received_by is null or received_at is not null);

update public.textbook_orders set received_by = user_id where received_at is not null;

-- 배송 해제 시 수령 확인자도 지운다. (나머지는 기존과 같다)
create or replace function private.stamp_order_delivery()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_shipped is distinct from old.is_shipped then
    if new.is_shipped then
      new.shipped_at := now();
      new.shipped_by := auth.uid();
    else
      new.shipped_at := null;
      new.shipped_by := null;
      new.received_at := null;
      new.received_by := null;
    end if;
  else
    new.shipped_at := old.shipped_at;
    new.shipped_by := old.shipped_by;
  end if;

  if new.is_shipped and new.status = 'cancelled' then
    raise exception '취소된 신청은 배송 처리할 수 없습니다. (배송된 신청은 먼저 배송을 해제해 주세요)';
  end if;
  return new;
end;
$$;

-- 회원 본인 수령 확인: 확인자도 기록한다. (나머지는 기존과 같다)
create or replace function public.confirm_textbook_received(p_order_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
begin
  if auth.uid() is null or not private.is_approved_user() then
    raise exception '승인된 회원만 수령 확인할 수 있습니다.';
  end if;

  select * into v_order from public.textbook_orders
  where id = p_order_id
  for update;

  if not found or v_order.user_id is distinct from auth.uid() then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;
  if v_order.status = 'cancelled' then
    raise exception '취소된 신청은 수령 확인할 수 없습니다.';
  end if;
  if not v_order.is_shipped then
    raise exception '아직 배송되지 않은 신청입니다.';
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

-- 관리자 수령 체크/해제. 수령 시각을 돌려준다. (해제하면 null)
-- 이미 같은 상태면 기존 기록을 그대로 둔다.
create function public.admin_set_textbook_received(p_order_id uuid, p_received boolean)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
begin
  if not private.is_admin() then
    raise exception '관리자만 수령 처리할 수 있습니다.';
  end if;
  if p_received is null then
    raise exception '수령 여부를 지정해 주세요.';
  end if;

  select * into v_order from public.textbook_orders
  where id = p_order_id
  for update;

  if not found then
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

revoke execute on function public.admin_set_textbook_received(uuid, boolean) from public, anon;
grant execute on function public.admin_set_textbook_received(uuid, boolean) to authenticated;
