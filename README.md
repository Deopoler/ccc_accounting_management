# CCC 회계 관리 시스템

동아리(CCC) 회계 업무용 웹앱. 여러 캠퍼스가 함께 쓴다. 회원은 교재를 신청하고 이벤트 송금 여부를 확인하며,
캠퍼스 관리자는 자기 캠퍼스의 가입 승인·입금 확인·송금 현황을, 총괄 관리자는 모든 캠퍼스를 관리한다.

- 접속: <https://deopoler.github.io/ccc_accounting_management/>
- [기능 소개](docs/기능소개.md) · [사용법](docs/사용법.md) (화면 사진 포함)

- Flutter Web (Material 3, 반응형) + Riverpod + go_router
- Supabase (Auth + Postgres + RLS + Edge Functions)
- 로그인은 **캠퍼스 / 학번 / 비밀번호**. 내부적으로 가상 이메일로 Supabase Auth 를 사용한다.
  KAIST 는 `{학번}@ccc.local`, 다른 캠퍼스는 `{학번}@{캠퍼스 코드}.ccc.local`.

## 기능

| 회원 | 관리자 |
| --- | --- |
| 가입 (관리자 승인 후 이용) | 가입 승인 / 거절, 관리자 지정, 비밀번호 초기화 |
| 홈: 내 교재 신청·이벤트 송금 요약 | 교재 카테고리(추가·이름·순서·삭제), 교재 등록 / 수정 / 순서 / 신청 가능 여부 |
| 교재 신청: 카테고리 → 교재 선택(교재명 검색), 주간 회차, 완료 시 송금 계좌 안내·복사 | 교재 신청 현황: 회차·교재·상태·검색 필터, 입금확인, 교재별 집계, CSV |
| 내 신청 내역: 이번 회차 신청은 수정·취소 | 이벤트 등록 / 수정 / 삭제, 입금자명 지정, 송금 대상 지정(전체 선택), 개인별 금액 조정 |
| 이벤트별 내 송금 여부와 송금 안내(금액·계좌·입금자명 복사) | 이벤트별 송금률·수금액, 송금 토글, 미납자 복사·CSV |
| 비밀번호 변경 | 송금 계좌 설정 (캠퍼스별) |

총괄 관리자는 위 관리자 기능을 **모든 캠퍼스**에서 쓰고(캠퍼스 전환), 캠퍼스 추가·이름 변경, 총괄 관리자 지정을 한다.

## 폴더 구조

```text
lib/
  core/        config(환경변수) · router(가드) · theme · utils · 공통 위젯(셸, 로딩/에러/빈 상태)
  features/
    auth/      로그인 · 가입 · 승인 대기 · 비밀번호 변경 · 세션/프로필
    home/      대시보드
    textbooks/ 교재 신청 (회원)
    events/    이벤트 송금 현황 (회원)
    admin/     회원 · 교재 · 신청 현황 · 이벤트 관리, CSV
    settings/  송금 계좌 등 앱 설정
    (각 feature 는 data / domain / presentation 으로 분리)
supabase/
  migrations/          스키마 + RLS 마이그레이션 SQL (이름 순서대로 적용)
  functions/           Edge Functions (admin-members: 비밀번호 초기화 / 가입 거절)
  bootstrap_admin.sql  최초 관리자 지정 SQL
  tests/               PGlite 기반 RLS/권한 테스트 (Node)
assets/fonts/          Pretendard (현대 한글 11,172자 전체, 보통·굵게) + 라이선스(OFL)
tool/fonts/            폰트 생성 스크립트
test/                  Flutter 단위 / 반응형 레이아웃 테스트
```

## 1. 개발 환경

- Flutter stable (3.47 이상), Chrome
- Node.js 20 이상 (DB 테스트, Supabase CLI)

```sh
flutter pub get
npm install        # 선택: 루트 package.json 의 Supabase CLI (npx supabase 로 실행)
```

## 2. Supabase 설정

### 2-1. 프로젝트 생성

