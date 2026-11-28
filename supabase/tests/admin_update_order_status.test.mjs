// 관리자 일괄 상태 변경 RPC(admin_update_order_status):
// 원자적 롤백(입금 연결 유지), 중복 id 정리, RLS/캠퍼스 격리, 입력 검증.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';

import { asAnon, asUser, campusId, createCampus, createDb, createUser } from './helpers.mjs';

const sha256 = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

async function assertConflict(promise) {
  await assert.rejects(
    promise,
    (e) => e.code === 'P0009' && /변경됨, 다시 확인/.test(e.message),
  );
}

describe('admin_update_order_status', () => {
  let db;
  let kaist;
  let snu;
  let kAdmin;
  let sAdmin;
  let central;
  let hong;
  let kim;
  let snuMember;
  let kBook;
  let sBook;

  const placeOrder = async (userId, textbookId) => {
    const { rows } = await asUser(
      db,
      userId,
      'select public.place_textbook_order($1::jsonb) as id',
      [JSON.stringify([{ textbook_id: textbookId, quantity: 1 }])],
    );
    return rows[0].id;
  };

  beforeEach(async () => {
    db = await createDb();
    kaist = await campusId(db, 'kaist');
    snu = await createCampus(db, { code: 'snu', name: '서울대' });

    central = await createUser(db, { studentId: '20250133', name: '총괄', role: 'central_admin' });
    kAdmin = await createUser(db, { studentId: '20200001', name: 'KAIST관리자', role: 'campus_admin' });
    sAdmin = await createUser(db, { studentId: '20200002', name: '서울대관리자', role: 'campus_admin', campus: 'snu' });
    hong = await createUser(db, { studentId: '20240001', name: '홍길동' });
    kim = await createUser(db, { studentId: '20240002', name: '김철수' });
    snuMember = await createUser(db, { studentId: '20240003', name: '이영희', campus: 'snu' });

    await asUser(
      db,
      kAdmin,
      `select public.admin_update_deposit_settings($1, true, 'toss', 'KAIST CCC')`,
      [kaist],
    );

    kBook = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재A', 10000) returning id`,
      [kaist],
    )).rows[0].id;
    sBook = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '서울대교재', 10000) returning id`,
      [snu],
    )).rows[0].id;
  });

  test('충돌 행이 하나라도 있으면 전체가 롤백되고 자동 확인된 입금 연결도 그대로 유지된다', async () => {
    const o1 = await placeOrder(hong, kBook);
    const o2 = await placeOrder(kim, kBook);

    // o1 을 자동 입금 매칭해 paid + confirmed_deposit_id 연결 상태로 만든다.
    const { rows: [ingested] } = await db.query(
      `select status, deposit_id from public.ingest_bank_deposit(
         $1, 'deposit', 'toss', $2, $3,
         now(), '홍길동', 10000, '입금', 'KAIST CCC 홍길동 10,000원', 'viva.republica.toss', null
       )`,
      [kaist, sha256('dk-o1'), sha256('rh-o1')],
    );
    assert.equal(ingested.status, 'auto_matched');
    const depositId = ingested.deposit_id;

    // o1 은 paid, o2 는 requested 인 상태에서 둘 다 paid -> requested 로 일괄 변경 시도.
    await assertConflict(
      asUser(
        db,
        kAdmin,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[o1, o2], ['paid'], 'requested'],
      ),
    );

    // o1 도 롤백되어 paid + 입금 연결 유지, bank_deposits 도 auto_matched 유지.
    const { rows: orders } = await db.query(
      'select id, status::text as status, confirmed_deposit_id from public.textbook_orders where id = any($1::uuid[]) order by id',
      [[o1, o2]],
    );
    const byId = Object.fromEntries(orders.map((r) => [r.id, r]));
    assert.equal(byId[o1].status, 'paid');
    assert.equal(byId[o1].confirmed_deposit_id, depositId);
    assert.equal(byId[o2].status, 'requested');

    const { rows: [dep] } = await db.query(
      'select status::text as status from public.bank_deposits where id = $1',
      [depositId],
    );
    assert.equal(dep.status, 'auto_matched');
  });

  test('중복 id 를 제거하고 모든 행이 기대 상태와 일치하면 일괄 변경한다', async () => {
    const o1 = await placeOrder(hong, kBook);
    const o2 = await placeOrder(kim, kBook);

    const { rows: [res] } = await asUser(
      db,
      kAdmin,
      `select public.admin_update_order_status($1::uuid[], $2::text[], $3) as updated`,
      [[o1, o1, o2], ['requested'], 'paid'],
    );
    assert.equal(res.updated, 2);

    const { rows: orders } = await db.query(
      'select status::text as status from public.textbook_orders where id = any($1::uuid[])',
      [[o1, o2]],
    );
    assert.deepEqual(orders.map((r) => r.status), ['paid', 'paid']);
  });

  test('security invoker: 일반 회원, 타 캠퍼스 관리자, anon 은 변경할 수 없고 혼합 요청도 롤백된다', async () => {
    const kOrder = await placeOrder(hong, kBook);
    const sOrder = await placeOrder(snuMember, sBook);

    await assertDenied(
      asAnon(
        db,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[kOrder], ['requested'], 'paid'],
      ),
    );
    await assertConflict(
      asUser(
        db,
        hong,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[kOrder], ['requested'], 'paid'],
      ),
    );
    // 서울대 관리자가 자기 캠퍼스 주문 + KAIST 주문을 섞어 요청해도 둘 다 롤백된다.
    await assertConflict(
      asUser(
        db,
        sAdmin,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[sOrder, kOrder], ['requested'], 'paid'],
      ),
    );

    const { rows: afterMixed } = await db.query(
      'select status::text as status from public.textbook_orders where id = any($1::uuid[])',
      [[kOrder, sOrder]],
    );
    assert.deepEqual(afterMixed.map((r) => r.status), ['requested', 'requested']);

    // 총괄 관리자는 여러 캠퍼스 주문을 함께 처리할 수 있다.
    const { rows: [centralRes] } = await asUser(
      db,
      central,
      `select public.admin_update_order_status($1::uuid[], $2::text[], $3) as updated`,
      [[kOrder, sOrder], ['requested'], 'paid'],
    );
    assert.equal(centralRes.updated, 2);
  });

  test('빈 id 목록이나 잘못된 상태 문자열은 거부한다', async () => {
    const o1 = await placeOrder(hong, kBook);
    await assert.rejects(
      asUser(
        db,
        kAdmin,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[], ['requested'], 'paid'],
      ),
      (e) => e.code === 'P0001',
    );
    await assert.rejects(
      asUser(
        db,
        kAdmin,
        `select public.admin_update_order_status($1::uuid[], $2::text[], $3)`,
        [[o1], ['requested'], 'invalid_status'],
      ),
      (e) => e.code === 'P0001',
    );
  });
});
