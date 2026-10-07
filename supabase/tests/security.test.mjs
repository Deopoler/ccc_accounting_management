// RLS / 권한 우회 시도 + 스키마 전체 회귀 검사.
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import { asAnon, asUser, createDb, createUser } from './helpers.mjs';

async function assertDenied(promise) {
  await assert.rejects(promise, (e) => e.code === '42501' || /permission denied/.test(e.message));
}

let db;
let admin;
let alice;
let bob;
let pending;
let bookId;
let eventId;
let bobOrderId;

before(async () => {
  db = await createDb();
  admin = await createUser(db, { studentId: '20200001', name: '관리자', role: 'campus_admin' });
  alice = await createUser(db, { studentId: '20240001', name: '앨리스' });
  bob = await createUser(db, { studentId: '20240002', name: '밥' });
  pending = await createUser(db, { studentId: '20249999', approved: false });

  bookId = (await db.query(`insert into public.textbooks (campus_id, title, price) values ((select id from public.campuses where code = 'kaist'), '교재', 10000) returning id`)).rows[0].id;
  eventId = (await db.query(`insert into public.events (campus_id, title, amount) values ((select id from public.campuses where code = 'kaist'), '행사', 5000) returning id`)).rows[0].id;
  await db.query(
    `insert into public.event_payments (event_id, user_id) values ($1, $2), ($1, $3)`,
    [eventId, alice, bob],
  );
  const items = JSON.stringify([{ textbook_id: bookId, quantity: 1 }]);
  bobOrderId = (await asUser(db, bob, 'select public.place_textbook_order($1::jsonb) as id', [items])).rows[0].id;
});

// ---------------------------------------------------------------------------
// 스키마 전체 회귀 검사: 새 테이블/함수를 추가할 때 실수를 잡는다.
// ---------------------------------------------------------------------------
describe('스키마 회귀 검사', () => {
  test('public 스키마의 모든 테이블에 RLS 가 켜져 있다', async () => {
    const { rows } = await db.query(`
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
    assert.deepEqual(rows, []);
  });

  test('anon 에게 열린 테이블/뷰 권한이 없다', async () => {
    const { rows } = await db.query(`
      select table_name, privilege_type from information_schema.role_table_grants
      where grantee = 'anon' and table_schema = 'public'`);
    assert.deepEqual(rows, []);
  });

  test('anon 이 실행할 수 있는 함수는 캠퍼스 목록(로그인 화면용)뿐이다', async () => {
    const { rows } = await db.query(`
      select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'execute')`);
    assert.deepEqual(rows.map((r) => r.fn), ['public.list_campuses']);
  });

  test('authenticated 가 실행할 수 있는 함수는 허용 목록뿐이다', async () => {
    const { rows } = await db.query(`
      select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and has_function_privilege('authenticated', p.oid, 'execute')
      order by 1`);
    assert.deepEqual(rows.map((r) => r.fn), [
      'private.admin_campus_id',
      'private.is_approved_user',
      'private.is_central_admin',
      'private.my_campus_id',
      'public.admin_move_textbook_order',
      'public.admin_set_order_round_deadline',
      'public.admin_set_textbook_received',
      'public.cancel_textbook_order',
      'public.confirm_textbook_received',
      'public.get_order_round',
      'public.list_campuses',
      'public.place_textbook_order',
      'public.update_textbook_order',
    ]);
  });

  test('SECURITY DEFINER 함수는 모두 search_path 를 고정한다', async () => {
    const { rows } = await db.query(`
      select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private') and p.prosecdef
        and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')`);
    assert.deepEqual(rows, []);
  });

  test('뷰는 security_invoker 로 조회자의 RLS 를 따른다', async () => {
    const { rows } = await db.query(`
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'v'
        and not coalesce('security_invoker=true' = any(c.reloptions), false)`);
    assert.deepEqual(rows, []);
  });
});

