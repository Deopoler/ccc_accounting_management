// 피드백함: 보내기 권한 / 제한, 총괄 관리자만 조회 · 확인 처리, 푸시 요청 트리거.
import assert from 'node:assert/strict';
import { before, beforeEach, describe, test } from 'node:test';

import { asAnon, asUser, campusId, createCampus, createDb, createUser } from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

const submit = (db, userId, content) =>
  asUser(db, userId, 'select public.submit_feedback($1) as id', [content]);

let db;
let central;
let central2;
let campusAdmin;
let member;
let member2;
let pending;
let deactivated;
let otherCampusMember;
let otherCampusId;

before(async () => {
  db = await createDb();
  otherCampusId = await createCampus(db, { code: 'snu', name: '서울대' });
  central = await createUser(db, { studentId: '20200001', name: '총괄', role: 'central_admin' });
  central2 = await createUser(db, { studentId: '20200002', name: '총괄2', role: 'central_admin' });
  campusAdmin = await createUser(db, { studentId: '20200003', name: '캠퍼스관리자', role: 'campus_admin' });
  member = await createUser(db, { studentId: '20240001', name: '회원1' });
  member2 = await createUser(db, { studentId: '20240002', name: '회원2' });
  pending = await createUser(db, { studentId: '20249999', approved: false });
  deactivated = await createUser(db, { studentId: '20240003', name: '비활성' });
  await db.query('update public.profiles set deactivated_at = now() where id = $1', [deactivated]);
  otherCampusMember = await createUser(db, { studentId: '20240004', name: '서울대회원', campus: 'snu' });
});

beforeEach(async () => {
  await db.query('delete from public.feedback');
  await db.query('delete from net.requests');
  await db.query('delete from vault.decrypted_secrets');
});

describe('피드백 보내기', () => {
  test('승인된 회원은 보낼 수 있고 user_id / campus_id 는 서버가 채운다', async () => {
    const { rows } = await submit(db, member, '  앱이 편해요.\n감사합니다.  ');
    const row = (await db.query('select * from public.feedback where id = $1', [rows[0].id])).rows[0];
    assert.equal(row.user_id, member);
    assert.equal(row.campus_id, await campusId(db, 'kaist'));
    assert.equal(row.content, '앱이 편해요.\n감사합니다.');
    assert.equal(row.resolved_at, null);
    assert.equal(row.resolved_by, null);
  });

  test('다른 캠퍼스 회원은 자기 캠퍼스로 기록된다', async () => {
    const { rows } = await submit(db, otherCampusMember, '안녕하세요');
    const row = (await db.query('select campus_id from public.feedback where id = $1', [rows[0].id])).rows[0];
    assert.equal(row.campus_id, otherCampusId);
  });

  test('관리자도 회원처럼 보낼 수 있다', async () => {
    await submit(db, campusAdmin, '관리자 의견');
    await submit(db, central, '총괄 의견');
    assert.equal((await db.query('select * from public.feedback')).rows.length, 2);
  });

  test('anon 은 보낼 수 없다', async () => {
    await assertDenied(asAnon(db, `select public.submit_feedback('안녕')`));
  });

  test('승인 대기 / 비활성화된 회원은 보낼 수 없다', async () => {
    await assertRaises(submit(db, pending, '안녕'), /승인된 회원만/);
    await assertRaises(submit(db, deactivated, '안녕'), /승인된 회원만/);
    assert.equal((await db.query('select * from public.feedback')).rows.length, 0);
  });

  test('내용은 공백 제외 1자 이상 2000자 이하', async () => {
    await assertRaises(submit(db, member, ''), /1자 이상 2000자 이하/);
    await assertRaises(submit(db, member, '  \n\t '), /1자 이상 2000자 이하/);
    await assertRaises(submit(db, member, null), /1자 이상 2000자 이하/);
    await assertRaises(submit(db, member, 'ㄱ'.repeat(2001)), /1자 이상 2000자 이하/);
    // 앞뒤 공백은 길이에 세지 않는다.
    await submit(db, member, `  ${'ㄱ'.repeat(2000)}  `);
    await submit(db, member, 'ㄱ');
    assert.equal((await db.query('select * from public.feedback')).rows.length, 2);
  });

  test('테이블에 직접 넣을 수 없다 (RPC 로만)', async () => {
    const kaist = await campusId(db, 'kaist');
    for (const who of [member, campusAdmin, central]) {
      await assertDenied(asUser(db, who, `
        insert into public.feedback (user_id, campus_id, content) values ($1, $2, 'x')`, [who, kaist]));
    }
    await assertDenied(asAnon(db, `
      insert into public.feedback (user_id, campus_id, content) values ($1, $2, 'x')`, [member, kaist]));
  });

  test('10분에 5건까지만 보낼 수 있다', async () => {
    for (let i = 0; i < 5; i++) await submit(db, member, `의견 ${i}`);
    await assertRaises(submit(db, member, '여섯 번째'), /잠시 후 다시 보내 주세요\./);
    // 다른 사람은 영향이 없다.
    await submit(db, member2, '다른 회원');
    assert.equal((await db.query('select * from public.feedback where user_id = $1', [member])).rows.length, 5);

    // 10분이 지난 건은 세지 않는다.
    await db.query(
      `update public.feedback set created_at = now() - interval '11 minutes' where user_id = $1`,
      [member],
    );
    await submit(db, member, '다시 보냄');
    assert.equal((await db.query('select * from public.feedback where user_id = $1', [member])).rows.length, 6);
  });

  test('동시에 보내도 제한을 넘지 못한다', async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 8 }, (_, i) => submit(db, member, `동시 ${i}`)),
    );
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 5);
    assert.equal((await db.query('select * from public.feedback where user_id = $1', [member])).rows.length, 5);
  });
});

