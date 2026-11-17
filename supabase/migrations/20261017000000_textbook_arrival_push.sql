-- =============================================================================
-- 교재 도착(배송) 웹 푸시 알림
--
--   * 승인된 회원과 관리자 모두 push_subscriptions 에 본인 기기 구독을 저장할 수 있다.
--     (save_push_subscription RPC. 같은 기기에서 다른 계정으로 로그인하면 구독이 옮겨 간다)
--   * 관리자가 신청을 배송 처리(textbook_orders.is_shipped: false → true)하면
--     문장 단위(statement-level) 트리거가 주문자(user_id)별로 묶어 pg_net 으로 Edge Function `push` 를 호출한다.
--     한 번에 여러 신청을 배송 체크해도 회원마다 알림 요청은 한 번만 간다.
--   * 알림 요청이 실패해도 배송 처리는 실패하지 않는다.
-- =============================================================================

-- 승인된 회원(일반 회원, 관리자)은 이 기기의 푸시 구독을 저장한다.
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_approved
  ) then
    raise exception '승인된 회원만 알림을 받을 수 있습니다.';
  end if;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        created_at = now();
end;
$$;

-- -----------------------------------------------------------------------------
-- 교재 도착(배송) 알림 트리거
-- -----------------------------------------------------------------------------
create function private.notify_order_shipped_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_user_id uuid;
  v_order_ids jsonb;
begin
  if not exists (
    select 1
    from new_orders n
    join old_orders o on o.id = n.id
    where n.is_shipped and not o.is_shipped and n.status <> 'cancelled'
  ) then
    return null;
  end if;

  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  for v_user_id, v_order_ids in
    select n.user_id, jsonb_agg(n.id order by n.created_at, n.id)
    from new_orders n
    join old_orders o on o.id = n.id
    where n.is_shipped and not o.is_shipped and n.status <> 'cancelled'
    group by n.user_id
  loop
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object(
        'type', 'order_shipped',
        'user_id', v_user_id,
        'order_ids', v_order_ids
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', v_secret
      ),
      timeout_milliseconds := 10000
    );
  end loop;
  return null;
exception when others then
  -- 알림 때문에 배송 처리가 실패하면 안 된다.
  raise warning '교재 도착 알림 요청 실패: %', sqlerrm;
  return null;
end;
$$;

create trigger textbook_orders_notify_shipped
  after update on public.textbook_orders
  referencing old table as old_orders new table as new_orders
  for each statement
  execute function private.notify_order_shipped_push();

revoke execute on function private.notify_order_shipped_push() from public, anon, authenticated;
