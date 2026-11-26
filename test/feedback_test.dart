// 피드백함: 총괄 관리자만 쓰는 화면 접근 / 메뉴, 보내기 창, 목록 화면.
import 'package:ccc_accounting_management/core/router/auth_guard.dart';
import 'package:ccc_accounting_management/core/router/routes.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/utils/app_exception.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_hub_page.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/feedback/data/feedback_repository.dart';
import 'package:ccc_accounting_management/features/feedback/domain/feedback_entry.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/admin_feedback_page.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_dialog.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Profile _profile(UserRole role) => Profile(
  id: 'u1',
  campusId: 'k',
  studentId: '20240001',
  name: '홍길동',
  role: role,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026),
);

String? _go(String location, Profile profile) => authRedirect((
  signedIn: true,
  profile: profile,
), Uri.parse(location));

FeedbackEntry _entry(String id, {bool resolved = false, String? content}) =>
    FeedbackEntry(
      id: id,
      userId: 'm-$id',
      content: content ?? '앱이 편해요 $id',
      createdAt: DateTime(2026, 11, 18, 15, 30),
      resolvedAt: resolved ? DateTime(2026, 11, 18, 16) : null,
      resolvedBy: resolved ? 'u1' : null,
      senderName: '회원$id',
      senderStudentId: '2024$id',
      campusName: 'KAIST',
    );

class _FakeFeedback implements FeedbackRepository {
  final sent = <String>[];
  final calls = <String>[];
  Object? submitError;

  final entries = [_entry('1'), _entry('2', resolved: true)];

  @override
  Future<void> submit(String content) async {
    final error = submitError;
    if (error != null) throw error;
    sent.add(content);
  }

  @override
  Future<List<FeedbackEntry>> fetchFeedback({
    bool unresolvedOnly = false,
  }) async {
    calls.add('fetch unresolvedOnly=$unresolvedOnly');
    return [
      for (final e in entries)
        if (!unresolvedOnly || !e.isResolved) e,
    ];
  }

  @override
  Future<void> setResolved(String id, {required bool resolved}) async =>
      calls.add('resolve $id $resolved');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Profile? profile,
  _FakeFeedback? repo,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        currentUserIdProvider.overrideWith((ref) => profile?.id ?? 'u1'),
        if (profile != null)
          currentProfileProvider.overrideWith((ref) async => profile),
        campusesProvider.overrideWith((ref) async => const <Campus>[]),
        if (repo != null) feedbackRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('접근 / 메뉴', () {
    test('피드백 화면은 총괄 관리자만 들어갈 수 있다', () {
      expect(
        _go('/admin/feedback', _profile(UserRole.campusAdmin)),
        AppRoutes.admin,
      );
      expect(_go('/admin/feedback', _profile(UserRole.member)), AppRoutes.home);
      expect(_go('/admin/feedback', _profile(UserRole.centralAdmin)), isNull);
    });

    test('피드백은 총괄 관리자 메뉴이며 관리자 메뉴로 돌아간다', () {
      expect(centralDestinations.map((d) => d.path), contains('/admin/feedback'));
      expect(adminDestinations.map((d) => d.path), isNot(contains('/admin/feedback')));
      final meta = routeMetaFor('/admin/feedback');
      expect(meta.title, '피드백');
      expect(meta.parent, AppRoutes.admin);
    });

    testWidgets('관리자 허브의 피드백 메뉴는 총괄 관리자에게만 보인다', (tester) async {
      await _pump(tester, const AdminHubPage(), profile: _profile(UserRole.centralAdmin));
      expect(find.text('피드백'), findsOneWidget);
      expect(find.text('캠퍼스 관리'), findsOneWidget);

      await _pump(tester, const AdminHubPage(), profile: _profile(UserRole.campusAdmin));
      expect(find.text('피드백'), findsNothing);
      expect(find.text('회원 관리'), findsOneWidget);
    });
  });

