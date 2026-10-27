-- 로컬 테스트(PGlite)용 Supabase 환경 최소 재현.
-- 실제 Supabase 에 적용하지 않는다.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;

create table auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text unique,
  encrypted_password  text,
  raw_user_meta_data  jsonb not null default '{}'
);

-- Supabase 의 auth.uid() 와 동일하게 JWT sub 클레임을 읽는다.
create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Supabase 기본 권한 재현: public 스키마의 새 객체는 API 롤에 모두 GRANT 된다.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;

-- Vault: 이름으로 secret 을 꺼낸다. (실제는 암호화 저장된 뷰)
create schema vault;
create table vault.decrypted_secrets (
  name              text primary key,
  decrypted_secret  text not null
);

-- pg_net: 실제로 보내지 않고 요청을 기록만 한다.
create schema net;
create table net.requests (
  id       bigserial primary key,
  url      text not null,
  body     jsonb,
  headers  jsonb
);
create function net.http_post(
  url text,
  body jsonb default '{}',
  params jsonb default '{}',
  headers jsonb default '{"Content-Type": "application/json"}',
  timeout_milliseconds int default 5000
) returns bigint
language sql as $$
  insert into net.requests (url, body, headers) values (url, body, headers) returning id
$$;
