import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/auth/presentation/login_page.dart';
import 'package:ccc_accounting_management/features/auth/presentation/signup_page.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kaist = Campus(
  id: 'k',
  code: 'kaist',
  name: 'KAIST',
  emailDomain: 'ccc.local',
);
const _snu = Campus(
  id: 's',
  code: 'snu',
  name: '서울대',
  emailDomain: 'snu.ccc.local',
);

class _FakeCampuses implements CampusRepository {
  _FakeCampuses(this.campuses);

  final List<Campus> campuses;

  @override
  Future<List<Campus>> listCampuses() async => campuses;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// 로그인 / 가입 요청을 기록만 한다.
class _RecordingAuth implements AuthRepository {
  final calls = <String>[];

  @override
  Future<void> signIn({
    required Campus campus,
    required String studentId,
    required String password,
  }) async => calls.add('signIn ${campus.code} $studentId');

  @override
  Future<void> signUp({
    required Campus campus,
    required String studentId,
    required String name,
    required String password,
  }) async => calls.add('signUp ${campus.code} $studentId');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_RecordingAuth> _pump(
  WidgetTester tester,
  Widget page,
  List<Campus> campuses,
) async {
  final auth = _RecordingAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        campusRepositoryProvider.overrideWithValue(_FakeCampuses(campuses)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: page),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _fillLogin(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, '학번'), '20240001');
  await tester.enterText(
    find.widgetWithText(TextFormField, '비밀번호'),
    'abcd1234',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('캠퍼스가 하나면 선택 칸 없이 그 캠퍼스로 로그인한다', (tester) async {
    final auth = await _pump(tester, const LoginPage(), [_kaist]);
    expect(find.text('캠퍼스'), findsNothing);
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['signIn kaist 20240001']);
  });

  testWidgets('캠퍼스가 여럿이면 고르기 전에는 로그인하지 않는다', (tester) async {
    final auth = await _pump(tester, const LoginPage(), [_kaist, _snu]);
    expect(find.text('캠퍼스'), findsOneWidget);
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(find.text('캠퍼스를 선택해 주세요.'), findsOneWidget);
    expect(auth.calls, isEmpty);

    await tester.tap(find.text('캠퍼스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서울대').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['signIn snu 20240001']);

    // 다음에는 마지막 캠퍼스가 기억된다.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_campus_code'), 'snu');
  });

  testWidgets('마지막으로 쓴 캠퍼스가 미리 선택된다', (tester) async {
    SharedPreferences.setMockInitialValues({'last_campus_code': 'snu'});
    final auth = await _pump(tester, const LoginPage(), [_kaist, _snu]);
    expect(find.text('서울대'), findsOneWidget);
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['signIn snu 20240001']);
  });

  testWidgets('가입도 고른 캠퍼스로 한다', (tester) async {
    SharedPreferences.setMockInitialValues({'last_campus_code': 'snu'});
    final auth = await _pump(tester, const SignupPage(), [_kaist, _snu]);
    await tester.enterText(
      find.widgetWithText(TextFormField, '학번'),
      '20240001',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '이름'), '홍길동');
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      'abcd1234',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호 확인'),
      'abcd1234',
    );
    final submit = find.widgetWithText(FilledButton, '가입하기');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(auth.calls, ['signUp snu 20240001']);
  });
}