[supabase.com](https://supabase.com) 에서 새 프로젝트를 만든다. (Region: Northeast Asia (Seoul) 권장)

### 2-2. Auth 설정 (중요)

Dashboard > **Authentication** 에서

| 설정 | 값 | 이유 |
| --- | --- | --- |
| Allow new users to sign up | **켬** | 회원이 앱에서 직접 가입한다. 가입만으로는 아무 데이터도 볼 수 없고 관리자 승인이 필요하다. |
| Email provider | 켬 | 학번을 가상 이메일로 매핑해 사용 |
| Confirm email | **끔** | `@ccc.local` 은 가상 이메일이라 확인 메일을 받을 수 없다. 켜 두면 가입 후 로그인이 안 된다. |
| Minimum password length | 8 | 앱의 비밀번호 규칙과 맞춤 |

### 2-3. 스키마 / RLS 적용

평소에는 **CI 가 자동으로 적용**한다. ([5. 배포](#5-배포-github-pages), [3-1 테스트 서버](#3-1-테스트-서버-staging))
새 프로젝트를 처음 만들 때만 아래처럼 직접 적용한다.

**SQL Editor**: [supabase/migrations/](supabase/migrations/) 의 파일을 **이름 순서대로** 하나씩 붙여넣고 실행한다.
SQL Editor 로 적용했다면 CI 를 쓰기 전에 [적용 이력 맞추기](#적용-이력-맞추기-sql-editor-로-적용해-온-db)를 한다.

1. `20260929000000_init.sql` — 스키마 / RLS / 교재 신청 RPC
2. `20260930000000_self_signup_approval.sql` — 자유 가입 + 관리자 승인
3. `20261001000000_manual_event_targets.sql` — 이벤트 대상 자동 등록 제거
4. `20261002000000_event_payment_amount.sql` — 이벤트 개인별 금액
5. `20261003000000_event_deposit_name.sql` — 이벤트 입금자명
6. `20261004000000_textbook_categories.sql` — 교재 카테고리
7. `20261005000000_textbook_sort_order.sql` — 교재 순서
8. `20261006000000_order_round_wed_9am.sql` — 신청 마감을 수요일 오전 9시로
9. `20261007000000_order_delivery.sql` — 교재 배송 / 수령 확인
10. `20261008000000_admin_order_received.sql` — 관리자 수령 처리 / 확인자 기록
11. `20261009000000_campuses.sql` — 캠퍼스 / 역할(회원·캠퍼스 관리자·총괄 관리자) / 캠퍼스별 RLS.
    회원이 있는 DB 에서는 학번 20250133(KAIST) 계정이 있어야 적용된다.
12. `20261010000000_revoke_rls_auto_enable.sql` — Supabase 가 만든 함수의 실행 권한 회수
13. `20261011000000_order_rounds.sql` — 캠퍼스별 신청 회차, 관리자 마감 일시 변경 / 신청 회차 이동
14. `20261012000000_order_rounds_next.sql` — 신청을 다음 회차로 옮기기
15. `20261013000000_order_rounds_backfill.sql` — 신청이 없어도 지난 1년 회차를 만들어 둔다
16. `20261014000000_purge_old_data.sql` — 1년 지난 회차 / 교재 신청 / 이벤트 자동 삭제

**또는 CLI** (접속 문자열은 [CLI 로 적용할 때](#cli-로-적용할-때) 참고):

```sh
npx supabase db push --db-url "<Session pooler 접속 문자열>"
```

### 2-4. Edge Function (비밀번호 초기화 / 가입 거절)

[supabase/functions/admin-members/index.ts](supabase/functions/admin-members/index.ts) 를 배포하고 기본 비밀번호를 secret 으로 설정한다.
호출자의 토큰과 관리자 여부는 함수 안에서 직접 검증하므로 JWT 검증을 끈다. ([supabase/config.toml](supabase/config.toml) 의 `verify_jwt = false`)
배포는 평소 CI 가 한다. `DEFAULT_PASSWORD` 만 프로젝트마다 한 번 설정한다.

```sh
npx supabase login
npx supabase secrets set DEFAULT_PASSWORD='영문숫자8자이상' --project-ref <프로젝트 ref>
npx supabase functions deploy admin-members --project-ref <프로젝트 ref>   # 직접 배포할 때만
```

CLI 없이: Dashboard > **Edge Functions** > Deploy a new function > Via Editor 에서 이름을 `admin-members` 로 하고
index.ts 내용을 붙여넣어 배포한 뒤, 함수 설정에서 **Verify JWT** 를 끄고 **Edge Functions > Secrets** 에 `DEFAULT_PASSWORD` 를 추가한다.

### 2-5. 앱에 접속 정보 주입

- **Project URL**: 프로젝트 상단 **Connect** 버튼, 또는 Project Settings > **Data API**.
  대시보드 주소 `.../project/<ref>` 의 ref 로 `https://<ref>.supabase.co` 를 만들어도 된다.
- **publishable key**(`sb_publishable_...`, 구 anon key): Project Settings > **API Keys**

`env.example.json` 을 `env.json` 으로 복사한 뒤 채운다. `env.json` 은 git 에 올라가지 않는다.

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
}
```

> publishable 키는 브라우저에 노출되는 공개 키다. 실제 권한은 RLS 가 강제한다.
> **secret / service_role 키는 절대 앱이나 env.json 에 넣지 않는다.** (Edge Function 에서만 사용)

### 2-6. 최초 총괄 관리자 지정

1. 앱에서 **가입하기**로 본인 계정을 만든다. (승인 대기 화면이 나오면 정상)
2. [supabase/bootstrap_admin.sql](supabase/bootstrap_admin.sql) 의 학번 / 캠퍼스를 바꿔 SQL Editor 에서 실행
3. 승인 대기 화면에서 **승인 여부 다시 확인**

이후 캠퍼스 추가, 캠퍼스 관리자 지정은 앱에서 한다. ([6. 관리자 운영 가이드](#6-관리자-운영-가이드))

## 3. 실행

```sh
flutter run -d chrome --dart-define-from-file=env.json           # 운영 서버
flutter run -d chrome --dart-define-from-file=env.staging.json   # 테스트 서버
```

### 3-1. 테스트 서버 (staging)

운영 데이터와 분리된 Supabase 프로젝트를 하나 더 두고, **DB 변경과 새 기능은 테스트 서버에서 먼저 확인**한다.

| | 운영 | 테스트 서버 |
| --- | --- | --- |
| Supabase 프로젝트 | 기존 프로젝트 | 별도 프로젝트 (무료 플랜 조직당 2개) |
| 접속 정보 | `env.json` | `env.staging.json` (`APP_ENV: staging`) |
| 앱 | GitHub Pages | 로컬 실행 (`flutter run`) |
| 화면 표시 | 없음 | 오른쪽 위 주황색 **테스트 서버** 띠 |

#### 만들기 (최초 1회)

1. Supabase 에서 새 프로젝트를 만들고 [2-2 Auth 설정](#2-2-auth-설정-중요)을 운영과 똑같이 한다.
2. `DEFAULT_PASSWORD` 를 설정한다. (2-4, `--project-ref` 만 테스트 서버 것으로)
3. 저장소 Secrets 에 `STAGING_DB_URL`, `STAGING_PROJECT_REF` 를 넣는다. ([5. 배포](#5-배포-github-pages) 표 참고)
   이후 `feature/**` 브랜치에 push 하면 마이그레이션 / Edge Function 이 테스트 서버에 적용된다.
4. `env.staging.example.json` 을 `env.staging.json` 으로 복사해 테스트 서버의 URL / publishable 키를 넣는다.
5. 테스트 서버로 앱을 띄워 관리자 / 회원 테스트 계정을 가입시키고, 2-6 처럼 관리자를 지정한다.

#### 작업 순서

1. `feature/<이름>` 브랜치에서 작업한다. 마이그레이션을 추가하면 `supabase/tests` 에서 `npm test`
2. 브랜치에 push → CI([staging.yml](.github/workflows/staging.yml))가 테스트 후 **테스트 서버**에
   마이그레이션 / Edge Function 을 적용한다. `env.staging.json` 으로 앱을 띄워 확인한다.
3. `main` 에 merge → CI([deploy-pages.yml](.github/workflows/deploy-pages.yml))가 테스트 후 **운영**에
   마이그레이션 / Edge Function 을 적용하고, 그다음 앱을 배포한다.

> **`main` 에 merge 하는 순간 운영 DB 가 바뀐다.** 앱이 준비되지 않은 DB 변경은 `main` 에 넣지 않는다.
> 적용된 마이그레이션 파일은 고치지 말고 새 마이그레이션을 추가한다. (CI 는 이미 적용된 버전을 다시 실행하지 않는다)

#### CLI 로 적용할 때

두 프로젝트를 오가므로 `link` 대신 대상을 매번 명시한다.

```sh
npx supabase migration list --db-url "postgresql://postgres.<ref>:<DB 비밀번호>@<pooler 호스트>:5432/postgres"
```

- 접속 문자열: Dashboard 상단 **Connect** > Connection String > **Session pooler** (5432).
  Direct connection 은 IPv6 전용이라 GitHub Actions 에서 접속되지 않을 수 있고, Transaction pooler(6543)는 마이그레이션에 맞지 않는다.
- DB 비밀번호는 프로젝트를 만들 때 정한 것. Project Settings > Database 에서 재설정할 수 있다. (앱은 API 키를 쓰므로 영향 없음)
  특수문자는 URL 인코딩해야 하므로 영문 / 숫자로 된 비밀번호가 편하다.
- PowerShell 에서는 여러 줄 명령의 `\` 를 쓸 수 없으니 한 줄로 실행하고, 비밀번호에 `$` 가 있으면 작은따옴표로 감싼다.

#### 적용 이력 맞추기 (SQL Editor 로 적용해 온 DB)

CLI 는 `supabase_migrations.schema_migrations` 의 이력으로 적용 여부를 판단한다. SQL Editor 로만 적용한 DB 는 이력이 비어 있어
CI 가 전부 다시 적용하려다 실패하므로, 이미 적용된 버전을 한 번 표시한다. (스키마는 바꾸지 않는다)

```sh
npx supabase migration repair --status applied <적용된 버전들...> --db-url "<접속 문자열>"
```

## 4. 테스트

```sh
flutter analyze
flutter test                      # 단위 테스트 + 반응형 레이아웃 테스트

cd supabase/tests && npm install && npm test   # DB (RLS / 권한 / RPC / 트리거)
```

| 테스트 | 내용 |
| --- | --- |
| `test/auth_guard_test.dart` | 로그인 / 승인 대기 / 비밀번호 변경 / 역할별 라우팅, open redirect 방지 |
| `test/textbook_order_test.dart`, `event_test.dart`, `textbook_category_test.dart` | 회차, 수정 가능 여부, 집계, 필터, D-day, 정렬, 입금자명, 카테고리 묶기 |
| `test/csv_exports_test.dart` | CSV 행 구성, BOM, 수식 주입 방지 |
| `test/responsive_test.dart` | 모든 화면을 320 / 360 / 840 / 1280px (다크 테마 포함)로 렌더링해 overflow 등 레이아웃 오류 검사, 실제 라우터로 카테고리 이동 시 선택 수량 유지 검사 |
| `supabase/tests/rls.test.mjs` | 역할별 조회 / 수정 권한, 교재 신청 RPC, 송금 기록 트리거 |
| `supabase/tests/order_rounds.test.mjs` | 캠퍼스별 회차 자동 생성, 마감 일시 변경, 신청 회차 이동, 기존 데이터 이전 |
| `supabase/tests/signup.test.mjs` | 가입 트리거, 승인 전 차단, 승인 / 관리자 권한 |
| `supabase/tests/security.test.mjs` | 우회 시도 + **스키마 회귀 검사** (RLS 누락, anon 권한, 함수 실행 권한 허용 목록, SECURITY DEFINER search_path, 뷰 security_invoker) |

DB 테스트는 실제 Supabase 없이 PGlite(WASM Postgres)에 Supabase 의 `auth` 스키마와 롤을 흉내 내어 마이그레이션을 적용한 뒤,
`authenticated` / `anon` 롤로 SQL 을 실행해 검증한다. **마이그레이션을 추가하면 반드시 `npm test` 를 실행한다.**

## 5. 배포 (GitHub Pages)

[.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml) 이 `main` 에 push 될 때마다
**테스트(analyze · flutter test · DB 권한 테스트) → 운영 DB 마이그레이션 / Edge Function → 웹 빌드 → Pages 배포**를 한다.
테스트가 실패하면 DB 도 바꾸지 않고 배포하지 않는다. 새 앱이 새 컬럼을 조회하므로 DB 를 먼저 바꾼다.

### 최초 1회 설정

1. GitHub 에 저장소를 만들고 이 프로젝트를 push 한다.
   무료 플랜에서 Pages 는 **public 저장소**만 가능하다. (코드에 비밀값은 없다: `env.json` 은 커밋되지 않고, publishable 키는 공개 키다)
2. 저장소 **Settings > Secrets and variables > Actions > New repository secret**

   | Secret | 값 | 용도 |
   | --- | --- | --- |
   | `SUPABASE_URL` | `https://<운영 ref>.supabase.co` | 앱 빌드 |
   | `SUPABASE_PUBLISHABLE_KEY` | 운영 `sb_publishable_...` | 앱 빌드 |
   | `PROD_DB_URL` / `STAGING_DB_URL` | 각 프로젝트 Session pooler 접속 문자열 (DB 비밀번호 포함) | 마이그레이션 적용 |
   | `PROD_PROJECT_REF` / `STAGING_PROJECT_REF` | 각 프로젝트 ref | Edge Function 배포 대상 |
   | `SUPABASE_ACCESS_TOKEN` | Supabase 계정 > Access Tokens (`sbp_...`). 가능하면 두 프로젝트의 Edge Functions 배포 권한만 | Edge Function 배포 |

   선택: **Settings > Environments** 에 `production` 을 만들고 **Required reviewers** 를 지정하면
   운영 DB 를 바꾸기 전에 Actions 화면에서 승인을 기다린다.
3. 저장소 **Settings > Pages > Build and deployment > Source** 를 **GitHub Actions** 로 선택
4. **Actions** 탭에서 워크플로가 끝나면 주소가 나온다: `https://<아이디>.github.io/<저장소>/`
5. Supabase Dashboard > Authentication > **URL Configuration** 의 Site URL 을 위 주소로 바꾼다.

### 동작 방식

- 저장소 이름으로 `--base-href /<저장소>/` 를 자동 설정한다. (`<아이디>.github.io` 저장소면 `/`)
- GitHub Pages 에는 SPA rewrite 가 없어서 `/home` 등에서 새로고침하면 404 가 된다.
  빌드 결과의 `index.html` 을 `404.html` 로 복사해, 없는 경로에서도 같은 앱이 뜨고 라우터가 화면을 연다.
- 로컬에서 같은 결과물 만들기 (Git Bash 는 경로 자동 변환을 꺼야 한다):

```sh
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /<저장소>/ --dart-define-from-file=env.json
cp build/web/index.html build/web/404.html
```

## 6. 관리자 운영 가이드

- **가입 승인**: 관리자 > 회원 관리 > 승인 대기. 학번·이름이 실제 회원과 맞는지 확인 후 승인. 잘못된 가입은 **거절**(계정 삭제, 재가입 가능).
- **비밀번호 분실**: 회원 관리 > ⋮ > **비밀번호 초기화** → 회원에게 기본 비밀번호를 직접 전달. 다음 로그인 때 새 비밀번호로 변경이 강제된다.
- **캠퍼스 관리자 추가**: 회원 관리 > ⋮ > **캠퍼스 관리자로 지정**. 캠퍼스 관리자도 자기 캠퍼스 회원을 지정할 수 있다.
  캠퍼스의 마지막 관리자는 해제할 수 없다. (총괄 관리자는 가능)
- **교재 입금 확인**: 교재 신청 현황에서 회차를 고르고 **입금확인** 체크. 입금확인된 신청은 회원이 수정·취소할 수 없다.
- **이벤트**: 이벤트 추가(입금자명 형식 지정) → 이벤트 화면에서 **대상 추가 > 회원 전체 선택** → 금액이 다른 회원은 ⋮ > **금액 변경** → 송금이 확인되면 스위치를 켠다.
- **송금 계좌 / 기본 비밀번호**: 계좌는 관리자 > 설정 (캠퍼스별). 기본 비밀번호는 Supabase Dashboard > Edge Functions > Secrets 의 `DEFAULT_PASSWORD`.

### 총괄 관리자

- **캠퍼스 전환**: 사이드 메뉴(모바일은 관리 탭) 위의 **관리 중인 캠퍼스**. 관리자 화면만 바뀌고 제목에 캠퍼스가 붙는다.
  회원 화면(교재 신청, 이벤트, 입금 안내)은 본인 캠퍼스 그대로다.
- **캠퍼스 추가**: 관리자 > 캠퍼스 관리 > 캠퍼스 추가. 이름과 영문 코드(예: `snu`)를 정한다.
  코드는 그 캠퍼스 회원의 로그인 아이디(`학번@snu.ccc.local`)에 쓰이므로 **바꿀 수 없다**. 이름은 바꿀 수 있다.
- **새 캠퍼스 시작**: 캠퍼스 추가 → 그 캠퍼스 담당자가 앱에서 캠퍼스를 골라 가입 → 캠퍼스 관리 > **이 캠퍼스 관리하기** →
  회원 관리에서 승인하고 **캠퍼스 관리자로 지정** → 이후 교재 / 이벤트 / 계좌는 캠퍼스 관리자가 관리한다.
- **총괄 관리자 지정 / 해제**: 회원 관리 > ⋮. 해제하면 캠퍼스 관리자로 남는다. 마지막 총괄 관리자는 해제할 수 없다.

## 인증 흐름

- 로그인: 캠퍼스(로그인 전 `list_campuses` 로 목록) + 학번 → `{학번 소문자}@{캠퍼스 이메일 도메인}` 으로 Supabase Auth 로그인.
  캠퍼스가 하나면 선택 칸 없이 자동 선택하고, 마지막으로 쓴 캠퍼스를 브라우저에 기억한다.
- 가입: `/signup` 에서 캠퍼스·학번·이름·비밀번호 → `signUp`. DB 트리거가 프로필을 **승인 대기**로 만든다.
  학번과 캠퍼스는 가입 이메일에서 서버가 정하고 role 은 항상 member 다. (user_metadata 는 사용자가 조작할 수 있으므로 이름만 사용)
- 라우터 가드 ([lib/core/router/auth_guard.dart](lib/core/router/auth_guard.dart))
  1. 로그인 안 됨 → `/login?from=<원래 경로>` (`/signup` 은 허용)
  2. 프로필 로딩 중 / 프로필 없음 → `/loading`
  3. 가입 승인 전 → `/pending` 외 모든 화면 차단
  4. `must_change_password` (관리자 비밀번호 초기화 후) → `/change-password` 외 모든 화면 차단
  5. member 가 `/admin/**` 접근 → `/home`, 총괄 관리자가 아닌데 `/admin/campuses` 접근 → `/admin`
- 비밀번호 변경: 현재 비밀번호로 재인증 후 변경. 비밀번호가 실제로 바뀌면 DB 트리거가 `must_change_password` 를 해제한다.
- 역할 체크는 화면 표시용이다. 데이터 권한은 RLS 가 강제한다.

## 권한 모델

- 모든 테이블 RLS ON, `anon` 은 모든 테이블/함수 접근 불가. `private` 스키마는 API 에 노출되지 않는다.
- 모든 사용자의 Postgres 롤은 `authenticated` 이다. 역할 / 캠퍼스 구분은 RLS 정책의
  `private.my_campus_id()` (승인된 사용자의 캠퍼스), `private.admin_campus_id()` (캠퍼스 관리자의 캠퍼스),
  `private.is_central_admin()` 으로 한다. 캠퍼스 관리자는 자기 캠퍼스, 총괄 관리자는 전체를 다룬다.
- 캠퍼스가 섞이지 않게 DB 가 막는다: 다른 캠퍼스 교재 신청(RPC), 다른 캠퍼스 카테고리(복합 FK),
  다른 캠퍼스 회원을 송금 대상으로 지정(트리거). 교재 / 이벤트는 다른 캠퍼스로 옮길 수 없다.
- 총괄 관리자 지정 / 해제, 회원의 캠퍼스 이동은 총괄 관리자만 한다. (트리거)
- 컬럼 권한(GRANT)으로 **관리자도 클라이언트에서 바꿀 수 없는 컬럼**을 막는다.
  - `profiles.id / student_id / created_at`, `textbook_orders.total_price / user_id / round_start`,
    `textbook_order_items.*`, `event_payments.paid_at / confirmed_by`
- 교재 신청/수정/취소는 RPC(`place_textbook_order`, `update_textbook_order`, `cancel_textbook_order`)로만 가능하다.
  주문자는 `auth.uid()`, 가격은 교재 테이블에서 서버가 계산한다.
- `must_change_password` 는 클라이언트가 바꿀 수 없고, 비밀번호가 실제로 바뀔 때만 트리거가 해제한다. (강제 변경 우회 불가)
- 로그인 아이디(이메일 = 학번)는 트리거로 변경을 막는다. (남의 학번 선점 방지)
- 비밀번호 초기화 / 가입 거절은 Edge Function(service role)에서 호출자가 **승인된 관리자**이고 대상이 자기 캠퍼스 회원인지
  (총괄 관리자는 전체) 검증 후 수행한다. 총괄 관리자 계정은 총괄 관리자만 다룬다.
  본인 계정은 대상이 될 수 없고, 승인된 회원은 삭제하지 않는다. (회계 기록 보존)

| 테이블 | 승인 대기 | member | campus_admin (자기 캠퍼스) | central_admin |
| --- | --- | --- | --- | --- |
| campuses | - | 자기 캠퍼스 조회 | 자기 캠퍼스 이름 / 계좌 수정 | 전체, 추가 / 삭제 |
| profiles | 본인 조회 | 본인 조회 | 조회, 이름 / 승인 / 캠퍼스 관리자 지정 | 전체, 총괄 관리자 지정, 캠퍼스 이동 |
| textbooks / textbook_categories | - | 자기 캠퍼스 조회 | CRUD | 전체 CRUD |
| textbook_orders / items | - | 본인 조회, RPC 로 신청·수정·취소 | 조회, 상태 / 배송 / 수령 처리, 삭제 | 전체 |
| events | - | 자기 캠퍼스 조회 | CRUD | 전체 CRUD |
| event_payments | - | 본인 조회 | 조회, 송금 여부 토글, 개인별 금액, 대상 추가/제외 | 전체 |
| app_settings (이전 앱 호환) | - | 조회 | - | 수정 |

로그인 전(`anon`)에는 `list_campuses()` (캠퍼스 이름 / 코드 / 로그인 도메인)만 호출할 수 있다.

> 새 테이블을 추가하는 마이그레이션에서는 Supabase 기본 권한 때문에 `anon`, `authenticated` 에
> 모든 권한이 자동으로 부여된다. 반드시 RLS 를 켜고 권한을 회수한 뒤 필요한 것만 다시 GRANT 한다.
> (`security.test.mjs` 의 회귀 검사가 이를 잡아낸다)

## 보안 점검 결과 (7단계)

| 항목 | 결과 |
| --- | --- |
| DB 권한 테스트 (PGlite) | 84개 통과. 회원·승인 대기·anon·관리자 각각의 우회 시도 포함 |
| 회귀 검사의 유효성 | RLS 없는 테이블 / anon 권한 / 허용되지 않은 함수 / search_path 없는 definer 함수를 일부러 만들어 모두 검출됨을 확인 |
| 실제 프로젝트 (anon 키) | 모든 테이블·뷰 42501 거부, `private` 스키마 미노출, 외부 도메인·`role: admin` 가입 시도 트리거에서 거부, Edge Function 토큰 없이 401 |
| 반응형 | 17개 화면 × 4개 크기 레이아웃 오류 없음. 점검 중 사이드 메뉴 선택 배경이 가려지던 문제, 320px 교재 카드 overflow 수정 |

남은 위험과 대응:

- **학번 사칭 가입**: 누구나 남의 학번으로 먼저 가입을 시도할 수 있다. 승인 전에는 아무것도 볼 수 없으므로 관리자가 승인 시 본인 확인을 하고, 잘못된 가입은 거절한다.
- **publishable 키 노출**: 설계상 공개 키다. 모든 권한은 RLS / RPC / Edge Function 에서 서버가 판단한다.

## 디자인

토스 앱의 스타일 **원칙**을 참고했다. (토스 자산은 사용하지 않는다)
색·폰트·둥글기는 [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart) 한 곳에서 관리하고, 화면에서는 `context.colors`(AppColors) / `AppRadius` 만 쓴다.

| 토큰 | 라이트 | 다크 | 용도 |
| --- | --- | --- | --- |
| primary | `#0064FF` | `#3D8BFF` | 유일한 강조색. 주요 버튼, 해야 할 일(미납·입금 대기·승인 대기) |
| textPrimary | `#191F28` | `#ECEEF1` | 본문 |
| textSecondary | `#8B95A1` | `#8B95A1` | 보조 글자 |
| background | `#FFFFFF` | `#111217` | 화면 배경 |
| surfaceMuted | `#F2F4F6` | `#1E2027` | 카드, 구분 영역, 입력칸 |
| error | `#F04452` | `#FF6B75` | 오류와 삭제 같은 위험 동작에만 |

- **둥글기** 12(입력칸·버튼) / 16(카드·다이얼로그), **그림자 없음**(면 색과 얇은 구분선으로 구분)
- **금액**은 `AmountText` 로 크고 굵게 (17 / 22 / 28)
- **화면당 파란 버튼(FilledButton) 하나**. 보조 동작은 회색 버튼(OutlinedButton) 또는 글자 버튼(TextButton)
- **상태 배지**(`AppBadge`): 파랑 = 해야 할 일(미납, 신청=입금 대기), 회색 = 끝난 일(완납, 입금확인), 흐림 = 비활성(취소, 신청 불가)
- 다크 모드에서는 `#0064FF` 글자가 어두운 배경에서 읽기 어려워 같은 계열의 밝은 파랑을 쓴다.

### 다크 테마

- 내 정보 메뉴 > **화면 테마** 에서 시스템 설정 / 라이트 / 다크를 고른다. 선택은 브라우저에 저장되고,
  앱 시작 전에 읽어 첫 화면부터 적용한다. 첫 로딩 화면(index.html)도 기기가 다크 모드면 어둡게 나온다.
- 반응형 테스트가 모든 화면을 다크 테마로도 렌더링해 레이아웃 오류를 검사한다.

## 폰트

- UI 폰트는 앱에 포함한 **Pretendard** 다. 현대 한글 음절 **11,172자 전체**와 라틴, 자주 쓰는 기호가 들어 있어
  드문 글자(예: 똠, 햏, 뷁)도 네모(□)나 늦은 로딩 없이 바로 그려진다. 한자는 크기 때문에 넣지 않았다. (필요하면 브라우저 대체 폰트로 그려진다)
- 굵기는 보통(400)·굵게(700) 두 가지다. Flutter 웹은 등록된 폰트를 시작할 때 모두 받으므로 파일 수를 줄였다. (각 약 2.6MB)
  600 은 700 으로 그려진다.
- 원본 가변 폰트에서 굵기별로 필요한 글자만 추려 만든다. 다시 만들 때:

```sh
cd tool/fonts && npm install && npm run build   # 원본 자동 다운로드, 한글 누락 시 실패
```

- 라이선스: SIL Open Font License 1.1 ([assets/fonts/Pretendard-LICENSE.txt](assets/fonts/Pretendard-LICENSE.txt)), 앱의 라이선스 목록에도 등록된다.

## CSV 내보내기

- 교재 신청 현황: **신청 목록** / **교재별 집계** (화면의 회차·교재·상태·검색 필터가 적용된 결과)
- 이벤트 송금 현황: **미납자 CSV**
- UTF-8 BOM 을 붙여 Excel 에서 한글이 깨지지 않는다.
- 이름 등 사용자 입력값이 `= + - @` 로 시작하면 앞에 `'` 를 붙여 스프레드시트 수식 실행(CSV injection)을 막는다.

## 업무 규칙

### 교재 신청 회차

- 회차는 캠퍼스마다 `order_rounds` 에 저장된다. 회차는 빈틈없이 이어진다. (다음 회차 시작 = 이전 회차 마감)
  신청이 없어도 지난 1년(52주) 회차는 항상 있다.
- 용량 관리를 위해 캠퍼스에 새 회차가 만들어질 때(대략 매주) 그 캠퍼스의 **1년 지난 데이터를 지운다**.
  마감이 1년 넘게 지난 회차와 그 교재 신청, 마감일(없으면 만든 날)이 1년 넘게 지난 이벤트와 송금 기록.
- 기본은 매주 **수요일 오전 9시 (KST)** 마감. 관리자가 **설정**에서 이번 회차의 마감 일시를 바꿀 수 있고,
  다음 회차부터는 그 마감에서 1주일씩 이어진다. 이번 회차가 마감되면 서버가 다음 회차를 만든다.
- 주문은 신청 시점의 회차(`round_id`)에 속한다. 관리자는 신청 날짜와 상관없이 같은 캠퍼스의 다른 회차로 옮길 수 있다.
  다음 회차로 옮기면 그 회차를 미리 만든다. (`admin_create_next_order_round`, 이번 회차 마감 ~ + 7일. 이번 회차 마감을 바꾸면 함께 맞춰진다)
  (`round_start` 는 이전 앱 호환용으로 남아 있고 트리거가 회차 시작 날짜로 채운다)
- 회원은 **마감 전 회차**(이번 회차, 관리자가 옮긴 다음 회차)이고 상태가 **신청**인 본인 주문만 수정·취소할 수 있다.
  마감된 회차나 입금확인된 주문은 변경할 수 없다. (서버 RPC 에서 강제)
- 신청 시점의 교재 가격이 `unit_price` 로 저장된다.

### 교재 카테고리

- 관리자가 카테고리를 만들고 순서(↑↓)를 정한다. 카테고리 안의 교재 순서도 ↑↓로 정한다. (새 교재는 맨 뒤) 교재 추가·수정 창에서 카테고리를 고른다. 카테고리가 없으면 "기타".
- 회원은 카테고리 목록 → 카테고리 안의 교재 순으로 고른다. 주소는 `/textbooks?category=<id>`.
  여러 카테고리에서 고른 수량은 유지되며 하단 합계로 한 번에 신청한다. 카테고리 목록 화면에서 교재명 검색도 된다.
- 신청 가능한 교재가 없는 카테고리는 회원에게 보이지 않는다.
- 교재가 들어 있는 카테고리는 삭제할 수 없다. (교재를 다른 카테고리로 옮긴 뒤 삭제)

### 이벤트 송금 대상

- 송금 대상은 관리자가 이벤트 화면의 **대상 추가**에서 직접 고른다. ("회원 전체 선택" 지원)
- 이벤트 생성이나 회원 승인 시 자동 등록은 하지 않는다.
- 대상은 개별로 제외할 수 있다.
- **이벤트별 송금**: 회원은 미송금 이벤트마다 카드 안의 안내(금액·계좌·입금자명)대로 따로 송금한다. 여러 이벤트 합산 송금 안내는 하지 않는다.
- **입금자명**: 이벤트마다 관리자가 형식을 정한다. `{이름}`, `{학번}` 을 쓸 수 있고(예: `{이름}순여행` → `홍길동순여행`), 비우면 회원 이름.
  관리자 송금 현황과 미납자 CSV 에 회원별 입금자명이 나와 통장 내역과 대조할 수 있다.
- **개인별 금액**: 송금 현황의 회원 ⋮ > **금액 변경**으로 일부 회원의 금액만 바꿀 수 있다.
  비워 두면(= 기본 금액으로) 이벤트 금액을 따르며, 이벤트 금액을 나중에 바꿔도 조정된 회원의 금액은 유지된다.
  수금액·미수금·송금률 분모 금액, 회원의 미송금 합계, 미납자 CSV 모두 개인별 금액 기준이다.