describe('피드백 조회 / 확인 처리', () => {
  let fid;
  beforeEach(async () => {
    fid = (await submit(db, member, '조회 테스트')).rows[0].id;
  });

  test('총괄 관리자는 모든 피드백을 조회한다', async () => {
    await submit(db, otherCampusMember, '서울대 의견');
    for (const who of [central, central2]) {
      const { rows } = await asUser(db, who, 'select content from public.feedback order by created_at');
      assert.deepEqual(rows.map((r) => r.content).sort(), ['서울대 의견', '조회 테스트']);
    }
  });

  test('보낸 회원도 본인 것을 조회할 수 없다', async () => {
    assert.equal((await asUser(db, member, 'select * from public.feedback')).rows.length, 0);
    assert.equal((await asUser(db, member2, 'select * from public.feedback')).rows.length, 0);
  });

  test('캠퍼스 관리자(같은 캠퍼스 포함)와 승인 대기 / 비활성화 계정은 조회할 수 없다', async () => {
    for (const who of [campusAdmin, pending, deactivated]) {
      assert.equal((await asUser(db, who, 'select * from public.feedback')).rows.length, 0);
    }
  });

  test('anon 은 조회할 수 없다', async () => {
    await assertDenied(asAnon(db, 'select * from public.feedback'));
  });

  test('profiles / campuses 를 조인해 보낸 사람 정보를 함께 읽는다 (총괄 관리자)', async () => {
    const { rows } = await asUser(db, central, `
      select f.content, p.name, p.student_id, c.name as campus_name
      from public.feedback f
      join public.profiles p on p.id = f.user_id
      join public.campuses c on c.id = f.campus_id`);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].name, '회원1');
    assert.equal(rows[0].student_id, '20240001');
  });

  test('총괄 관리자는 확인 처리 / 해제할 수 있고 확인한 사람은 서버가 기록한다', async () => {
    // resolved_by 에 다른 사람을 넣어도 본인으로 기록된다.
    const r = await asUser(
      db,
      central,
      `update public.feedback set resolved_at = now(), resolved_by = $2 where id = $1`,
      [fid, central2],
    );
    assert.equal(r.affectedRows, 1);
    let row = (await db.query('select resolved_at, resolved_by from public.feedback where id = $1', [fid])).rows[0];
    assert.ok(row.resolved_at);
    assert.equal(row.resolved_by, central);

    // 이미 확인된 건을 다른 총괄 관리자가 다시 확인해도 처음 기록을 유지한다.
    await asUser(db, central2, `update public.feedback set resolved_at = now(), resolved_by = $2 where id = $1`, [fid, central2]);
    const again = (await db.query('select resolved_at, resolved_by from public.feedback where id = $1', [fid])).rows[0];
    assert.equal(again.resolved_by, central);
    assert.deepEqual(again.resolved_at, row.resolved_at);

    // 해제
    await asUser(db, central2, 'update public.feedback set resolved_at = null, resolved_by = null where id = $1', [fid]);
    row = (await db.query('select resolved_at, resolved_by from public.feedback where id = $1', [fid])).rows[0];
    assert.deepEqual(row, { resolved_at: null, resolved_by: null });
  });

  test('resolved_at 만 바꿔도 resolved_by 가 채워지고, 해제하면 resolved_by 도 지워진다', async () => {
    await asUser(db, central, 'update public.feedback set resolved_at = now() where id = $1', [fid]);
    let row = (await db.query('select resolved_by from public.feedback where id = $1', [fid])).rows[0];
    assert.equal(row.resolved_by, central);
    await asUser(db, central, 'update public.feedback set resolved_at = null where id = $1', [fid]);
    row = (await db.query('select resolved_by from public.feedback where id = $1', [fid])).rows[0];
    assert.equal(row.resolved_by, null);
  });

  test('회원 / 캠퍼스 관리자 / 비활성화 계정은 확인 처리할 수 없다', async () => {
    for (const who of [member, campusAdmin, deactivated]) {
      const r = await asUser(db, who, 'update public.feedback set resolved_at = now() where id = $1', [fid]);
      assert.equal(r.affectedRows, 0);
    }
    await assertDenied(asAnon(db, 'update public.feedback set resolved_at = now()'));
    const row = (await db.query('select resolved_at from public.feedback where id = $1', [fid])).rows[0];
    assert.equal(row.resolved_at, null);
  });

  test('총괄 관리자도 내용 / 작성자 / 캠퍼스 / 시각을 바꾸거나 지울 수 없다', async () => {
    await assertDenied(asUser(db, central, `update public.feedback set content = '수정' where id = $1`, [fid]));
    await assertDenied(asUser(db, central, 'update public.feedback set user_id = $2 where id = $1', [fid, member2]));
    await assertDenied(asUser(db, central, 'update public.feedback set campus_id = $2 where id = $1', [fid, otherCampusId]));
    await assertDenied(asUser(db, central, `update public.feedback set created_at = now() where id = $1`, [fid]));
    await assertDenied(asUser(db, central, 'delete from public.feedback where id = $1', [fid]));
  });

  test('보낸 회원이 사라져도(프로필 삭제) 피드백은 함께 지워지고 확인자 기록은 비워진다', async () => {
    // 다른 테스트에 영향이 없도록 이 테스트 전용 계정을 쓴다.
    const tempAdmin = await createUser(db, { studentId: '20200090', role: 'central_admin' });
    const tempMember = await createUser(db, { studentId: '20240090' });
    const id = (await submit(db, tempMember, '삭제 테스트')).rows[0].id;
    await asUser(db, tempAdmin, 'update public.feedback set resolved_at = now() where id = $1', [id]);

    await db.query('delete from auth.users where id = $1', [tempAdmin]);
    const row = (await db.query('select resolved_by from public.feedback where id = $1', [id])).rows[0];
    assert.equal(row.resolved_by, null);

    await db.query('delete from auth.users where id = $1', [tempMember]);
    assert.equal((await db.query('select * from public.feedback where id = $1', [id])).rows.length, 0);
  });
});

