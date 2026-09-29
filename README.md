# CCC 회계 관리 시스템

동아리(CCC) 회계 업무용 웹앱. 회원은 교재를 신청하고 이벤트 송금 여부를 확인하며, 회계 관리자는 가입 승인·입금 확인·송금 현황을 관리한다.

- Flutter Web (Material 3, 반응형) + Riverpod + go_router
- Supabase (Auth + Postgres + RLS + Edge Functions)
- 로그인은 **학번 / 비밀번호**. 내부적으로 `{학번}@ccc.local` 가상 이메일로 Supabase Auth 를 사용한다.

## 기능

| 회원 | 관리자 |
| --- | --- |
| 가입 (관리자 승인 후 이용) | 가입 승인 / 거절, 관리자 지정, 비밀번호 초기화 |
| 홈: 내 교재 신청·이벤트 송금 요약 | 교재 카테고리(추가·이름·순서·삭제), 교재 등록 / 수정 / 순서 / 신청 가능 여부 |
| 교재 신청: 카테고리 → 교재 선택(교재명 검색), 주간 회차, 완료 시 송금 계좌 안내·복사 | 교재 신청 현황: 회차·교재·상태·검색 필터, 입금확인, 교재별 집계, CSV |
| 내 신청 내역: 이번 회차 신청은 수정·취소 | 이벤트 등록 / 수정 / 삭제, 입금자명 지정, 송금 대상 지정(전체 선택), 개인별 금액 조정 |
| 이벤트별 내 송금 여부와 송금 안내(금액·계좌·입금자명 복사) | 이벤트별 송금률·수금액, 송금 토글, 미납자 복사·CSV |
| 비밀번호 변경 | 송금 계좌 설정 |

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

**SQL Editor**: [supabase/migrations/](supabase/migrations/) 의 파일을 **이름 순서대로** 하나씩 붙여넣고 실행한다.

1. `20260929000000_init.sql` — 스키마 / RLS / 교재 신청 RPC
2. `20260930000000_self_signup_approval.sql` — 자유 가입 + 관리자 승인
3. `20261001000000_manual_event_targets.sql` — 이벤트 대상 자동 등록 제거
4. `20261002000000_event_payment_amount.sql` — 이벤트 개인별 금액
5. `20261003000000_event_deposit_name.sql` — 이벤트 입금자명
6. `20261004000000_textbook_categories.sql` — 교재 카테고리
7. `20261005000000_textbook_sort_order.sql` — 교재 순서
8. `20261006000000_order_round_wed_9am.sql` — 신청 마감을 수요일 오전 9시로

**또는 CLI**:

```sh
npx supabase init          # supabase/config.toml 생성 (기존 migrations 유지)
npx supabase login
npx supabase link --project-ref <프로젝트 ref>
npx supabase db push
```

### 2-4. Edge Function (비밀번호 초기화 / 가입 거절)

[supabase/functions/admin-members/index.ts](supabase/functions/admin-members/index.ts) 를 배포하고 기본 비밀번호를 secret 으로 설정한다.
호출자의 토큰과 관리자 여부는 함수 안에서 직접 검증하므로 `--no-verify-jwt` 로 배포한다.

```sh
npx supabase login
npx supabase secrets set DEFAULT_PASSWORD='영문숫자8자이상' --project-ref <프로젝트 ref>
npx supabase functions deploy admin-members --no-verify-jwt --project-ref <프로젝트 ref>
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

### 2-6. 최초 관리자 지정

1. 앱에서 **가입하기**로 관리자 본인 계정을 만든다. (승인 대기 화면이 나오면 정상)
2. [supabase/bootstrap_admin.sql](supabase/bootstrap_admin.sql) 의 학번을 바꿔 SQL Editor 에서 실행
3. 승인 대기 화면에서 **승인 여부 다시 확인**

## 3. 실행

```sh
flutter run -d chrome --dart-define-from-file=env.json
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
| `supabase/tests/signup.test.mjs` | 가입 트리거, 승인 전 차단, 승인 / 관리자 권한 |
| `supabase/tests/security.test.mjs` | 우회 시도 + **스키마 회귀 검사** (RLS 누락, anon 권한, 함수 실행 권한 허용 목록, SECURITY DEFINER search_path, 뷰 security_invoker) |

DB 테스트는 실제 Supabase 없이 PGlite(WASM Postgres)에 Supabase 의 `auth` 스키마와 롤을 흉내 내어 마이그레이션을 적용한 뒤,
`authenticated` / `anon` 롤로 SQL 을 실행해 검증한다. **마이그레이션을 추가하면 반드시 `npm test` 를 실행한다.**

## 5. 배포 (GitHub Pages)

[.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml) 이 `main` 에 push 될 때마다
**테스트(analyze · flutter test · DB 권한 테스트) → 웹 빌드 → Pages 배포**를 한다. 테스트가 실패하면 배포하지 않는다.

### 최초 1회 설정

1. GitHub 에 저장소를 만들고 이 프로젝트를 push 한다.
   무료 플랜에서 Pages 는 **public 저장소**만 가능하다. (코드에 비밀값은 없다: `env.json` 은 커밋되지 않고, publishable 키는 공개 키다)
