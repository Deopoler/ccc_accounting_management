-- =============================================================================
-- 용량 관리: 1년이 지난 교재 신청 / 회차 / 이벤트를 지운다.
--
--   * 회차: 마감이 1년 넘게 지난 회차. 그 회차의 교재 신청(품목 포함)도 함께 지운다.
--   * 이벤트: 마감일이 1년 넘게 지난 이벤트 (마감일이 없으면 만든 날 기준). 송금 기록도 함께 지운다.
--   * 캠퍼스에 새 회차가 만들어질 때(대략 매주) 그 캠퍼스 것을 지운다. (예약 작업 없이)
--     지난 회차 채우기(1년)와 겹치지 않는다: 채우는 회차는 마감이 1년 안이다.
-- =============================================================================

create function private.purge_old_campus_data(p_campus_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.textbook_orders o
  using public.order_rounds r
  where r.id = o.round_id
    and r.campus_id = p_campus_id
    and r.deadline < now() - interval '1 year';

  delete from public.order_rounds
  where campus_id = p_campus_id
    and deadline < now() - interval '1 year';

  delete from public.events
  where campus_id = p_campus_id
    and coalesce(
      (due_date + 1)::timestamp at time zone 'Asia/Seoul',
      created_at
    ) < now() - interval '1 year';
end;
$$;

-- 새 회차를 만들 때 오래된 데이터를 지운다. (나머지는 기존과 같다)
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
    perform private.backfill_order_rounds(p_campus_id);
  end if;

  while v_round.deadline <= now() loop
    insert into public.order_rounds (campus_id, starts_at, deadline)
    values (p_campus_id, v_round.deadline, v_round.deadline + interval '7 days')
    returning * into v_round;
  end loop;

  perform private.purge_old_campus_data(p_campus_id);
  return v_round;
end;
$$;

revoke execute on function private.purge_old_campus_data(uuid) from public, anon, authenticated;

-- 기존 데이터
select private.purge_old_campus_data(id) from public.campuses;
