// 자동 입금 확인: 매칭 알고리즘, 중복 방지, 취소/수동 연결, 보관 기간, 푸시 알림, 권한 격리.
//
// PGlite 는 단일 연결 WASM Postgres 라 아래 병렬 경합 시나리오는 여기서 동시 실행할 수 없다.
// (행 잠금 및 advisory lock 으로 서버 SQL 에서 직렬화하며, 실제 Postgres 통합 테스트에서만 병렬 검증 가능)
//   1. 같은 캠퍼스에 동일 입금 알림 2건이 같은 밀리초에 동시 수집되는 경우 (campus advisory lock + UNIQUE dedupe_key)
//   2. match_and_confirm_deposit 과 관리자의 수동 입금확인/admin_undo_deposit 이 동시에 실행되는 경우
//   3. 합산 입금에 연결된 2건의 주문을 서로 다른 세션이 동시에 미납으로 되돌리는 경우 (sync_deposit_after_unlink 의 deposit FOR UPDATE)
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { before, beforeEach, describe, test } from 'node:test';

import { asAnon, asUser, campusId, createCampus, createDb, createUser } from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

const sha256 = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

async function ingest(db, {
  campus,
  kind = 'deposit',
  bankCode = 'toss',
  dedupeKey = null,
  rawHash = null,
  depositedAt = null,
  depositorName = null,
  amount = null,
  rawTitle = null,
  rawText = null,
  rawPackage = null,
  reason = null,
}) {
  const uniq = `${Date.now()}-${Math.random()}`;
  const dk = dedupeKey ?? (kind === 'ping' || kind === 'ignored' ? null : sha256(`dk:${uniq}`));
  const rh = rawHash ?? (kind === 'ping' || kind === 'ignored' ? null : sha256(`rh:${uniq}`));
  const { rows } = await db.query(
    `select status, deposit_id from public.ingest_bank_deposit(
       $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12
     )`,
    [
      campus, kind, bankCode, dk, rh,
      depositedAt, depositorName, amount,
      rawTitle, rawText, rawPackage, reason,
    ],
  );
  return rows[0];
}

// Mirror of Dart renderDepositName in lib/features/events/domain/event.dart for parity verification.
function dartRenderDepositName(template, { name, studentId }) {
  const t = template.trim();
  if (!t) return name;
  return t.replaceAll('{이름}', name).replaceAll('{학번}', studentId);
}

describe('입금자명 렌더링 Dart-SQL 일치 검증', () => {
  test('private.render_event_deposit_name 결과가 Dart renderDepositName 과 모든 케이스에서 같다', async () => {
    const db = await createDb();
    const cases = [
      { template: '', name: '홍길동', studentId: '20240001' },
      { template: '   \t\n ', name: '홍길동', studentId: '20240001' },
      { template: '{이름}', name: '홍길동', studentId: '20240001' },
      { template: '{학번}', name: '홍길동', studentId: '20240001' },
      { template: '{이름}MT', name: '홍길동', studentId: '20240001' },
      { template: '{학번}{이름}', name: '홍길동', studentId: '20240001' },
      { template: '수련회{이름}', name: '김', studentId: '1' },
      { template: '  {이름} {학번} 순여행  ', name: '홍길동', studentId: '20250133' },
      { template: '고정텍스트', name: '홍길동', studentId: '20240001' },
      { template: '{이름}-{이름}-{학번}', name: '이영희', studentId: '20231234' },
    ];

    for (const c of cases) {
      const { rows } = await db.query(
        'select private.render_event_deposit_name($1, $2, $3) as rendered',
        [c.template, c.name, c.studentId],
      );
      assert.equal(
        rows[0].rendered,
        dartRenderDepositName(c.template, { name: c.name, studentId: c.studentId }),
        `template=${JSON.stringify(c.template)}`,
      );
    }
  });
});

