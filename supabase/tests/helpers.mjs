import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');

/** Supabase 스텁 + 모든 마이그레이션을 적용한 새 DB. */
export async function createDb() {
  const db = new PGlite();
  await db.exec(await readFile(join(here, 'supabase_stub.sql'), 'utf8'));
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    await db.exec(await readFile(join(migrationsDir, f), 'utf8'));
  }
  return db;
}

/**
 * 앱에서 가입(signUp)한 것처럼 auth 사용자를 만든다. 프로필은 DB 트리거가 만든다.
 * 기본으로 관리자 승인까지 처리한다.
 * @returns {Promise<string>} user id
 */
export async function createUser(
  db,
  { studentId, name = studentId, role = 'member', approved = true },
) {
  const id = await signUp(db, { email: `${studentId}@ccc.local`, name });
  if (role !== 'member' || approved) {
    await db.query(
      `update public.profiles set role = $2, is_approved = $3 where id = $1`,
      [id, role, approved],
    );
  }
  return id;
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
