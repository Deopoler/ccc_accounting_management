// 교재 신청 회차: 캠퍼스별 회차 / 자동 생성 / 관리자 마감 변경 / 신청 회차 이동 / 기존 데이터 이전.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import {
  applyMigration,
  asUser,
  campusId,
  createCampus,
  createDb,
  createDbBefore,
  createUser,
} from './helpers.mjs';

const ROUNDS = '20261011000000';
const BACKFILL = '20261013000000';
const WEEK = 7 * 24 * 3600 * 1000;

/** 회차가 빈틈없이 이어지고, 모두 1주이며, 가장 오래된 회차가 1년 이상 전에 시작하는지 */
function assertYearOfWeeks(all) {
  for (let i = 1; i < all.length; i++) {
    assert.equal(all[i].starts_at.getTime(), all[i - 1].deadline.getTime(), '회차는 빈틈없이 이어진다');
  }
  assert.ok(Date.now() - all[0].starts_at.getTime() >= 364 * 24 * 3600 * 1000, '지난 1년 회차가 있다');
}

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied|row-level security/.test(e.message));
}

async function assertRaises(promise, pattern) {
  await assert.rejects(promise, (e) => e.code === 'P0001' && pattern.test(e.message));
}

const items = (...pairs) => JSON.stringify(pairs.map(([textbook_id, quantity]) => ({ textbook_id, quantity })));

/** 캠퍼스의 회차 (오래된 것부터) */
async function rounds(db, campus) {
  const { rows } = await db.query(
    'select id, starts_at, deadline from public.order_rounds where campus_id = $1 order by starts_at',
    [campus],
  );
  return rows;
}

/** 이번 회차 바로 앞에 마감된 회차를 만든다. (서비스 롤) */
async function addPastRound(db, campus) {
  const [first] = await rounds(db, campus);
  const { rows } = await db.query(
    `insert into public.order_rounds (campus_id, starts_at, deadline)
     values ($1, $2::timestamptz - interval '7 days', $2) returning id`,
    [campus, first.starts_at],
  );
  return rows[0].id;
}

let db;
let kaist;
let snu;
let central;
let kAdmin;
let kMember;
let sAdmin;
let sMember;
let kBook;

before(async () => {
  db = await createDb();
  kaist = await campusId(db, 'kaist');
  snu = await createCampus(db, { code: 'snu', name: '서울대' });

  central = await createUser(db, { studentId: '20250133', name: '총괄', role: 'central_admin' });
  kAdmin = await createUser(db, { studentId: '20200001', name: 'KAIST 관리자', role: 'campus_admin' });
  kMember = await createUser(db, { studentId: '20240001', name: 'KAIST 회원' });
  sAdmin = await createUser(db, { studentId: '20200001', name: '서울대 관리자', role: 'campus_admin', campus: 'snu' });
  sMember = await createUser(db, { studentId: '20240001', name: '서울대 회원', campus: 'snu' });

  kBook = (await db.query(
    `insert into public.textbooks (campus_id, title, price) values ($1, 'KAIST 교재', 10000) returning id`, [kaist],
  )).rows[0].id;
});

