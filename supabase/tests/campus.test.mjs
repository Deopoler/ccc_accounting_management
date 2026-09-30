// 캠퍼스: 가입 / 캠퍼스 간 격리 / 역할 규칙 / 기존 데이터 이전.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import {
  applyMigration,
  asAnon,
  asUser,
  campusId,
  createCampus,
  createDb,
  createDbBefore,
  createUser,
  signUp,
} from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied|row-level security/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

const items = (...pairs) => JSON.stringify(pairs.map(([textbook_id, quantity]) => ({ textbook_id, quantity })));

let db;
let kaist;
let snu;
let central; // KAIST 소속 총괄 관리자
let kAdmin; // KAIST 캠퍼스 관리자
let kMember;
let sAdmin; // SNU 캠퍼스 관리자
let sMember;
let sMember2;
let kBook;
let sBook;
let kCategory;
let kEvent;
let sEvent;
let kOrder;

before(async () => {
  db = await createDb();
  kaist = await campusId(db, 'kaist');
  snu = await createCampus(db, { code: 'snu', name: '서울대' });

  central = await createUser(db, { studentId: '20250133', name: '총괄', role: 'central_admin' });
  kAdmin = await createUser(db, { studentId: '20200001', name: 'KAIST 관리자', role: 'campus_admin' });
  kMember = await createUser(db, { studentId: '20240001', name: 'KAIST 회원' });
  sAdmin = await createUser(db, { studentId: '20200001', name: '서울대 관리자', role: 'campus_admin', campus: 'snu' });
  sMember = await createUser(db, { studentId: '20240001', name: '서울대 회원', campus: 'snu' });
  sMember2 = await createUser(db, { studentId: '20240002', name: '서울대 회원2', campus: 'snu' });

  kCategory = (await db.query(
    `insert into public.textbook_categories (campus_id, name) values ($1, '성경공부') returning id`, [kaist])).rows[0].id;
  kBook = (await db.query(
    `insert into public.textbooks (campus_id, title, price, category_id) values ($1, 'KAIST 교재', 10000, $2) returning id`,
    [kaist, kCategory])).rows[0].id;
  sBook = (await db.query(
    `insert into public.textbooks (campus_id, title, price) values ($1, '서울대 교재', 8000) returning id`, [snu])).rows[0].id;
  kEvent = (await db.query(
    `insert into public.events (campus_id, title, amount) values ($1, 'KAIST 수련회', 50000) returning id`, [kaist])).rows[0].id;
  sEvent = (await db.query(
    `insert into public.events (campus_id, title, amount) values ($1, '서울대 수련회', 40000) returning id`, [snu])).rows[0].id;
  await db.query(`insert into public.event_payments (event_id, user_id) values ($1, $2)`, [kEvent, kMember]);
  kOrder = (await asUser(db, kMember, 'select public.place_textbook_order($1::jsonb) as id', [items([kBook, 1])])).rows[0].id;
});

