// 이벤트 설정 "새로 가입한 회원 자동 추가": 승인 시점 등록 / 조건 / 권한.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import { asUser, campusId, createCampus, createDb, createUser, signUp } from './helpers.mjs';

const seoulToday = `(now() at time zone 'Asia/Seoul')::date`;

let db;
let kaist;
let snu;
let kAdmin;

async function createEvent(campus, { title, auto = true, due = null }) {
  const { rows } = await db.query(
    `insert into public.events (campus_id, title, amount, due_date, auto_enroll_new_members)
     values ($1, $2, 10000, ${due ?? 'null'}, $3) returning id`,
    [campus, title, auto],
  );
  return rows[0].id;
}

async function enrolled(userId) {
  const { rows } = await db.query(
    `select e.title from public.event_payments p
     join public.events e on e.id = p.event_id
     where p.user_id = $1 order by e.title`,
    [userId],
  );
  return rows.map((r) => r.title);
}

const pending = (studentId, campus = 'kaist') => createUser(db, { studentId, approved: false, campus });
const approve = (userId) => db.query('update public.profiles set is_approved = true where id = $1', [userId]);

before(async () => {
  db = await createDb();
  kaist = await campusId(db, 'kaist');
  snu = await createCampus(db, { code: 'snu', name: '서울대' });
  kAdmin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
});

describe('승인 시 자동 등록', () => {
  test('설정이 켜진 같은 캠퍼스의 진행 중 이벤트에만 등록된다', async () => {
    await createEvent(kaist, { title: 'T1 켜짐 마감없음' });
    await createEvent(kaist, { title: 'T1 켜짐 마감전', due: `${seoulToday} + 3` });
    await createEvent(kaist, { title: 'T1 켜짐 오늘마감', due: seoulToday });
    await createEvent(kaist, { title: 'T1 꺼짐', auto: false });
    await createEvent(kaist, { title: 'T1 켜짐 마감지남', due: `${seoulToday} - 1` });
    await createEvent(snu, { title: 'T1 다른 캠퍼스' });

    const user = await pending('20250101');
    assert.deepEqual(await enrolled(user), []);
    await approve(user);
    assert.deepEqual(await enrolled(user), ['T1 켜짐 마감없음', 'T1 켜짐 마감전', 'T1 켜짐 오늘마감']);
  });

  test('다른 캠퍼스 회원은 자기 캠퍼스 이벤트에만 등록된다', async () => {
    const user = await pending('20250102', 'snu');
    await approve(user);
    assert.ok((await enrolled(user)).includes('T1 다른 캠퍼스'));
    assert.ok(!(await enrolled(user)).some((t) => t.startsWith('T1 켜짐')));
  });

  test('승인 상태로 프로필이 만들어져도 등록된다 (insert)', async () => {
    await createEvent(kaist, { title: 'T3 켜짐' });
    const id = await signUp(db, { email: '20250103@ccc.local', name: '직접 승인' });
    await db.query('delete from public.profiles where id = $1', [id]);
    await db.query(
      `insert into public.profiles (id, campus_id, student_id, name, is_approved)
       values ($1, $2, '20250103', '직접 승인', true)`,
      [id, kaist],
    );
    assert.ok((await enrolled(id)).includes('T3 켜짐'));
  });

  test('승인 대기 상태로 만들어진 프로필은 등록되지 않는다', async () => {
    const user = await pending('20250104');
    assert.deepEqual(await enrolled(user), []);
  });

  test('역할과 상관없이 승인된 계정이면 등록된다 (직접 대상 선택과 같음)', async () => {
    const id = await createEvent(kaist, { title: 'T5 켜짐' });
    const admin2 = await pending('20250105');
    await db.query(`update public.profiles set role = 'campus_admin' where id = $1`, [admin2]);
    await approve(admin2);
    assert.ok((await enrolled(admin2)).includes('T5 켜짐'));
    await db.query('delete from public.events where id = $1', [id]);
  });
});

