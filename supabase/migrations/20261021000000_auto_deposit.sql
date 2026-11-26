-- 자동 입금 확인: 캠퍼스 설정, 입금 내역, 자동 매칭/취소/수동 연결, 보관 기간, 푸시 알림.

create table public.campus_deposit_settings (
  campus_id            uuid primary key references public.campuses (id) on delete cascade,
  enabled              boolean not null default false,
  bank_code            text not null default 'toss' check (bank_code in ('toss')),
  account_label        text not null default '' check (char_length(account_label) <= 50),
  token_hash           text unique check (token_hash is null or token_hash ~ '^[0-9a-f]{64}$'),
  token_prefix         text check (token_prefix is null or char_length(token_prefix) <= 20),
  token_rotated_at     timestamptz,
  last_received_at     timestamptz,
  last_ignored_at      timestamptz,
  last_ignored_reason  text check (last_ignored_reason is null or char_length(last_ignored_reason) <= 50),
  ignored_count        integer not null default 0 check (ignored_count >= 0),
  rate_window_start    timestamptz,
  rate_window_count    integer not null default 0 check (rate_window_count >= 0),
  updated_at           timestamptz not null default now(),
  constraint campus_deposit_settings_enabled_requires_label
    check (not enabled or char_length(btrim(account_label)) > 0)
);

create trigger campus_deposit_settings_set_updated_at
  before update on public.campus_deposit_settings
  for each row execute function private.set_updated_at();

create table public.bank_deposits (
  id                  uuid primary key default gen_random_uuid(),
  campus_id           uuid not null references public.campuses (id) on delete cascade,
  dedupe_key          text not null check (char_length(dedupe_key) between 1 and 128),
  raw_hash            text not null check (raw_hash ~ '^[0-9a-f]{64}$'),
  bank_code           text not null check (bank_code in ('toss')),
  status              text not null check (
    status in ('unparsed', 'unmatched', 'ambiguous', 'auto_matched', 'manual_matched', 'ignored', 'undone')
  ),
  depositor_name      text check (depositor_name is null or char_length(depositor_name) between 1 and 100),
  amount              integer check (amount is null or amount between 1 and 100000000),
  deposited_at        timestamptz not null,
  received_at         timestamptz not null default now(),
  raw_title           text check (raw_title is null or char_length(raw_title) <= 300),
  raw_text            text check (raw_text is null or char_length(raw_text) <= 1000),
  raw_package         text check (raw_package is null or char_length(raw_package) <= 100),
  raw_expires_at      timestamptz,
  match_reason        text check (match_reason is null or char_length(match_reason) <= 100),
  candidate_snapshot  jsonb,
  matched_at          timestamptz,
  matched_by          uuid references public.profiles (id) on delete set null,
  undone_at           timestamptz,
  undone_by           uuid references public.profiles (id) on delete set null,
  ignored_at          timestamptz,
  ignored_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint bank_deposits_campus_dedupe_key unique (campus_id, dedupe_key),
  constraint bank_deposits_parsed_fields check (
    status in ('unparsed', 'ignored')
    or (depositor_name is not null and amount is not null)
  ),
  constraint bank_deposits_raw_only_unparsed check (
    status = 'unparsed'
    or (raw_title is null and raw_text is null and raw_package is null and raw_expires_at is null)
  )
);

create index bank_deposits_campus_received_idx
  on public.bank_deposits (campus_id, received_at desc);
create index bank_deposits_campus_status_received_idx
  on public.bank_deposits (campus_id, status, received_at desc);
create index bank_deposits_campus_raw_hash_deposited_idx
  on public.bank_deposits (campus_id, raw_hash, deposited_at desc);
create index bank_deposits_raw_expires_idx
  on public.bank_deposits (campus_id, raw_expires_at)
  where raw_expires_at is not null;

create trigger bank_deposits_set_updated_at
  before update on public.bank_deposits
  for each row execute function private.set_updated_at();

-- 어떤 입금으로 확인됐는지 주문/송금 행에 기록한다. 클라이언트에는 UPDATE 권한을 주지 않는다.
alter table public.textbook_orders
  add column confirmed_deposit_id uuid references public.bank_deposits (id) on delete set null;
create index textbook_orders_confirmed_deposit_idx
  on public.textbook_orders (confirmed_deposit_id)
  where confirmed_deposit_id is not null;