// ---------------------------------------------------------------------------
describe('가입 / 로그인 아이디', () => {
  test('이메일 도메인으로 캠퍼스가 정해진다 (KAIST 는 ccc.local)', async () => {
    const k = await signUp(db, { email: '20249001@ccc.local', name: 'a' });
    const s = await signUp(db, { email: '20249001@snu.ccc.local', name: 'b' });
    const rows = (await db.query('select id, campus_id, student_id from public.profiles where id = any($1)', [[k, s]])).rows;
    const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
    assert.equal(byId[k].campus_id, kaist);
    assert.equal(byId[s].campus_id, snu);
    // 다른 캠퍼스끼리는 학번이 같아도 된다
    assert.equal(byId[k].student_id, byId[s].student_id);
  });

  test('같은 캠퍼스 안에서 학번은 중복될 수 없다', async () => {
    await assert.rejects(signUp(db, { email: '20249001@snu.ccc.local', name: 'c' }), (e) => e.code === '23505');
  });

  test('없는 캠퍼스 도메인 / 다른 도메인은 가입할 수 없다', async () => {
    await assertRaises(signUp(db, { email: '20249002@yonsei.ccc.local', name: 'x' }), /존재하지 않는 캠퍼스/);
    await assertRaises(signUp(db, { email: '20249002@evil.com', name: 'x' }), /학번 형식/);
    await assertRaises(signUp(db, { email: '20249002@a.b.ccc.local', name: 'x' }), /학번 형식/);
  });

  test('로그인 전에도 캠퍼스 목록(이름 / 코드 / 도메인만)을 볼 수 있다', async () => {
    const { rows } = await asAnon(db, 'select * from public.list_campuses()');
    assert.deepEqual(rows.map((r) => [r.code, r.email_domain]).sort(), [['kaist', 'ccc.local'], ['snu', 'snu.ccc.local']]);
    assert.deepEqual(Object.keys(rows[0]).sort(), ['code', 'email_domain', 'id', 'name']);
  });

  test('로그인 전에는 캠퍼스 테이블(계좌 포함)을 직접 볼 수 없다', async () => {
    await assertDenied(asAnon(db, 'select * from public.campuses'));
  });
});

// ---------------------------------------------------------------------------
describe('캠퍼스 관리', () => {
  test('총괄 관리자만 캠퍼스를 추가하고, 이메일 도메인은 코드로 정해진다', async () => {
    await assertDenied(asUser(db, kAdmin, `insert into public.campuses (code, name) values ('yonsei', '연세대')`));
    const { rows } = await asUser(db, central,
      `insert into public.campuses (code, name) values ('yonsei', '연세대') returning email_domain`);
    assert.equal(rows[0].email_domain, 'yonsei.ccc.local');
  });

  test('이메일 도메인은 직접 정할 수 없다', async () => {
    await assertDenied(asUser(db, central,
      `insert into public.campuses (code, name, email_domain) values ('korea', '고려대', 'ccc.local')`));
  });

  test('캠퍼스 코드는 누구도 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, central, `update public.campuses set code = 'kaist2' where id = $1`, [kaist]));
    await assertRaises(db.query(`update public.campuses set code = 'kaist2' where id = $1`, [kaist]), /코드는 바꿀 수 없습니다/);
    await assertRaises(db.query(`update public.campuses set email_domain = 'x.ccc.local' where id = $1`, [kaist]), /코드는 바꿀 수 없습니다/);
  });

  test('캠퍼스 관리자는 자기 캠퍼스의 이름 / 계좌만 바꿀 수 있다', async () => {
    const own = await asUser(db, sAdmin, `update public.campuses set bank_name = '국민', account_number = '1-2' where id = $1`, [snu]);
    assert.equal(own.affectedRows, 1);
    const other = await asUser(db, sAdmin, `update public.campuses set account_number = 'hacked' where id = $1`, [kaist]);
    assert.equal(other.affectedRows, 0);
  });

  test('회원은 자기 캠퍼스 정보(계좌)만 본다', async () => {
    const { rows } = await asUser(db, sMember, 'select code, account_number from public.campuses');
    assert.deepEqual(rows, [{ code: 'snu', account_number: '1-2' }]);
  });

  test('총괄 관리자는 모든 캠퍼스를 본다', async () => {
    const { rows } = await asUser(db, central, 'select code from public.campuses order by code');
    assert.deepEqual(rows.map((r) => r.code), ['kaist', 'snu', 'yonsei']);
  });
});

