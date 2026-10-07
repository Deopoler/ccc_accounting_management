# CCC 회계 관리 시스템

CCC 의 교재 신청과 이벤트 회비를 관리하는 웹앱. 여러 캠퍼스가 함께 쓴다.

- **회원**: 교재를 신청하고, 이벤트 송금 안내를 보고 송금 여부를 확인한다.
- **캠퍼스 관리자**: 자기 캠퍼스의 가입 승인, 교재 / 신청 회차, 입금 · 배송 확인, 이벤트 송금 현황을 관리한다.
- **총괄 관리자**: 모든 캠퍼스를 관리하고 캠퍼스를 추가한다.

접속: <https://deopoler.github.io/ccc_accounting_management/>

## 문서

| 대상 | 문서 |
| --- | --- |
| 사용자 | [기능 소개](docs/기능소개.md) · [사용법](docs/사용법.md) (회원 / 캠퍼스 관리자 / 총괄 관리자) |
| 개발 | [설치와 Supabase 설정](docs/개발/설치.md) · [테스트 서버와 배포](docs/개발/테스트서버와배포.md) · [테스트](docs/개발/테스트.md) |
| 설계 | [인증 · 권한 · 보안](docs/개발/권한과보안.md) · [업무 규칙](docs/개발/업무규칙.md) · [디자인 · 폰트](docs/개발/디자인.md) |

## 기술

- Flutter Web (Material 3, 반응형) + Riverpod + go_router
- Supabase: Auth, Postgres + RLS, Edge Functions
- 로그인은 캠퍼스 / 학번 / 비밀번호. 내부적으로 가상 이메일(`{학번}@ccc.local`, `{학번}@{캠퍼스 코드}.ccc.local`)로 Supabase Auth 를 쓴다.
- 모든 데이터 권한은 서버(RLS / RPC / Edge Function)가 판단한다. 앱의 역할 체크는 화면 표시용이다.

## 빠른 시작

Flutter stable (3.47 이상), Chrome, Node.js 20 이상이 필요하다.

```sh
flutter pub get
cp env.example.json env.json      # Supabase URL / publishable 키 입력 (커밋되지 않음)
flutter run -d chrome --dart-define-from-file=env.json
```

테스트 서버는 `env.staging.json` 으로 실행한다. Supabase 프로젝트를 새로 만드는 방법은 [설치](docs/개발/설치.md) 참고.

```sh
flutter analyze && flutter test
cd supabase/tests && npm install && npm test    # DB 권한 테스트 (마이그레이션을 바꾸면 필수)
```

## 개발 흐름

1. `feature/<이름>` 브랜치에서 작업하고 push → CI 가 테스트 후 **테스트 서버** DB 에 적용
2. `env.staging.json` 으로 앱을 띄워 확인
3. `main` 에 merge → CI 가 테스트 후 **운영 DB** 에 적용하고 GitHub Pages 에 배포

> `main` 에 merge 하는 순간 운영 DB 가 바뀐다. 이미 적용된 마이그레이션은 고치지 말고 새 파일을 추가한다.
> 자세한 내용은 [테스트 서버와 배포](docs/개발/테스트서버와배포.md).

## 폴더 구조

```text
lib/
  core/          config · router(가드) · theme · utils · 공통 위젯
  features/      auth · home · textbooks · events · admin · campus · settings
                 (각 feature 는 data / domain / presentation)
supabase/
  migrations/    스키마 + RLS (이름 순서대로 적용)
  functions/     Edge Function (admin-members: 비밀번호 초기화 / 가입 거절)
  tests/         PGlite 기반 DB 권한 테스트
test/            Flutter 단위 / 반응형 레이아웃 테스트
docs/            사용자 문서, docs/개발/ 개발 문서
assets/fonts/    Pretendard (현대 한글 전체) + 라이선스
tool/fonts/      폰트 생성 스크립트
```