describe('피드백 알림 트리거', () => {
  const configure = () => db.query(`
    insert into vault.decrypted_secrets (name, decrypted_secret) values
      ('push_function_url', 'https://ref.supabase.co/functions/v1/push'),
      ('push_webhook_secret', 's3cret')`);

  test('피드백을 보내면 함수 주소로 feedback_id 와 secret 을 보낸다', async () => {
    await configure();
    const { rows: sent } = await submit(db, member, '알림 테스트');
    const { rows } = await db.query('select url, body, headers from net.requests');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].url, 'https://ref.supabase.co/functions/v1/push');
    assert.deepEqual(rows[0].body, { type: 'feedback', feedback_id: sent[0].id });
    assert.equal(rows[0].headers['x-push-secret'], 's3cret');
  });

  test('피드백을 보낼 때마다 한 번씩 알리고, 확인 처리는 알리지 않는다', async () => {
    await configure();
    const a = (await submit(db, member, '하나')).rows[0].id;
    await submit(db, member2, '둘');
    assert.equal((await db.query('select * from net.requests')).rows.length, 2);
    await asUser(db, central, 'update public.feedback set resolved_at = now() where id = $1', [a]);
    assert.equal((await db.query('select * from net.requests')).rows.length, 2);
  });

  test('거부된 요청(승인 대기 회원 등)은 알리지 않는다', async () => {
    await configure();
    await assert.rejects(submit(db, pending, '안녕'));
    assert.equal((await db.query('select * from net.requests')).rows.length, 0);
  });

  test('Vault 설정이 없으면 보내지 않고 피드백은 저장된다', async () => {
    const { rows } = await submit(db, member, '설정 없음');
    assert.equal((await db.query('select 1 from public.feedback where id = $1', [rows[0].id])).rows.length, 1);
    assert.equal((await db.query('select * from net.requests')).rows.length, 0);
  });

  test('알림 요청이 실패해도 피드백은 저장된다', async () => {
    await configure();
    await db.query('alter table net.requests add constraint fail_all check (false)');
    try {
      const { rows } = await submit(db, member, '알림 실패');
      assert.equal((await db.query('select 1 from public.feedback where id = $1', [rows[0].id])).rows.length, 1);
    } finally {
      await db.query('alter table net.requests drop constraint fail_all');
    }
  });
});
