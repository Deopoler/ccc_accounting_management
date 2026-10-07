import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import { asAnon, asUser, createDb, createUser } from './helpers.mjs';

/** 권한 오류(42501)로 실패해야 한다. */
async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

/** 서버 함수의 raise exception(P0001)으로 실패해야 한다. */
async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

let db;
let admin;
let alice;
let bob;
let bookA;
let bookB;
let inactiveBook;

before(async () => {
  db = await createDb();
  admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
  alice = await createUser(db, { studentId: '20240001', name: '앨리스' });
  bob = await createUser(db, { studentId: '20240002', name: '밥' });

  const { rows } = await db.query(`
    insert into public.textbooks (campus_id, title, price, is_active)
    select (select id from public.campuses where code = 'kaist'), t, p, a from (values
      ('교재 A', 10000, true), ('교재 B', 7000, true), ('비활성 교재', 5000, false)) v (t, p, a)
    returning id`);
  [bookA, bookB, inactiveBook] = rows.map((r) => r.id);
});

describe('anon', () => {
  test('어떤 테이블도 조회할 수 없다', async () => {
    for (const t of ['profiles', 'textbooks', 'textbook_orders', 'events', 'event_payments', 'app_settings', 'campuses']) {
      await assertDenied(asAnon(db, `select * from public.${t}`));
    }
  });

  test('RPC 를 호출할 수 없다', async () => {
    await assertDenied(asAnon(db, `select public.place_textbook_order('[]'::jsonb)`));
  });
});

describe('profiles', () => {
  test('회원은 본인 프로필만 조회한다', async () => {
    const { rows } = await asUser(db, alice, 'select id from public.profiles');
    assert.deepEqual(rows.map((r) => r.id), [alice]);
  });

  test('관리자는 전체 프로필을 조회한다', async () => {
    const { rows } = await asUser(db, admin, 'select id from public.profiles');
    assert.equal(rows.length, 3);
  });

  test('회원은 본인 role / 플래그를 바꿀 수 없다', async () => {
    // 관리자 비밀번호 초기화 상황
    await db.query('update public.profiles set must_change_password = true where id = $1', [alice]);
    const r1 = await asUser(db, alice, `update public.profiles set role = 'campus_admin' where id = $1`, [alice]);
    assert.equal(r1.affectedRows, 0);
    const r2 = await asUser(db, alice, `update public.profiles set must_change_password = false where id = $1`, [alice]);
    assert.equal(r2.affectedRows, 0);
    const { rows } = await db.query('select role, must_change_password from public.profiles where id = $1', [alice]);
    assert.equal(rows[0].role, 'member');
    assert.equal(rows[0].must_change_password, true);
  });

  test('학번은 관리자도 변경할 수 없다', async () => {
    await assertDenied(asUser(db, admin, `update public.profiles set student_id = 'x9999' where id = $1`, [alice]));
  });

  test('프로필을 직접 만들 수 없다', async () => {
    await assertDenied(asUser(db, alice, `insert into public.profiles (id, student_id, name) values ($1, '1234', 'x')`, [bob]));
  });

  test('마지막 관리자는 강등할 수 없다', async () => {
    await assertRaises(
      asUser(db, admin, `update public.profiles set role = 'member' where id = $1`, [admin]),
      /마지막 관리자/,
    );
  });
});

describe('비밀번호 변경 플래그', () => {
  test('auth.users 비밀번호가 바뀌면 must_change_password 가 해제된다', async () => {
    const carol = await createUser(db, { studentId: '20240003' });
    // 관리자 비밀번호 초기화 상황
    await db.query('update public.profiles set must_change_password = true where id = $1', [carol]);
    await db.query(`update auth.users set raw_user_meta_data = '{"name":"x"}' where id = $1`, [carol]);
    let { rows } = await db.query('select must_change_password from public.profiles where id = $1', [carol]);
    assert.equal(rows[0].must_change_password, true, '비밀번호 외 변경은 플래그를 유지');

    await db.query(`update auth.users set encrypted_password = 'new-hash' where id = $1`, [carol]);
    ({ rows } = await db.query('select must_change_password from public.profiles where id = $1', [carol]));
    assert.equal(rows[0].must_change_password, false);
  });
});

