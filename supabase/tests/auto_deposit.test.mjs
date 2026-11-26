// 자동 입금 확인: 매칭 알고리즘, 중복 방지, 취소/수동 연결, 보관 기간, 푸시 알림, 권한 격리.
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

    // 같은 회차 2건 합산(10,000 + 15,000 = 25,000) + 0원 주문이 섞여도 유료 2건 합산에 영향 없음
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

    // 이벤트 기본 금액(30,000)은 amount_override(20,000)와 달라 미매칭
    const wrong = await ingest(db, { campus: kaist, depositorName: '홍길동수련회', amount: 30000 });
    assert.equal(wrong.status, 'unmatched');

    // 공백 변형('홍길동 수련회') + 개인별 금액(20,000)으로 자동 확인
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

    // 3자('홍길동')는 6자 미만이라 '홍길동겨울수련회'에 접두사 매칭되지 않는다.
    const shortRes = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 50000 });
    assert.equal(shortRes.status, 'unmatched');

    // 6자('홍길동겨울수')는 후보가 1건이므로 자동 확인된다.
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

  test('엄격한 동명이인 보호: 다른 활성 회원이 같은 이름이면 미납이 1명뿐이어도 ambiguous, 학번 포함 이벤트는 자동 확인', async () => {
    const hong2 = await createUser(db, { studentId: '20250099', name: '홍길동' });
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);

    // hong2 는 주문이 없지만 같은 캠퍼스 활성 동명이인이므로 자동 확인하지 않는다.
    const tbRes = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(tbRes.status, 'ambiguous');
    const { rows: [tbDep] } = await db.query('select match_reason from public.bank_deposits where id = $1', [tbRes.deposit_id]);
    assert.equal(tbDep.match_reason, 'same_name_members');

    // 학번 포함 이벤트('{이름}{학번}')는 구분 가능하므로 자동 확인된다.
    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount, deposit_name)
       values ($1, '학번행사', 12000, '{이름}{학번}') returning id`,
      [kaist],
    )).rows[0].id;
    await db.query('insert into public.event_payments (event_id, user_id) values ($1, $2)', [ev, hong]);

    const evRes = await ingest(db, { campus: kaist, depositorName: '홍길동20240001', amount: 12000 });
    assert.equal(evRes.status, 'auto_matched');

    // hong2 가 비활성화되면 더 이상 동명이인 충돌이 아니므로 재매칭 시 자동 확인된다.
    await db.query('update public.profiles set deactivated_at = now() where id = $1', [hong2]);
    const rematch = (await asUser(db, admin, 'select public.admin_rematch_deposit($1) as s', [tbRes.deposit_id])).rows[0].s;
    assert.equal(rematch, 'auto_matched');
  });

  test('과/부족 입금, 선입금(주문 없음)은 unmatched 로 남고 주문 생성 후 재매칭하면 자동 확인된다', async () => {
    const early = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    assert.equal(early.status, 'unmatched');

    const over = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 11000 });
    assert.equal(over.status, 'unmatched');

    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const rematch = (await asUser(db, admin, 'select public.admin_rematch_deposit($1) as s', [early.deposit_id])).rows[0].s;
    assert.equal(rematch, 'auto_matched');
  });
});

describe('중복 방지, 진단 지표, 속도 제한', () => {
  let db;
  let kaist;
  let admin;
  let hong;
  let book10k;

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

  test('같은 dedupe_key 와 15초 이내 동일 raw_hash 는 중복 무시하고, 15초 초과 동일 입금 2건은 모두 처리한다', async () => {
    const t0 = new Date('2026-11-26T03:00:00Z');
    const t3 = new Date('2026-11-26T03:00:03Z');
    const t30 = new Date('2026-11-26T03:00:30Z');
    const sameRaw = sha256('viva.republica.toss|입금 10,000원|홍길동 -> 내 KAIST CCC');
    const dk1 = sha256('dk1');

    const r1 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: dk1, rawHash: sameRaw, depositedAt: t0.toISOString(),
    });
    assert.equal(r1.status, 'unmatched');

    // 정확히 같은 dedupe_key 재전송 -> duplicate
    const dup1 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: dk1, rawHash: sameRaw, depositedAt: t30.toISOString(),
    });
    assert.equal(dup1.status, 'duplicate');
    assert.equal(dup1.deposit_id, r1.deposit_id);

    // 다른 dedupe_key 지만 3초 차 동일 raw_hash -> duplicate
    const dup2 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256('dk2'), rawHash: sameRaw, depositedAt: t3.toISOString(),
    });
    assert.equal(dup2.status, 'duplicate');
    assert.equal(dup2.deposit_id, r1.deposit_id);

    // 30초 뒤 실제 동일 금액/입금자 두 번째 송금 -> 별도 건으로 처리
    const r2 = await ingest(db, {
      campus: kaist, depositorName: '홍길동', amount: 10000,
      dedupeKey: sha256('dk3'), rawHash: sameRaw, depositedAt: t30.toISOString(),
    });
    assert.equal(r2.status, 'unmatched');
    assert.notEqual(r2.deposit_id, r1.deposit_id);

    const { rows: [cnt] } = await db.query('select count(*)::int as n from public.bank_deposits');
    assert.equal(cnt.n, 2);
  });

  test('ignored 와 ping 은 원문을 저장하지 않고 last_received_at 및 ignored 진단을 갱신한다', async () => {
    const ping = await ingest(db, { campus: kaist, kind: 'ping' });
    assert.equal(ping.status, 'pong');

    const ig1 = await ingest(db, { campus: kaist, kind: 'ignored', reason: 'no_account_label' });
    assert.equal(ig1.status, 'ignored');
    const ig2 = await ingest(db, { campus: kaist, kind: 'ignored', reason: 'withdrawal' });
    assert.equal(ig2.status, 'ignored');

    const { rows: [s] } = await asUser(
      db,
      admin,
      `select last_received_at, last_ignored_at, last_ignored_reason, ignored_count
       from public.campus_deposit_settings where campus_id = $1`,
      [kaist],
    );
    assert.ok(s.last_received_at);
    assert.ok(s.last_ignored_at);
    assert.equal(s.last_ignored_reason, 'withdrawal');
    assert.equal(s.ignored_count, 2);
    assert.equal((await db.query('select count(*)::int as n from public.bank_deposits')).rows[0].n, 0);
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

describe('취소, 수동 연결, 무시, 재해석, 보관 기간, 푸시 트리거', () => {
  let db;
  let kaist;
  let admin;
  let hong;
  let book10k;
  let book15k;

  const configurePush = () => db.query(`
    insert into vault.decrypted_secrets (name, decrypted_secret) values
      ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
      ('push_webhook_secret', 's3cret')`);

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

  test('admin_undo_deposit 은 합산 자동확인된 주문 전체를 되돌리고 undone 상태로 바꾼다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book15k, quantity: 1 }]);
    const dep = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 25000 });
    assert.equal(dep.status, 'auto_matched');

    await asUser(db, admin, 'select public.admin_undo_deposit($1)', [dep.deposit_id]);

    const { rows: ords } = await db.query(
      'select status, confirmed_deposit_id from public.textbook_orders where id = any($1::uuid[])',
      [[o1, o2]],
    );
    assert.ok(ords.every((o) => o.status === 'requested' && o.confirmed_deposit_id === null));

    const { rows: [d] } = await db.query(
      'select status, undone_at, undone_by, matched_at from public.bank_deposits where id = $1',
      [dep.deposit_id],
    );
    assert.equal(d.status, 'undone');
    assert.ok(d.undone_at);
    assert.equal(d.undone_by, admin);
    assert.equal(d.matched_at, null);
  });

  test('기존 주문/이벤트 화면에서 직접 미납으로 되돌리면 입금 연결이 해제되고 undone 처리된다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const dep1 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    await asUser(db, admin, `update public.textbook_orders set status = 'requested' where id = $1`, [o1]);

    const { rows: [ord] } = await db.query('select confirmed_deposit_id from public.textbook_orders where id = $1', [o1]);
    assert.equal(ord.confirmed_deposit_id, null);
    const { rows: [d1] } = await db.query('select status, undone_by from public.bank_deposits where id = $1', [dep1.deposit_id]);
    assert.equal(d1.status, 'undone');
    assert.equal(d1.undone_by, admin);

    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, 'MT', 20000) returning id`,
      [kaist],
    )).rows[0].id;
    const epId = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev, hong],
    )).rows[0].id;
    const dep2 = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 20000 });
    assert.equal(dep2.status, 'auto_matched');

    await asUser(db, admin, 'update public.event_payments set is_paid = false where id = $1', [epId]);
    const { rows: [d2] } = await db.query('select status from public.bank_deposits where id = $1', [dep2.deposit_id]);
    assert.equal(d2.status, 'undone');
  });

  test('수동 연결(이벤트/복수 주문), 무시 및 되돌리기, unparsed 재해석이 동작한다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const o2 = await placeOrder(hong, [{ textbook_id: book15k, quantity: 1 }]);
    // 부족 입금(24,000원) -> unmatched -> 관리자가 수동 연결
    const under = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 24000 });
    assert.equal(under.status, 'unmatched');

    await asUser(db, admin, 'select public.admin_link_deposit_to_orders($1, $2::uuid[])', [under.deposit_id, [o1, o2]]);
    const { rows: [dUnder] } = await db.query('select status, matched_by from public.bank_deposits where id = $1', [under.deposit_id]);
    assert.equal(dUnder.status, 'manual_matched');
    assert.equal(dUnder.matched_by, admin);

    // 이벤트 수동 연결 + 무시/되돌리기
    const ev = (await db.query(
      `insert into public.events (campus_id, title, amount) values ($1, '수련회', 30000) returning id`,
      [kaist],
    )).rows[0].id;
    const epId = (await db.query(
      'insert into public.event_payments (event_id, user_id) values ($1, $2) returning id',
      [ev, hong],
    )).rows[0].id;
    const extra = await ingest(db, { campus: kaist, depositorName: '다른이름', amount: 30000 });
    await asUser(db, admin, 'select public.admin_ignore_deposit($1, true)', [extra.deposit_id]);
    assert.equal((await db.query('select status from public.bank_deposits where id = $1', [extra.deposit_id])).rows[0].status, 'ignored');
    await asUser(db, admin, 'select public.admin_ignore_deposit($1, false)', [extra.deposit_id]);
    await asUser(db, admin, 'select public.admin_link_deposit_to_event($1, $2)', [extra.deposit_id, epId]);
    assert.equal((await db.query('select is_paid, confirmed_deposit_id from public.event_payments where id = $1', [epId])).rows[0].confirmed_deposit_id, extra.deposit_id);

    // unparsed 저장 -> apply_deposit_reparse 성공 시 원문 삭제 + 자동 매칭
    const o3 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const unp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      rawTitle: '토스', rawText: '알 수 없는 형식 KAIST CCC', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });
    assert.equal(unp.status, 'unparsed');
    const { rows: [beforeReparse] } = await db.query(
      'select raw_text, raw_expires_at from public.bank_deposits where id = $1',
      [unp.deposit_id],
    );
    assert.equal(beforeReparse.raw_text, '알 수 없는 형식 KAIST CCC');
    assert.ok(beforeReparse.raw_expires_at);

    const { rows: [reparsed] } = await db.query(
      `select status from public.apply_deposit_reparse($1, 'deposit', '홍길동', 10000, null)`,
      [unp.deposit_id],
    );
    assert.equal(reparsed.status, 'auto_matched');
    const { rows: [afterReparse] } = await db.query(
      'select raw_title, raw_text, raw_expires_at from public.bank_deposits where id = $1',
      [unp.deposit_id],
    );
    assert.equal(afterReparse.raw_title, null);
    assert.equal(afterReparse.raw_text, null);
    assert.equal(afterReparse.raw_expires_at, null);
    assert.equal((await db.query('select status from public.textbook_orders where id = $1', [o3])).rows[0].status, 'paid');
  });

  test('보관 기간: 14일 지난 unparsed 원문은 지워지고, 1년 지난 입금 내역은 purge 로 삭제된다', async () => {
    const o1 = await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);
    const matched = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    const unp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      rawTitle: 'T', rawText: '원문 KAIST CCC', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });

    // 15일 경과 시뮬레이션 -> 다음 ingest 때 만료 원문 정리
    await db.query(
      `update public.bank_deposits set raw_expires_at = now() - interval '1 day' where id = $1`,
      [unp.deposit_id],
    );
    await ingest(db, { campus: kaist, kind: 'ping' });

    const { rows: [expired] } = await db.query(
      'select raw_title, raw_text, raw_expires_at from public.bank_deposits where id = $1',
      [unp.deposit_id],
    );
    assert.equal(expired.raw_title, null);
    assert.equal(expired.raw_text, null);
    assert.equal(expired.raw_expires_at, null);

    // 1년 초과 입금 내역 -> purge_old_campus_data 로 삭제되고 연결된 주문 FK 는 null 로 정리된다.
    await db.query(
      `update public.bank_deposits set received_at = now() - interval '366 days' where id = $1`,
      [matched.deposit_id],
    );
    await db.query('select private.purge_old_campus_data($1)', [kaist]);

    assert.equal((await db.query('select 1 from public.bank_deposits where id = $1', [matched.deposit_id])).rows.length, 0);
    assert.equal((await db.query('select confirmed_deposit_id from public.textbook_orders where id = $1', [o1])).rows[0].confirmed_deposit_id, null);
  });

  test('푸시 트리거: 자동 확인은 deposit_confirmed, 검토 필요 신규 입금은 deposit_review, 취소/실패 안전성', async () => {
    await configurePush();
    await placeOrder(hong, [{ textbook_id: book10k, quantity: 1 }]);

    const auto = await ingest(db, { campus: kaist, depositorName: '홍길동', amount: 10000 });
    const unm = await ingest(db, { campus: kaist, depositorName: '미매칭', amount: 9999 });
    const unp = await ingest(db, {
      campus: kaist, kind: 'unparsed',
      rawTitle: 'T', rawText: '미해석 KAIST CCC', rawPackage: 'viva.republica.toss', reason: 'no_amount',
    });

    const { rows: reqs } = await db.query('select body, headers from net.requests order by id');
    assert.deepEqual(reqs.map((r) => r.body), [
      { type: 'deposit_confirmed', deposit_id: auto.deposit_id },
      { type: 'deposit_review', deposit_id: unm.deposit_id },
      { type: 'deposit_review', deposit_id: unp.deposit_id },
    ]);
    assert.equal(reqs[0].headers['x-push-secret'], 's3cret');

    // undo 와 여전히 미매칭인 rematch 는 관리자 푸시를 다시 보내지 않는다.
    await asUser(db, admin, 'select public.admin_undo_deposit($1)', [auto.deposit_id]);
    await asUser(db, admin, 'select public.admin_rematch_deposit($1)', [unm.deposit_id]);
    assert.equal((await db.query('select count(*)::int as n from net.requests')).rows[0].n, 3);

    // 푸시 전송이 실패해도 입금 수집은 성공한다.
    await db.query('delete from net.requests');
    await db.query('alter table net.requests add constraint fail_all check (false)');
    try {
      const ok = await ingest(db, { campus: kaist, depositorName: '누군가', amount: 5000 });
      assert.equal(ok.status, 'unmatched');
    } finally {
      await db.query('alter table net.requests drop constraint fail_all');
    }
  });
});

