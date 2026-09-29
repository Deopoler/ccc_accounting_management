-- =============================================================================
-- 이벤트 개인별 금액
--
--   * event_payments.amount_override: null 이면 이벤트 기본 금액(events.amount),
--     값이 있으면 해당 회원에게만 적용되는 금액.
--   * 관리자만 수정할 수 있다. (기존 RLS: event_payments update 는 admin 만)
--   * 요약 뷰의 수금액 / 목표 금액은 개인별 금액 기준으로 계산한다.
-- =============================================================================

alter table public.event_payments
  add column amount_override integer
    check (amount_override is null or amount_override between 0 and 100000000);

grant update (amount_override) on public.event_payments to authenticated;

-- 기존 컬럼 순서를 유지하고 expected_amount 를 끝에 추가한다.
create or replace view public.event_payment_summaries
with (security_invoker = true)
as
select
  e.id as event_id,
  count(p.id)::int as target_count,
  (count(p.id) filter (where p.is_paid))::int as paid_count,
  coalesce(sum(coalesce(p.amount_override, e.amount)) filter (where p.is_paid), 0)::bigint
    as collected_amount,
  coalesce(sum(coalesce(p.amount_override, e.amount)), 0)::bigint as expected_amount
from public.events e
left join public.event_payments p on p.event_id = e.id
group by e.id;
