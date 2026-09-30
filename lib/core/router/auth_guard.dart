import '../../features/auth/domain/profile.dart';
import 'routes.dart';

/// 라우터 가드에 필요한 인증 상태 스냅샷.
typedef AuthSnapshot = ({bool signedIn, Profile? profile});

/// 로그인하지 않아도 들어갈 수 있는 화면.
const _publicPaths = {AppRoutes.login, AppRoutes.signup};

/// 로그인 전후 "대기" 화면. 로그인 후 여기 머물 이유가 없으면 원래 경로로 보낸다.
const _entryPaths = {
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.splash,
  AppRoutes.pending,
};

/// 로그인 여부 / 가입 승인 / 비밀번호 변경 필요 / 역할에 따라 이동할 경로를 결정한다.
/// null 이면 그대로 둔다.
///
/// 역할 체크는 화면 접근 제어용이며, 데이터 권한은 서버 RLS 가 강제한다.
String? authRedirect(AuthSnapshot auth, Uri uri) {
  final path = uri.path;

  if (!auth.signedIn) {
    return _publicPaths.contains(path) ? null : _withFrom(AppRoutes.login, uri);
  }

  final profile = auth.profile;
  if (profile == null) {
    // 프로필 로딩 중이거나, 로딩 실패 / 프로필 없음 → 스플래시에서 처리
    return path == AppRoutes.splash ? null : _withFrom(AppRoutes.splash, uri);
  }

  if (!profile.isApproved) {
    return path == AppRoutes.pending ? null : _withFrom(AppRoutes.pending, uri);
  }

  if (profile.mustChangePassword) {
    return path == AppRoutes.changePassword ? null : AppRoutes.changePassword;
  }

  if (_entryPaths.contains(path)) {
    return safeFrom(uri.queryParameters['from']) ?? AppRoutes.home;
  }

  if (!profile.isAdmin &&
      (path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/'))) {
    return AppRoutes.home;
  }
  if (!profile.isCentralAdmin &&
      (path == AppRoutes.adminCampuses ||
          path.startsWith('${AppRoutes.adminCampuses}/'))) {
    return AppRoutes.admin;
  }
  return null;
}

/// 로그인 후 돌아갈 경로를 `from` 쿼리로 넘긴다. 진입 화면끼리는 기존 from 을 유지한다.
String _withFrom(String target, Uri uri) {
  final from = _entryPaths.contains(uri.path)
      ? safeFrom(uri.queryParameters['from'])
      : safeFrom(uri.toString());
  if (from == null || from == AppRoutes.home) return target;
  return Uri(path: target, queryParameters: {'from': from}).toString();
}

/// 외부 URL 로의 open redirect 를 막기 위해 앱 내부 경로만 허용한다.
String? safeFrom(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  final path = Uri.tryParse(from)?.path;
  if (path == null || path == '/' || _entryPaths.contains(path)) return null;
  return from;
}