// ---------------------------------------------------------------------------
describe('캠퍼스 간 격리', () => {
  test('회원은 자기 캠퍼스의 교재 / 카테고리 / 이벤트만 본다', async () => {
    const books = (await asUser(db, sMember, 'select title from public.textbooks')).rows.map((r) => r.title);
    assert.deepEqual(books, ['서울대 교재']);
    assert.equal((await asUser(db, sMember, 'select * from public.textbook_categories')).rows.length, 0);
    const events = (await asUser(db, sMember, 'select title from public.events')).rows.map((r) => r.title);
    assert.deepEqual(events, ['서울대 수련회']);
  });

  test('다른 캠퍼스 교재는 신청할 수 없고, 신청은 회원의 캠퍼스로 기록된다', async () => {
    await assertRaises(
      asUser(db, sMember, 'select public.place_textbook_order($1::jsonb)', [items([kBook, 1])]),
      /신청할 수 없는 교재/,
    );
    const id = (await asUser(db, sMember, 'select public.place_textbook_order($1::jsonb) as id', [items([sBook, 2])])).rows[0].id;
    const o = (await db.query('select campus_id, total_price from public.textbook_orders where id = $1', [id])).rows[0];
    assert.equal(o.campus_id, snu);
    assert.equal(o.total_price, 16000);
  });

  test('캠퍼스 관리자는 다른 캠퍼스 회원 / 신청 / 송금을 볼 수 없다', async () => {
    const profiles = (await asUser(db, sAdmin, 'select campus_id from public.profiles')).rows;
    assert.ok(profiles.length > 0 && profiles.every((r) => r.campus_id === snu));
    const orders = (await asUser(db, sAdmin, 'select campus_id from public.textbook_orders')).rows;
    assert.ok(orders.length > 0 && orders.every((r) => r.campus_id === snu));
    const oi = (await asUser(db, sAdmin, 'select * from public.textbook_order_items where order_id = $1', [kOrder])).rows;
    assert.equal(oi.length, 0);
    const pays = (await asUser(db, sAdmin, 'select * from public.event_payments where event_id = $1', [kEvent])).rows;
    assert.equal(pays.length, 0);
  });

  test('캠퍼스 관리자는 다른 캠퍼스 데이터를 바꿀 수 없다', async () => {
    for (const [sql, params] of [
      ['update public.textbooks set price = 1 where id = $1', [kBook]],
      ['delete from public.textbooks where id = $1', [kBook]],
      ['update public.events set amount = 1 where id = $1', [kEvent]],
      ['update public.textbook_orders set is_shipped = true where id = $1', [kOrder]],
      [`update public.textbook_orders set status = 'paid' where id = $1`, [kOrder]],
      ['update public.profiles set is_approved = false where id = $1', [kMember]],
      ['update public.event_payments set is_paid = true where event_id = $1', [kEvent]],
    ]) {
      const r = await asUser(db, sAdmin, sql, params);
      assert.equal(r.affectedRows, 0, sql);
    }
    await assertRaises(
      asUser(db, sAdmin, 'select public.admin_set_textbook_received($1, true)', [kOrder]),
      /찾을 수 없습니다/,
    );
  });

  test('캠퍼스 관리자는 다른 캠퍼스에 교재 / 이벤트 / 카테고리를 만들 수 없다', async () => {
    await assertDenied(asUser(db, sAdmin, `insert into public.textbooks (campus_id, title, price) values ($1, 'x', 1)`, [kaist]));
    await assertDenied(asUser(db, sAdmin, `insert into public.events (campus_id, title, amount) values ($1, 'x', 1)`, [kaist]));
    await assertDenied(asUser(db, sAdmin, `insert into public.textbook_categories (campus_id, name) values ($1, 'x')`, [kaist]));
  });

  test('교재를 다른 캠퍼스 카테고리에 넣을 수 없다', async () => {
    await assert.rejects(
      asUser(db, sAdmin, `insert into public.textbooks (campus_id, title, price, category_id) values ($1, 'x', 1, $2)`, [snu, kCategory]),
      (e) => e.code === '23503',
    );
  });

  test('교재 / 이벤트를 다른 캠퍼스로 옮길 수 없다', async () => {
    await assertDenied(asUser(db, sAdmin, 'update public.textbooks set campus_id = $1 where id = $2', [kaist, sBook]));
    await assertDenied(asUser(db, central, 'update public.events set campus_id = $1 where id = $2', [kaist, sEvent]));
  });

  test('송금 대상은 이벤트와 같은 캠퍼스 회원만', async () => {
    await assertRaises(
      asUser(db, sAdmin, 'insert into public.event_payments (event_id, user_id) values ($1, $2)', [sEvent, kMember]),
      /같은 캠퍼스의 회원만/,
    );
    const r = await asUser(db, sAdmin, 'insert into public.event_payments (event_id, user_id) values ($1, $2)', [sEvent, sMember]);
    assert.equal(r.affectedRows, 1);
  });

  test('총괄 관리자는 모든 캠퍼스 데이터를 보고 처리한다', async () => {
    const campuses = new Set((await asUser(db, central, 'select campus_id from public.textbook_orders')).rows.map((r) => r.campus_id));
    assert.deepEqual([...campuses].sort(), [kaist, snu].sort());
    const r = await asUser(db, central, `update public.textbook_orders set status = 'paid' where id = $1`, [kOrder]);
    assert.equal(r.affectedRows, 1);
  });
});

