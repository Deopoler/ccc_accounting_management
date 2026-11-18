-- =============================================================================
-- 피드백함
--
--   * 승인된 활성 회원은 앱에서 피드백을 보낸다. (submit_feedback RPC 로만 저장한다. 테이블 직접 INSERT 권한 없음)
--       - user_id / campus_id 는 호출한 사람의 프로필에서 서버가 채운다.
--       - 한 사람이 10분에 5건까지만 보낼 수 있다.
--   * 피드백은 총괄 관리자(private.is_central_admin())만 읽고, 확인 처리(resolved_at / resolved_by)할 수 있다.
--     회원은 본인 것도 읽을 수 없고, 캠퍼스 관리자도 읽을 수 없다.
--   * 피드백이 저장되면 트리거가 pg_net 으로 Edge Function `push` 를 호출한다. (type: 'feedback')
--     함수가 총괄 관리자의 기기로 푸시를 보낸다. (signup_push 와 같은 방식, 같은 Vault secret)
--   * 알림 요청이 실패해도 피드백 저장은 실패하지 않는다.
-- =============================================================================

create table public.feedback (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  -- 보낸 시점의 캠퍼스 (회원이 캠퍼스를 옮겨도 그대로)
  campus_id    uuid not null references public.campuses (id) on delete restrict,
  content      text not null
               check (char_length(btrim(content, E' \t\r\n')) between 1 and 2000),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references public.profiles (id) on delete set null,
  check (resolved_by is null or resolved_at is not null)
);

create index feedback_created_at_idx on public.feedback (created_at desc);
create index feedback_user_created_at_idx on public.feedback (user_id, created_at desc);

alter table public.feedback enable row level security;

-- 총괄 관리자만 조회 / 확인 처리. INSERT 정책은 없다. (RPC 로만 저장)
create policy "feedback: central admin select" on public.feedback
  for select to authenticated
  using ((select private.is_central_admin()));

create policy "feedback: central admin update" on public.feedback
  for update to authenticated
  using ((select private.is_central_admin()))
  with check ((select private.is_central_admin()));

revoke all on public.feedback from anon, authenticated;
grant select on public.feedback to authenticated;
grant update (resolved_at, resolved_by) on public.feedback to authenticated;

-- -----------------------------------------------------------------------------
-- 확인 처리 보호: resolved_by / resolved_at 은 서버가 정한다. (다른 사람 이름으로 확인할 수 없다)
-- auth.uid() 가 없는 호출(서비스 롤, 프로필 삭제로 인한 resolved_by 정리 등)은 그대로 둔다.
-- -----------------------------------------------------------------------------
create function private.guard_feedback_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.resolved_at is null then
    -- 확인 해제
    new.resolved_by := null;
  elsif old.resolved_at is null then
    -- 새로 확인
    new.resolved_at := now();
    new.resolved_by := auth.uid();
  else
    -- 이미 확인된 것은 처음 확인한 사람 / 시각을 유지한다.
    new.resolved_at := old.resolved_at;
    new.resolved_by := old.resolved_by;
  end if;
  return new;
end;
$$;

create trigger feedback_guard_update
  before update of resolved_at, resolved_by on public.feedback
  for each row execute function private.guard_feedback_update();

-- -----------------------------------------------------------------------------
-- 피드백 보내기
-- -----------------------------------------------------------------------------
create function public.submit_feedback(p_content text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_content text := btrim(coalesce(p_content, ''), E' \t\r\n');
  v_campus_id uuid;
  v_id uuid;
begin
  if v_uid is null or not private.is_approved_user() then
    raise exception '승인된 회원만 피드백을 보낼 수 있습니다.';
  end if;

  if char_length(v_content) not between 1 and 2000 then
    raise exception '피드백은 1자 이상 2000자 이하로 입력해 주세요.';
  end if;

  -- 같은 사람이 동시에 여러 번 보내도 제한을 넘지 못하게 직렬화한다.
  perform pg_advisory_xact_lock(hashtextextended('feedback:' || v_uid::text, 0));
  if (
    select count(*) from public.feedback
    where user_id = v_uid and created_at > now() - interval '10 minutes'
  ) >= 5 then
    raise exception '잠시 후 다시 보내 주세요.';
  end if;

  select campus_id into v_campus_id from public.profiles where id = v_uid;

  insert into public.feedback (user_id, campus_id, content)
  values (v_uid, v_campus_id, v_content)
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 피드백 알림 트리거 (signup_push 와 같은 방식)
-- -----------------------------------------------------------------------------
create function private.notify_feedback_push()
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
    body := jsonb_build_object('type', 'feedback', 'feedback_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  -- 알림 때문에 피드백 저장이 실패하면 안 된다.
  raise warning '피드백 알림 요청 실패: %', sqlerrm;
  return new;
end;
$$;

create trigger feedback_notify_push
  after insert on public.feedback
  for each row execute function private.notify_feedback_push();

revoke execute on function private.guard_feedback_update() from public, anon, authenticated;
revoke execute on function private.notify_feedback_push() from public, anon, authenticated;
revoke execute on function public.submit_feedback(text) from public, anon;
grant execute on function public.submit_feedback(text) to authenticated;
