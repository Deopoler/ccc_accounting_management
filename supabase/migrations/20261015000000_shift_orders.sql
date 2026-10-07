-- =============================================================================
-- 선택한 신청을 한 번에 이전 / 다음 회차로 옮긴다.
--
--   * 신청마다 자기 회차 기준으로 바로 앞(이전) / 바로 뒤(다음) 회차로 옮긴다.
--   * 이번 회차의 다음 회차가 없으면 만든다. 다음 회차보다 뒤로는 옮길 수 없다.
--   * 전부 옮기거나, 하나라도 옮길 수 없으면 아무것도 옮기지 않는다.
-- =============================================================================

create function public.admin_shift_textbook_orders(p_order_ids uuid[], p_offset int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.textbook_orders;
  v_round public.order_rounds;
  v_target uuid;
  v_count int := 0;
begin
  if p_offset is null or p_offset not in (-1, 1) then
    raise exception '이전 또는 다음 회차로만 옮길 수 있습니다.';
  end if;
  if p_order_ids is null or cardinality(p_order_ids) = 0 then
    raise exception '옮길 신청을 선택해 주세요.';
  end if;
  if cardinality(p_order_ids) > 1000 then
    raise exception '한 번에 옮길 수 있는 신청 수를 초과했습니다.';
  end if;

  for v_order in
    select * from public.textbook_orders
    where id = any (p_order_ids)
    order by id
    for update
  loop
    if private.can_admin_campus(v_order.campus_id) is not true then
      raise exception '신청 내역을 찾을 수 없습니다.';
    end if;

    select * into v_round from public.order_rounds where id = v_order.round_id;

    if p_offset < 0 then
      select id into v_target from public.order_rounds
      where campus_id = v_round.campus_id and deadline = v_round.starts_at;
      if not found then
        raise exception '이전 회차가 없습니다. (1년이 지난 회차는 삭제됩니다)';
      end if;
    else
      select id into v_target from public.order_rounds
      where campus_id = v_round.campus_id and starts_at = v_round.deadline;
      if not found then
        -- 다음 회차가 없는 회차는 이번 회차(→ 다음 회차를 만든다) 또는 이미 다음 회차뿐이다.
        if v_round.id <> (private.ensure_order_round(v_round.campus_id)).id then
          raise exception '다음 회차보다 뒤로는 옮길 수 없습니다.';
        end if;
        v_target := (public.admin_create_next_order_round(v_round.campus_id)).id;
      end if;
    end if;

    update public.textbook_orders set round_id = v_target where id = v_order.id;
    v_count := v_count + 1;
  end loop;

  if v_count <> (select count(distinct x) from unnest(p_order_ids) as x) then
    raise exception '신청 내역을 찾을 수 없습니다. 목록을 새로 불러와 주세요.';
  end if;
  return v_count;
end;
$$;

revoke execute on function public.admin_shift_textbook_orders(uuid[], int) from public, anon;
grant execute on function public.admin_shift_textbook_orders(uuid[], int) to authenticated;
