-- =============================================================================
-- 교재 신청 마감: 매주 수요일 오전 9시 (KST)
--
--   * 회차는 수요일 09:00 에 시작해 다음 수요일 09:00 에 마감된다.
--   * 회차는 지금처럼 시작 수요일의 날짜(round_start)로 식별하므로 기존 주문은 그대로다.
--   * private.order_round_for(ts): 임의 시각의 회차 (경계 테스트용). 클라이언트는 호출할 수 없다.
-- =============================================================================

-- 시각 → 회차 시작일(수요일). KST 기준으로 9시간을 빼면 "수요일 09:00" 이 "수요일 00:00" 이 되므로
-- 그 날짜가 속한 주의 수요일을 구하면 된다.
create function private.order_round_for(p_at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select d - ((extract(isodow from d)::int - 3 + 7) % 7)
  from (select ((p_at at time zone 'Asia/Seoul') - interval '9 hours')::date as d) t;
$$;

revoke execute on function private.order_round_for(timestamptz) from public, anon, authenticated;

-- 회원은 private.order_round_for 를 직접 실행할 수 없으므로 definer 로 감싼다. (부작용 없는 날짜 계산)
create or replace function public.current_order_round()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select private.order_round_for(now());
$$;

-- 회차 시작일 → 마감 시각 (다음 수요일 09:00 KST)
create or replace function public.order_round_deadline(p_round_start date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select ((p_round_start + 7)::timestamp + interval '9 hours') at time zone 'Asia/Seoul';
$$;