describe('보안, RLS, 캠퍼스 격리', () => {
  let db;
  let kaist;
  let otherCampus;
  let central;
  let kaistAdmin;
  let otherAdmin;
  let member;
  let depositId;

  before(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    otherCampus = await createCampus(db, { code: 'snu', name: 'SNU' });
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

  test('token_hash 와 rate_window 컬럼은 관리자도 SELECT 할 수 없다', async () => {
    await assertDenied(asUser(db, kaistAdmin, 'select token_hash from public.campus_deposit_settings'));
    await assertDenied(asUser(db, central, 'select token_hash from public.campus_deposit_settings'));
    await assertDenied(asUser(db, central, 'select rate_window_count from public.campus_deposit_settings'));
  });

  test('일반 회원과 타 캠퍼스 관리자, anon 은 설정과 입금 내역을 보거나 조작할 수 없다', async () => {
    assert.equal((await asUser(db, member, 'select campus_id from public.campus_deposit_settings')).rows.length, 0);
    assert.equal((await asUser(db, member, 'select id from public.bank_deposits')).rows.length, 0);
    assert.equal((await asUser(db, otherAdmin, 'select campus_id from public.campus_deposit_settings')).rows.length, 0);
    assert.equal((await asUser(db, otherAdmin, 'select id from public.bank_deposits')).rows.length, 0);
    assert.equal((await asUser(db, kaistAdmin, 'select id from public.bank_deposits')).rows.length, 1);
    assert.equal((await asUser(db, central, 'select id from public.bank_deposits')).rows.length, 1);

    await assertDenied(asAnon(db, 'select id from public.bank_deposits'));
    await assertDenied(asUser(db, kaistAdmin, `update public.bank_deposits set status = 'ignored'`));
    await assertDenied(asUser(db, kaistAdmin, 'delete from public.bank_deposits'));
    await assertDenied(asUser(db, kaistAdmin, 'update public.textbook_orders set confirmed_deposit_id = $1', [depositId]));
    await assertDenied(asUser(db, kaistAdmin, 'update public.event_payments set confirmed_deposit_id = $1', [depositId]));

    await assertRaises(
      asUser(db, otherAdmin, 'select public.admin_ignore_deposit($1, true)', [depositId]),
      /찾을 수 없습니다/,
    );
    await assertRaises(
      asUser(db, member, 'select public.admin_rotate_deposit_token($1)', [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, otherAdmin, `select public.admin_update_deposit_settings($1, true, 'toss', 'X')`, [kaist]),
      /권한이 없습니다/,
    );
    await assertRaises(
      asUser(db, kaistAdmin, `select public.admin_update_deposit_settings($1, true, 'toss', '   ')`, [kaist]),
      /계좌 별칭/,
    );
  });

  test('service_role 전용 ingest / reparse RPC 는 authenticated 와 anon 이 호출할 수 없다', async () => {
    await assertDenied(
      asUser(db, central, `select * from public.ingest_bank_deposit($1, 'ping')`, [kaist]),
    );
    await assertDenied(
      asAnon(db, `select * from public.ingest_bank_deposit($1, 'ping')`, [kaist]),
    );
    await assertDenied(
      asUser(db, central, `select * from public.apply_deposit_reparse($1, 'ignored')`, [depositId]),
    );
    await assertDenied(
      asAnon(db, `select * from public.apply_deposit_reparse($1, 'ignored')`, [depositId]),
    );
  });
});