describe('교재', () => {
  test('회원은 교재를 조회할 수 있지만 수정할 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select id from public.textbooks');
    assert.equal(rows.length, 3);
    const r = await asUser(db, alice, 'update public.textbooks set price = 0');
    assert.equal(r.affectedRows, 0);
    await assert.rejects(asUser(db, alice, `insert into public.textbooks (campus_id, title, price) values ((select id from public.campuses where code = 'kaist'), 'x', 1)`));
  });

  test('관리자는 교재를 추가/수정할 수 있다', async () => {
    const { rows } = await asUser(db, admin, `insert into public.textbooks (campus_id, title, price) values ((select id from public.campuses where code = 'kaist'), '임시', 1000) returning id`);
    const r = await asUser(db, admin, 'update public.textbooks set price = 2000 where id = $1', [rows[0].id]);
    assert.equal(r.affectedRows, 1);
    await asUser(db, admin, 'delete from public.textbooks where id = $1', [rows[0].id]);
  });
});

describe('교재 신청', () => {
  const items = (...pairs) => JSON.stringify(pairs.map(([textbook_id, quantity]) => ({ textbook_id, quantity })));

  test('회원은 주문 테이블에 직접 insert 할 수 없다', async () => {
    await assertDenied(
      asUser(db, alice, `insert into public.textbook_orders (user_id, round_start, total_price) values ($1, current_date, 0)`, [alice]),
    );
    await assertDenied(
      asUser(db, alice, `insert into public.textbook_order_items (order_id, textbook_id, quantity, unit_price) values (gen_random_uuid(), $1, 1, 0)`, [bookA]),
    );
  });

  test('RPC 신청: 가격은 서버가 교재 테이블에서 계산한다', async () => {
    const { rows } = await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [items([bookA, 2], [bookB, 1])]);
    const orderId = rows[0].id;
    const order = (await db.query('select * from public.textbook_orders where id = $1', [orderId])).rows[0];
    assert.equal(order.user_id, alice);
    assert.equal(order.status, 'requested');
    assert.equal(order.total_price, 27000);
    const { rows: round } = await asUser(db, alice, 'select id, round_start from public.get_order_round()');
    assert.equal(order.round_id, round[0].id);
    assert.equal(order.round_start.toISOString(), round[0].round_start.toISOString());
  });

  test('비활성 교재 / 잘못된 수량 / 중복 교재 / 빈 목록은 거부된다', async () => {
    await assertRaises(asUser(db, alice, 'select public.place_textbook_order($1::jsonb)', [items([inactiveBook, 1])]), /신청할 수 없는 교재/);
    await assertRaises(asUser(db, alice, 'select public.place_textbook_order($1::jsonb)', [items([bookA, 0])]), /수량/);
    await assertRaises(asUser(db, alice, 'select public.place_textbook_order($1::jsonb)', [items([bookA, 1], [bookA, 2])]), /올바르지 않습니다/);
    await assertRaises(asUser(db, alice, `select public.place_textbook_order('[]'::jsonb)`), /선택해 주세요/);
  });

  test('다른 회원의 주문/품목은 보이지 않는다', async () => {
    await asUser(db, bob, 'select public.place_textbook_order($1::jsonb)', [items([bookB, 1])]);
    const { rows } = await asUser(db, alice, 'select user_id from public.textbook_orders');
    assert.ok(rows.length > 0 && rows.every((r) => r.user_id === alice));
    const { rows: its } = await asUser(db, alice, `
      select o.user_id from public.textbook_order_items i
      join public.textbook_orders o on o.id = i.order_id`);
    assert.ok(its.every((r) => r.user_id === alice));
  });

  test('회원은 주문 상태/금액을 직접 바꿀 수 없다', async () => {
    const r = await asUser(db, alice, `update public.textbook_orders set status = 'paid' where user_id = $1`, [alice]);
    assert.equal(r.affectedRows, 0);
    await assertDenied(asUser(db, alice, 'update public.textbook_orders set total_price = 0'));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set total_price = 0'));
  });

  test('회원은 다른 회원의 주문을 수정/취소할 수 없다', async () => {
    const { rows } = await db.query('select id from public.textbook_orders where user_id = $1 limit 1', [bob]);
    await assertRaises(asUser(db, alice, 'select public.cancel_textbook_order($1)', [rows[0].id]), /찾을 수 없습니다/);
    await assertRaises(
      asUser(db, alice, 'select public.update_textbook_order($1, $2::jsonb)', [rows[0].id, items([bookA, 1])]),
      /찾을 수 없습니다/,
    );
  });

  test('회원은 본인 주문을 수정하면 합계가 다시 계산된다', async () => {
    const { rows } = await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [items([bookA, 1])]);
    await asUser(db, alice, 'select public.update_textbook_order($1, $2::jsonb)', [rows[0].id, items([bookB, 3])]);
    const order = (await db.query('select total_price from public.textbook_orders where id = $1', [rows[0].id])).rows[0];
    assert.equal(order.total_price, 21000);
  });

  test('입금확인된 주문은 회원이 취소할 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [items([bookA, 1])]);
    const r = await asUser(db, admin, `update public.textbook_orders set status = 'paid' where id = $1`, [rows[0].id]);
    assert.equal(r.affectedRows, 1);
    await assertRaises(asUser(db, alice, 'select public.cancel_textbook_order($1)', [rows[0].id]), /입금확인/);
  });

  test('마감된(이전) 회차 주문은 회원이 취소/수정할 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [items([bookA, 1])]);
    const { rows: past } = await db.query(`
      insert into public.order_rounds (campus_id, starts_at, deadline)
      select r.campus_id, r.starts_at - interval '7 days', r.starts_at
      from public.textbook_orders o join public.order_rounds r on r.id = o.round_id
      where o.id = $1
      returning id`, [rows[0].id]);
    await db.query('update public.textbook_orders set round_id = $2 where id = $1', [rows[0].id, past[0].id]);
    await assertRaises(asUser(db, alice, 'select public.cancel_textbook_order($1)', [rows[0].id]), /마감/);
  });

  test('회원은 이번 회차의 본인 주문을 취소할 수 있다', async () => {
    const { rows } = await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [items([bookA, 1])]);
    await asUser(db, alice, 'select public.cancel_textbook_order($1)', [rows[0].id]);
    const order = (await db.query('select status from public.textbook_orders where id = $1', [rows[0].id])).rows[0];
    assert.equal(order.status, 'cancelled');
  });
});

