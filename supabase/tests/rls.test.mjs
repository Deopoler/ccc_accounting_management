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
  admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'admin' });
  alice = await createUser(db, { studentId: '20240001', name: '앨리스' });
  bob = await createUser(db, { studentId: '20240002', name: '밥' });

  const { rows } = await db.query(`
    insert into public.textbooks (title, price, is_active) values
      ('교재 A', 10000, true), ('교재 B', 7000, true), ('비활성 교재', 5000, false)
    returning id`);
  [bookA, bookB, inactiveBook] = rows.map((r) => r.id);
});

describe('anon', () => {
  test('어떤 테이블도 조회할 수 없다', async () => {
    for (const t of ['profiles', 'textbooks', 'textbook_orders', 'events', 'event_payments', 'app_settings']) {
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
    const r1 = await asUser(db, alice, `update public.profiles set role = 'admin' where id = $1`, [alice]);
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
    await assert.rejects(asUser(db, alice, `insert into public.textbooks (title, price) values ('x', 1)`));
  });

  test('관리자는 교재를 추가/수정할 수 있다', async () => {
    const { rows } = await asUser(db, admin, `insert into public.textbooks (title, price) values ('임시', 1000) returning id`);
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
    const { rows: round } = await db.query('select public.current_order_round() as r');
    assert.equal(order.round_start.toISOString(), round[0].r.toISOString());
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
    await db.query(`update public.textbook_orders set round_start = round_start - 7 where id = $1`, [rows[0].id]);
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
  test('회차 시작일은 수요일, 마감은 7일 뒤 00:00 KST(= 15:00 UTC 전날)', async () => {
    const { rows } = await asUser(db, alice, `
      select round_start, deadline,
             extract(isodow from round_start)::int as dow,
             to_char(deadline at time zone 'UTC', 'HH24:MI') as utc_time,
             deadline > now() and deadline <= now() + interval '7 days' as in_range
      from public.get_order_round()`);
    assert.equal(rows[0].dow, 3);
    assert.equal(rows[0].utc_time, '15:00');
    assert.equal(rows[0].in_range, true);
  });
});

describe('이벤트 송금', () => {
  let eventId;

  before(async () => {
    const { rows } = await asUser(db, admin, `
      insert into public.events (title, amount, due_date) values ('수련회', 50000, current_date + 30) returning id`);
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

  test('관리자는 계좌 정보를 수정할 수 있다', async () => {
    const r = await asUser(db, admin, `update public.app_settings set value = '123-456' where key = 'account_number'`);
    assert.equal(r.affectedRows, 1);
  });
});

describe('내부 함수', () => {
  test('private 스키마 함수는 is_admin 외에 호출할 수 없다', async () => {
    await assertDenied(asUser(db, alice, `select private.replace_order_items(gen_random_uuid(), '[]'::jsonb)`));
    await assertDenied(asUser(db, alice, `select private.lock_own_editable_order(gen_random_uuid())`));
  });
});

describe('이벤트 개인별 금액', () => {
  let ev;

  before(async () => {
    ev = (await asUser(db, admin, `insert into public.events (title, amount) values ('MT', 30000) returning id`)).rows[0].id;
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
      `insert into public.events (title, amount, deposit_name) values ('MT2', 1000, '{이름}MT') returning deposit_name`);
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