// ---------------------------------------------------------------------------
// 회원이 시도할 수 있는 우회
// ---------------------------------------------------------------------------
describe('회원의 우회 시도', () => {
  test('주문 조회에 profiles 를 조인해도 다른 회원 정보가 새지 않는다', async () => {
    const { rows } = await asUser(db, alice, `
      select p.student_id from public.textbook_orders o join public.profiles p on p.id = o.user_id`);
    assert.ok(rows.every((r) => r.student_id === '20240001'));
  });

  test('다른 회원의 주문 id 로 품목을 조회할 수 없다', async () => {
    const { rows } = await asUser(db, alice, 'select * from public.textbook_order_items where order_id = $1', [bobOrderId]);
    assert.equal(rows.length, 0);
  });

  test('본인 주문도 직접 삭제할 수 없다 (RPC 취소만 가능)', async () => {
    const own = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [
      JSON.stringify([{ textbook_id: bookId, quantity: 1 }]),
    ])).rows[0].id;
    const r = await asUser(db, alice, 'delete from public.textbook_orders where id = $1', [own]);
    assert.equal(r.affectedRows, 0);
  });

  test('품목 가격/수량을 직접 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, alice, 'update public.textbook_order_items set unit_price = 0'));
    await assertDenied(asUser(db, alice, 'delete from public.textbook_order_items'));
  });

  test('upsert 로 교재 가격 / 계좌를 덮어쓸 수 없다', async () => {
    await assert.rejects(asUser(db, alice, `
      insert into public.textbooks (campus_id, title, price) values ((select id from public.campuses where code = 'kaist'), 'x', 0)`));
    await assert.rejects(asUser(db, alice, `
      insert into public.app_settings (key, value) values ('account_number', 'hacked')
      on conflict (key) do update set value = excluded.value`));
    const { rows } = await db.query(`select value from public.app_settings where key = 'account_number'`);
    assert.notEqual(rows[0].value, 'hacked');
  });

  test('이벤트 / 송금 행을 삭제할 수 없다', async () => {
    assert.equal((await asUser(db, alice, 'delete from public.events')).affectedRows, 0);
    assert.equal((await asUser(db, alice, 'delete from public.event_payments')).affectedRows, 0);
  });

  test('다른 회원의 송금 여부를 볼 수도, 바꿀 수도 없다', async () => {
    const { rows } = await asUser(db, alice, 'select * from public.event_payments where user_id = $1', [bob]);
    assert.equal(rows.length, 0);
    const r = await asUser(db, alice, 'update public.event_payments set is_paid = true where user_id = $1', [bob]);
    assert.equal(r.affectedRows, 0);
  });

  test('요약 뷰로 다른 회원의 송금 상태를 추론할 수 없다', async () => {
    await db.query('update public.event_payments set is_paid = true where user_id = $1', [bob]);
    const { rows } = await asUser(db, alice, 'select * from public.event_payment_summaries where event_id = $1', [eventId]);
    assert.equal(rows[0].target_count, 1);
    assert.equal(rows[0].paid_count, 0);
  });

  test('RPC 에 다른 회원 id 를 넘길 방법이 없다 (user_id 는 auth.uid() 로 고정)', async () => {
    const id = (await asUser(db, alice, 'select public.place_textbook_order($1::jsonb) as id', [
      JSON.stringify([{ textbook_id: bookId, quantity: 1, user_id: bob, unit_price: 0 }]),
    ])).rows[0].id;
    const { rows } = await db.query('select user_id, total_price from public.textbook_orders where id = $1', [id]);
    assert.equal(rows[0].user_id, alice);
    assert.equal(rows[0].total_price, 10000);
  });

  test('잘못된 JSON 으로 RPC 를 깨뜨려도 주문이 남지 않는다', async () => {
    const before = (await db.query('select count(*)::int as n from public.textbook_orders')).rows[0].n;
    await assert.rejects(asUser(db, alice, `select public.place_textbook_order('{"a":1}'::jsonb)`));
    await assert.rejects(asUser(db, alice, `select public.place_textbook_order('[{"textbook_id":"not-a-uuid","quantity":1}]'::jsonb)`));
    const after = (await db.query('select count(*)::int as n from public.textbook_orders')).rows[0].n;
    assert.equal(after, before);
  });

  test('관리자 판정 함수를 조작할 수 없다 (함수 재정의 권한 없음)', async () => {
    await assertDenied(asUser(db, alice, `
      create or replace function private.is_admin() returns boolean language sql as $$ select true $$`));
  });
});

// ---------------------------------------------------------------------------
// 승인 대기 / anon
// ---------------------------------------------------------------------------
describe('승인 대기 / anon', () => {
  test('승인 대기 사용자는 요약 뷰 / 회차 외 아무것도 볼 수 없다', async () => {
    for (const t of ['textbooks', 'events', 'event_payments', 'textbook_orders', 'app_settings', 'event_payment_summaries']) {
      const { rows } = await asUser(db, pending, `select * from public.${t}`);
      assert.equal(rows.length, 0, t);
    }
  });

  test('anon 은 회차 조회 RPC 도 호출할 수 없다', async () => {
    await assertDenied(asAnon(db, 'select * from public.get_order_round()'));
  });
});

// ---------------------------------------------------------------------------
// 관리자도 할 수 없는 것
// ---------------------------------------------------------------------------
describe('관리자 제한', () => {
  test('주문 금액 / 회차 / 소유자는 관리자도 바꿀 수 없다', async () => {
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set total_price = 0'));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set round_start = current_date'));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set round_id = gen_random_uuid()'));
    await assertDenied(asUser(db, admin, 'update public.textbook_orders set user_id = $1', [admin]));
  });

  test('관리자도 주문을 직접 만들 수 없다 (RPC 로만)', async () => {
    await assertDenied(asUser(db, admin, `
      insert into public.textbook_orders (user_id, round_start) values ($1, current_date)`, [alice]));
  });

  test('관리자도 profiles 를 직접 만들거나 지울 수 없다 (Edge Function 으로만)', async () => {
    await assertDenied(asUser(db, admin, `insert into public.profiles (id, student_id, name) values (gen_random_uuid(), '11112222', 'x')`));
    await assertDenied(asUser(db, admin, 'delete from public.profiles where id = $1', [pending]));
  });
});