  group('FeedbackEntry', () {
    test('조회 결과(보낸 사람 / 캠퍼스 포함)를 읽는다', () {
      final e = FeedbackEntry.fromJson({
        'id': 'f1',
        'user_id': 'u1',
        'content': '안녕하세요',
        'created_at': '2026-11-18T06:30:00Z',
        'resolved_at': null,
        'resolved_by': null,
        'profiles': {'name': '홍길동', 'student_id': '20240001'},
        'campuses': {'name': 'KAIST'},
      });
      expect(e.senderName, '홍길동');
      expect(e.senderStudentId, '20240001');
      expect(e.campusName, 'KAIST');
      expect(e.isResolved, isFalse);

      final done = FeedbackEntry.fromJson({
        'id': 'f2',
        'user_id': 'u1',
        'content': 'x',
        'created_at': '2026-11-18T06:30:00Z',
        'resolved_at': '2026-11-18T07:00:00Z',
        'resolved_by': 'u9',
      });
      expect(done.isResolved, isTrue);
      expect(done.resolvedBy, 'u9');
      expect(done.senderName, isEmpty);
    });
  });

  group('보내기 창', () {
    Future<void> open(WidgetTester tester, _FakeFeedback repo) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showFeedbackDialog(context),
              child: const Text('열기'),
            ),
          ),
        ),
        repo: repo,
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    Finder sendButton() => find.widgetWithText(FilledButton, '보내기');

    testWidgets('내용이 비어 있으면 보낼 수 없고, 보내면 안내 메시지를 보여 준다', (tester) async {
      final repo = _FakeFeedback();
      await open(tester, repo);

      expect(find.text('피드백 보내기'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  앱이 편해요\n감사합니다  ');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.sent, ['앱이 편해요\n감사합니다']);
      expect(find.text('피드백 보내기'), findsNothing);
      expect(find.text('피드백을 보냈습니다. 감사합니다.'), findsOneWidget);
    });

    testWidgets('실패하면 창과 입력 내용을 유지하고 이유를 보여 준다', (tester) async {
      final repo = _FakeFeedback()
        ..submitError = const AppException('잠시 후 다시 보내 주세요.');
      await open(tester, repo);

      await tester.enterText(find.byType(TextField), '여러 번 보내 봅니다');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('피드백 보내기'), findsOneWidget);
      expect(find.text('잠시 후 다시 보내 주세요.'), findsOneWidget);
      expect(find.text('여러 번 보내 봅니다'), findsOneWidget);
      expect(find.text('피드백을 보냈습니다. 감사합니다.'), findsNothing);
      expect(repo.sent, isEmpty);
    });

    testWidgets('내용은 2000자까지만 입력된다', (tester) async {
      await open(tester, _FakeFeedback());
      await tester.enterText(find.byType(TextField), 'ㄱ' * 2100);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text.length, FeedbackEntry.maxLength);
    });
  });

  group('피드백 목록', () {
    testWidgets('미확인만 기본으로 보이고, 전체로 바꾸면 확인한 것도 보인다', (tester) async {
      final repo = _FakeFeedback();
      await _pump(tester, const AdminFeedbackPage(), repo: repo);

      expect(find.text('회원1 (20241)'), findsOneWidget);
      expect(find.text('KAIST · 2026.11.18 15:30'), findsOneWidget);
      expect(find.text('앱이 편해요 1'), findsOneWidget);
      expect(find.text('회원2 (20242)'), findsNothing);
      expect(repo.calls, ['fetch unresolvedOnly=true']);

      await tester.tap(find.text('전체'));
      await tester.pumpAndSettle();
      expect(find.text('회원2 (20242)'), findsOneWidget);
      expect(repo.calls.last, 'fetch unresolvedOnly=false');
    });

    testWidgets('확인 스위치로 확인 처리 / 해제를 요청한다', (tester) async {
      final repo = _FakeFeedback();
      await _pump(tester, const AdminFeedbackPage(), repo: repo);
      await tester.tap(find.text('전체'));
      await tester.pumpAndSettle();

      final switches = find.byType(Switch);
      expect(tester.widget<Switch>(switches.at(0)).value, isFalse);
      expect(tester.widget<Switch>(switches.at(1)).value, isTrue);

      await tester.tap(switches.at(0));
      await tester.pumpAndSettle();
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('resolve')), [
        'resolve 1 true',
        'resolve 2 false',
      ]);
    });

    testWidgets('피드백이 없으면 안내 문구를 보여 준다', (tester) async {
      final repo = _FakeFeedback()..entries.clear();
      await _pump(tester, const AdminFeedbackPage(), repo: repo);
      expect(find.text('확인하지 않은 피드백이 없습니다.'), findsOneWidget);
    });
  });
}
