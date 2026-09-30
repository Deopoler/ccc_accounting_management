-- =============================================================================
-- 교재 배송 확인
--
--   상태 흐름: 신청 → (관리자) 배송됨 → (회원) 수령 완료
--
--   * textbook_orders.is_shipped: 관리자만 바꾼다. (기존 RLS: orders update 는 admin 만)
--     shipped_at / shipped_by 는 트리거가 기록한다. (event_payments.is_paid 와 같은 방식)
--   * textbook_orders.received_at: 회원 본인이 RPC(confirm_textbook_received)로만 기록한다.
--     클라이언트에 컬럼 권한을 주지 않으므로 관리자도 직접 조작할 수 없다.
--   * 배송을 해제하면 수령 기록도 함께 지운다. (수령 완료는 항상 배송됨 상태여야 한다)
--   * 취소된 신청은 배송 처리할 수 없고, 배송된 신청은 취소 상태로 바꿀 수 없다.
--   * 배송된 신청은 회원이 수정/취소할 수 없다.
-- =============================================================================

alter table public.textbook_orders
  add column is_shipped   boolean not null default false,
  add column shipped_at   timestamptz,
  add column shipped_by   uuid,
  add column received_at  timestamptz,
  add constraint textbook_orders_shipped_by_fkey
    foreign key (shipped_by) references public.profiles (id) on delete set null,
  add constraint textbook_orders_received_requires_shipped
    check (received_at is null or is_shipped);

-- 배송 시각/처리자는 서버에서만 기록한다.
create function private.stamp_order_delivery()
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

create trigger textbook_orders_stamp_delivery
  before update on public.textbook_orders
  for each row execute function private.stamp_order_delivery();

-- 배송된 신청은 회원이 수정/취소할 수 없다. (나머지는 기존 검사와 같다)
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
  if v_order.round_start <> public.current_order_round() then
    raise exception '신청이 마감된 회차는 변경할 수 없습니다.';
  end if;
end;
$$;

-- 회원 본인이 교재 수령을 확인한다. 이미 확인했으면 기존 시각을 그대로 돌려준다.
create function public.confirm_textbook_received(p_order_id uuid)
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

  update public.textbook_orders set received_at = now() where id = p_order_id;
  return now();
end;
$$;

-- -----------------------------------------------------------------------------
-- 권한
-- -----------------------------------------------------------------------------

-- 배송 여부만 변경 가능 (shipped_at / shipped_by / received_at 은 서버 전용)
grant update (is_shipped) on public.textbook_orders to authenticated;

revoke execute on function private.stamp_order_delivery() from public, anon, authenticated;

revoke execute on function public.confirm_textbook_received(uuid) from public, anon;
grant execute on function public.confirm_textbook_received(uuid) to authenticated;