describe('이번 회차', () => {
  test('회차가 없으면 주간 규칙으로 만든다: 수요일 09:00 KST ~ 다음 수요일 09:00 KST', async () => {
    assert.equal((await rounds(db, snu)).length, 0, '새 캠퍼스는 회차가 없다');
    const { rows } = await asUser(db, sMember, `
      select id, round_start,
             extract(isodow from round_start)::int as dow,
             to_char(starts_at at time zone 'UTC', 'HH24:MI') as start_utc,
             deadline - starts_at = interval '7 days' as week,
             starts_at <= now() and deadline > now() as in_range
      from public.get_order_round()`);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].dow, 3);
    assert.equal(rows[0].start_utc, '00:00');
    assert.equal(rows[0].week, true);
    assert.equal(rows[0].in_range, true);

    // 신청이 없어도 지난 1년(52주) 회차가 함께 만들어진다.
    const all = await rounds(db, snu);
    assert.equal(all.at(-1).id, rows[0].id);
    assert.equal(all.length, 53);
    assert.ok(all.every((r) => r.deadline - r.starts_at === WEEK));
    assertYearOfWeeks(all);
  });

  test('다시 조회해도 같은 회차', async () => {
    const a = (await asUser(db, sMember, 'select id from public.get_order_round()')).rows[0].id;
    const b = (await asUser(db, sAdmin, 'select id from public.get_order_round($1)', [snu])).rows[0].id;
    assert.equal(a, b);
  });

  test('마감이 지나면 마감 + 7일 회차가 이어서 만들어진다 (오래 비었으면 그 사이 회차도)', async () => {
    const campus = await createCampus(db, { code: 'gap', name: '공백' });
    const member = await createUser(db, { studentId: '20249999', campus: 'gap' });
    // 3주 전 목요일 15:00 에 마감된 회차
    await db.query(`
      insert into public.order_rounds (campus_id, starts_at, deadline)
      values ($1, now() - interval '28 days', date_trunc('hour', now()) - interval '20 days')`, [campus]);

    const { rows } = await asUser(db, member, 'select id, starts_at, deadline from public.get_order_round()');
    const all = await rounds(db, campus);
    assert.equal(all.at(-1).id, rows[0].id);
    assert.ok(all.length >= 3);
    for (let i = 1; i < all.length; i++) {
      assert.equal(all[i].starts_at.getTime(), all[i - 1].deadline.getTime(), '회차는 빈틈없이 이어진다');
      assert.equal(all[i].deadline - all[i].starts_at, 7 * 24 * 3600 * 1000);
    }
    assert.ok(rows[0].deadline > new Date() && rows[0].starts_at <= new Date());
  });

  test('다른 캠퍼스의 회차는 조회할 수 없다 (총괄 관리자는 가능)', async () => {
    await assertRaises(asUser(db, kMember, 'select * from public.get_order_round($1)', [snu]), /권한/);
    await assertRaises(asUser(db, kAdmin, 'select * from public.get_order_round($1)', [snu]), /권한/);
    const { rows } = await asUser(db, central, 'select * from public.get_order_round($1)', [snu]);
    assert.equal(rows.length, 1);
    const { rows: list } = await asUser(db, kMember, 'select campus_id from public.order_rounds');
    assert.ok(list.length > 0 && list.every((r) => r.campus_id === kaist));
  });

  test('승인 대기 사용자는 회차가 없다', async () => {
    const pending = await createUser(db, { studentId: '20248888', approved: false });
    const { rows } = await asUser(db, pending, 'select * from public.get_order_round()');
    assert.equal(rows.length, 0);
  });

  test('회차 테이블은 직접 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, kAdmin, `
      insert into public.order_rounds (campus_id, starts_at, deadline) values ($1, now(), now() + interval '1 day')`, [kaist]));
    await assertDenied(asUser(db, kAdmin, `update public.order_rounds set deadline = now() + interval '1 day'`));
    await assertDenied(asUser(db, kAdmin, 'delete from public.order_rounds'));
  });

  test('회차 계산 내부 함수는 회원이 직접 호출할 수 없다', async () => {
    await assertDenied(asUser(db, kMember, 'select private.ensure_order_round($1)', [kaist]));
    await assertDenied(asUser(db, kMember, 'select private.order_round_for(now())'));
  });
});

describe('마감 일시 변경', () => {
  let round;

  before(async () => {
    round = (await asUser(db, kMember, 'select id, starts_at, deadline from public.get_order_round()')).rows[0];
  });

  test('캠퍼스 관리자는 이번 회차의 마감 일시를 바꿀 수 있다', async () => {
    const { rows } = await asUser(db, kAdmin, `
      select deadline = date_trunc('minute', now()) + interval '3 days 15 minutes' as ok
      from public.admin_set_order_round_deadline($1, date_trunc('minute', now()) + interval '3 days 15 minutes')`,
    [round.id]);
    assert.equal(rows[0].ok, true);
    const { rows: cur } = await asUser(db, kMember, 'select id, deadline from public.get_order_round()');
    assert.equal(cur[0].id, round.id, '회차는 그대로, 마감만 바뀐다');
  });

  test('바뀐 마감이 지나면 다음 회차는 그 시각에서 7일 뒤 마감', async () => {
    const campus = await createCampus(db, { code: 'next', name: '다음' });
    const admin = await createUser(db, { studentId: '20201111', role: 'campus_admin', campus: 'next' });
    const r = (await asUser(db, admin, 'select id from public.get_order_round()')).rows[0];
    await asUser(db, admin, `select public.admin_set_order_round_deadline($1, now() + interval '1 hour')`, [r.id]);
    // 마감 시각이 지난 상황 (서비스 롤로 시간을 당긴다)
    await db.query(`update public.order_rounds set deadline = now() - interval '1 minute' where id = $1`, [r.id]);

    const { rows } = await asUser(db, admin, 'select id, starts_at, deadline from public.get_order_round()');
    const [prev] = (await rounds(db, campus)).filter((x) => x.id === r.id);
    assert.notEqual(rows[0].id, r.id);
    assert.equal(rows[0].starts_at.getTime(), prev.deadline.getTime());
    assert.equal(rows[0].deadline - rows[0].starts_at, 7 * 24 * 3600 * 1000);
  });

  test('지난 시각 / 회차 시작 전 / 1년 넘게 뒤 / 비어 있는 마감은 거부된다', async () => {
    await assertRaises(asUser(db, kAdmin, `select public.admin_set_order_round_deadline($1, now() - interval '1 minute')`, [round.id]), /지금보다 뒤/);
    await assertRaises(asUser(db, kAdmin, `select public.admin_set_order_round_deadline($1, now() + interval '2 years')`, [round.id]), /1년/);
    await assertRaises(asUser(db, kAdmin, 'select public.admin_set_order_round_deadline($1, null)', [round.id]), /지정해 주세요/);
  });

  test('이미 마감된 회차는 바꿀 수 없다', async () => {
    const past = await addPastRound(db, kaist);
    await assertRaises(
      asUser(db, kAdmin, `select public.admin_set_order_round_deadline($1, now() + interval '1 day')`, [past]),
      /이미 마감/,
    );
  });

  test('회원 / 다른 캠퍼스 관리자는 바꿀 수 없다, 총괄 관리자는 가능', async () => {
    await assertRaises(asUser(db, kMember, `select public.admin_set_order_round_deadline($1, now() + interval '1 day')`, [round.id]), /찾을 수 없습니다/);
    await assertRaises(asUser(db, sAdmin, `select public.admin_set_order_round_deadline($1, now() + interval '1 day')`, [round.id]), /찾을 수 없습니다/);
    await asUser(db, central, `select public.admin_set_order_round_deadline($1, now() + interval '2 days')`, [round.id]);
  });
});

describe('신청 회차 이동', () => {
  let order;
  let current;
  let past;

  before(async () => {
    order = (await asUser(db, kMember, 'select public.place_textbook_order($1::jsonb) as id', [items([kBook, 1])])).rows[0].id;
    current = (await asUser(db, kMember, 'select id from public.get_order_round()')).rows[0].id;
    [past] = (await rounds(db, kaist)).filter((r) => r.deadline <= new Date()).map((r) => r.id);
    assert.ok(past, '마감된 회차가 있어야 한다');
  });

  test('관리자는 신청 날짜와 상관없이 지난 회차로 옮길 수 있다', async () => {
    await asUser(db, kAdmin, 'select public.admin_move_textbook_order($1, $2)', [order, past]);
    const { rows } = await db.query(`
      select o.round_id, o.round_start = (r.starts_at at time zone 'Asia/Seoul')::date as synced
      from public.textbook_orders o join public.order_rounds r on r.id = o.round_id where o.id = $1`, [order]);
    assert.equal(rows[0].round_id, past);
    assert.equal(rows[0].synced, true, 'round_start 도 맞춰진다');
  });

  test('지난 회차로 옮긴 신청은 회원이 수정할 수 없고, 이번 회차로 되돌리면 다시 수정할 수 있다', async () => {
    await assertRaises(asUser(db, kMember, 'select public.cancel_textbook_order($1)', [order]), /마감/);
    await asUser(db, kAdmin, 'select public.admin_move_textbook_order($1, $2)', [order, current]);
    await asUser(db, kMember, 'select public.update_textbook_order($1, $2::jsonb)', [order, items([kBook, 2])]);
  });

  test('다른 캠퍼스 회차로는 옮길 수 없다', async () => {
    const snuRound = (await asUser(db, sMember, 'select id from public.get_order_round()')).rows[0].id;
    await assertRaises(asUser(db, kAdmin, 'select public.admin_move_textbook_order($1, $2)', [order, snuRound]), /같은 캠퍼스/);
    await assertRaises(asUser(db, central, 'select public.admin_move_textbook_order($1, $2)', [order, snuRound]), /같은 캠퍼스/);
  });

  test('회원 / 다른 캠퍼스 관리자는 옮길 수 없고, 직접 update 도 막힌다', async () => {
    await assertRaises(asUser(db, kMember, 'select public.admin_move_textbook_order($1, $2)', [order, past]), /찾을 수 없습니다/);
    await assertRaises(asUser(db, sAdmin, 'select public.admin_move_textbook_order($1, $2)', [order, past]), /찾을 수 없습니다/);
    await assertDenied(asUser(db, kAdmin, 'update public.textbook_orders set round_id = $2 where id = $1', [order, past]));
  });

  test('총괄 관리자는 옮길 수 있다', async () => {
    await asUser(db, central, 'select public.admin_move_textbook_order($1, $2)', [order, past]);
    await asUser(db, central, 'select public.admin_move_textbook_order($1, $2)', [order, current]);
  });
});

describe('다음 회차', () => {
  let campus;
  let admin;
  let member;
  let book;

  before(async () => {
    campus = await createCampus(db, { code: 'nx', name: '다음 회차' });
    admin = await createUser(db, { studentId: '20203333', role: 'campus_admin', campus: 'nx' });
    member = await createUser(db, { studentId: '20243333', campus: 'nx' });
    book = (await db.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재', 1000) returning id`, [campus],
    )).rows[0].id;
  });

  test('관리자는 다음 회차를 만든다: 이번 회차 마감 ~ 마감 + 7일, 다시 불러도 같은 회차', async () => {
    const cur = (await asUser(db, member, 'select id, deadline from public.get_order_round()')).rows[0];
    const next = (await asUser(db, admin, 'select * from public.admin_create_next_order_round($1)', [campus])).rows[0];
    assert.equal(next.starts_at.getTime(), cur.deadline.getTime());
    assert.equal(next.deadline - next.starts_at, 7 * 24 * 3600 * 1000);
    const again = (await asUser(db, admin, 'select id from public.admin_create_next_order_round($1)', [campus])).rows[0];
    assert.equal(again.id, next.id);
    assert.equal((await rounds(db, campus)).at(-1).id, next.id);

    // 다음 회차가 있어도 이번 회차는 그대로
    const still = (await asUser(db, member, 'select id from public.get_order_round()')).rows[0];
    assert.equal(still.id, cur.id);
  });

  test('회원 / 다른 캠퍼스 관리자는 다음 회차를 만들 수 없다', async () => {
    await assertRaises(asUser(db, member, 'select public.admin_create_next_order_round($1)', [campus]), /권한/);
    await assertRaises(asUser(db, kAdmin, 'select public.admin_create_next_order_round($1)', [campus]), /권한/);
  });

  test('다음 회차로 옮긴 신청은 회원이 수정 / 취소할 수 있고, 새 신청은 이번 회차에 들어간다', async () => {
    const order = (await asUser(db, member, 'select public.place_textbook_order($1::jsonb) as id', [items([book, 1])])).rows[0].id;
    const next = (await asUser(db, admin, 'select id from public.admin_create_next_order_round($1)', [campus])).rows[0].id;
    await asUser(db, admin, 'select public.admin_move_textbook_order($1, $2)', [order, next]);
    await asUser(db, member, 'select public.update_textbook_order($1, $2::jsonb)', [order, items([book, 3])]);

    const cur = (await asUser(db, member, 'select id from public.get_order_round()')).rows[0].id;
    const fresh = (await asUser(db, member, 'select public.place_textbook_order($1::jsonb) as id', [items([book, 1])])).rows[0].id;
    const { rows } = await db.query('select round_id from public.textbook_orders where id = $1', [fresh]);
    assert.equal(rows[0].round_id, cur);
  });

  test('이번 회차 마감을 바꾸면 다음 회차도 새 마감 ~ 새 마감 + 7일로 맞춰진다', async () => {
    const cur = (await asUser(db, member, 'select id from public.get_order_round()')).rows[0].id;
    await asUser(db, admin, `select public.admin_set_order_round_deadline($1, date_trunc('minute', now()) + interval '2 days')`, [cur]);
    const [current, next] = (await rounds(db, campus)).slice(-2);
    assert.equal(current.id, cur);
    assert.equal(next.starts_at.getTime(), current.deadline.getTime());
    assert.equal(next.deadline - next.starts_at, WEEK);
  });

  test('다음 회차의 마감은 아직 바꿀 수 없다', async () => {
    const next = (await asUser(db, admin, 'select id from public.admin_create_next_order_round($1)', [campus])).rows[0].id;
    await assertRaises(
      asUser(db, admin, `select public.admin_set_order_round_deadline($1, now() + interval '20 days')`, [next]),
      /시작된 뒤/,
    );
  });

  test('이번 회차가 마감되면 미리 만든 다음 회차가 이번 회차가 된다', async () => {
    const before = await rounds(db, campus);
    const [cur, next] = before.slice(-2);
    // 시간이 지난 상황: 두 회차를 1주 앞으로 당긴다. (서비스 롤)
    await db.query(`update public.order_rounds set starts_at = starts_at - interval '20 days', deadline = deadline - interval '20 days' where id = $1`, [cur.id]);
    await db.query(`update public.order_rounds set starts_at = starts_at - interval '20 days' where id = $1`, [next.id]);
    const now = (await asUser(db, member, 'select id from public.get_order_round()')).rows[0].id;
    assert.equal(now, next.id);
    assert.equal((await rounds(db, campus)).length, before.length, '새 회차를 만들지 않는다');
  });
});

