// 웹 푸시: 구독 저장 권한과 가입 / 교재 도착 트리거의 알림 요청.
import assert from 'node:assert/strict';
import { before, beforeEach, describe, test } from 'node:test';

import { asAnon, asUser, createDb, createUser, signUp } from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

const save = (db, userId, endpoint, p256dh = 'key', auth = 'auth') =>
  asUser(db, userId, 'select public.save_push_subscription($1, $2, $3)', [endpoint, p256dh, auth]);

let db;
let admin;
let admin2;
let member;
let member2;
let pending;
let bookId;

before(async () => {
  db = await createDb();
  admin = await createUser(db, { studentId: '20200001', role: 'campus_admin' });
  admin2 = await createUser(db, { studentId: '20200002', role: 'campus_admin' });
  member = await createUser(db, { studentId: '20240001', name: '회원1' });
  member2 = await createUser(db, { studentId: '20240002', name: '회원2' });
  pending = await createUser(db, { studentId: '20249999', approved: false });
  bookId = (
    await db.query(
      `insert into public.textbooks (campus_id, title, price)
       values ((select id from public.campuses where code = 'kaist'), '귀납적 성경연구', 10000)
       returning id`,
    )
  ).rows[0].id;
});

describe('푸시 구독 저장', () => {
  test('승인된 회원과 관리자는 구독을 저장하고 본인 구독만 본다', async () => {
    await save(db, admin, 'https://push.example.com/a1');
    await save(db, member, 'https://push.example.com/m1');

    const { rows: adminRows } = await asUser(db, admin, 'select endpoint, user_id from public.push_subscriptions');
    assert.deepEqual(adminRows, [{ endpoint: 'https://push.example.com/a1', user_id: admin }]);

    const { rows: memberRows } = await asUser(db, member, 'select endpoint, user_id from public.push_subscriptions');
    assert.deepEqual(memberRows, [{ endpoint: 'https://push.example.com/m1', user_id: member }]);

    assert.equal((await asUser(db, admin2, 'select * from public.push_subscriptions')).rows.length, 0);
  });

  test('승인 대기 / anon 은 저장할 수 없다', async () => {
    await assertRaises(save(db, pending, 'https://push.example.com/p'), /승인된 회원만/);
    await assertDenied(asAnon(db, `select public.save_push_subscription('https://x', 'k', 'a')`));
  });

  test('테이블에 직접 넣거나 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, admin, `
      insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
      values ($1, 'https://push.example.com/x', 'k', 'a')`, [admin]));
    await assertDenied(asUser(db, admin, `update public.push_subscriptions set user_id = $1`, [admin2]));
  });

  test('같은 기기에서 다른 승인된 계정으로 켜면 구독이 그 계정으로 옮겨 간다', async () => {
    await save(db, admin, 'https://push.example.com/shared', 'k1');
    await save(db, member, 'https://push.example.com/shared', 'k2');
    const { rows } = await db.query(
      `select user_id, p256dh from public.push_subscriptions where endpoint = 'https://push.example.com/shared'`,
    );
    assert.deepEqual(rows, [{ user_id: member, p256dh: 'k2' }]);
  });

  test('본인 구독만 해제할 수 있다', async () => {
    await save(db, admin, 'https://push.example.com/a2');
    const other = await asUser(db, admin2, `delete from public.push_subscriptions where endpoint = 'https://push.example.com/a2'`);
    assert.equal(other.affectedRows, 0);
    const own = await asUser(db, admin, `delete from public.push_subscriptions where endpoint = 'https://push.example.com/a2'`);
    assert.equal(own.affectedRows, 1);
  });

  test('https 가 아닌 주소는 저장할 수 없다', async () => {
    await assert.rejects(save(db, admin, 'http://push.example.com/insecure'));
  });
});

describe('가입 알림 트리거', () => {
  beforeEach(async () => {
    await db.query('delete from net.requests');
    await db.query('delete from vault.decrypted_secrets');
  });

  const configure = () => db.query(`
    insert into vault.decrypted_secrets (name, decrypted_secret) values
      ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
      ('push_webhook_secret', 's3cret')`);

  test('가입하면 함수 주소로 가입자 id 와 secret 을 보낸다', async () => {
    await configure();
    const id = await signUp(db, { email: '20241001@ccc.local', name: '새회원' });
    const { rows } = await db.query('select url, body, headers from net.requests');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].url, 'https://ref.supabase.co/functions/v1/push');
    assert.deepEqual(rows[0].body, { type: 'signup', profile_id: id });
    assert.equal(rows[0].headers['x-push-secret'], 's3cret');
  });

  test('Vault 설정이 없으면 보내지 않고 가입은 된다', async () => {
    const id = await signUp(db, { email: '20241002@ccc.local', name: '새회원' });
    assert.equal((await db.query('select 1 from public.profiles where id = $1', [id])).rows.length, 1);
    assert.equal((await db.query('select * from net.requests')).rows.length, 0);
  });

  test('알림 요청이 실패해도 가입은 된다', async () => {
    await configure();
    await db.query('alter table net.requests add constraint fail_all check (false)');
    try {
      const id = await signUp(db, { email: '20241003@ccc.local', name: '새회원' });
      assert.equal((await db.query('select 1 from public.profiles where id = $1', [id])).rows.length, 1);
    } finally {
      await db.query('alter table net.requests drop constraint fail_all');
    }
  });

  test('가입할 때 한 번만 알리고, 승인은 알리지 않는다', async () => {
    await configure();
    const { rows: u } = await db.query(
      `insert into auth.users (email) values ('20241004@ccc.local') returning id`,
    );
    await db.query('update public.profiles set is_approved = true where id = $1', [u[0].id]);
    assert.equal((await db.query('select * from net.requests')).rows.length, 1);
  });
});

describe('교재 도착(배송) 알림 트리거', () => {
  beforeEach(async () => {
    await db.query('delete from net.requests');
    await db.query('delete from vault.decrypted_secrets');
  });

  const configure = () => db.query(`
    insert into vault.decrypted_secrets (name, decrypted_secret) values
      ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
      ('push_webhook_secret', 's3cret')`);

  const placeOrder = async (userId) => {
    const items = JSON.stringify([{ textbook_id: bookId, quantity: 1 }]);
    const { rows } = await asUser(db, userId, 'select public.place_textbook_order($1::jsonb) as id', [items]);
    return rows[0].id;
  };

  test('배송 체크(false → true)하면 주문자 id 와 신청 id 목록을 보낸다', async () => {
    await configure();
    const orderId = await placeOrder(member);

    await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [orderId]);

    const { rows } = await db.query('select url, body, headers from net.requests');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].url, 'https://ref.supabase.co/functions/v1/push');
    assert.deepEqual(rows[0].body, {
      type: 'order_shipped',
      user_id: member,
      order_ids: [orderId],
    });
    assert.equal(rows[0].headers['x-push-secret'], 's3cret');
  });

  test('한 회원의 여러 신청을 한꺼번에 배송 체크해도 알림 요청은 한 번만 보낸다', async () => {
    await configure();
    const o1 = await placeOrder(member);
    const o2 = await placeOrder(member);
    const o3 = await placeOrder(member2);

    await asUser(
      db,
      admin,
      'update public.textbook_orders set is_shipped = true where id = any($1::uuid[])',
      [[o1, o2, o3]],
    );

    const { rows } = await db.query('select body from net.requests order by id');
    assert.equal(rows.length, 2);
    const byUser = new Map(rows.map((r) => [r.body.user_id, r.body.order_ids]));
    assert.deepEqual(byUser.get(member).sort(), [o1, o2].sort());
    assert.deepEqual(byUser.get(member2), [o3]);
  });

  test('입금확인 변경, 이미 배송된 건 수정, 수령 확인, 배송 해제는 알리지 않는다', async () => {
    await configure();
    const orderId = await placeOrder(member);

    // 배송 전 입금확인
    await asUser(db, admin, `update public.textbook_orders set status = 'paid' where id = $1`, [orderId]);
    assert.equal((await db.query('select * from net.requests')).rows.length, 0);

    // 배송 체크 → 1건
    await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [orderId]);
    assert.equal((await db.query('select * from net.requests')).rows.length, 1);

    // 이미 배송된 건 수령 확인 / 배송 해제 → 추가 요청 없음
    await asUser(db, member, 'select public.confirm_textbook_received($1)', [orderId]);
    await asUser(db, admin, 'update public.textbook_orders set is_shipped = false where id = $1', [orderId]);
    assert.equal((await db.query('select * from net.requests')).rows.length, 1);
  });

  test('Vault 설정이 없거나 알림 요청이 실패해도 배송 처리는 된다', async () => {
    const o1 = await placeOrder(member);
    await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [o1]);
    assert.equal(
      (await db.query('select is_shipped from public.textbook_orders where id = $1', [o1])).rows[0].is_shipped,
      true,
    );
    assert.equal((await db.query('select * from net.requests')).rows.length, 0);

    await configure();
    const o2 = await placeOrder(member);
    await db.query('alter table net.requests add constraint fail_all check (false)');
    try {
      await asUser(db, admin, 'update public.textbook_orders set is_shipped = true where id = $1', [o2]);
      assert.equal(
        (await db.query('select is_shipped from public.textbook_orders where id = $1', [o2])).rows[0].is_shipped,
        true,
      );
    } finally {
      await db.query('alter table net.requests drop constraint fail_all');
    }
  });
});
