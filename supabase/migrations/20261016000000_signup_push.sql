-- =============================================================================
-- 가입 신청 웹 푸시 알림
--
--   * 관리자가 설정 화면에서 "이 기기에서 알림 받기"를 켜면 브라우저 푸시 구독이 push_subscriptions 에 저장된다.
--     (save_push_subscription RPC. 같은 기기에서 다른 관리자로 로그인하면 구독이 그 관리자에게 옮겨 간다)
--   * 가입(승인 대기 프로필 생성) 트리거가 pg_net 으로 Edge Function `push` 를 호출한다.
--     함수가 가입한 캠퍼스의 캠퍼스 관리자와 총괄 관리자의 기기로 푸시를 보낸다.
--   * 함수 주소와 호출용 secret 은 Vault 에 둔다. 없으면 알림만 보내지 않는다.
--       select vault.create_secret('https://<ref>.supabase.co/functions/v1/push', 'push_function_url');
--       select vault.create_secret('<임의의 긴 문자열>', 'push_webhook_secret');  -- 함수 secret PUSH_WEBHOOK_SECRET 과 같게
--   * 알림 요청이 실패해도 가입은 실패하지 않는다. (pg_net 은 커밋 후 비동기로 보낸다)
-- =============================================================================

-- Supabase 에는 있다. (로컬 테스트용 PGlite 에는 없어서 스텁을 쓴다)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 푸시 구독 (기기 = 브라우저마다 하나)
-- -----------------------------------------------------------------------------
create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  endpoint    text not null unique
              check (endpoint ~ '^https://' and char_length(endpoint) <= 1000),
  p256dh      text not null check (char_length(p256dh) between 1 and 200),
  auth        text not null check (char_length(auth) between 1 and 100),
  created_at  timestamptz not null default now()
);

create index push_subscriptions_user_id_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

-- 본인 기기만 조회 / 해제. 저장은 RPC 로만 한다.
create policy "push_subscriptions: own select" on public.push_subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "push_subscriptions: own delete" on public.push_subscriptions
  for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.push_subscriptions from anon, authenticated;
grant select, delete on public.push_subscriptions to authenticated;

-- 관리자만 구독을 저장한다. 같은 endpoint(기기)가 있으면 현재 관리자에게 옮긴다.
create function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and is_approved and role <> 'member'
  ) then
    raise exception '관리자만 알림을 받을 수 있습니다.';
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
-- 가입 알림 트리거
-- -----------------------------------------------------------------------------
create function private.notify_signup_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if v_url is null or v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('type', 'signup', 'profile_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  -- 알림 때문에 가입이 실패하면 안 된다.
  raise warning '가입 알림 요청 실패: %', sqlerrm;
  return new;
end;
$$;

create trigger profiles_notify_signup
  after insert on public.profiles
  for each row
  when (not new.is_approved)
  execute function private.notify_signup_push();

revoke execute on function private.notify_signup_push() from public, anon, authenticated;
revoke execute on function public.save_push_subscription(text, text, text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;