alter table public.event_payments
  add column confirmed_deposit_id uuid references public.bank_deposits (id) on delete set null;
create index event_payments_confirmed_deposit_idx
  on public.event_payments (confirmed_deposit_id)
  where confirmed_deposit_id is not null;

-- Dart renderDepositName 과 동일한 규칙: 앞뒤 공백 제거 후 비어 있으면 이름, 아니면 {이름}/{학번} 치환.
create function private.render_event_deposit_name(
  p_template text,
  p_name text,
  p_student_id text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_t text := btrim(coalesce(p_template, ''), E' \t\r\n');
begin
  if v_t = '' then
    return p_name;
  end if;
  return replace(replace(v_t, '{이름}', p_name), '{학번}', p_student_id);
end;
$$;

create function private.normalize_depositor_name(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(normalize(coalesce(p_text, ''), NFC), '\s+', '', 'g'));
$$;

-- 은행 입금자명 잘림(6~10자)을 고려해 6자 이상일 때만 접두사 일치를 허용한다.
create function private.depositor_name_matches(p_dep_norm text, p_expected_norm text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_dep_norm <> ''
    and p_expected_norm <> ''
    and (
      p_dep_norm = p_expected_norm
      or (
        char_length(p_dep_norm) >= 6
        and char_length(p_expected_norm) > char_length(p_dep_norm)
        and starts_with(p_expected_norm, p_dep_norm)
      )
    );
$$;

-- 입금 푸시 알림 요청. 알림 실패가 입금 처리를 되돌리지 않는다.
create function private.notify_deposit_push(p_deposit_id uuid, p_is_new_ingest boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_type text;
  v_url text;
  v_secret text;
begin
  select status into v_status from public.bank_deposits where id = p_deposit_id;
  if not found then
    return;
  end if;

  if v_status = 'auto_matched' then
    v_type := 'deposit_confirmed';
  elsif p_is_new_ingest and v_status in ('unmatched', 'ambiguous', 'unparsed') then
    v_type := 'deposit_review';
  else
    return;
  end if;

  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if v_url is null or v_secret is null then
    return;
  end if;

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('type', v_type, 'deposit_id', p_deposit_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    timeout_milliseconds := 10000
  );
exception when others then
  raise warning '입금 알림 요청 실패: %', sqlerrm;
end;
$$;

-- 한 트랜잭션 안에서 미납 주문/송금을 잠그고 정확히 1건일 때만 자동 확인한다.
create function private.match_and_confirm_deposit(p_deposit_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_dep_norm text;
  v_count int;
  v_has_event boolean;
  v_has_textbook boolean;
  v_snapshot jsonb;
  v_cand record;
  v_event_template text;
  v_has_homonym boolean := false;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.depositor_name is null or v_deposit.amount is null then
    raise exception '해석되지 않은 입금은 자동 매칭할 수 없습니다.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('deposit_match:' || v_deposit.campus_id::text, 0));

  v_dep_norm := private.normalize_depositor_name(v_deposit.depositor_name);
  if v_dep_norm = '' then
    update public.bank_deposits
    set status = 'unmatched',
        match_reason = 'empty_depositor_name',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'unmatched';
  end if;

  -- 관리자 수동 확인이나 회원 주문 수정과 경합하지 않도록 같은 캠퍼스 미납 행을 고정 순서로 잠근다.
  perform 1 from public.textbook_orders o
  where o.campus_id = v_deposit.campus_id and o.status = 'requested'
  order by o.id
  for update of o;

  perform 1 from public.event_payments ep
  join public.events e on e.id = ep.event_id
  where e.campus_id = v_deposit.campus_id and not ep.is_paid
  order by ep.id
  for update of ep;

  with candidates as (
    select
      'event'::text as kind,
      ep.user_id,
      e.id as event_id,
      ep.id as event_payment_id,
      null::uuid[] as order_ids,
      case
        when v_dep_norm = private.normalize_depositor_name(
          private.render_event_deposit_name(e.deposit_name, p.name, p.student_id)
        ) then 'exact'
        else 'prefix'
      end as match_mode,
      e.title || ' (' || p.name || ')' as label,
      coalesce(ep.amount_override, e.amount) as amount
    from public.event_payments ep
    join public.events e on e.id = ep.event_id
    join public.profiles p on p.id = ep.user_id
    where e.campus_id = v_deposit.campus_id
      and not ep.is_paid
      and p.is_approved
      and coalesce(ep.amount_override, e.amount) = v_deposit.amount
      and private.depositor_name_matches(
        v_dep_norm,
        private.normalize_depositor_name(
          private.render_event_deposit_name(e.deposit_name, p.name, p.student_id)
        )
      )

    union all

    select
      'textbook_single'::text as kind,
      o.user_id,
      null::uuid as event_id,
      null::uuid as event_payment_id,
      array[o.id] as order_ids,
      case
        when v_dep_norm = private.normalize_depositor_name(p.name) then 'exact'
        else 'prefix'
      end as match_mode,
      p.name || ' 교재 신청' as label,
      o.total_price as amount
    from public.textbook_orders o
    join public.profiles p on p.id = o.user_id
    where o.campus_id = v_deposit.campus_id
      and o.status = 'requested'
      and o.total_price = v_deposit.amount
      and p.is_approved
      and private.depositor_name_matches(v_dep_norm, private.normalize_depositor_name(p.name))

    union all

    select
      'textbook_round_sum'::text as kind,
      o.user_id,
      null::uuid as event_id,
      null::uuid as event_payment_id,
      array_agg(o.id order by o.id) as order_ids,
      case
        when v_dep_norm = private.normalize_depositor_name(p.name) then 'exact'
        else 'prefix'
      end as match_mode,
      p.name || ' 교재 합산 (' || count(*) || '건)' as label,
      sum(o.total_price)::int as amount
    from public.textbook_orders o
    join public.profiles p on p.id = o.user_id
    where o.campus_id = v_deposit.campus_id
      and o.status = 'requested'
      and o.total_price > 0
      and p.is_approved
      and private.depositor_name_matches(v_dep_norm, private.normalize_depositor_name(p.name))
    group by o.user_id, o.round_id, p.name
    having count(*) >= 2 and sum(o.total_price) = v_deposit.amount
  )
  select
    count(*)::int,
    bool_or(kind = 'event'),
    bool_or(kind <> 'event'),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'kind', kind,
          'user_id', user_id,
          'event_id', event_id,
          'event_payment_id', event_payment_id,
          'order_ids', order_ids,
          'match_mode', match_mode,
          'label', label,
          'amount', amount
        )
        order by kind, event_payment_id, order_ids
      ),
      '[]'::jsonb
    )
  into v_count, v_has_event, v_has_textbook, v_snapshot
  from (select * from candidates limit 20) limited;

  if v_count = 0 then
    update public.bank_deposits
    set status = 'unmatched',
        match_reason = 'no_candidate',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'unmatched';
  end if;

  if v_count > 1 then
    update public.bank_deposits
    set status = 'ambiguous',
        match_reason = case
          when v_has_event and v_has_textbook then 'cross_type_conflict'
          else 'multiple_candidates'
        end,
        candidate_snapshot = v_snapshot,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'ambiguous';
  end if;

  select
    x ->> 'kind' as kind,
    (x ->> 'user_id')::uuid as user_id,
    (x ->> 'event_id')::uuid as event_id,
    (x ->> 'event_payment_id')::uuid as event_payment_id,
    case
      when x -> 'order_ids' is null or jsonb_typeof(x -> 'order_ids') = 'null' then null::uuid[]
      else array(select jsonb_array_elements_text(x -> 'order_ids')::uuid)
    end as order_ids,
    x ->> 'match_mode' as match_mode
  into v_cand
  from jsonb_array_elements(v_snapshot) as x
  limit 1;

  -- 같은 캠퍼스의 다른 활성 승인 회원이 같은 입금자명을 만들 수 있으면 오매칭을 막기 위해 검토로 보낸다.
  if v_cand.kind = 'event' then
    select deposit_name into v_event_template from public.events where id = v_cand.event_id;
    select exists (
      select 1 from public.profiles p2
      where p2.campus_id = v_deposit.campus_id
        and p2.id <> v_cand.user_id
        and p2.is_approved
        and p2.deactivated_at is null
        and private.depositor_name_matches(
          v_dep_norm,
          private.normalize_depositor_name(
            private.render_event_deposit_name(v_event_template, p2.name, p2.student_id)
          )
        )
    ) into v_has_homonym;
  else
    select exists (
      select 1 from public.profiles p2
      where p2.campus_id = v_deposit.campus_id
        and p2.id <> v_cand.user_id
        and p2.is_approved
        and p2.deactivated_at is null
        and private.depositor_name_matches(v_dep_norm, private.normalize_depositor_name(p2.name))
    ) into v_has_homonym;
  end if;

  if v_has_homonym then
    update public.bank_deposits
    set status = 'ambiguous',
        match_reason = 'same_name_members',
        candidate_snapshot = v_snapshot,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'ambiguous';
  end if;

  perform set_config('app.deposit_rpc', 'match', true);

  if v_cand.kind = 'event' then
    update public.event_payments
    set is_paid = true,
        confirmed_deposit_id = v_deposit.id
    where id = v_cand.event_payment_id
      and not is_paid;
  else
    update public.textbook_orders
    set status = 'paid',
        confirmed_deposit_id = v_deposit.id
    where id = any (v_cand.order_ids)
      and status = 'requested';
  end if;

  update public.bank_deposits
  set status = 'auto_matched',
      match_reason = v_cand.match_mode || '_' || v_cand.kind,
      candidate_snapshot = null,
      matched_at = now(),
      matched_by = null
  where id = v_deposit.id;

  return 'auto_matched';
end;
$$;

-- 주문이나 송금을 기존 화면에서 수동으로 미납/취소로 바꾸면 연결된 입금도 함께 정리한다.
create function private.clear_order_deposit_on_unpay()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.confirmed_deposit_id is not null
     and new.status <> 'paid'
     and current_setting('app.deposit_rpc', true) is distinct from 'undo' then
    new.confirmed_deposit_id := null;
  end if;
  return new;
end;
$$;

create trigger textbook_orders_clear_deposit_on_unpay
  before update of status on public.textbook_orders
  for each row execute function private.clear_order_deposit_on_unpay();

create function private.clear_event_payment_deposit_on_unpay()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.confirmed_deposit_id is not null
     and not new.is_paid
     and current_setting('app.deposit_rpc', true) is distinct from 'undo' then
    new.confirmed_deposit_id := null;
  end if;
  return new;
end;
$$;

create trigger event_payments_clear_deposit_on_unpay
  before update of is_paid on public.event_payments
  for each row execute function private.clear_event_payment_deposit_on_unpay();

create function private.sync_deposit_after_unlink()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit_id uuid := old.confirmed_deposit_id;
begin
  if v_deposit_id is null
     or current_setting('app.deposit_rpc', true) = 'undo' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.confirmed_deposit_id is not distinct from old.confirmed_deposit_id then
    return null;
  end if;

  if not exists (select 1 from public.textbook_orders where confirmed_deposit_id = v_deposit_id)
     and not exists (select 1 from public.event_payments where confirmed_deposit_id = v_deposit_id) then
    update public.bank_deposits
    set status = 'undone',
        undone_at = now(),
        undone_by = auth.uid(),
        matched_at = null,
        matched_by = null
    where id = v_deposit_id
      and status in ('auto_matched', 'manual_matched');
  end if;
  return null;
end;
$$;

create trigger textbook_orders_sync_deposit_unlink
  after update or delete on public.textbook_orders
  for each row execute function private.sync_deposit_after_unlink();

create trigger event_payments_sync_deposit_unlink
  after update or delete on public.event_payments
  for each row execute function private.sync_deposit_after_unlink();

-- 만료된 원문(14일)을 지운다.
create function private.purge_expired_raw_deposits(p_campus_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.bank_deposits
  set raw_title = null,
      raw_text = null,
      raw_package = null,
      raw_expires_at = null,
      match_reason = coalesce(match_reason, 'raw_expired')
  where campus_id = p_campus_id
    and raw_expires_at is not null
    and raw_expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 기존 1년 정리 함수에 입금 내역과 만료 원문 정리를 추가한다.
create or replace function private.purge_old_campus_data(p_campus_id uuid)
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

  perform private.purge_expired_raw_deposits(p_campus_id);

  delete from public.bank_deposits
  where campus_id = p_campus_id
    and received_at < now() - interval '1 year';
end;
$$;

-- Edge Function(service_role) 전용 입금 수집 진입점.
create function public.ingest_bank_deposit(
  p_campus_id uuid,
  p_parse_kind text,
  p_bank_code text default 'toss',
  p_dedupe_key text default null,
  p_raw_hash text default null,
  p_deposited_at timestamptz default null,
  p_depositor_name text default null,
  p_amount integer default null,
  p_raw_title text default null,
  p_raw_text text default null,
  p_raw_package text default null,
  p_reason text default null
)
returns table (status text, deposit_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.campus_deposit_settings;
  v_now timestamptz := now();
  v_deposited_at timestamptz := coalesce(p_deposited_at, v_now);
  v_existing_id uuid;
  v_id uuid;
  v_final_status text;
begin
  if p_parse_kind not in ('ping', 'ignored', 'unparsed', 'deposit') then
    raise exception '올바르지 않은 수집 상태입니다.';
  end if;

  select * into v_settings
  from public.campus_deposit_settings
  where campus_id = p_campus_id
  for update;

  if not found or not v_settings.enabled or char_length(btrim(v_settings.account_label)) = 0 then
    return query select 'disabled'::text, null::uuid;
    return;
  end if;

  -- 캠퍼스당 분당 60건으로 제한해 단말 루프로 인한 과부하를 막는다.
  if v_settings.rate_window_start is null
     or v_settings.rate_window_start <= v_now - interval '1 minute' then
    update public.campus_deposit_settings
    set rate_window_start = v_now,
        rate_window_count = 1,
        last_received_at = v_now
    where campus_id = p_campus_id;
  elsif v_settings.rate_window_count >= 60 then
    return query select 'rate_limited'::text, null::uuid;
    return;
  else
    update public.campus_deposit_settings
    set rate_window_count = v_settings.rate_window_count + 1,
        last_received_at = v_now
    where campus_id = p_campus_id;
  end if;

  perform private.purge_expired_raw_deposits(p_campus_id);

  if p_parse_kind = 'ping' then
    return query select 'pong'::text, null::uuid;
    return;
  end if;

  if p_parse_kind = 'ignored' then
    update public.campus_deposit_settings
    set last_ignored_at = v_now,
        last_ignored_reason = left(coalesce(nullif(btrim(p_reason), ''), 'ignored'), 50),
        ignored_count = ignored_count + 1
    where campus_id = p_campus_id;
    return query select 'ignored'::text, null::uuid;
    return;
  end if;

  if p_dedupe_key is null or p_raw_hash is null then
    raise exception '중복 방지 키가 필요합니다.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('deposit_match:' || p_campus_id::text, 0));

  select id into v_existing_id
  from public.bank_deposits
  where campus_id = p_campus_id and dedupe_key = p_dedupe_key;
  if found then
    return query select 'duplicate'::text, v_existing_id;
    return;
  end if;

  select id into v_existing_id
  from public.bank_deposits
  where campus_id = p_campus_id
    and raw_hash = p_raw_hash
    and abs(extract(epoch from deposited_at - v_deposited_at)) <= 15
  order by received_at desc
  limit 1;
  if found then
    return query select 'duplicate'::text, v_existing_id;
    return;
  end if;

  if p_parse_kind = 'unparsed' then
    insert into public.bank_deposits (
      campus_id, dedupe_key, raw_hash, bank_code, status,
      deposited_at, raw_title, raw_text, raw_package, raw_expires_at, match_reason
    )
    values (
      p_campus_id, p_dedupe_key, p_raw_hash, p_bank_code, 'unparsed',
      v_deposited_at,
      left(coalesce(p_raw_title, ''), 300),
      left(coalesce(p_raw_text, ''), 1000),
      left(coalesce(p_raw_package, ''), 100),
      v_now + interval '14 days',
      left(coalesce(nullif(btrim(p_reason), ''), 'parse_failed'), 100)
    )
    returning id into v_id;

    perform private.notify_deposit_push(v_id, true);
    return query select 'unparsed'::text, v_id;
    return;
  end if;

  insert into public.bank_deposits (
    campus_id, dedupe_key, raw_hash, bank_code, status,
    depositor_name, amount, deposited_at
  )
  values (
    p_campus_id, p_dedupe_key, p_raw_hash, p_bank_code, 'unmatched',
    left(btrim(coalesce(p_depositor_name, '')), 100),
    p_amount,
    v_deposited_at
  )
  returning id into v_id;

  v_final_status := private.match_and_confirm_deposit(v_id);
  perform private.notify_deposit_push(v_id, true);
  return query select v_final_status, v_id;
end;
$$;

-- Edge Function(service_role) 전용 재해석 결과 반영.
create function public.apply_deposit_reparse(
  p_deposit_id uuid,
  p_parse_kind text,
  p_depositor_name text default null,
  p_amount integer default null,
  p_reason text default null
)
returns table (status text, deposit_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_final_status text;
begin
  if p_parse_kind not in ('ignored', 'unparsed', 'deposit') then
    raise exception '올바르지 않은 재해석 결과입니다.';
  end if;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status <> 'unparsed' then
    raise exception '해석 실패 상태의 입금만 다시 해석할 수 있습니다.';
  end if;

  if p_parse_kind = 'ignored' then
    update public.bank_deposits
    set status = 'ignored',
        match_reason = left(coalesce(nullif(btrim(p_reason), ''), 'ignored'), 100),
        raw_title = null,
        raw_text = null,
        raw_package = null,
        raw_expires_at = null,
        ignored_at = now()
    where id = p_deposit_id;
    return query select 'ignored'::text, p_deposit_id;
    return;
  end if;

  if p_parse_kind = 'unparsed' then
    update public.bank_deposits
    set match_reason = left(coalesce(nullif(btrim(p_reason), ''), 'parse_failed'), 100)
    where id = p_deposit_id;
    return query select 'unparsed'::text, p_deposit_id;
    return;
  end if;

  update public.bank_deposits
  set status = 'unmatched',
      depositor_name = left(btrim(coalesce(p_depositor_name, '')), 100),
      amount = p_amount,
      raw_title = null,
      raw_text = null,
      raw_package = null,
      raw_expires_at = null,
      match_reason = null
  where id = p_deposit_id;

  v_final_status := private.match_and_confirm_deposit(p_deposit_id);
  if v_final_status = 'auto_matched' then
    perform private.notify_deposit_push(p_deposit_id, false);
  end if;
  return query select v_final_status, p_deposit_id;
end;
$$;

-- 관리자 RPC: 설정 변경, 토큰 발급/교체, 수동 연결, 확인 취소, 무시, 재매칭.
create function public.admin_update_deposit_settings(
  p_campus_id uuid,
  p_enabled boolean,
  p_bank_code text,
  p_account_label text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text := btrim(coalesce(p_account_label, ''));
begin
  if private.can_admin_campus(p_campus_id) is not true then
    raise exception '캠퍼스 설정을 바꿀 권한이 없습니다.';
  end if;
  if p_enabled is null then
    raise exception '사용 여부를 지정해 주세요.';
  end if;
  if p_bank_code is null or p_bank_code not in ('toss') then
    raise exception '지원하지 않는 은행입니다.';
  end if;
  if char_length(v_label) > 50 then
    raise exception '계좌 별칭은 50자 이하로 입력해 주세요.';
  end if;
  if p_enabled and v_label = '' then
    raise exception '계좌 별칭을 먼저 입력해 주세요.';
  end if;

  insert into public.campus_deposit_settings (campus_id, enabled, bank_code, account_label)
  values (p_campus_id, p_enabled, p_bank_code, v_label)
  on conflict (campus_id) do update
    set enabled = excluded.enabled,
        bank_code = excluded.bank_code,
        account_label = excluded.account_label;
end;
$$;

create function public.admin_rotate_deposit_token(p_campus_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_hash text;
begin
  if private.can_admin_campus(p_campus_id) is not true then
    raise exception '토큰을 발급할 권한이 없습니다.';
  end if;

  v_token := 'dep_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_hash := encode(pg_catalog.sha256(convert_to(v_token, 'UTF8')), 'hex');

  insert into public.campus_deposit_settings (campus_id, token_hash, token_prefix, token_rotated_at)
  values (p_campus_id, v_hash, left(v_token, 10), now())
  on conflict (campus_id) do update
    set token_hash = excluded.token_hash,
        token_prefix = excluded.token_prefix,
        token_rotated_at = excluded.token_rotated_at;

  return v_token;
end;
$$;

create function public.admin_link_deposit_to_event(p_deposit_id uuid, p_event_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_payment public.event_payments;
  v_event_campus uuid;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone', 'ignored')
     or v_deposit.depositor_name is null
     or v_deposit.amount is null then
    raise exception '연결할 수 없는 입금 상태입니다.';
  end if;

  select ep.*, e.campus_id into v_payment.id, v_payment.event_id, v_payment.user_id, v_payment.is_paid,
    v_payment.paid_at, v_payment.confirmed_by, v_payment.amount_override, v_payment.confirmed_deposit_id, v_event_campus
  from public.event_payments ep
  join public.events e on e.id = ep.event_id
  where ep.id = p_event_payment_id
  for update of ep;

  if not found or v_event_campus <> v_deposit.campus_id then
    raise exception '이벤트 송금 대상을 찾을 수 없습니다.';
  end if;
  if v_payment.is_paid then
    raise exception '이미 송금 확인된 대상입니다.';
  end if;

  update public.event_payments
  set is_paid = true,
      confirmed_deposit_id = p_deposit_id
  where id = p_event_payment_id;

  update public.bank_deposits
  set status = 'manual_matched',
      match_reason = 'manual_link_event',
      candidate_snapshot = null,
      matched_at = now(),
      matched_by = auth.uid(),
      ignored_at = null,
      ignored_by = null
  where id = p_deposit_id;
end;
$$;

create function public.admin_link_deposit_to_orders(p_deposit_id uuid, p_order_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_order public.textbook_orders;
  v_count int := 0;
begin
  if p_order_ids is null or cardinality(p_order_ids) = 0 then
    raise exception '연결할 신청을 선택해 주세요.';
  end if;
  if cardinality(p_order_ids) > 100 then
    raise exception '한 번에 연결할 수 있는 신청 수를 초과했습니다.';
  end if;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone', 'ignored')
     or v_deposit.depositor_name is null
     or v_deposit.amount is null then
    raise exception '연결할 수 없는 입금 상태입니다.';
  end if;

  for v_order in
    select * from public.textbook_orders
    where id = any (p_order_ids)
    order by id
    for update
  loop
    if v_order.campus_id <> v_deposit.campus_id then
      raise exception '같은 캠퍼스의 신청만 연결할 수 있습니다.';
    end if;
    if v_order.status <> 'requested' then
      raise exception '입금 대기 상태인 신청만 연결할 수 있습니다.';
    end if;
    v_count := v_count + 1;
  end loop;

  if v_count <> (select count(distinct x) from unnest(p_order_ids) as x) then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;

  update public.textbook_orders
  set status = 'paid',
      confirmed_deposit_id = p_deposit_id
  where id = any (p_order_ids);

  update public.bank_deposits
  set status = 'manual_matched',
      match_reason = 'manual_link_orders',
      candidate_snapshot = null,
      matched_at = now(),
      matched_by = auth.uid(),
      ignored_at = null,
      ignored_by = null
  where id = p_deposit_id;
end;
$$;

create function public.admin_undo_deposit(p_deposit_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('auto_matched', 'manual_matched') then
    raise exception '확인 완료된 입금만 취소할 수 있습니다.';
  end if;

  perform set_config('app.deposit_rpc', 'undo', true);

  perform 1 from public.textbook_orders
  where confirmed_deposit_id = p_deposit_id
  order by id
  for update;

  update public.textbook_orders
  set status = case when status = 'paid' then 'requested' else status end,
      confirmed_deposit_id = null
  where confirmed_deposit_id = p_deposit_id;

  perform 1 from public.event_payments
  where confirmed_deposit_id = p_deposit_id
  order by id
  for update;

  update public.event_payments
  set is_paid = false,
      confirmed_deposit_id = null
  where confirmed_deposit_id = p_deposit_id;

  update public.bank_deposits
  set status = 'undone',
      undone_at = now(),
      undone_by = auth.uid(),
      matched_at = null,
      matched_by = null
  where id = p_deposit_id;
end;
$$;

create function public.admin_ignore_deposit(p_deposit_id uuid, p_ignore boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
begin
  if p_ignore is null then
    raise exception '무시 여부를 지정해 주세요.';
  end if;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;

  if p_ignore then
    if v_deposit.status not in ('unparsed', 'unmatched', 'ambiguous', 'undone') then
      raise exception '이미 확인되었거나 무시된 입금입니다.';
    end if;

    update public.bank_deposits
    set status = 'ignored',
        raw_title = null,
        raw_text = null,
        raw_package = null,
        raw_expires_at = null,
        ignored_at = now(),
        ignored_by = auth.uid()
    where id = p_deposit_id;
  else
    if v_deposit.status <> 'ignored' then
      raise exception '무시된 입금만 되돌릴 수 있습니다.';
    end if;
    if v_deposit.depositor_name is null or v_deposit.amount is null then
      raise exception '해석되지 않은 상태로 무시된 입금은 되돌릴 수 없습니다.';
    end if;

    update public.bank_deposits
    set status = 'unmatched',
        ignored_at = null,
        ignored_by = null
    where id = p_deposit_id;
  end if;
end;
$$;

create function public.admin_rematch_deposit(p_deposit_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_status text;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone')
     or v_deposit.depositor_name is null
     or v_deposit.amount is null then
    raise exception '다시 매칭할 수 없는 상태입니다.';
  end if;

  v_status := private.match_and_confirm_deposit(p_deposit_id);
  if v_status = 'auto_matched' then
    perform private.notify_deposit_push(p_deposit_id, false);
  end if;
  return v_status;
end;
$$;

-- RLS 및 권한: 관리자는 자기 캠퍼스만 조회, 쓰기는 RPC 로만 허용. token_hash 는 관리자도 읽지 못한다.
alter table public.campus_deposit_settings enable row level security;
alter table public.bank_deposits enable row level security;

create policy "campus_deposit_settings: campus admin select"
  on public.campus_deposit_settings
  for select to authenticated
  using (
    (select private.is_central_admin())
    or campus_id = (select private.admin_campus_id())
  );

create policy "bank_deposits: campus admin select"
  on public.bank_deposits
  for select to authenticated
  using (
    (select private.is_central_admin())
    or campus_id = (select private.admin_campus_id())
  );

revoke all on public.campus_deposit_settings from anon, authenticated;
grant select (
  campus_id,
  enabled,
  bank_code,
  account_label,
  token_prefix,
  token_rotated_at,
  last_received_at,
  last_ignored_at,
  last_ignored_reason,
  ignored_count,
  updated_at
) on public.campus_deposit_settings to authenticated;

revoke all on public.bank_deposits from anon, authenticated;
grant select on public.bank_deposits to authenticated;

revoke execute on function
  private.render_event_deposit_name(text, text, text),
  private.normalize_depositor_name(text),
  private.depositor_name_matches(text, text),
  private.notify_deposit_push(uuid, boolean),
  private.match_and_confirm_deposit(uuid),
  private.clear_order_deposit_on_unpay(),
  private.clear_event_payment_deposit_on_unpay(),
  private.sync_deposit_after_unlink(),
  private.purge_expired_raw_deposits(uuid)
from public, anon, authenticated;

revoke execute on function
  public.ingest_bank_deposit(uuid, text, text, text, text, timestamptz, text, integer, text, text, text, text),
  public.apply_deposit_reparse(uuid, text, text, integer, text)
from public, anon, authenticated;
grant execute on function
  public.ingest_bank_deposit(uuid, text, text, text, text, timestamptz, text, integer, text, text, text, text),
  public.apply_deposit_reparse(uuid, text, text, integer, text)
to service_role;

revoke execute on function
  public.admin_update_deposit_settings(uuid, boolean, text, text),
  public.admin_rotate_deposit_token(uuid),
  public.admin_link_deposit_to_event(uuid, uuid),
  public.admin_link_deposit_to_orders(uuid, uuid[]),
  public.admin_undo_deposit(uuid),
  public.admin_ignore_deposit(uuid, boolean),
  public.admin_rematch_deposit(uuid)
from public, anon;

grant execute on function
  public.admin_update_deposit_settings(uuid, boolean, text, text),
  public.admin_rotate_deposit_token(uuid),
  public.admin_link_deposit_to_event(uuid, uuid),
  public.admin_link_deposit_to_orders(uuid, uuid[]),
  public.admin_undo_deposit(uuid),
  public.admin_ignore_deposit(uuid, boolean),
  public.admin_rematch_deposit(uuid)
to authenticated;