describe('기존 데이터 이전', () => {
  test('주간 규칙대로 첫 신청 회차부터 이번 회차까지 만들고 기존 신청을 연결한다', async () => {
    const old = await createDbBefore(ROUNDS);
    const k = await campusId(old, 'kaist');
    await createCampus(old, { code: 'empty', name: '신청 없음' });
    const member = await createUser(old, { studentId: '20240001' });
    const { rows: [{ updated }] } = await old.query(`
      insert into public.textbook_orders (user_id, campus_id, round_start, updated_at)
      values ($1, $2, private.order_round_for(now()) - 21, '2026-01-01'),
             ($1, $2, private.order_round_for(now()), '2026-01-01')
      returning updated_at as updated`, [member, k]);

    await applyMigration(old, ROUNDS);

    const { rows } = await old.query(`
      select o.round_start, r.starts_at, r.deadline, o.updated_at,
             (r.starts_at at time zone 'Asia/Seoul')::date = o.round_start as same_day,
             to_char(r.starts_at at time zone 'Asia/Seoul', 'HH24:MI') as kst
      from public.textbook_orders o join public.order_rounds r on r.id = o.round_id
      order by o.round_start`);
    assert.equal(rows.length, 2);
    for (const r of rows) {
      assert.equal(r.same_day, true);
      assert.equal(r.kst, '09:00');
      assert.equal(r.updated_at.getTime(), updated.getTime(), 'updated_at 은 그대로');
    }

    const kRounds = await rounds(old, k);
    assert.equal(kRounds.length, 4, '3주 전 ~ 이번 회차');
    assert.ok(kRounds.at(-1).deadline > new Date());
    const empty = await rounds(old, await campusId(old, 'empty'));
    assert.equal(empty.length, 1, '신청이 없는 캠퍼스는 이번 회차만');
  });
});