describe('신청 회차', () => {
  test('경계: 주간 규칙에서 수요일 09:00 KST 에 새 회차가 시작된다 (회차가 없는 캠퍼스의 첫 회차)', async () => {
    const cases = [
      ['2026-09-30 08:59:59+09', '2026-09-23'], // 수요일 마감 직전 → 이전 회차
      ['2026-09-30 09:00:00+09', '2026-09-30'], // 수요일 09:00 → 새 회차
      ['2026-10-06 23:59:59+09', '2026-09-30'], // 화요일 밤 → 아직 이번 회차
      ['2026-10-07 08:59:59+09', '2026-09-30'], // 다음 수요일 마감 직전
      ['2026-10-07 09:00:00+09', '2026-10-07'],
      ['2026-10-04 12:00:00+09', '2026-09-30'], // 일요일
    ];
    for (const [at, expected] of cases) {
      const { rows } = await db.query(`select to_char(private.order_round_for($1::timestamptz), 'YYYY-MM-DD') as r`, [at]);
      assert.equal(rows[0].r, expected, at);
    }
  });
});

describe('이벤트 송금', () => {
  let eventId;

  before(async () => {
    const { rows } = await asUser(db, admin, `
      insert into public.events (campus_id, title, amount, due_date) values ((select id from public.campuses where code = 'kaist'), '수련회', 50000, current_date + 30) returning id`);
    eventId = rows[0].id;
  });

  test('이벤트를 만들어도 송금 대상은 자동으로 등록되지 않는다', async () => {
    const { rows } = await db.query('select 1 from public.event_payments where event_id = $1', [eventId]);
    assert.equal(rows.length, 0);
  });

  test('관리자가 대상을 추가하면 미송금으로 등록된다', async () => {
    await asUser(db, admin, `
      insert into public.event_payments (event_id, user_id) values ($1, $2), ($1, $3)
      on conflict (event_id, user_id) do nothing`, [eventId, alice, bob]);
    const { rows } = await db.query('select user_id, is_paid from public.event_payments where event_id = $1', [eventId]);
    assert.deepEqual(new Set(rows.map((r) => r.user_id)), new Set([alice, bob]));
    assert.ok(rows.every((r) => r.is_paid === false));
  });

  test('새 회원은 기존 이벤트에 자동 등록되지 않는다', async () => {
    const dave = await createUser(db, { studentId: '20240004' });
    const { rows } = await db.query('select 1 from public.event_payments where user_id = $1', [dave]);
    assert.equal(rows.length, 0);
  });

  test('회원은 본인 송금 여부만 볼 수 있다', async () => {
    const { rows } = await asUser(db, alice, 'select user_id from public.event_payments');
    assert.ok(rows.length > 0 && rows.every((r) => r.user_id === alice));
  });

  test('회원은 본인 송금 여부를 바꿀 수 없다', async () => {
    const r = await asUser(db, alice, 'update public.event_payments set is_paid = true where user_id = $1', [alice]);
    assert.equal(r.affectedRows, 0);
    await assertDenied(asUser(db, alice, `insert into public.event_payments (event_id, user_id) values ($1, $2)`, [eventId, alice]));
  });

  test('관리자 송금 확인 시 확인자/시각이 서버에서 기록된다', async () => {
    await asUser(db, admin, 'update public.event_payments set is_paid = true where event_id = $1 and user_id = $2', [eventId, alice]);
    let { rows } = await db.query('select * from public.event_payments where event_id = $1 and user_id = $2', [eventId, alice]);
    assert.equal(rows[0].is_paid, true);
    assert.equal(rows[0].confirmed_by, admin);
    assert.ok(rows[0].paid_at instanceof Date);

    await asUser(db, admin, 'update public.event_payments set is_paid = false where event_id = $1 and user_id = $2', [eventId, alice]);
    ({ rows } = await db.query('select * from public.event_payments where event_id = $1 and user_id = $2', [eventId, alice]));
    assert.equal(rows[0].confirmed_by, null);
    assert.equal(rows[0].paid_at, null);
  });

  test('확인자/시각은 관리자도 직접 조작할 수 없다', async () => {
    await assertDenied(asUser(db, admin, 'update public.event_payments set confirmed_by = $1', [bob]));
    await assertDenied(asUser(db, admin, 'update public.event_payments set paid_at = now()'));
  });

  test('송금 요약 뷰는 조회자의 RLS 를 따른다', async () => {
    await asUser(db, admin, 'update public.event_payments set is_paid = true where event_id = $1 and user_id = $2', [eventId, bob]);
    const { rows: adminView } = await asUser(db, admin, 'select * from public.event_payment_summaries where event_id = $1', [eventId]);
    assert.equal(adminView[0].target_count, 2);
    assert.equal(adminView[0].paid_count, 1);
    assert.equal(Number(adminView[0].collected_amount), 50000);

    const { rows: aliceView } = await asUser(db, alice, 'select * from public.event_payment_summaries where event_id = $1', [eventId]);
    assert.equal(aliceView[0].target_count, 1, '회원에게는 본인 행만 집계된다');
    assert.equal(aliceView[0].paid_count, 0);
  });
});