// ---------------------------------------------------------------------------
describe('역할 규칙', () => {
  test('캠퍼스 관리자는 자기 캠퍼스 회원을 캠퍼스 관리자로 지정할 수 있다', async () => {
    const r = await asUser(db, sAdmin, `update public.profiles set role = 'campus_admin' where id = $1`, [sMember2]);
    assert.equal(r.affectedRows, 1);
  });

  test('다른 캠퍼스 회원은 지정할 수 없다', async () => {
    const r = await asUser(db, sAdmin, `update public.profiles set role = 'campus_admin' where id = $1`, [kMember]);
    assert.equal(r.affectedRows, 0);
  });

  test('캠퍼스 관리자는 총괄 관리자를 지정 / 변경할 수 없다', async () => {
    await assertRaises(
      asUser(db, sAdmin, `update public.profiles set role = 'central_admin' where id = $1`, [sMember]),
      /총괄 관리자 지정은/,
    );
    // 총괄 관리자는 KAIST 소속이라 KAIST 관리자에게 보이지만 바꿀 수 없다.
    await assertRaises(
      asUser(db, kAdmin, `update public.profiles set is_approved = false where id = $1`, [central]),
      /총괄 관리자 정보는/,
    );
  });

  test('캠퍼스 이동은 총괄 관리자만', async () => {
    await assertRaises(
      asUser(db, sAdmin, 'update public.profiles set campus_id = $1 where id = $2', [kaist, sMember]),
      /캠퍼스는 총괄 관리자만/,
    );
    const moved = await createUser(db, { studentId: '20247777', campus: 'snu' });
    const r = await asUser(db, central, 'update public.profiles set campus_id = $1 where id = $2', [kaist, moved]);
    assert.equal(r.affectedRows, 1);
  });

  test('캠퍼스의 마지막 관리자는 해제할 수 없다 (다른 관리자가 있으면 가능)', async () => {
    // SNU 관리자: sAdmin, sMember2
    const r = await asUser(db, sMember2, `update public.profiles set role = 'member' where id = $1`, [sAdmin]);
    assert.equal(r.affectedRows, 1);
    await assertRaises(
      asUser(db, sMember2, `update public.profiles set role = 'member' where id = $1`, [sMember2]),
      /마지막 관리자/,
    );
  });

  test('총괄 관리자는 캠퍼스의 마지막 관리자도 해제할 수 있다', async () => {
    const r = await asUser(db, central, `update public.profiles set role = 'member' where id = $1`, [sMember2]);
    assert.equal(r.affectedRows, 1);
    // 복구
    await asUser(db, central, `update public.profiles set role = 'campus_admin' where id = $1`, [sAdmin]);
  });

  test('총괄 관리자는 다른 사람을 총괄 관리자로 지정할 수 있고, 마지막 총괄 관리자는 해제할 수 없다', async () => {
    await assertRaises(
      asUser(db, central, `update public.profiles set role = 'campus_admin' where id = $1`, [central]),
      /마지막 총괄 관리자/,
    );
    const r = await asUser(db, central, `update public.profiles set role = 'central_admin' where id = $1`, [kAdmin]);
    assert.equal(r.affectedRows, 1);
    const back = await asUser(db, kAdmin, `update public.profiles set role = 'campus_admin' where id = $1`, [kAdmin]);
    assert.equal(back.affectedRows, 1);
  });

  test('승인 대기 사용자는 자기 캠퍼스 데이터도 볼 수 없다', async () => {
    const waiting = await createUser(db, { studentId: '20248888', campus: 'snu', approved: false });
    for (const t of ['textbooks', 'events', 'campuses', 'textbook_categories']) {
      const { rows } = await asUser(db, waiting, `select * from public.${t}`);
      assert.equal(rows.length, 0, t);
    }
  });
});

