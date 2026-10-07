-- =============================================================================
-- 지난 회차는 신청이 없어도 있게 한다.
--
--   * 캠퍼스마다 최근 1년(52주) 회차가 항상 있도록, 가장 오래된 회차 앞으로 1주씩 채운다.
--     (회차는 빈틈없이 이어지므로 가장 오래된 회차 시작에서 7일씩 거슬러 올라간다)
--   * 새 캠퍼스는 첫 회차를 만들 때 함께 채운다.
--   * 관리자는 신청을 이 지난 회차로도 옮길 수 있다.
-- =============================================================================

-- 가장 오래된 회차 앞으로, 시작이 지금보다 1년 이상 전이 될 때까지 1주 회차를 채운다.
create function private.backfill_order_rounds(p_campus_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oldest timestamptz;
begin
  select min(starts_at) into v_oldest from public.order_rounds where campus_id = p_campus_id;
  if v_oldest is null then
    return;
  end if;

  while v_oldest > now() - interval '364 days' loop
    insert into public.order_rounds (campus_id, starts_at, deadline)
    values (p_campus_id, v_oldest - interval '7 days', v_oldest);
    v_oldest := v_oldest - interval '7 days';
  end loop;
end;
$$;

-- 첫 회차를 만들 때 지난 1년 회차도 채운다. (나머지는 기존과 같다)
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

  return v_round;
end;
$$;

revoke execute on function private.backfill_order_rounds(uuid) from public, anon, authenticated;

-- 기존 캠퍼스
select private.backfill_order_rounds(id) from public.campuses;