describe('등록하지 않는 경우', () => {
  test('비활성화된 상태로 승인되면 등록하지 않고, 승인 처리는 실패하지 않는다', async () => {
    await createEvent(kaist, { title: 'T6 켜짐' });
    const user = await pending('20250106');
    await db.query('update public.profiles set is_approved = true, deactivated_at = now() where id = $1', [user]);
    assert.deepEqual(await enrolled(user), []);
  });

  test('비활성화 회원을 복구해도 등록하지 않는다', async () => {
    const user = await createUser(db, { studentId: '20250107' });
    await createEvent(kaist, { title: 'T7 켜짐' });
    await db.query('update public.profiles set deactivated_at = now() where id = $1', [user]);
    await db.query('update public.profiles set deactivated_at = null where id = $1', [user]);
    assert.ok(!(await enrolled(user)).includes('T7 켜짐'));
  });

  test('설정을 켜도 이미 승인된 회원은 추가되지 않는다', async () => {
    const user = await createUser(db, { studentId: '20250108' });
    const id = await createEvent(kaist, { title: 'T8 나중에 켬', auto: false });
    await db.query('update public.events set auto_enroll_new_members = true where id = $1', [id]);
    assert.ok(!(await enrolled(user)).includes('T8 나중에 켬'));
  });

  test('이벤트를 만들 때 기존 회원이 추가되지 않는다', async () => {
    const user = await createUser(db, { studentId: '20250109' });
    await createEvent(kaist, { title: 'T9 새 이벤트' });
    assert.ok(!(await enrolled(user)).includes('T9 새 이벤트'));
  });

  test('승인과 무관한 프로필 수정은 등록하지 않는다', async () => {
    const user = await createUser(db, { studentId: '20250110' });
    await createEvent(kaist, { title: 'T10 켜짐' });
    await db.query(`update public.profiles set name = '이름변경' where id = $1`, [user]);
    assert.ok(!(await enrolled(user)).includes('T10 켜짐'));
  });
});

describe('중복 / 재승인', () => {
  test('같은 값으로 다시 수정해도 중복 행이 생기지 않는다', async () => {
    await createEvent(kaist, { title: 'T11 켜짐' });
    const user = await pending('20250111');
    await approve(user);
    await approve(user);
    await db.query('update public.profiles set is_approved = true where id = $1', [user]);
    const rows = (await enrolled(user)).filter((t) => t === 'T11 켜짐');
    assert.equal(rows.length, 1);
  });

  test('승인 해제 후 다시 승인해도 기존 송금 기록을 덮어쓰지 않는다', async () => {
    await createEvent(kaist, { title: 'T12 켜짐' });
    const user = await pending('20250112');
    await approve(user);
    await db.query(
      `update public.event_payments set is_paid = true
       where user_id = $1 and event_id = (select id from public.events where title = 'T12 켜짐')`,
      [user],
    );
    await db.query('update public.profiles set is_approved = false where id = $1', [user]);
    await approve(user);
    const { rows } = await db.query(
      `select is_paid from public.event_payments
       where user_id = $1 and event_id = (select id from public.events where title = 'T12 켜짐')`,
      [user],
    );
    assert.deepEqual(rows, [{ is_paid: true }]);
  });

  test('관리자가 직접 제외한 회원도 승인이 다시 일어나면 다시 등록된다', async () => {
    await createEvent(kaist, { title: 'T13 켜짐' });
    const user = await pending('20250113');
    await approve(user);
    await db.query('delete from public.event_payments where user_id = $1', [user]);
    await db.query('update public.profiles set is_approved = false where id = $1', [user]);
    await approve(user);
    assert.ok((await enrolled(user)).includes('T13 켜짐'));
  });
});

describe('설정 권한', () => {
  test('캠퍼스 관리자가 이벤트를 만들 때 설정할 수 있고 기본값은 꺼짐이다', async () => {
    const { rows: on } = await asUser(
      db,
      kAdmin,
      `insert into public.events (campus_id, title, amount, auto_enroll_new_members)
       values ($1, 'T14 켜짐', 1000, true) returning auto_enroll_new_members`,
      [kaist],
    );
    assert.equal(on[0].auto_enroll_new_members, true);
    const { rows: off } = await asUser(
      db,
      kAdmin,
      `insert into public.events (campus_id, title, amount) values ($1, 'T14 기본', 1000)
       returning auto_enroll_new_members`,
      [kaist],
    );
    assert.equal(off[0].auto_enroll_new_members, false);
  });

  test('캠퍼스 관리자가 수정할 수 있다', async () => {
    const id = await createEvent(kaist, { title: 'T15', auto: false });
    const r = await asUser(db, kAdmin, 'update public.events set auto_enroll_new_members = true where id = $1', [id]);
    assert.equal(r.affectedRows, 1);
  });

  test('일반 회원은 바꿀 수 없다', async () => {
    const member = await createUser(db, { studentId: '20250116' });
    const id = await createEvent(kaist, { title: 'T16', auto: false });
    const r = await asUser(db, member, 'update public.events set auto_enroll_new_members = true where id = $1', [id]);
    assert.equal(r.affectedRows, 0);
    const { rows } = await db.query('select auto_enroll_new_members from public.events where id = $1', [id]);
    assert.equal(rows[0].auto_enroll_new_members, false);
  });

  test('자동 등록 함수는 직접 호출할 수 없다', async () => {
    const member = await createUser(db, { studentId: '20250117' });
    await assert.rejects(
      asUser(db, member, 'select private.enroll_approved_member_in_events()'),
      (e) => e.code === '42501' || /permission denied/.test(e.message),
    );
  });
});