// ---------------------------------------------------------------------------
describe('기존 데이터 이전 (마이그레이션)', () => {
  const CAMPUS = '20261009';

  async function legacyDb() {
    const old = await createDbBefore(CAMPUS);
    const signUpLegacy = async (studentId, name) =>
      (await old.query(
        `insert into auth.users (email, encrypted_password, raw_user_meta_data) values ($1, 'x', $2) returning id`,
        [`${studentId}@ccc.local`, JSON.stringify({ name })],
      )).rows[0].id;
    return { old, signUpLegacy };
  }

  test('모두 KAIST 로, 관리자는 캠퍼스 관리자로, 20250133 은 총괄 관리자로, 계좌는 KAIST 로', async () => {
    const { old, signUpLegacy } = await legacyDb();
    const head = await signUpLegacy('20250133', '총괄');
    const otherAdmin = await signUpLegacy('20200001', '관리자');
    const member = await signUpLegacy('20240001', '회원');
    await old.query(`update public.profiles set is_approved = true`);
    await old.query(`update public.profiles set role = 'admin' where id = any($1)`, [[head, otherAdmin]]);
    await old.query(`update public.app_settings set value = '카카오뱅크' where key = 'bank_name'`);
    await old.query(`update public.app_settings set value = '3333-01' where key = 'account_number'`);
    const book = (await old.query(`insert into public.textbooks (title, price) values ('교재', 1000) returning id`)).rows[0].id;
    await old.query(`insert into public.events (title, amount) values ('행사', 1000)`);

    await applyMigration(old, CAMPUS);

    const kaistId = (await old.query(`select id from public.campuses where code = 'kaist'`)).rows[0].id;
    const roles = Object.fromEntries((await old.query('select id, role, campus_id from public.profiles')).rows
      .map((r) => [r.id, r]));
    assert.equal(roles[head].role, 'central_admin');
    assert.equal(roles[otherAdmin].role, 'campus_admin');
    assert.equal(roles[member].role, 'member');
    assert.ok(Object.values(roles).every((r) => r.campus_id === kaistId));

    const c = (await old.query(`select * from public.campuses where code = 'kaist'`)).rows[0];
    assert.equal(c.email_domain, 'ccc.local');
    assert.equal(c.bank_name, '카카오뱅크');
    assert.equal(c.account_number, '3333-01');
    assert.equal((await old.query('select campus_id from public.textbooks where id = $1', [book])).rows[0].campus_id, kaistId);
    assert.equal((await old.query(`select count(*)::int n from public.events where campus_id = $1`, [kaistId])).rows[0].n, 1);

    // 기존 회원은 그대로 로그인 / 신청할 수 있다
    const order = (await asUser(old, member, 'select public.place_textbook_order($1::jsonb) as id', [items([book, 1])])).rows[0].id;
    assert.ok(order);
  });

  test('회원이 있는데 20250133 계정이 없으면 마이그레이션을 멈춘다', async () => {
    const { old, signUpLegacy } = await legacyDb();
    await signUpLegacy('20200001', '관리자');
    await assert.rejects(applyMigration(old, CAMPUS), /20250133/);
  });
});