describe('app_settings', () => {
  test('회원은 계좌 정보를 조회만 할 수 있다', async () => {
    const { rows } = await asUser(db, alice, 'select key from public.app_settings order by key');
    assert.deepEqual(rows.map((r) => r.key), ['account_holder', 'account_number', 'bank_name']);
    const r = await asUser(db, alice, `update public.app_settings set value = 'hacked' where key = 'account_number'`);
    assert.equal(r.affectedRows, 0);
  });

  test('계좌는 캠퍼스로 옮겨졌다: 이전 설정은 총괄 관리자만 수정한다', async () => {
    const r = await asUser(db, admin, `update public.app_settings set value = '123-456' where key = 'account_number'`);
    assert.equal(r.affectedRows, 0);
    const c = await asUser(db, admin, `update public.campuses set account_number = '123-456' where code = 'kaist'`);
    assert.equal(c.affectedRows, 1);
  });
});

describe('내부 함수', () => {
  test('private 스키마 내부 함수는 호출할 수 없다', async () => {
    await assertDenied(asUser(db, alice, `select private.replace_order_items(gen_random_uuid(), '[]'::jsonb)`));
    await assertDenied(asUser(db, alice, `select private.lock_own_editable_order(gen_random_uuid())`));
  });
});

describe('이벤트 개인별 금액', () => {
  let ev;

  before(async () => {
    ev = (await asUser(db, admin, `insert into public.events (campus_id, title, amount) values ((select id from public.campuses where code = 'kaist'), 'MT', 30000) returning id`)).rows[0].id;
    await asUser(db, admin, `insert into public.event_payments (event_id, user_id) values ($1, $2), ($1, $3)`, [ev, alice, bob]);
  });

  test('관리자는 일부 회원의 금액을 바꿀 수 있고, 요약은 개인 금액 기준이다', async () => {
    const r = await asUser(db, admin,
      'update public.event_payments set amount_override = 10000 where event_id = $1 and user_id = $2', [ev, alice]);
    assert.equal(r.affectedRows, 1);
    await asUser(db, admin, 'update public.event_payments set is_paid = true where event_id = $1', [ev]);

    const { rows } = await asUser(db, admin, 'select * from public.event_payment_summaries where event_id = $1', [ev]);
    assert.equal(Number(rows[0].expected_amount), 40000);
    assert.equal(Number(rows[0].collected_amount), 40000);
  });

  test('회원은 본인 금액을 볼 수 있지만 바꿀 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select amount_override from public.event_payments where event_id = $1', [ev]);
    assert.equal(rows[0].amount_override, 10000);
    const r = await asUser(db, alice,
      'update public.event_payments set amount_override = 0 where event_id = $1 and user_id = $2', [ev, alice]);
    assert.equal(r.affectedRows, 0);
  });

  test('음수 금액은 거부된다', async () => {
    await assert.rejects(asUser(db, admin,
      'update public.event_payments set amount_override = -1 where event_id = $1', [ev]));
  });

  test('기본 금액으로 되돌리면(null) 이벤트 금액이 적용된다', async () => {
    await asUser(db, admin, 'update public.event_payments set amount_override = null where event_id = $1', [ev]);
    const { rows } = await asUser(db, admin, 'select expected_amount from public.event_payment_summaries where event_id = $1', [ev]);
    assert.equal(Number(rows[0].expected_amount), 60000);
  });
});

