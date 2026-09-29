import 'package:ccc_accounting_management/core/router/auth_guard.dart';
import 'package:ccc_accounting_management/core/router/routes.dart';
import 'package:ccc_accounting_management/features/auth/domain/credentials.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile({
  UserRole role = UserRole.member,
  bool mustChange = false,
  bool approved = true,
}) => Profile(
  id: 'u1',
  studentId: '20240001',
  name: '홍길동',
  role: role,
  mustChangePassword: mustChange,
  isApproved: approved,
  createdAt: DateTime(2026),
);

String? _go(String location, {bool signedIn = true, Profile? profile}) =>
    authRedirect((signedIn: signedIn, profile: profile), Uri.parse(location));

void main() {
  group('로그아웃 상태', () {
    test('보호된 화면은 로그인으로 보내고 원래 경로를 기억한다', () {
      expect(
        _go('/admin/orders', signedIn: false),
        '/login?from=%2Fadmin%2Forders',
      );
      expect(_go('/home', signedIn: false), AppRoutes.login);
    });

    test('로그인 / 가입 화면은 그대로 둔다', () {
      expect(_go('/login', signedIn: false), isNull);
      expect(_go('/signup', signedIn: false), isNull);
    });
  });

  group('로그인 직후', () {
    test('프로필을 불러오는 동안 스플래시로 가며 from 을 유지한다', () {
      expect(_go('/login?from=%2Fevents'), '/loading?from=%2Fevents');
      expect(_go('/loading?from=%2Fevents'), isNull);
    });

    test('프로필을 불러오면 원래 경로로 이동한다', () {
      expect(_go('/loading?from=%2Fevents', profile: _profile()), '/events');
      expect(_go('/login', profile: _profile()), AppRoutes.home);
    });
  });

  group('가입 승인 대기', () {
    final p = _profile(approved: false);

    test('승인 전에는 승인 대기 화면만 볼 수 있다', () {
      expect(_go('/home', profile: p), AppRoutes.pending);
      expect(_go('/admin', profile: p), '/pending?from=%2Fadmin');
      expect(
        _go('/change-password', profile: p),
        '/pending?from=%2Fchange-password',
      );
      expect(_go('/pending', profile: p), isNull);
    });

    test('가입 직후(스플래시)에서 승인 대기로 간다', () {
      expect(_go('/loading', profile: p), AppRoutes.pending);
    });

    test('승인되면 승인 대기 화면에서 홈으로 간다', () {
      expect(_go('/pending', profile: _profile()), AppRoutes.home);
    });

    test('승인되지 않은 관리자는 관리자가 아니다', () {
      expect(_profile(role: UserRole.admin, approved: false).isAdmin, isFalse);
    });
  });

  group('비밀번호 초기화 후 변경', () {
    final p = _profile(mustChange: true);

    test('어떤 화면이든 비밀번호 변경으로 보낸다', () {
      expect(_go('/home', profile: p), AppRoutes.changePassword);
      expect(_go('/admin', profile: p), AppRoutes.changePassword);
      expect(_go('/change-password', profile: p), isNull);
    });
  });

  group('역할', () {
    test('회원은 관리자 화면에 들어갈 수 없다', () {
      expect(_go('/admin', profile: _profile()), AppRoutes.home);
      expect(_go('/admin/events/abc', profile: _profile()), AppRoutes.home);
      expect(_go('/home', profile: _profile()), isNull);
    });

    test('관리자는 관리자 화면에 들어갈 수 있다', () {
      final admin = _profile(role: UserRole.admin);
      expect(_go('/admin/orders', profile: admin), isNull);
    });

    test('회원은 비밀번호 변경 화면에 들어갈 수 있다', () {
      expect(_go('/change-password', profile: _profile()), isNull);
    });
  });

  group('safeFrom', () {
    test('외부 URL 로의 이동을 막는다', () {
      expect(safeFrom('https://evil.example'), isNull);
      expect(safeFrom('//evil.example'), isNull);
      expect(safeFrom('/login'), isNull);
      expect(safeFrom('/pending'), isNull);
      expect(safeFrom('/events'), '/events');
    });
  });

  group('credentials', () {
    test('학번을 가상 이메일로 변환한다', () {
      expect(studentIdToEmail(' 20240001 '), '20240001@ccc.local');
    });

    test('이름 검사', () {
      expect(validateName('  '), isNotNull);
      expect(validateName('홍길동'), isNull);
    });

    test('학번 형식 검사', () {
      expect(validateStudentId(''), isNotNull);
      expect(validateStudentId('12'), isNotNull);
      expect(validateStudentId('2024@01'), isNotNull);
      expect(validateStudentId('20240001'), isNull);
    });

    test('새 비밀번호 규칙: 8자 이상, 영문+숫자', () {
      expect(validateNewPassword('abc123'), isNotNull);
      expect(validateNewPassword('abcdefgh'), isNotNull);
      expect(validateNewPassword('12345678'), isNotNull);
      expect(validateNewPassword('abcd1234'), isNull);
    });
  });
}