describe('자동 매칭 및 예외 처리', () => {
  let db;
  let kaist;
  let admin;
  let hong;
  let kim;
  let book10k;
  let book15k;
  let bookFree;

  const placeOrder = async (userId, items) => {
    const { rows } = await asUser(
      db,
      userId,
      'select public.place_textbook_order($1::jsonb) as id',
      [JSON.stringify(items)],
    );
    return rows[0].id;
  };

  beforeEach(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
    hong = await createUser(db, { studentId: '20240001', name: '홍길동' });
    kim = await createUser(db, { studentId: '20240002', name: '김철수' });

    await asUser(
      db,
      admin,
      `select public.admin_update_deposit_settings($1, true, 'toss', 'KAIST CCC')`,
      [kaist],
    );

    book10k = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재A', 10000) returning id`,
      [kaist],
    )).rows[0].id;
    book15k = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재B', 15000) returning id`,
      [kaist],
    )).rows[0].id;
    bookFree = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '무료교재', 0) returning id`,
      [kaist],
    )).rows[0].id;
  });

  test('교재 단건 신청과 같은 회차 합산 신청을 자동 확인한다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const r1 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(r1.status, 'auto_matched');

    const { rows: [ord1] } = await db.query(
      'select status, confirmed_deposit_id from public.textbook_orders where id = $1',
      [o1],
    );
    assert.equal(ord1.status, 'paid');
    assert.equal(ord1.confirmed_deposit_id, r1.deposit_id);

    const o2 = await placeOrder(kim, [{ textbook_id: book10k, quantity: 1 }]);
    const o3 = await placeOrder(kim, [{ textbook_id: book15k, quantity: 1 }]);
    const oFree = await placeOrder(kim, [{ textbook_id: bookFree, quantity: 1 }]);
    const r2 = await ingest(db, { campus: kaist, depositorName: '김철수', amount: 25000 });
    assert.equal(r2.status, 'auto_matched');

    const { rows: kimOrders } = await db.query(
      'select id, status, confirmed_deposit_id from public.textbook_orders where id = any($1::uuid[]) order by id',
      [[o2, o3, oFree]],
    );
    const byId = new Map(kimOrders.map((r) => [r.id, r]));
    assert.equal(byId.get(o2).status, 'paid');
    assert.equal(byId.get(o2).confirmed_deposit_id, r2.deposit_id);
    assert.equal(byId.get(o3).status, 'paid');
    assert.equal(byId.get(o3).confirmed_deposit_id, r2.deposit_id);
    assert.equal(byId.get(oFree).status, 'requested');
  });

  test('다른 회차 주문 합산은 자동 확인하지 않고 미매칭으로 남긴다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book15k, quantity: 1 }]);
    await asUser(db, admin, 'select public.admin_shift_textbook_orders($1::uuid[], 1)', [[o2]]);

    const res = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 25000 });
    assert.equal(res.status, 'unmatched');

    const { rows } = await db.query(
      `select status from public.textbook_orders where id = any($1::uuid[])`,
      [[o1, o2]],
    );
    assert.ok(rows.every((r) => r.status === 'requested'));
  });

  test('같은 금액 미납 주문이 2건이면 ambiguous 로 검토 목록에 보낸다', async () => {
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);

    const res = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(res.status, 'ambiguous');
  });

  test('이벤트 송금: 기본 형식, 자리표시자, 개인별 금액(amount_override)으로 자동 확인한다', async () => {
    const eventId = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '여름수련회', 30000, '{이름}수련회') returning id`,
      [kaist],
    )).rows[0].id;
    const ep1 = (await db.query(
      `insert into public.event_payments (event_id, user_id, amount_override)
       values ($1, $2, 20000) returning id`,
      [eventId, hong],
    )).rows[0].id;

    const wrong = await ingest(db, { campus: kaist, depositorName: '홍길동수련회', amount: 30000 });
    assert.equal(wrong.status, 'unmatched');

    const ok = await ingest(db, { campus: kaist, depositorName: '홍길동 수련회', amount: 20000 });
    assert.equal(ok.status, 'auto_matched');

    const { rows: [ep] } = await db.query(
      'select is_paid, confirmed_by, confirmed_deposit_id from public.event_payments where id = $1',
      [ep1],
    );
    assert.equal(ep.is_paid, true);
    assert.equal(ep.confirmed_by, null);
    assert.equal(ep.confirmed_deposit_id, ok.deposit_id);
  });

  test('입금자명 은행 잘림: 6자 이상 접두사는 후보가 1건일 때만 자동 확인하고, 6자 미만은 접두사 매칭하지 않는다', async () => {
    const eventId = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '겨울수련회', 50000, '{이름}겨울수련회') returning id`,
      [kaist],
    )).rows[0].id;
    await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2)',
      [eventId, hong],
    );

    const shortRes = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 50000 });
    assert.equal(shortRes.status, 'unmatched');

    const prefixRes = await ingest(db, { campus: kaist, depositorName: '홍길동겨울수', amount: 50000 });
    assert.equal(prefixRes.status, 'auto_matched');
  });

  test('접두사 매칭 후보가 2건 이상이면 ambiguous 로 보낸다', async () => {
    const e1 = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '수련회1', 50000, '{이름}여름수련회A') returning id`,
      [kaist],
    )).rows[0].id;
    const e2 = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '수련회2', 50000, '{이름}여름수련회B') returning id`,
      [kaist],
    )).rows[0].id;
    await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $3), ($2, $3)',
      [e1, e2, hong],
    );

    const res = await ingest(db, { campus: kaist, depositorName: '홍길동여름수련', amount: 50000 });
    assert.equal(res.status, 'ambiguous');
  });

  test('이벤트와 교재 신청이 모두 후보면 cross_type_conflict 로 ambiguous 처리한다', async () => {
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '소모임', 10000, '') returning id`,
      [kaist],
    )).rows[0].id;
    await db.query('insert into public.event_payments (event_id, user_id) values ($1, $2)', [ev, hong]);

    const res = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(res.status, 'ambiguous');
    const { rows: [dep] } = await db.query('select match_reason from public.bank_deposits where id = $1', [res.deposit_id]);
    assert.equal(dep.match_reason, 'cross_type_conflict');
  });

  test('비활성 회원은 자동 매칭 후보에서 제외되고, 비활성 동명이인도 동명이인 충돌(same_name_members)로 검토에 보낸다', async () => {
    // 1) 비활성 회원의 미납 교재 신청 / 이벤트 송금은 자동 확인되지 않는다.
    const oKim = await placeOrder(kim, [{ textbook_id: book10k, quantity: 1 }]);
    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '행사', 12000, '{이름}행사') returning id`,
      [kaist],
    )).rows[0].id;
    const epKim = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev, kim],
    )).rows[0].id;
    await db.query('update public.profiles set deactivated_at = now() where id = $1', [kim]);

    const rTb = await ingest(db, { campus: kaist, depositorName: '김철수', amount: 10000 });
    assert.equal(rTb.status, 'unmatched');
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [oKim])).rows[0].status, 'requested');

    const rEv = await ingest(db, { campus: kaist, depositorName: '김철수행사', amount: 12000 });
    assert.equal(rEv.status, 'unmatched');
    assert.equal((await db.query('select is_paid from public.event_payments where id = $1', [epKim])).rows[0].is_paid, false);

    // 2) 비활성화된 동명이인(hong2)이 있어도 same_name_members 충돌로 자동 확인하지 않는다.
    const hong2 = await createUser(db, { studentId: '20250099', name: '홍길동' });
    await db.query('update public.profiles set deactivated_at = now() where id = $1', [hong2]);
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);

    const tbRes = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(tbRes.status, 'ambiguous');
    const { rows: [tbDep] } = await db.query('select match_reason from public.bank_deposits where id = $1', [tbRes.deposit_id]);
    assert.equal(tbDep.match_reason, 'same_name_members');

    // 학번 포함 이벤트('{이름}{학번}')는 구분 가능하므로 자동 확인된다.
    const evId = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '학번행사', 13000, '{이름}{학번}') returning id`,
      [kaist],
    )).rows[0].id;
    await db.query('insert into public.event_payments (event_id, user_id) values ($1, $2)', [evId, hong]);
    const evRes = await ingest(db, { campus: kaist, depositorName: '홍길동20240001', amount: 13000 });
    assert.equal(evRes.status, 'auto_matched');
  });

  test('과/부족 입금, 선입금은 unmatched 로 남고 주문 생성 후 재매칭하면 자동 확인된다', async () => {
    const early = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(early.status, 'unmatched');

    const over = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 11000 });
    assert.equal(over.status, 'unmatched');

    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const rematch = (await asUser(db, admin, 'select public.admin_rematch_deposit($1) as s', [early.deposit_id])).rows[0].s;
    assert.equal(rematch, 'auto_matched');
  });

  test('입금자명이 가려진 입금(masked_deposit)은 금액과 14일 원문을 보관한 unmatched 로 저장되고 절대 자동 확인되지 않으며 수동 연결할 수 있다', async () => {
    await db.query(`
      insert into vault.decrypted_secrets (name, decrypted_secret) values
        ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
        ('push_webhook_secret', 's3cret')`);

    const book1 = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '테스트교재', 1) returning id`,
      [kaist],
    )).rows[0].id;
    const o1 = await placeOrder(hong, [{ textbook_id: book1, quantity: 1 }]);

    const res = await ingest(db, {
      campus: kaist,
      kind: 'masked_deposit',
      amount: 1,
      rawTitle: '1원 입금',
      rawText: '**** → 내 KAIST CCC 모임통장',
      rawPackage: 'viva.republica.toss',
      reason: 'masked_depositor',
    });
    assert.equal(res.status, 'unmatched');

    // 단일 1원 후보가 있어도 자동 확인되지 않고 관리자 검토 푸시가 발송된다.
    assert.equal(
      (await db.query('select status from public.textbook_orders where id = $1', [o1])).rows[0].status,
      'requested',
    );
    const { rows: reqs } = await db.query('select body from net.requests');
    assert.deepEqual(reqs.map((r) => r.body), [
      { type: 'deposit_review', deposit_id: res.deposit_id },
    ]);

    // admin_list_bank_deposits 로 금액과 14일 원문이 조회된다.
    const { rows: [listed] } = await asUser(
      db,
      admin,
      'select status, depositor_name, amount, match_reason, raw_title, raw_text, raw_expires_at from public.admin_list_bank_deposits($1) where id = $2',
      [kaist, res.deposit_id],
    );
    assert.equal(listed.status, 'unmatched');
    assert.equal(listed.depositor_name, null);
    assert.equal(listed.amount, 1);
    assert.equal(listed.match_reason, 'masked_depositor');
    assert.equal(listed.raw_title, '1원 입금');
    assert.equal(listed.raw_text, '**** → 내 KAIST CCC 모임통장');
    assert.ok(listed.raw_expires_at);

    // 재매칭해도 자동 확인되지 않고 unmatched(masked_depositor)를 유지한다.
    const rematch = (await asUser(
      db, admin, 'select public.admin_rematch_deposit($1) as s', [res.deposit_id],
    )).rows[0].s;
    assert.equal(rematch, 'unmatched');
    assert.equal(
      (await db.query('select status from public.textbook_orders where id = $1', [o1])).rows[0].status,
      'requested',
    );

    // 금액이 다른 주문은 mismatch 가드에 막히고, 일치하는 1원 주문은 수동 연결이 성공하며 원문이 지워진다.
    const o10k = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    await assertRaises(
      asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[])', [res.deposit_id, [o10k]]),
      /합계가 다릅니다/,
    );
    await asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[])', [res.deposit_id, [o1]]);
    assert.equal(
      (await db.query('select status, confirmed_deposit_id from public.textbook_orders where id = $1', [o1])).rows[0].status,
      'paid',
    );
    const { rows: [linked] } = await db.query(
      'select status, raw_title, raw_text, raw_expires_at from public.bank_deposits where id = $1',
      [res.deposit_id],
    );
    assert.equal(linked.status, 'manual_matched');
    assert.equal(linked.raw_title, null);
    assert.equal(linked.raw_text, null);
    assert.equal(linked.raw_expires_at, null);

    // 기존 unparsed 행을 masked_deposit 으로 재해석해도 금액과 원문을 유지한 unmatched 로 바뀐다.
    const oldUnp = await ingest(db, {
      campus: kaist,
      kind: 'unparsed',
      rawTitle: '1원 입금',
      rawText: '**** → 내 KAIST CCC 모임통장',
      rawPackage: 'viva.republica.toss',
      reason: 'no_depositor',
    });
    const { rows: [rep] } = await db.query(
      `select status from public.apply_deposit_reparse($1, 'masked_deposit', null, 1, 'masked_depositor')`,
      [oldUnp.deposit_id],
    );
    assert.equal(rep.status, 'unmatched');
    const { rows: [repRow] } = await db.query(
      'select status, depositor_name, amount, match_reason, raw_text from public.bank_deposits where id = $1',
      [oldUnp.deposit_id],
    );
    assert.equal(repRow.status, 'unmatched');
    assert.equal(repRow.depositor_name, null);
    assert.equal(repRow.amount, 1);
    assert.equal(repRow.match_reason, 'masked_depositor');
    assert.equal(repRow.raw_text, '**** → 내 KAIST CCC 모임통장');
  });

  test('매칭 중 예외가 발생해도 입금 행은 unmatched(match_error)로 보존되고 검토 푸시를 보낸다', async () => {
    await db.query(`
      insert into vault.decrypted_secrets (name, decrypted_secret) values
        ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
        ('push_webhook_secret', 's3cret')`);
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);

    // 테스트 전용 트리거로 주문 UPDATE 중 예외를 유발한다.
    await db.exec(`
      create function private.test_fail_order_paid() returns trigger language plpgsql as $$
      begin
        if new.status = 'paid' then
          raise exception 'simulated match failure';
        end if;
        return new;
      end;
      $$;
      create trigger test_fail_order_paid_trg
        before update on public.textbook_orders
        for each row execute function private.test_fail_order_paid();
    `);
    try {
      const res = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
      assert.equal(res.status, 'unmatched');

      const { rows: [dep] } = await db.query(
        'select status, match_reason from public.bank_deposits where id = $1',
        [res.deposit_id],
      );
      assert.equal(dep.status, 'unmatched');
      assert.equal(dep.match_reason, 'match_error');

      const { rows: reqs } = await db.query('select body from net.requests');
      assert.deepEqual(reqs.map((r) => r.body), [
        { type: 'deposit_review', deposit_id: res.deposit_id },
      ]);
    } finally {
      await db.exec(`
        drop trigger test_fail_order_paid_trg on public.textbook_orders;
        drop function private.test_fail_order_paid();
      `);
    }
  });
});

describe('중복 방지, 진단 지표, 계좌 별칭 검증, 속도 제한', () => {
  let db;
  let kaist;
  let admin;
  let hong;
  let book10k;

  const placeOrder = async (userId, items) => {
    const { rows } = await asUser(
      db,
      userId,
      'select public.place_textbook_order($1::jsonb) as id',
      [JSON.stringify(items)],
    );
    return rows[0].id;
  };

  beforeEach(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
    hong = await createUser(db, { studentId: '20240001', name: '홍길동' });
    await asUser(db, admin, `select public.admin_update_deposit_settings($1, true, 'toss', 'KAIST CCC')`, [kaist]);
    book10k = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재', 10000) returning id`,
      [kaist],
    )).rows[0].id;
  });

  test('정확한 재전송은 duplicate_count/last_duplicate_at 을 기록하고, 60초 이내 동일 원문 2건은 둘 다 저장하되 두 번째는 ambiguous(possible_duplicate)로 보낸다', async () => {
    await db.query(`
      insert into vault.decrypted_secrets (name, decrypted_secret) values
        ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
        ('push_webhook_secret', 's3cret')`);
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    // 2건 중 1건만 남겨 첫 입금이 자동 확인되도록 만든다.
    await asUser(db, admin, `update public.textbook_orders set status = 'cancelled' where id = $1`, [o2]);

    const t0 = new Date('2026-11-26T03:00:00Z');
    const t20 = new Date('2026-11-26T03:00:20Z');
    const t90 = new Date('2026-11-26T03:01:30Z');
    const sameRaw = sha256('viva.republica.toss|입금 10,000원|홍길동 -> 내 KAIST CCC');
    const dk1 = sha256(`${sameRaw}|1795575600`);

    const r1 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: dk1, rawHash: sameRaw, depositedAt: t0.toISOString(),
    });
    assert.equal(r1.status, 'auto_matched');

    // 정확히 같은 dedupe_key 재전송 -> duplicate, 원본 행에 duplicate_count/last_duplicate_at 기록
    const dup = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: dk1, rawHash: sameRaw, depositedAt: t0.toISOString(),
    });
    assert.equal(dup.status, 'duplicate');
    assert.equal(dup.deposit_id, r1.deposit_id);

    const { rows: [orig] } = await db.query(
      'select duplicate_count, last_duplicate_at from public.bank_deposits where id = $1',
      [r1.deposit_id],
    );
    assert.equal(orig.duplicate_count, 1);
    assert.ok(orig.last_duplicate_at);

    // 새 주문이 있어도 60초 이내 동일 raw_hash 두 번째 알림은 자동 확인하지 않고 ambiguous(possible_duplicate) + duplicate_of_id 기록
    const o3 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const nearDup = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256(`${sameRaw}|1795575620`), rawHash: sameRaw, depositedAt: t20.toISOString(),
    });
    assert.equal(nearDup.status, 'ambiguous');
    assert.notEqual(nearDup.deposit_id, r1.deposit_id);

    const { rows: [d2] } = await db.query(
      'select status, match_reason, duplicate_of_id from public.bank_deposits where id = $1',
      [nearDup.deposit_id],
    );
    assert.equal(d2.status, 'ambiguous');
    assert.equal(d2.match_reason, 'possible_duplicate');
    assert.equal(d2.duplicate_of_id, r1.deposit_id);
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o3])).rows[0].status, 'requested');

    const { rows: reqs } = await db.query('select body from net.requests order by id');
    assert.deepEqual(reqs.map((r) => r.body), [
      { type: 'deposit_confirmed', deposit_id: r1.deposit_id },
      { type: 'deposit_review', deposit_id: nearDup.deposit_id },
    ]);

    // 60초 초과(t90) 동일 원문은 정상 매칭된다.
    const r3 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256(`${sameRaw}|1795575690`), rawHash: sameRaw, depositedAt: t90.toISOString(),
    });
    assert.equal(r3.status, 'auto_matched');
    assert.equal((await db.query('select count(*)::int as n from public.bank_deposits')).rows[0].n, 3);
  });

  test('possible_duplicate 는 재매칭 · 재해석으로 자동 확인되지 않고, 중복 아님 확인 후에만 재매칭이 자동 확인된다', async () => {
    const t0 = new Date('2026-11-26T03:00:00Z');
    const t15 = new Date('2026-11-26T03:00:15Z');
    const t25 = new Date('2026-11-26T03:00:25Z');
    const sameRaw = sha256('dup-guard-raw');

    const orig = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256('dup-guard-1'), rawHash: sameRaw, depositedAt: t0.toISOString(),
    });
    assert.equal(orig.status, 'unmatched');

    // 1) 파싱된 60초 이내 동일 원문 -> possible_duplicate
    const nearParsed = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256('dup-guard-2'), rawHash: sameRaw, depositedAt: t15.toISOString(),
    });
    assert.equal(nearParsed.status, 'ambiguous');

    // 일치하는 주문이 생겨도 possible_duplicate 상태에서 admin_rematch_deposit 는 자동 확인하지 않는다.
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const rematchBlocked = (await asUser(
      db, admin, 'select public.admin_rematch_deposit($1) as s', [nearParsed.deposit_id],
    )).rows[0].s;
    assert.equal(rematchBlocked, 'ambiguous');
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o1])).rows[0].status, 'requested');

    // 2) unparsed 상태로 들어온 60초 이내 동일 원문은 재해석해도 duplicate_of_id 와 possible_duplicate 를 유지하며 자동 확인되지 않는다.
    const nearUnp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      dedupeKey: sha256('dup-guard-3'), rawHash: sameRaw, depositedAt: t25.toISOString(),
      rawTitle: '토스', rawText: 'KAIST CCC 원문', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });
    assert.equal(nearUnp.status, 'unparsed');

    const { rows: [reparseStillUnp] } = await db.query(
      `select status from public.apply_deposit_reparse($1, 'unparsed', null, null, 'no_depositor')`,
      [nearUnp.deposit_id],
    );
    assert.equal(reparseStillUnp.status, 'unparsed');
    const { rows: [unpRow] } = await db.query(
      'select match_reason, duplicate_of_id from public.bank_deposits where id = $1',
      [nearUnp.deposit_id],
    );
    assert.equal(unpRow.match_reason, 'possible_duplicate');
    assert.ok(unpRow.duplicate_of_id);

    const { rows: [reparseDep] } = await db.query(
      `select status from public.apply_deposit_reparse($1, 'deposit', '홍길동', 10000, null)`,
      [nearUnp.deposit_id],
    );
    assert.equal(reparseDep.status, 'ambiguous');
    const { rows: [depRow] } = await db.query(
      'select status, match_reason, duplicate_of_id from public.bank_deposits where id = $1',
      [nearUnp.deposit_id],
    );
    assert.equal(depRow.status, 'ambiguous');
    assert.equal(depRow.match_reason, 'possible_duplicate');
    assert.ok(depRow.duplicate_of_id);
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o1])).rows[0].status, 'requested');

    // 3) "중복 아님" 해제 후에는 duplicate_cleared_at / duplicate_cleared_by 가 기록되고 재매칭 시 자동 확인된다.
    await asUser(db, admin, 'select public.admin_clear_possible_duplicate($1)', [nearParsed.deposit_id]);
    const { rows: [cleared] } = await db.query(
      'select status, match_reason, duplicate_cleared_at, duplicate_cleared_by from public.bank_deposits where id = $1',
      [nearParsed.deposit_id],
    );
    assert.equal(cleared.status, 'unmatched');
    assert.equal(cleared.match_reason, 'duplicate_cleared');
    assert.ok(cleared.duplicate_cleared_at);
    assert.equal(cleared.duplicate_cleared_by, admin);

    const rematchOk = (await asUser(
      db, admin, 'select public.admin_rematch_deposit($1) as s', [nearParsed.deposit_id],
    )).rows[0].s;
    assert.equal(rematchOk, 'auto_matched');
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o1])).rows[0].status, 'paid');

    // 4) 중복 아님을 누르지 않은 possible_duplicate 도 관리자 수동 연결은 허용된다.
    const o2 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    await asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[])', [nearUnp.deposit_id, [o2]]);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [nearUnp.deposit_id])).rows[0].status, 'manual_matched');
  });

  test('last_deposit_notification_at 은 ping/duplicate 를 제외한 실제 알림에만 갱신된다', async () => {
    await ingest(db, { campus: kaist, kind: 'ping' });
    let { rows: [s] } = await asUser(
      db,
      admin,
      `select last_received_at, last_deposit_notification_at, last_ignored_at, last_ignored_reason, ignored_count
       from public.campus_deposit_settings where campus_id = $1`,
      [kaist],
    );
    assert.ok(s.last_received_at);
    assert.equal(s.last_deposit_notification_at, null);

    await ingest(db, { campus: kaist, kind: 'ignored', reason: 'no_account_label' });
    ({ rows: [s] } = await asUser(
      db,
      admin,
      `select last_received_at, last_deposit_notification_at, last_ignored_at, last_ignored_reason, ignored_count
       from public.campus_deposit_settings where campus_id = $1`,
      [kaist],
    ));
    assert.ok(s.last_deposit_notification_at);
    assert.equal(s.last_ignored_reason, 'no_account_label');
    assert.equal(s.ignored_count, 1);

    const dk = sha256('exact-notif');
    const rh = sha256('exact-raw');
    await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000, dedupeKey: dk, rawHash: rh });
    await db.query(
      `update public.campus_deposit_settings set last_deposit_notification_at = '2026-01-01T00:00:00Z' where campus_id = $1`,
      [kaist],
    );
    const dup = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000, dedupeKey: dk, rawHash: rh });
    assert.equal(dup.status, 'duplicate');
    ({ rows: [s] } = await asUser(
      db,
      admin,
      'select last_deposit_notification_at from public.campus_deposit_settings where campus_id = $1',
      [kaist],
    ));
    assert.equal(new Date(s.last_deposit_notification_at).toISOString(), '2026-01-01T00:00:00.000Z');
  });

  test('너무 짧거나 일반적인 계좌 별칭은 거부한다', async () => {
    for (const shortLabel of ['CCC', '가 나', 'ab']) {
      await assertRaises(
        asUser(db, admin, `select public.admin_update_deposit_settings($1, true, 'toss', $2)`, [kaist, shortLabel]),
        /4자 이상/,
      );
    }
    for (const generic of ['토스뱅크', '모임통장', '동아리통장', '회비통장', 'TossBank']) {
      await assertRaises(
        asUser(db, admin, `select public.admin_update_deposit_settings($1, true, 'toss', $2)`, [kaist, generic]),
        /일반적인 계좌 별칭/,
      );
    }
    // 비활성화 상태에서는 빈 별칭 저장 허용
    await asUser(db, admin, `select public.admin_update_deposit_settings($1, false, 'toss', '')`, [kaist]);
  });

  test('캠퍼스당 분당 60건 초과 요청은 rate_limited 를 돌려준다', async () => {
    await db.query(
      'update public.campus_deposit_settings set rate_window_start = now(), rate_window_count = 60 where campus_id = $1',
      [kaist],
    );
    const res = await ingest(db, { campus: kaist, kind: 'ping' });
    assert.equal(res.status, 'rate_limited');
  });
});

