import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');

const migrationFiles = async () =>
  (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();

/** Supabase 스텁 + 모든 마이그레이션을 적용한 새 DB. */
export async function createDb() {
  return createDbBefore(null);
}

/**
 * [version] 으로 시작하는 마이그레이션 직전까지 적용한 새 DB. (데이터 이전 검증용)
 * version 이 null 이면 전부 적용한다.
 */
export async function createDbBefore(version) {
  const db = new PGlite();
  await db.exec(await readFile(join(here, 'supabase_stub.sql'), 'utf8'));
  for (const f of await migrationFiles()) {
    if (version && f >= version) break;
    await db.exec(await readFile(join(migrationsDir, f), 'utf8'));
  }
  return db;
}

/** [version] 으로 시작하는 마이그레이션 하나를 적용한다. */
export async function applyMigration(db, version) {
  const f = (await migrationFiles()).find((name) => name.startsWith(version));
  if (!f) throw new Error(`마이그레이션 없음: ${version}`);
  await db.exec(await readFile(join(migrationsDir, f), 'utf8'));
}

/**
 * 앱에서 가입(signUp)한 것처럼 auth 사용자를 만든다. 프로필은 DB 트리거가 만든다.
 * 기본으로 관리자 승인까지 처리한다.
 * @returns {Promise<string>} user id
 */
export async function createUser(
  db,
  { studentId, name = studentId, role = 'member', approved = true, campus = 'kaist' },
) {
  const { rows: c } = await db.query('select email_domain from public.campuses where code = $1', [campus]);
  if (c.length === 0) throw new Error(`캠퍼스 없음: ${campus}`);
  const id = await signUp(db, { email: `${studentId}@${c[0].email_domain}`, name });
  if (role !== 'member' || approved) {
    await db.query(
      `update public.profiles set role = $2, is_approved = $3 where id = $1`,
      [id, role, approved],
    );
  }
  return id;
}

/** 캠퍼스를 만든다. (서비스 롤 / SQL Editor 로 만든 것과 같다) @returns {Promise<string>} campus id */
export async function createCampus(db, { code, name = code }) {
  const { rows } = await db.query(
    'insert into public.campuses (code, name) values ($1, $2) returning id',
    [code, name],
  );
  return rows[0].id;
}

/** 캠퍼스 코드 → id */
export async function campusId(db, code) {
  return (await db.query('select id from public.campuses where code = $1', [code])).rows[0].id;
}

/** GoTrue signUp 이 하는 auth.users insert. */
export async function signUp(db, { email, name }) {
  const { rows } = await db.query(
    `insert into auth.users (email, encrypted_password, raw_user_meta_data)
     values ($1, 'hash', $2) returning id`,
    [email, JSON.stringify(name === undefined ? {} : { name })],
  );
  return rows[0].id;
}

/**
 * [userId] 로 로그인한 `authenticated` 롤로 SQL 을 실행한다. userId 가 null 이면 `anon`.
 * 트랜잭션 안에서 실행되므로 실패해도 다른 테스트에 영향이 없다.
 */
export async function asUser(db, userId, sql, params = []) {
  return db.transaction(async (tx) => {
    if (userId) {
      await tx.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId]);
      await tx.exec('set local role authenticated');
    } else {
      await tx.exec('set local role anon');
    }
    return tx.query(sql, params);
  });
}

export const asAnon = (db, sql, params) => asUser(db, null, sql, params);