describe('이벤트 입금자명', () => {
  test('관리자는 입금자명 형식을 지정할 수 있다', async () => {
    const { rows } = await asUser(db, admin,
      `insert into public.events (campus_id, title, amount, deposit_name) values ((select id from public.campuses where code = 'kaist'), 'MT2', 1000, '{이름}MT') returning deposit_name`);
    assert.equal(rows[0].deposit_name, '{이름}MT');
  });

  test('회원은 입금자명을 볼 수 있지만 바꿀 수 없다', async () => {
    const { rows } = await asUser(db, alice, `select deposit_name from public.events where title = 'MT2'`);
    assert.equal(rows[0].deposit_name, '{이름}MT');
    const r = await asUser(db, alice, `update public.events set deposit_name = 'x' where title = 'MT2'`);
    assert.equal(r.affectedRows, 0);
  });

  test('너무 긴 입금자명은 거부된다', async () => {
    await assert.rejects(asUser(db, admin,
      `update public.events set deposit_name = repeat('가', 51) where title = 'MT2'`));
  });
});

describe('교재 카테고리', () => {
  let categoryId;

  test('관리자는 카테고리를 만들고 교재를 넣을 수 있다', async () => {
    categoryId = (await asUser(db, admin,
      `insert into public.textbook_categories (campus_id, name, sort_order) values ((select id from public.campuses where code = 'kaist'), '성경공부', 1) returning id`)).rows[0].id;
    const r = await asUser(db, admin,
      `update public.textbooks set category_id = $1 where title = '교재 A'`, [categoryId]);
    assert.equal(r.affectedRows, 1);
  });

  test('회원은 카테고리를 볼 수 있지만 만들거나 바꿀 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select name from public.textbook_categories');
    assert.deepEqual(rows.map((r) => r.name), ['성경공부']);
    await assert.rejects(asUser(db, alice, `insert into public.textbook_categories (campus_id, name) values ((select id from public.campuses where code = 'kaist'), 'x')`));
    const r = await asUser(db, alice, `update public.textbook_categories set name = 'x'`);
    assert.equal(r.affectedRows, 0);
    const r2 = await asUser(db, alice, `update public.textbooks set category_id = null`);
    assert.equal(r2.affectedRows, 0);
  });

  test('승인 대기 사용자는 카테고리를 볼 수 없다', async () => {
    const waiting = await createUser(db, { studentId: '20248888', approved: false });
    const { rows } = await asUser(db, waiting, 'select * from public.textbook_categories');
    assert.equal(rows.length, 0);
  });

  test('교재가 있는 카테고리는 삭제할 수 없다', async () => {
    await assert.rejects(
      asUser(db, admin, 'delete from public.textbook_categories where id = $1', [categoryId]),
      (e) => e.code === '23503',
    );
  });

  test('이름이 비었거나 중복이면 거부된다', async () => {
    await assert.rejects(asUser(db, admin, `insert into public.textbook_categories (campus_id, name) values ((select id from public.campuses where code = 'kaist'), '  ')`));
    await assert.rejects(asUser(db, admin, `insert into public.textbook_categories (campus_id, name) values ((select id from public.campuses where code = 'kaist'), '성경공부')`));
  });
});