describe('취소, 부분 미납, 삭제 보존, 수동 연결, 만료 원문 숨김, 보관 기간', () => {
  let db;
  let kaist;
  let admin;
  let hong;
  let book10k;
  let book15k;

  const placeOrder = async (userId, items) => {
    const { rows } = await asUser(
      db,
      userId,
      'select public.place_textbook_order($1::jsonb) as id',
      [JSON.stringify(items)],
    );
    return rows[0].id;
  };

  beforeEach(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
    hong = await createUser(db, { studentId: '20240001', name: '홍길동' });
    await asUser(db, admin, `select public.admin_update_deposit_settings($1, true, 'toss', 'KAIST CCC')`, [kaist]);
    book10k = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재A', 10000) returning id`,
      [kaist],
    )).rows[0].id;
    book15k = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재B', 15000) returning id`,
      [kaist],
    )).rows[0].id;
  });

  test('합산 자동확인 후 1건만 수동 미납 처리해도 입금 상태가 유지되고, undo 후 rematch 하면 2건이 다시 합산 확인된다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book15k, quantity: 1 }]);
    const dep = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 25000 });
    assert.equal(dep.status, 'auto_matched');

    // o1 만 수동 미납 -> o1 연결 해제, o2 는 여전히 연결돼 있으므로 입금은 auto_matched 유지
    await asUser(db, admin, `update public.textbook_orders set status = 'requested' where id = $1`, [o1]);
    assert.equal((await db.query('select confirmed_deposit_id from public.textbook_orders where id = $1', [o1])).rows[0].confirmed_deposit_id, null);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [dep.deposit_id])).rows[0].status, 'auto_matched');

    // admin_undo_deposit -> 남은 o2 도 requested 로 돌아가고 입금은 undone
    await asUser(db, admin, 'select public.admin_undo_deposit($1)', [dep.deposit_id]);
    assert.equal((await db.query('select status, confirmed_deposit_id from public.textbook_orders where id = $1', [o2])).rows[0].status, 'requested');
    assert.equal((await db.query('select status, undone_by from public.bank_deposits where id = $1', [dep.deposit_id])).rows[0].status, 'undone');

    // admin_rematch_deposit -> o1 + o2 합산(25,000)으로 다시 auto_matched
    const rematch = (await asUser(db, admin, 'select public.admin_rematch_deposit($1) as s', [dep.deposit_id])).rows[0].s;
    assert.equal(rematch, 'auto_matched');
    const { rows: both } = await db.query(
      'select status, confirmed_deposit_id from public.textbook_orders where id = any($1::uuid[])',
      [[o1, o2]],
    );
    assert.ok(both.every((r) => r.status === 'paid' && r.confirmed_deposit_id === dep.deposit_id));
  });

  test('연결된 주문이나 이벤트를 삭제(DELETE)해도 입금 상태는 undone 으로 바뀌지 않고 유지된다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const d1 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(d1.status, 'auto_matched');

    await asUser(db, admin, 'delete from public.textbook_orders where id = $1', [o1]);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [d1.deposit_id])).rows[0].status, 'auto_matched');

    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, 'MT', 20000) returning id`,
      [kaist],
    )).rows[0].id;
    await db.query('insert into public.event_payments (event_id, user_id) values ($1, $2)', [ev, hong]);
    const d2 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 20000 });
    assert.equal(d2.status, 'auto_matched');

    await asUser(db, admin, 'delete from public.events where id = $1', [ev]);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [d2.deposit_id])).rows[0].status, 'auto_matched');
  });

  test('만료된 원문은 정리가 돌기 전이라도 admin_list_bank_deposits 에서 숨겨지고, 직접 raw_* SELECT 는 차단된다', async () => {
    const unp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      rawTitle: '토스', rawText: '비밀 원문 KAIST CCC', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });

    // 만료 전에는 admin_list_bank_deposits 로 원문이 보인다.
    let { rows: [row] } = await asUser(
      db,
      admin,
      'select raw_title, raw_text, raw_package, match_reason from public.admin_list_bank_deposits($1) where id = $2',
      [kaist, unp.deposit_id],
    );
    assert.equal(row.raw_text, '비밀 원문 KAIST CCC');

    // 정리가 아직 돌지 않았어도 raw_expires_at 이 지나면 RPC 결과에서 즉시 숨겨진다.
    await db.query(
      `update public.bank_deposits set raw_expires_at = now() - interval '1 second' where id = $1`,
      [unp.deposit_id],
    );
    ({ rows: [row] } = await asUser(
      db,
      admin,
      'select raw_title, raw_text, raw_package, match_reason from public.admin_list_bank_deposits($1) where id = $2',
      [kaist, unp.deposit_id],
    ));
    assert.equal(row.raw_title, null);
    assert.equal(row.raw_text, null);
    assert.equal(row.raw_package, null);
    assert.equal(row.match_reason, 'raw_expired');

    // 직접 테이블에서 raw_* 컬럼을 SELECT 하려 하면 거부된다.
    await assertDenied(asUser(db, admin, 'select raw_text from public.bank_deposits'));
    await assertDenied(asUser(db, admin, 'select raw_title from public.bank_deposits'));
  });

  test('수동 연결 금액 불일치 가드, 무시 및 되돌리기, unparsed 재해석, 1년 정리가 동작한다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book15k, quantity: 1 }]);
    const under = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 24000 });
    // 금액 불일치(24,000 vs 25,000)는 p_allow_amount_mismatch = true 없이 거부된다.
    await assertRaises(
      asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[])', [under.deposit_id, [o1, o2]]),
      /합계가 다릅니다/,
    );
    await asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[], true)', [under.deposit_id, [o1, o2]]);
    assert.equal((await db.query('select status, matched_by from public.bank_deposits where id = $1', [under.deposit_id])).rows[0].status, 'manual_matched');

    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, '수련회', 30000) returning id`,
      [kaist],
    )).rows[0].id;
    const epId = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev, hong],
    )).rows[0].id;
    const wrongAmt = await ingest(db, { campus: kaist, depositorName: '다른이름', amount: 29000 });
    await assertRaises(
      asUser(db, admin, 'select public.admin_link_deposit_to_event($1, $2)', [wrongAmt.deposit_id, epId]),
      /금액이 다릅니다/,
    );
    const extra = await ingest(db, { campus: kaist, depositorName: '다른이름', amount: 30000 });
    await asUser(db, admin, 'select public.admin_ignore_deposit($1, true)', [extra.deposit_id]);
    await asUser(db, admin, 'select public.admin_ignore_deposit($1, false)', [extra.deposit_id]);
    await asUser(db, admin, 'select public.admin_link_deposit_to_event($1, $2)', [extra.deposit_id, epId]);
    assert.equal((await db.query('select confirmed_deposit_id from public.event_payments where id = $1', [epId])).rows[0].confirmed_deposit_id, extra.deposit_id);

    const ev2 = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, '수련회2', 30000) returning id`,
      [kaist],
    )).rows[0].id;
    const ep2Id = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev2, hong],
    )).rows[0].id;
    await asUser(db, admin, 'select public.admin_link_deposit_to_event($1, $2, true)', [wrongAmt.deposit_id, ep2Id]);
    assert.equal((await db.query('select confirmed_deposit_id from public.event_payments where id = $1', [ep2Id])).rows[0].confirmed_deposit_id, wrongAmt.deposit_id);

    const o3 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const unp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      rawTitle: '토스', rawText: '알 수 없는 형식 KAIST CCC', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });
    const { rows: [reparsed] } = await db.query(
      `select status from public.apply_deposit_reparse($1, 'deposit', '홍길동', 10000, null)`,
      [unp.deposit_id],
    );
    assert.equal(reparsed.status, 'auto_matched');
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o3])).rows[0].status, 'paid');

    await db.query(
      `update public.bank_deposits set received_at = now() - interval '366 days' where id = $1`,
      [unp.deposit_id],
    );
    await db.query('select private.purge_old_campus_data($1)', [kaist]);
    assert.equal((await db.query('select 1 from public.bank_deposits where id = $1', [unp.deposit_id])).rows.length, 0);
    assert.equal((await db.query('select confirmed_deposit_id from public.textbook_orders where id = $1', [o3])).rows[0].confirmed_deposit_id, null);
  });

  test('undo 와 수동 미납 처리를 어느 순서로 실행해도 입금과 주문/송금 상태가 일관된다', async () => {
    // 1) 수동 미납 먼저 -> 트리거가 입금을 undone 처리 -> 후속 admin_undo_deposit 는 중복 취소하지 않고 거부
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const d1 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(d1.status, 'auto_matched');

    await asUser(db, admin, `update public.textbook_orders set status = 'requested' where id = $1`, [o1]);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [d1.deposit_id])).rows[0].status, 'undone');
    await assertRaises(
      asUser(db, admin, 'select public.admin_undo_deposit($1)', [d1.deposit_id]),
      /확인 완료된 입금만 취소/,
    );

    // 2) admin_undo_deposit 먼저 -> 입금 undone, 이벤트 송금 미납 -> 후속 수동 미납 UPDATE 도 상태 일관 유지
    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, '캠프', 20000) returning id`,
      [kaist],
    )).rows[0].id;
    const epId = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev, hong],
    )).rows[0].id;
    const d2 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 20000 });
    assert.equal(d2.status, 'auto_matched');

    await asUser(db, admin, 'select public.admin_undo_deposit($1)', [d2.deposit_id]);
    await asUser(db, admin, 'update public.event_payments set is_paid = false where id = $1', [epId]);
    const { rows: [epAfter] } = await db.query('select is_paid, confirmed_deposit_id from public.event_payments where id = $1', [epId]);
    assert.equal(epAfter.is_paid, false);
    assert.equal(epAfter.confirmed_deposit_id, null);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [d2.deposit_id])).rows[0].status, 'undone');
  });

  test('서버 상태 필터 · 그룹별 카운트 · 페이지네이션이 페이지 크기를 넘겨도 오래된 검토 필요 행을 빠뜨리지 않는다', async () => {
    const oldReviewIds = [];
    for (let i = 0; i < 4; i++) {
      const r = await ingest(db, {
        campus: kaist,
        kind: i === 0 ? 'unparsed' : 'deposit',
        depositorName: i === 0 ? null : `미매칭${i}`,
        amount: i === 0 ? null : 10000,
        rawTitle: i === 0 ? '토스' : null,
        rawText: i === 0 ? 'KAIST CCC 미해석' : null,
        rawPackage: i === 0 ? 'viva.republica.toss' : null,
        reason: i === 0 ? 'no_amount' : null,
      });
      oldReviewIds.push(r.deposit_id);
      await db.query(
        `update public.bank_deposits set received_at = now() - interval '30 days' + ($2 || ' minutes')::interval where id = $1`,
        [r.deposit_id, i],
      );
    }

    // 페이지 크기(3)를 훨씬 넘는 최신 auto_matched 행 10건을 추가한다.
    for (let i = 0; i < 10; i++) {
      const { rows: [row] } = await db.query(
        `insert into public.bank_deposits (
           campus_id, dedupe_key, raw_hash, bank_code, status,
           depositor_name, amount, deposited_at, received_at, match_reason, matched_at
         ) values (
           $1, $2, $3, 'toss', 'auto_matched',
           '홍길동', 10000, now(), now() - ($4 || ' seconds')::interval, 'exact_textbook_single', now()
         ) returning id`,
        [kaist, sha256(`pg-dk-${i}`), sha256(`pg-rh-${i}`), i],
      );
      assert.ok(row.id);
    }

    const { rows: [counts] } = await asUser(
      db, admin, 'select * from public.admin_count_bank_deposits($1)', [kaist],
    );
    assert.equal(counts.needs_review, 4);
    assert.equal(counts.auto_matched, 10);
    assert.equal(counts.all_count, 14);
    assert.equal(counts.unparsed_with_raw, 1);

    // 페이지 크기 3으로 needs_review 만 조회해도 30일 전 행 4건이 페이지네이션으로 전부 나온다.
    const { rows: p1 } = await asUser(
      db, admin, `select id from public.admin_list_bank_deposits($1, 'needs_review', 3, 0)`, [kaist],
    );
    const { rows: p2 } = await asUser(
      db, admin, `select id from public.admin_list_bank_deposits($1, 'needs_review', 3, 3)`, [kaist],
    );
    assert.equal(p1.length, 3);
    assert.equal(p2.length, 1);
    assert.deepEqual(
      new Set([...p1, ...p2].map((r) => r.id)),
      new Set(oldReviewIds),
    );
  });
});

