// 가입 신청 웹 푸시: 구독 저장 권한과 가입 트리거의 알림 요청.
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
let pending;

before(async () => {
  db = await createDb();
  admin = await createUser(db, { studentId: '20200001', role: 'campus_admin' });
  admin2 = await createUser(db, { studentId: '20200002', role: 'campus_admin' });
  member = await createUser(db, { studentId: '20240001' });
  pending = await createUser(db, { studentId: '20249999', approved: false });
});

describe('푸시 구독 저장', () => {
  test('관리자는 구독을 저장하고 본인 구독만 본다', async () => {
    await save(db, admin, 'https://push.example.com/a1');
    const { rows } = await asUser(db, admin, 'select endpoint, user_id from public.push_subscriptions');
    assert.deepEqual(rows, [{ endpoint: 'https://push.example.com/a1', user_id: admin }]);
    assert.equal((await asUser(db, admin2, 'select * from public.push_subscriptions')).rows.length, 0);
  });

  test('회원 / 승인 대기 / anon 은 저장할 수 없다', async () => {
    await assertRaises(save(db, member, 'https://push.example.com/m'), /관리자만/);
    await assertRaises(save(db, pending, 'https://push.example.com/p'), /관리자만/);
    await assertDenied(asAnon(db, `select public.save_push_subscription('https://x', 'k', 'a')`));
  });

  test('테이블에 직접 넣거나 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, admin, `
      insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
      values ($1, 'https://push.example.com/x', 'k', 'a')`, [admin]));
    await assertDenied(asUser(db, admin, `update public.push_subscriptions set user_id = $1`, [admin2]));
  });

  test('같은 기기에서 다른 관리자가 켜면 구독이 그 관리자에게 옮겨 간다', async () => {
    await save(db, admin, 'https://push.example.com/shared', 'k1');
    await save(db, admin2, 'https://push.example.com/shared', 'k2');
    const { rows } = await db.query(
      `select user_id, p256dh from public.push_subscriptions where endpoint = 'https://push.example.com/shared'`,
    );
    assert.deepEqual(rows, [{ user_id: admin2, p256dh: 'k2' }]);
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
