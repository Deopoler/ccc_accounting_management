import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import { asUser, createDb, createUser, signUp } from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

let db;
let admin;

before(async () => {
  db = await createDb();
  admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'admin' });
  await db.query(`insert into public.textbooks (title, price) values ('교재 A', 10000)`);
});

describe('가입 트리거', () => {
  test('학번은 이메일에서 추출하고, 승인 대기 / member 로 생성된다', async () => {
    const id = await signUp(db, { email: 'A2024X01@ccc.local', name: ' 홍길동 ' });
    const { rows } = await db.query('select * from public.profiles where id = $1', [id]);
    assert.equal(rows[0].student_id, 'a2024x01');
    assert.equal(rows[0].name, '홍길동');
    assert.equal(rows[0].role, 'member');
    assert.equal(rows[0].is_approved, false);
    assert.equal(rows[0].must_change_password, false);
  });

  test('metadata 로 role 을 보내도 무시된다', async () => {
    const { rows } = await db.query(
      `insert into auth.users (email, raw_user_meta_data) values ('20249999@ccc.local', $1) returning id`,
      [JSON.stringify({ name: 'x', role: 'admin', is_approved: true })],
    );
    const p = (await db.query('select role, is_approved from public.profiles where id = $1', [rows[0].id])).rows[0];
    assert.equal(p.role, 'member');
    assert.equal(p.is_approved, false);
  });

  test('학번 형식이 아닌 이메일은 가입할 수 없다', async () => {
    await assertRaises(signUp(db, { email: 'someone@gmail.com', name: 'x' }), /학번 형식/);
    await assertRaises(signUp(db, { email: '12@ccc.local', name: 'x' }), /학번 형식/);
  });

  test('이름이 없으면 학번으로 대신한다 (대시보드에서 만든 계정)', async () => {
    const id = await signUp(db, { email: '20240500@ccc.local' });
    const { rows } = await db.query('select name from public.profiles where id = $1', [id]);
    assert.equal(rows[0].name, '20240500');
  });

  test('로그인 아이디(이메일)는 바꿀 수 없다', async () => {
    const id = await signUp(db, { email: '20240600@ccc.local', name: 'x' });
    await assertRaises(
      db.query(`update auth.users set email = '20240601@ccc.local' where id = $1`, [id]),
      /변경할 수 없습니다/,
    );
  });
});

describe('승인 전', () => {
  let pending;

  before(async () => {
    pending = await createUser(db, { studentId: '20241000', approved: false });
  });

  test('본인 프로필은 볼 수 있다 (승인 대기 화면용)', async () => {
    const { rows } = await asUser(db, pending, 'select is_approved from public.profiles');
    assert.deepEqual(rows, [{ is_approved: false }]);
  });

  test('교재 / 이벤트 / 계좌 정보를 볼 수 없다', async () => {
    for (const t of ['textbooks', 'events', 'app_settings']) {
      const { rows } = await asUser(db, pending, `select * from public.${t}`);
      assert.equal(rows.length, 0, t);
    }
  });

  test('교재를 신청할 수 없다', async () => {
    const { rows } = await db.query('select id from public.textbooks limit 1');
    await assertRaises(
      asUser(db, pending, 'select public.place_textbook_order($1::jsonb)', [
        JSON.stringify([{ textbook_id: rows[0].id, quantity: 1 }]),
      ]),
      /승인된 회원/,
    );
  });

  test('스스로 승인할 수 없다', async () => {
    const r = await asUser(db, pending, 'update public.profiles set is_approved = true where id = $1', [pending]);
    assert.equal(r.affectedRows, 0);
  });

});

describe('승인', () => {
  test('관리자가 승인하면 데이터를 볼 수 있다 (이벤트 대상 자동 등록은 없음)', async () => {
    await asUser(db, admin, `insert into public.events (title, amount) values ('수련회', 50000)`);

    const user = await createUser(db, { studentId: '20242000', approved: false });
    const r = await asUser(db, admin, 'update public.profiles set is_approved = true where id = $1', [user]);
    assert.equal(r.affectedRows, 1);

    const { rows: books } = await asUser(db, user, 'select id from public.textbooks');
    assert.ok(books.length > 0);

    const { rows: events } = await asUser(db, user, 'select title from public.events');
    assert.ok(events.some((e) => e.title === '수련회'));

    const { rows: pays } = await db.query('select 1 from public.event_payments where user_id = $1', [user]);
    assert.equal(pays.length, 0);
  });

  test('승인이 해제된 관리자는 관리자 권한을 잃는다', async () => {
    const admin2 = await createUser(db, { studentId: '20200002', role: 'admin' });
    await asUser(db, admin, 'update public.profiles set is_approved = false where id = $1', [admin2]);
    const { rows } = await asUser(db, admin2, 'select id from public.profiles');
    assert.deepEqual(rows.map((r) => r.id), [admin2]);
  });

  test('마지막 관리자는 승인 해제할 수 없다', async () => {
    await assertRaises(
      asUser(db, admin, 'update public.profiles set is_approved = false where id = $1', [admin]),
      /마지막 관리자/,
    );
  });

  test('회원은 다른 사람을 승인할 수 없다', async () => {
    const member = await createUser(db, { studentId: '20243000' });
    const other = await createUser(db, { studentId: '20243001', approved: false });
    const r = await asUser(db, member, 'update public.profiles set is_approved = true where id = $1', [other]);
    assert.equal(r.affectedRows, 0);
  });

  test('관리자도 학번/생성일은 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, admin, `update public.profiles set created_at = now()`));
  });
});