describe('지난 회차 채우기', () => {
  test('캠퍼스마다 지난 1년 회차를 채우고, 기존 회차 / 신청은 그대로 둔다', async () => {
    const old = await createDbBefore(BACKFILL);
    const k = await campusId(old, 'kaist');
    const member = await createUser(old, { studentId: '20240001' });
    const book = (await old.query(
      `insert into public.textbooks (campus_id, title, price) values ($1, '교재', 1000) returning id`, [k],
    )).rows[0].id;
    const order = (await asUser(old, member, 'select public.place_textbook_order($1::jsonb) as id', [items([book, 1])])).rows[0].id;
    const before = await rounds(old, k);
    assert.equal(before.length, 1, '마이그레이션 전에는 이번 회차만');

    await applyMigration(old, BACKFILL);

    const after = await rounds(old, k);
    assert.equal(after.length, 53);
    assert.equal(after.at(-1).id, before[0].id);
    assertYearOfWeeks(after);
    const { rows } = await old.query('select round_id from public.textbook_orders where id = $1', [order]);
    assert.equal(rows[0].round_id, before[0].id);

    // 다시 채워도 늘어나지 않는다.
    await old.query('select private.backfill_order_rounds($1)', [k]);
    assert.equal((await rounds(old, k)).length, 53);
  });

  test('관리자는 신청이 없던 지난 회차로도 옮길 수 있다', async () => {
    const order = (await asUser(db, kMember, 'select public.place_textbook_order($1::jsonb) as id', [items([kBook, 1])])).rows[0].id;
    const [oldest] = await rounds(db, kaist);
    await asUser(db, kAdmin, 'select public.admin_move_textbook_order($1, $2)', [order, oldest.id]);
    const { rows } = await db.query('select round_id from public.textbook_orders where id = $1', [order]);
    assert.equal(rows[0].round_id, oldest.id);
  });
});
