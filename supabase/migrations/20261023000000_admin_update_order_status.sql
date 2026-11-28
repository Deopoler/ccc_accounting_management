-- =============================================================================
-- 선택한 신청의 상태를 원자적으로 일괄 변경한다. (CAS: 기대한 이전 상태만 변경)
--
--   * security invoker: 호출자의 RLS(캠퍼스 관리자 / 총괄 관리자)와 컬럼 권한을 그대로 따른다.
--   * 요청한 고유 id 중 하나라도 상태가 다르거나 권한이 없으면 P0009 예외를 던져 전체를 롤백한다.
--     (paid -> requested 시 트리거가 입금 연결을 해제해도 충돌 시 함께 롤백된다.)
-- =============================================================================

create function public.admin_update_order_status(
  p_ids uuid[],
  p_from text[],
  p_to text
)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ids      uuid[];
  v_from     public.order_status[];
  v_to       public.order_status;
  v_expected int;
  v_updated  int;
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    raise exception '변경할 신청을 선택해 주세요.';
  end if;

  select array_agg(distinct x) into v_ids
  from unnest(p_ids) as x
  where x is not null;

  v_expected := coalesce(cardinality(v_ids), 0);
  if v_expected = 0 then
    raise exception '변경할 신청을 선택해 주세요.';
  end if;
  if v_expected > 1000 then
    raise exception '한 번에 변경할 수 있는 신청 수를 초과했습니다.';
  end if;

  if p_to is null or p_to not in ('requested', 'paid', 'cancelled') then
    raise exception '유효하지 않은 신청 상태입니다.';
  end if;
  if p_from is null or cardinality(p_from) = 0 then
    raise exception '신청 상태가 변경됨, 다시 확인해 주세요.'
      using errcode = 'P0009';
  end if;
  if exists (
    select 1 from unnest(p_from) as s
    where s is null or s not in ('requested', 'paid', 'cancelled')
  ) then
    raise exception '유효하지 않은 신청 상태입니다.';
  end if;

  v_to := p_to::public.order_status;
  select array_agg(distinct s::public.order_status) into v_from
  from unnest(p_from) as s;

  update public.textbook_orders
  set status = v_to
  where id = any (v_ids)
    and status = any (v_from);

  get diagnostics v_updated = row_count;
  if v_updated <> v_expected then
    raise exception '신청 상태가 변경됨, 다시 확인해 주세요.'
      using errcode = 'P0009';
  end if;

  return v_updated;
end;
$$;

revoke execute on function public.admin_update_order_status(uuid[], text[], text) from public, anon;
grant execute on function public.admin_update_order_status(uuid[], text[], text) to authenticated;