describe('교재 순서', () => {
  test('관리자는 교재 순서를 바꿀 수 있고 회원은 못 바꾼다', async () => {
    const r = await asUser(db, admin, `update public.textbooks set sort_order = 99 where title = '교재 B'`);
    assert.equal(r.affectedRows, 1);
    const r2 = await asUser(db, alice, `update public.textbooks set sort_order = 0`);
    assert.equal(r2.affectedRows, 0);
    const { rows } = await asUser(db, alice, `select sort_order from public.textbooks where title = '교재 B'`);
    assert.equal(rows[0].sort_order, 99);
  });
});

describe('교재 배송 / 수령', () => {
  const one = (bookId) => JSON.stringify([{ textbook_id: bookId, quantity: 1 }]);
  const order = async (id) =>
    (await db.query('select * from public.textbook_orders where id = $1', [id])).rows[0];
  let orderId;

  before(async () => {
    orderId = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [one(bookA)])).rows[0].id;
  });

  test('배송 전에는 회원이 수령 확인할 수 없다', async () => {
    await assertRaises(asUser(db, alice, 'select public.confirm_textbook_received($1)', [orderId]), /아직 배송되지/);
  });

  test('회원은 배송 여부 / 시각을 직접 바꿀 수 없다', async () => {
    const r = await asUser(db, alice, 'update public.textbook_orders set is_shipped = true where id = $1', [orderId]);
    assert.equal(r.affectedRows, 0);
    await assertDenied(asUser(db, alice, 'update public.textbook_orders set received_at = now()'));
  });

  test('관리자 배송 처리 시 처리자/시각이 서버에서 기록된다', async () => {
    const r = await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [orderId]);
    assert.equal(r.affectedRows, 1);
    const o = await order(orderId);
    assert.equal(o.shipped_by, admin);
    assert.ok(o.shipped_at instanceof Date);
    assert.equal(o.received_at, null);
  });

  test('배송 시각/수령 시각은 관리자도 직접 조작할 수 없다', async () => {
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set shipped_at = now()'));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set shipped_by = $1', [admin]));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set received_at = now()'));
  });

  test('배송된 신청은 회원이 수정/취소할 수 없다', async () => {
    await assertRaises(asUser(db, alice, 'select public.cancel_textbook_order($1)', [orderId]), /배송된 신청/);
  });

  test('다른 회원은 수령 확인할 수 없다', async () => {
    await assertRaises(asUser(db, bob, 'select public.confirm_textbook_received($1)', [orderId]), /찾을 수 없습니다/);
    await assertRaises(asUser(db, admin, 'select public.confirm_textbook_received($1)', [orderId]), /찾을 수 없습니다/);
    assert.equal((await order(orderId)).received_at, null);
  });

  test('본인은 배송된 신청의 수령을 확인할 수 있고, 다시 확인해도 시각이 바뀌지 않는다', async () => {
    const first = (await asUser(db, alice, 'select public.confirm_textbook_received($1) as t', [orderId])).rows[0].t;
    assert.ok(first instanceof Date);
    const again = (await asUser(db, alice, 'select public.confirm_textbook_received($1) as t', [orderId])).rows[0].t;
    assert.equal(again.getTime(), first.getTime());
    const o = await order(orderId);
    assert.equal(o.received_at.getTime(), first.getTime());
    assert.equal(o.received_by, alice);
  });

  test('관리자가 다른 컬럼을 바꿔도 배송/수령 기록은 유지된다', async () => {
    const before = await order(orderId);
    await asUser(db, admin, `update public.textbook_orders set status = 'paid' where id = $1`, [orderId]);
    const after = await order(orderId);
    assert.equal(after.shipped_at.getTime(), before.shipped_at.getTime());
    assert.equal(after.received_at.getTime(), before.received_at.getTime());
  });

  test('배송된 신청은 취소 상태로 바꿀 수 없다', async () => {
    await assertRaises(
      asUser(db, admin, `update public.textbook_orders set status = 'cancelled' where id = $1`, [orderId]),
      /취소된 신청은 배송/,
    );
  });

  test('배송을 해제하면 배송/수령 기록이 함께 초기화된다', async () => {
    await asUser(db, admin, 'update public.textbook_orders set is_shipped = false where id = $1', [orderId]);
    const o = await order(orderId);
    assert.equal(o.is_shipped, false);
    assert.equal(o.shipped_at, null);
    assert.equal(o.shipped_by, null);
    assert.equal(o.received_at, null);
    assert.equal(o.received_by, null);
  });

  test('취소된 신청은 배송 처리할 수 없다', async () => {
    const id = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [one(bookA)])).rows[0].id;
    await asUser(db, alice, 'select public.cancel_textbook_order($1)', [id]);
    await assertRaises(
      asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [id]),
      /취소된 신청은 배송/,
    );
  });
});