describe('보안, RLS, 캠퍼스 격리', () => {
  let db;
  let kaist;
  let central;
  let kaistAdmin;
  let otherAdmin;
  let member;
  let depositId;

  before(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    await createCampus(db, { code: 'snu', name: 'SNU' });
    central = await createUser(db, { studentId: '20250133', name: '총괄', role: 'central_admin' });
    kaistAdmin = await createUser(db, { studentId: '20200001', name: '카이스트관리자', role: 'campus_admin' });
    otherAdmin = await createUser(db, { studentId: '20200002', name: '타캠관리자', role: 'campus_admin', campus: 'snu' });
    member = await createUser(db, { studentId: '20240001', name: '일반회원' });

    await asUser(db, kaistAdmin, `select public.admin_update_deposit_settings($1, true, 'toss', 'KAIST CCC')`, [kaist]);
    const token = (await asUser(db, kaistAdmin, 'select public.admin_rotate_deposit_token($1) as t', [kaist])).rows[0].t;
    assert.ok(token.startsWith('dep_'));
    assert.equal(token.length, 68);

    const { rows: [stored] } = await db.query(
      'select token_hash, token_prefix from public.campus_deposit_settings where campus_id = $1',
      [kaist],
    );
    assert.equal(stored.token_hash, sha256(token));
    assert.equal(stored.token_prefix, token.slice(0, 10));

    depositId = (await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 })).deposit_id;
  });

  test('token_hash, rate_window, raw_* 컬럼은 관리자도 직접 SELECT 할 수 없다', async () => {
    await assertDenied(asUser(db, kaistAdmin, 'select token_hash from public.campus_deposit_settings'));
    await assertDenied(asUser(db, central, 'select token_hash from public.campus_deposit_settings'));
    await assertDenied(asUser(db, central, 'select rate_window_count from public.campus_deposit_settings'));
    await assertDenied(asUser(db, central, 'select raw_text from public.bank_deposits'));
  });

  test('일반 회원과 타 캠퍼스 관리자, anon 은 설정과 입금 내역을 보거나 조작할 수 없다', async () => {
    assert.equal((await asUser(db, member, 'select campus_id from public.campus_deposit_settings')).rows.length, 0);
    assert.equal((await asUser(db, member, 'select id from public.bank_deposits')).rows.length, 0);
    assert.equal((await asUser(db, otherAdmin, 'select campus_id from public.campus_deposit_settings')).rows.length, 0);
    assert.equal((await asUser(db, otherAdmin, 'select id from public.bank_deposits')).rows.length, 0);
    assert.equal((await asUser(db, kaistAdmin, 'select id from public.admin_list_bank_deposits($1)', [kaist])).rows.length, 1);
    assert.equal((await asUser(db, central, 'select id from public.admin_list_bank_deposits($1)', [kaist])).rows.length, 1);

    await assertRaises(
      asUser(db, otherAdmin, 'select id from public.admin_list_bank_deposits($1)', [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, member, 'select id from public.admin_list_bank_deposits($1)', [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, otherAdmin, 'select * from public.admin_count_bank_deposits($1)', [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, member, 'select * from public.admin_count_bank_deposits($1)', [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, otherAdmin, 'select public.admin_clear_possible_duplicate($1)', [depositId]),
      /입금 내역을 찾을 수 없습니다/,
    );
    await assertRaises(
      asUser(db, member, 'select public.admin_clear_possible_duplicate($1)', [depositId]),
      /입금 내역을 찾을 수 없습니다/,
    );
    await assertDenied(asAnon(db, 'select id from public.bank_deposits'));
    await assertDenied(asUser(db, kaistAdmin, `update public.bank_deposits set status = 'ignored'`));
    await assertDenied(asUser(db, kaistAdmin, 'delete from public.bank_deposits'));
    await assertDenied(asUser(db, kaistAdmin, 'update public.textbook_orders set confirmed_deposit_id = $1', [depositId]));
    await assertDenied(asUser(db, kaistAdmin, 'update public.event_payments set confirmed_deposit_id = $1', [depositId]));
  });

  test('service_role 전용 ingest / reparse RPC 는 authenticated 와 anon 이 호출할 수 없다', async () => {
    await assertDenied(asUser(db, central, `select * from public.ingest_bank_deposit($1, 'ping')`, [kaist]));
    await assertDenied(asAnon(db, `select * from public.ingest_bank_deposit($1, 'ping')`, [kaist]));
    await assertDenied(asUser(db, central, `select * from public.apply_deposit_reparse($1, 'ignored')`, [depositId]));
    await assertDenied(asAnon(db, `select * from public.apply_deposit_reparse($1, 'ignored')`, [depositId]));
  });
});