2. 저장소 **Settings > Secrets and variables > Actions > New repository secret**
   - `SUPABASE_URL` = `https://<ref>.supabase.co`
   - `SUPABASE_PUBLISHABLE_KEY` = `sb_publishable_...`
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
- **관리자 추가**: 회원 관리 > ⋮ > **관리자로 지정**. 마지막 관리자는 해제할 수 없다.
- **교재 입금 확인**: 교재 신청 현황에서 회차를 고르고 **입금확인** 체크. 입금확인된 신청은 회원이 수정·취소할 수 없다.
- **이벤트**: 이벤트 추가(입금자명 형식 지정) → 이벤트 화면에서 **대상 추가 > 회원 전체 선택** → 금액이 다른 회원은 ⋮ > **금액 변경** → 송금이 확인되면 스위치를 켠다.
- **송금 계좌 / 기본 비밀번호**: 계좌는 관리자 > 설정. 기본 비밀번호는 Supabase Dashboard > Edge Functions > Secrets 의 `DEFAULT_PASSWORD`.

## 인증 흐름

- 로그인: 학번 → `{학번 소문자}@ccc.local` 로 변환해 Supabase Auth 이메일/비밀번호 로그인.
- 가입: `/signup` 에서 학번·이름·비밀번호 → `signUp`. DB 트리거가 프로필을 **승인 대기**로 만든다.
  학번은 가입 이메일에서 추출하고 role 은 항상 member 다. (user_metadata 는 사용자가 조작할 수 있으므로 이름만 사용)
- 라우터 가드 ([lib/core/router/auth_guard.dart](lib/core/router/auth_guard.dart))
  1. 로그인 안 됨 → `/login?from=<원래 경로>` (`/signup` 은 허용)
  2. 프로필 로딩 중 / 프로필 없음 → `/loading`
  3. 가입 승인 전 → `/pending` 외 모든 화면 차단
  4. `must_change_password` (관리자 비밀번호 초기화 후) → `/change-password` 외 모든 화면 차단
  5. member 가 `/admin/**` 접근 → `/home`
- 비밀번호 변경: 현재 비밀번호로 재인증 후 변경. 비밀번호가 실제로 바뀌면 DB 트리거가 `must_change_password` 를 해제한다.
- 역할 체크는 화면 표시용이다. 데이터 권한은 RLS 가 강제한다.

## 권한 모델

- 모든 테이블 RLS ON, `anon` 은 모든 테이블/함수 접근 불가. `private` 스키마는 API 에 노출되지 않는다.
- admin / member 모두 Postgres 롤은 `authenticated` 이다. 역할 구분은 RLS 정책의
  `private.is_admin()` / `private.is_approved_user()` (profiles 조회)로 한다.
- 컬럼 권한(GRANT)으로 **관리자도 클라이언트에서 바꿀 수 없는 컬럼**을 막는다.
  - `profiles.id / student_id / created_at`, `textbook_orders.total_price / user_id / round_start`,
    `textbook_order_items.*`, `event_payments.paid_at / confirmed_by`
- 교재 신청/수정/취소는 RPC(`place_textbook_order`, `update_textbook_order`, `cancel_textbook_order`)로만 가능하다.
  주문자는 `auth.uid()`, 가격은 교재 테이블에서 서버가 계산한다.
- `must_change_password` 는 클라이언트가 바꿀 수 없고, 비밀번호가 실제로 바뀔 때만 트리거가 해제한다. (강제 변경 우회 불가)
- 로그인 아이디(이메일 = 학번)는 트리거로 변경을 막는다. (남의 학번 선점 방지)
- 비밀번호 초기화 / 가입 거절은 Edge Function(service role)에서 호출자가 **승인된 admin** 인지 검증 후 수행한다.
  본인 계정은 대상이 될 수 없고, 승인된 회원은 삭제하지 않는다. (회계 기록 보존)

| 테이블 | 승인 대기 | member | admin |
| --- | --- | --- | --- |
| profiles | 본인 조회 | 본인 조회 | 전체 조회, 이름/역할/승인 수정 |
| textbooks / textbook_categories | - | 조회 | CRUD |
| textbook_orders / items | - | 본인 조회, RPC 로 신청·수정·취소 | 전체 조회, 상태 변경, 삭제 |
| events | - | 조회 | CRUD |
| event_payments | - | 본인 조회 | 전체 조회, 송금 여부 토글, 개인별 금액, 대상 추가/제외 |
| app_settings | - | 조회 | 수정 |

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

- 매주 **수요일 오전 9시 (KST)** 에 신청이 마감되고 새 회차가 시작된다. (수요일 09:00 ~ 다음 수요일 09:00)
- 주문은 신청 시점의 회차(`round_start` = 회차 시작 수요일)에 속한다.
- 회원은 **이번 회차**이고 상태가 **신청**인 본인 주문만 수정·취소할 수 있다.
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
- **입금자명**: 이벤트마다 관리자가 형식을 정한다. `{이름}`, `{학번}` 을 쓸 수 있고(예: `{이름}MT` → `홍길동MT`), 비우면 회원 이름.
  관리자 송금 현황과 미납자 CSV 에 회원별 입금자명이 나와 통장 내역과 대조할 수 있다.
- **개인별 금액**: 송금 현황의 회원 ⋮ > **금액 변경**으로 일부 회원의 금액만 바꿀 수 있다.
  비워 두면(= 기본 금액으로) 이벤트 금액을 따르며, 이벤트 금액을 나중에 바꿔도 조정된 회원의 금액은 유지된다.
  수금액·미수금·송금률 분모 금액, 회원의 미송금 합계, 미납자 CSV 모두 개인별 금액 기준이다.