describe('관리자 수령 처리', () => {
  const one = (bookId) => JSON.stringify([{ textbook_id: bookId, quantity: 1 }]);
  const order = async (id) =>
    (await db.query('select * from public.textbook_orders where id = $1', [id])).rows[0];
  const setReceived = (userId, id, received) =>
    asUser(db, userId, 'select public.admin_set_textbook_received($1, $2) as t', [id, received]);
  let orderId;

  before(async () => {
    orderId = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [one(bookA)])).rows[0].id;
  });

  test('배송 전에는 관리자도 수령 처리할 수 없다', async () => {
    await assertRaises(setReceived(admin, orderId, true), /배송되지 않은/);
  });

  test('회원은 관리자 수령 처리를 호출할 수 없다', async () => {
    await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [orderId]);
    await assertRaises(setReceived(alice, orderId, true), /관리자만/);
    assert.equal((await order(orderId)).received_at, null);
  });

  test('관리자가 수령 처리하면 시각과 확인자(관리자)가 기록된다', async () => {
    const t = (await setReceived(admin, orderId, true)).rows[0].t;
    assert.ok(t instanceof Date);
    const o = await order(orderId);
    assert.equal(o.received_at.getTime(), t.getTime());
    assert.equal(o.received_by, admin);

    // 이미 수령된 건은 다시 체크해도 기록이 바뀌지 않는다.
    const again = (await setReceived(admin, orderId, true)).rows[0].t;
    assert.equal(again.getTime(), t.getTime());
  });

  test('관리자가 수령 처리한 건은 회원이 확인해도 기록이 바뀌지 않는다', async () => {
    await asUser(db, alice, 'select public.confirm_textbook_received($1)', [orderId]);
    assert.equal((await order(orderId)).received_by, admin);
  });

  test('관리자는 수령을 해제할 수 있다 (회원 확인 건 포함)', async () => {
    const r = (await setReceived(admin, orderId, false)).rows[0].t;
    assert.equal(r, null);
    let o = await order(orderId);
    assert.equal(o.received_at, null);
    assert.equal(o.received_by, null);
    assert.equal(o.is_shipped, true);

    await asUser(db, alice, 'select public.confirm_textbook_received($1)', [orderId]);
    await setReceived(admin, orderId, false);
    o = await order(orderId);
    assert.equal(o.received_at, null);
  });

  test('취소된 신청은 수령 처리할 수 없다', async () => {
    const id = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [one(bookA)])).rows[0].id;
    await asUser(db, alice, 'select public.cancel_textbook_order($1)', [id]);
    await assertRaises(setReceived(admin, id, true), /취소된 신청/);
  });

  test('확인자는 관리자도 직접 조작할 수 없다', async () => {
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set received_by = $1', [admin]));
  });
});
