-- 입금자 이름이 가려지거나(****) 비어 있지만 금액이 해석된 입금 알림 지원.
-- 20261021000000_auto_deposit.sql 적용 이후 스키마를 안전하게 업그레이드한다.

alter table public.bank_deposits
  drop constraint bank_deposits_parsed_fields,
  drop constraint bank_deposits_raw_only_unparsed,
  add constraint bank_deposits_parsed_fields check (
    status in ('unparsed', 'ignored')
    or (status = 'auto_matched' and depositor_name is not null and amount is not null)
    or (status in ('unmatched', 'ambiguous', 'manual_matched', 'undone') and amount is not null)
  ),
  add constraint bank_deposits_raw_only_unparsed check (
    status = 'unparsed'
    or (depositor_name is null and status in ('unmatched', 'ambiguous', 'undone'))
    or (raw_title is null and raw_text is null and raw_package is null and raw_expires_at is null)
  );

-- 잠금 순서: 캠퍼스 매칭 advisory lock -> textbook_orders(id순) -> event_payments(id순) -> deposit 행.
create or replace function private.match_and_confirm_deposit(p_deposit_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid;
  v_deposit public.bank_deposits;
  v_dep_norm text;
  v_count int;
  v_has_event boolean;
  v_has_textbook boolean;
  v_snapshot jsonb;
  v_cand record;
  v_event_template text;
  v_has_homonym boolean := false;
  v_updated int := 0;
begin
  select campus_id into v_campus_id from public.bank_deposits where id = p_deposit_id;
  if not found then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('deposit_match:' || v_campus_id::text, 0));

  perform 1 from public.textbook_orders o
  where o.campus_id = v_campus_id and o.status = 'requested'
  order by o.id
  for update of o;

  perform 1 from public.event_payments ep
  join public.events e on e.id = ep.event_id
  where e.campus_id = v_campus_id and not ep.is_paid
  order by ep.id
  for update of ep;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.amount is null then
    raise exception '해석되지 않은 입금은 자동 매칭할 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone') then
    raise exception '다시 매칭할 수 없는 상태입니다.';
  end if;

  if v_deposit.duplicate_of_id is not null and v_deposit.duplicate_cleared_at is null then
    update public.bank_deposits
    set status = 'ambiguous',
        match_reason = 'possible_duplicate',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'ambiguous';
  end if;

  if v_deposit.depositor_name is null then
    update public.bank_deposits
    set status = 'unmatched',
        match_reason = 'masked_depositor',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = v_deposit.id;
    return 'unmatched';
  end if;

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
      and p.deactivated_at is null
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
      and p.deactivated_at is null
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
      and p.deactivated_at is null
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

  -- 비활성화된 동명이인 회원이 입금했을 가능성까지 고려해 승인된 동명이인이 있으면 검토로 보낸다.
  if v_cand.kind = 'event' then
    select deposit_name into v_event_template from public.events where id = v_cand.event_id;
    select exists (
      select 1 from public.profiles p2
      where p2.campus_id = v_deposit.campus_id
        and p2.id <> v_cand.user_id
        and p2.is_approved
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

  if v_cand.kind = 'event' then
    update public.event_payments
    set is_paid = true,
        confirmed_deposit_id = v_deposit.id
    where id = v_cand.event_payment_id
      and not is_paid;
    get diagnostics v_updated = row_count;
    if v_updated <> 1 then
      raise exception '이벤트 송금 상태를 업데이트하지 못했습니다 (expected=1, actual=%).', v_updated;
    end if;
  else
    update public.textbook_orders
    set status = 'paid',
        confirmed_deposit_id = v_deposit.id
    where id = any (v_cand.order_ids)
      and status = 'requested';
    get diagnostics v_updated = row_count;
    if v_updated <> cardinality(v_cand.order_ids) then
      raise exception '교재 신청 상태를 업데이트하지 못했습니다 (expected=%, actual=%).',
        cardinality(v_cand.order_ids), v_updated;
    end if;
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

create or replace function public.ingest_bank_deposit(
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
  v_near_dup_id uuid;
  v_id uuid;
  v_final_status text;
begin
  if p_parse_kind not in ('ping', 'ignored', 'unparsed', 'masked_deposit', 'deposit') then
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
    set last_deposit_notification_at = v_now,
        last_ignored_at = v_now,
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
  where campus_id = p_campus_id and dedupe_key = p_dedupe_key
  for update;
  if found then
    update public.bank_deposits
    set duplicate_count = duplicate_count + 1,
        last_duplicate_at = v_now
    where id = v_existing_id;
    return query select 'duplicate'::text, v_existing_id;
    return;
  end if;

  update public.campus_deposit_settings
  set last_deposit_notification_at = v_now
  where campus_id = p_campus_id;

  select id into v_near_dup_id
  from public.bank_deposits
  where campus_id = p_campus_id
    and raw_hash = p_raw_hash
    and abs(extract(epoch from deposited_at - v_deposited_at)) <= 60
  order by received_at desc
  limit 1;

  if p_parse_kind = 'unparsed' then
    insert into public.bank_deposits (
      campus_id, dedupe_key, raw_hash, bank_code, status,
      deposited_at, raw_title, raw_text, raw_package, raw_expires_at,
      match_reason, duplicate_of_id
    )
    values (
      p_campus_id, p_dedupe_key, p_raw_hash, p_bank_code, 'unparsed',
      v_deposited_at,
      left(coalesce(p_raw_title, ''), 300),
      left(coalesce(p_raw_text, ''), 1000),
      left(coalesce(p_raw_package, ''), 100),
      v_now + interval '14 days',
      case
        when v_near_dup_id is not null then 'possible_duplicate'
        else left(coalesce(nullif(btrim(p_reason), ''), 'parse_failed'), 100)
      end,
      v_near_dup_id
    )
    returning id into v_id;

    perform private.notify_deposit_push(v_id, true);
    return query select 'unparsed'::text, v_id;
    return;
  end if;

  if p_parse_kind = 'masked_deposit' then
    if p_amount is null then
      raise exception '금액이 필요합니다.';
    end if;

    insert into public.bank_deposits (
      campus_id, dedupe_key, raw_hash, bank_code, status,
      depositor_name, amount, deposited_at,
      raw_title, raw_text, raw_package, raw_expires_at,
      match_reason, duplicate_of_id
    )
    values (
      p_campus_id, p_dedupe_key, p_raw_hash, p_bank_code,
      case when v_near_dup_id is not null then 'ambiguous' else 'unmatched' end,
      null,
      p_amount,
      v_deposited_at,
      left(coalesce(p_raw_title, ''), 300),
      left(coalesce(p_raw_text, ''), 1000),
      left(coalesce(p_raw_package, ''), 100),
      v_now + interval '14 days',
      case
        when v_near_dup_id is not null then 'possible_duplicate'
        else left(coalesce(nullif(btrim(p_reason), ''), 'masked_depositor'), 100)
      end,
      v_near_dup_id
    )
    returning id into v_id;

    perform private.notify_deposit_push(v_id, true);
    return query select
      case when v_near_dup_id is not null then 'ambiguous'::text else 'unmatched'::text end,
      v_id;
    return;
  end if;

  if v_near_dup_id is not null then
    insert into public.bank_deposits (
      campus_id, dedupe_key, raw_hash, bank_code, status,
      depositor_name, amount, deposited_at, match_reason, duplicate_of_id
    )
    values (
      p_campus_id, p_dedupe_key, p_raw_hash, p_bank_code, 'ambiguous',
      left(btrim(coalesce(p_depositor_name, '')), 100),
      p_amount,
      v_deposited_at,
      'possible_duplicate',
      v_near_dup_id
    )
    returning id into v_id;

    perform private.notify_deposit_push(v_id, true);
    return query select 'ambiguous'::text, v_id;
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

  begin
    v_final_status := private.match_and_confirm_deposit(v_id);
  exception when others then
    raise warning '입금 자동 매칭 오류(%): %', v_id, sqlerrm;
    update public.bank_deposits
    set status = 'unmatched',
        match_reason = 'match_error',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = v_id;
    v_final_status := 'unmatched';
  end;

  perform private.notify_deposit_push(v_id, true);
  return query select v_final_status, v_id;
end;
$$;

create or replace function public.apply_deposit_reparse(
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
  v_campus_id uuid;
  v_deposit public.bank_deposits;
  v_final_status text;
begin
  if p_parse_kind not in ('ignored', 'unparsed', 'masked_deposit', 'deposit') then
    raise exception '올바르지 않은 재해석 결과입니다.';
  end if;

  if p_parse_kind = 'deposit' then
    -- 잠금 순서 통일: advisory lock -> textbook_orders(id순) -> event_payments(id순) -> bank_deposits.
    select campus_id into v_campus_id from public.bank_deposits where id = p_deposit_id;
    if not found then
      raise exception '입금 내역을 찾을 수 없습니다.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('deposit_match:' || v_campus_id::text, 0));

    perform 1 from public.textbook_orders o
    where o.campus_id = v_campus_id and o.status = 'requested'
    order by o.id
    for update of o;

    perform 1 from public.event_payments ep
    join public.events e on e.id = ep.event_id
    where e.campus_id = v_campus_id and not ep.is_paid
    order by ep.id
    for update of ep;
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
    set match_reason = case
      when v_deposit.duplicate_of_id is not null and v_deposit.duplicate_cleared_at is null
        then 'possible_duplicate'
      else left(coalesce(nullif(btrim(p_reason), ''), 'parse_failed'), 100)
    end
    where id = p_deposit_id;
    return query select 'unparsed'::text, p_deposit_id;
    return;
  end if;

  if p_parse_kind = 'masked_deposit' then
    if p_amount is null then
      raise exception '금액이 필요합니다.';
    end if;

    v_final_status := case
      when v_deposit.duplicate_of_id is not null and v_deposit.duplicate_cleared_at is null then 'ambiguous'
      else 'unmatched'
    end;

    update public.bank_deposits
    set status = v_final_status,
        depositor_name = null,
        amount = p_amount,
        match_reason = case
          when v_deposit.duplicate_of_id is not null and v_deposit.duplicate_cleared_at is null
            then 'possible_duplicate'
          else left(coalesce(nullif(btrim(p_reason), ''), 'masked_depositor'), 100)
        end,
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = p_deposit_id;
    return query select v_final_status, p_deposit_id;
    return;
  end if;

  if v_deposit.duplicate_of_id is not null and v_deposit.duplicate_cleared_at is null then
    update public.bank_deposits
    set status = 'ambiguous',
        depositor_name = left(btrim(coalesce(p_depositor_name, '')), 100),
        amount = p_amount,
        raw_title = null,
        raw_text = null,
        raw_package = null,
        raw_expires_at = null,
        match_reason = 'possible_duplicate',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = p_deposit_id;
    return query select 'ambiguous'::text, p_deposit_id;
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

  begin
    v_final_status := private.match_and_confirm_deposit(p_deposit_id);
  exception when others then
    raise warning '재해석 자동 매칭 오류(%): %', p_deposit_id, sqlerrm;
    update public.bank_deposits
    set status = 'unmatched',
        match_reason = 'match_error',
        candidate_snapshot = null,
        matched_at = null,
        matched_by = null
    where id = p_deposit_id;
    v_final_status := 'unmatched';
  end;

  if v_final_status = 'auto_matched' then
    perform private.notify_deposit_push(p_deposit_id, false);
  end if;
  return query select v_final_status, p_deposit_id;
end;
$$;

create or replace function public.admin_link_deposit_to_event(
  p_deposit_id uuid,
  p_event_payment_id uuid,
  p_allow_amount_mismatch boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid;
  v_deposit public.bank_deposits;
  v_payment_is_paid boolean;
  v_expected_amount integer;
  v_event_campus uuid;
  v_event_found boolean := false;
begin
  select campus_id into v_campus_id from public.bank_deposits where id = p_deposit_id;
  if not found or private.can_admin_campus(v_campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;

  select ep.is_paid, coalesce(ep.amount_override, e.amount), e.campus_id
  into v_payment_is_paid, v_expected_amount, v_event_campus
  from public.event_payments ep
  join public.events e on e.id = ep.event_id
  where ep.id = p_event_payment_id
  for update of ep;
  v_event_found := found;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone', 'ignored')
     or v_deposit.amount is null then
    raise exception '연결할 수 없는 입금 상태입니다.';
  end if;
  if not v_event_found or v_event_campus <> v_deposit.campus_id then
    raise exception '이벤트 송금 대상을 찾을 수 없습니다.';
  end if;
  if v_payment_is_paid then
    raise exception '이미 송금 확인된 대상입니다.';
  end if;
  if v_expected_amount <> v_deposit.amount and coalesce(p_allow_amount_mismatch, false) is not true then
    raise exception '입금 금액과 선택한 이벤트 금액이 다릅니다. 금액 불일치를 확인한 뒤 다시 연결해 주세요.';
  end if;

  update public.event_payments
  set is_paid = true,
      confirmed_deposit_id = p_deposit_id
  where id = p_event_payment_id;

  update public.bank_deposits
  set status = 'manual_matched',
      match_reason = 'manual_link_event',
      candidate_snapshot = null,
      raw_title = null,
      raw_text = null,
      raw_package = null,
      raw_expires_at = null,
      matched_at = now(),
      matched_by = auth.uid(),
      ignored_at = null,
      ignored_by = null
  where id = p_deposit_id;
end;
$$;

create or replace function public.admin_link_deposit_to_orders(
  p_deposit_id uuid,
  p_order_ids uuid[],
  p_allow_amount_mismatch boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campus_id uuid;
  v_deposit public.bank_deposits;
  v_order public.textbook_orders;
  v_count int := 0;
  v_sum int := 0;
begin
  if p_order_ids is null or cardinality(p_order_ids) = 0 then
    raise exception '연결할 신청을 선택해 주세요.';
  end if;
  if cardinality(p_order_ids) > 100 then
    raise exception '한 번에 연결할 수 있는 신청 수를 초과했습니다.';
  end if;

  select campus_id into v_campus_id from public.bank_deposits where id = p_deposit_id;
  if not found or private.can_admin_campus(v_campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;

  for v_order in
    select * from public.textbook_orders
    where id = any (p_order_ids)
    order by id
    for update
  loop
    if v_order.campus_id <> v_campus_id then
      raise exception '같은 캠퍼스의 신청만 연결할 수 있습니다.';
    end if;
    if v_order.status <> 'requested' then
      raise exception '입금 대기 상태인 신청만 연결할 수 있습니다.';
    end if;
    v_count := v_count + 1;
    v_sum := v_sum + v_order.total_price;
  end loop;

  select * into v_deposit from public.bank_deposits where id = p_deposit_id for update;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.campus_id <> v_campus_id then
    raise exception '같은 캠퍼스의 신청만 연결할 수 있습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone', 'ignored')
     or v_deposit.amount is null then
    raise exception '연결할 수 없는 입금 상태입니다.';
  end if;
  if v_count <> (select count(distinct x) from unnest(p_order_ids) as x) then
    raise exception '신청 내역을 찾을 수 없습니다.';
  end if;
  if v_sum <> v_deposit.amount and coalesce(p_allow_amount_mismatch, false) is not true then
    raise exception '입금 금액과 선택한 교재 신청 합계가 다릅니다. 금액 불일치를 확인한 뒤 다시 연결해 주세요.';
  end if;

  update public.textbook_orders
  set status = 'paid',
      confirmed_deposit_id = p_deposit_id
  where id = any (p_order_ids);

  update public.bank_deposits
  set status = 'manual_matched',
      match_reason = 'manual_link_orders',
      candidate_snapshot = null,
      raw_title = null,
      raw_text = null,
      raw_package = null,
      raw_expires_at = null,
      matched_at = now(),
      matched_by = auth.uid(),
      ignored_at = null,
      ignored_by = null
  where id = p_deposit_id;
end;
$$;

create or replace function public.admin_clear_possible_duplicate(p_deposit_id uuid)
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
  if v_deposit.duplicate_of_id is null or v_deposit.duplicate_cleared_at is not null then
    raise exception '중복 확인이 필요한 입금이 아닙니다.';
  end if;
  if v_deposit.status not in ('unparsed', 'unmatched', 'ambiguous', 'undone') then
    raise exception '이미 처리된 입금은 중복 표시를 해제할 수 없습니다.';
  end if;

  update public.bank_deposits
  set duplicate_cleared_at = now(),
      duplicate_cleared_by = auth.uid(),
      status = case
        when status = 'ambiguous' and match_reason = 'possible_duplicate' then 'unmatched'
        else status
      end,
      match_reason = case
        when status = 'unparsed' and match_reason = 'possible_duplicate' then 'parse_failed'
        when depositor_name is null and match_reason = 'possible_duplicate' then 'masked_depositor'
        when match_reason = 'possible_duplicate' then 'duplicate_cleared'
        else match_reason
      end
  where id = p_deposit_id;
end;
$$;

create or replace function public.admin_ignore_deposit(p_deposit_id uuid, p_ignore boolean default true)
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
    if v_deposit.amount is null then
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

create or replace function public.admin_rematch_deposit(p_deposit_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deposit public.bank_deposits;
  v_status text;
begin
  select * into v_deposit from public.bank_deposits where id = p_deposit_id;
  if not found or private.can_admin_campus(v_deposit.campus_id) is not true then
    raise exception '입금 내역을 찾을 수 없습니다.';
  end if;
  if v_deposit.status not in ('unmatched', 'ambiguous', 'undone')
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

revoke execute on function
  private.match_and_confirm_deposit(uuid)
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
  public.admin_link_deposit_to_event(uuid, uuid, boolean),
  public.admin_link_deposit_to_orders(uuid, uuid[], boolean),
  public.admin_clear_possible_duplicate(uuid),
  public.admin_ignore_deposit(uuid, boolean),
  public.admin_rematch_deposit(uuid)
from public, anon;

grant execute on function
  public.admin_link_deposit_to_event(uuid, uuid, boolean),
  public.admin_link_deposit_to_orders(uuid, uuid[], boolean),
  public.admin_clear_possible_duplicate(uuid),
  public.admin_ignore_deposit(uuid, boolean),
  public.admin_rematch_deposit(uuid)
to authenticated;
