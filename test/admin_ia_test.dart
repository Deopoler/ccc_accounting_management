import 'dart:async';

import 'package:ccc_accounting_management/core/push/web_push.dart';
import 'package:ccc_accounting_management/core/router/app_router.dart';
import 'package:ccc_accounting_management/core/router/routes.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_badge_providers.dart';
import 'package:ccc_accounting_management/features/admin/presentation/member_providers.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/deposits/data/deposit_repository.dart';
import 'package:ccc_accounting_management/features/deposits/domain/bank_deposit.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/deposit_providers.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
import 'package:ccc_accounting_management/features/feedback/data/feedback_repository.dart';
import 'package:ccc_accounting_management/features/feedback/domain/feedback_entry.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_providers.dart';
import 'package:ccc_accounting_management/features/push/data/push_repository.dart';
import 'package:ccc_accounting_management/features/push/presentation/push_providers.dart';
import 'package:ccc_accounting_management/features/settings/data/settings_repository.dart';
import 'package:ccc_accounting_management/features/settings/domain/bank_account.dart';
import 'package:ccc_accounting_management/features/settings/presentation/settings_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/data/textbook_repository.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now();
final _round = OrderRound(
  id: 'r1',
  start: DateTime(_now.year, _now.month, _now.day, 9),
  deadline: DateTime(_now.year, _now.month, _now.day + 7, 9),
);

Profile _profile(
  String id, {
  String campusId = 'k',
  UserRole role = UserRole.member,
  bool isApproved = true,
  String? name,
}) => Profile(
  id: id,
  studentId: '20240001',
  name: name ?? id,
  role: role,
  mustChangePassword: false,
  isApproved: isApproved,
  campusId: campusId,
  createdAt: DateTime(2026, 1, 1),
);

FeedbackEntry _feedback(String id) => FeedbackEntry(
  id: id,
  userId: 'u-member',
  content: '피드백 $id',
  createdAt: DateTime(2026, 11, 1, 10),
  senderName: '홍길동',
  senderStudentId: '20240001',
  campusName: 'KAIST',
);

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.profile);
  final Profile profile;

  @override
  String? get currentUserId => profile.id;

  @override
  Future<Profile?> fetchProfile(String userId) async => profile;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCampuses implements CampusRepository {
  @override
  Future<List<Campus>> listCampuses() async => const [
    Campus(id: 'k', code: 'kaist', name: 'KAIST', emailDomain: 'ccc.local'),
    Campus(id: 's', code: 'snu', name: '서울대', emailDomain: 'snu.ccc.local'),
  ];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMembers implements MemberRepository {
  Map<String, List<Profile>> byCampus = {
    'k': [_profile('m1', isApproved: true, name: '승인회원')],
    's': [_profile('m2', campusId: 's', isApproved: true, name: '서울대회원')],
  };
  Completer<List<Profile>>? pending;
  Object? error;
  int calls = 0;

  @override
  Future<List<Profile>> fetchMembers(String campusId) {
    calls++;
    if (error != null) return Future.error(error!);
    final p = pending;
    if (p != null) return p.future;
    return Future.value(byCampus[campusId] ?? const []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeposits implements DepositRepository {
  Map<String, DepositCounts> countsByCampus = {
    'k': DepositCounts.empty,
    's': DepositCounts.empty,
  };
  Completer<DepositCounts>? pendingCounts;
  Object? countsError;
  int countCalls = 0;

  @override
  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<DepositCounts> fetchDepositCounts(String campusId) {
    countCalls++;
    if (countsError != null) return Future.error(countsError!);
    final p = pendingCounts;
    if (p != null) return p.future;
    return Future.value(countsByCampus[campusId] ?? DepositCounts.empty);
  }

  @override
  Future<CampusDepositSettings> fetchSettings(String campusId) async =>
      CampusDepositSettings(
        campusId: campusId,
        enabled: true,
        bankCode: 'toss',
        accountLabel: 'KAIST CCC',
      );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFeedback implements FeedbackRepository {
  List<FeedbackEntry> unresolved = const [];
  Completer<List<FeedbackEntry>>? pending;
  Object? error;
  int calls = 0;

  @override
  Future<List<FeedbackEntry>> fetchFeedback({bool unresolvedOnly = false}) {
    calls++;
    if (error != null) return Future.error(error!);
    final p = pending;
    if (p != null) return p.future;
    return Future.value(unresolved);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [_round];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [TextbookCategory(id: 'c1', name: '기본 교재', sortOrder: 0)];

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => [
    Textbook(
      id: 't1',
      title: '새생활의 시작',
      price: 5000,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      categoryId: 'c1',
      sortOrder: 0,
    ),
  ];

  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async => const [];

  @override
  Future<List<TextbookOrder>> fetchMyOrders(String userId) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEvents implements EventRepository {
  @override
  Future<List<Event>> fetchEvents(String campusId) async => [
    Event(
      id: 'e1',
      campusId: campusId,
      title: '수련회',
      amount: 30000,
      dueDate: null,
      description: '',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  @override
  Future<Event?> fetchEvent(String id) async => Event(
    id: id,
    campusId: 'k',
    title: '수련회',
    amount: 30000,
    dueDate: null,
    description: '',
    createdAt: DateTime(2026, 1, 1),
  );

  @override
  Future<Map<String, EventSummary>> fetchSummaries() async => const {};

  @override
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) async =>
      const {};

  @override
  Future<List<EventPayment>> fetchPayments(String eventId) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings implements SettingsRepository {
  @override
  Future<BankAccount> fetchBankAccount(String campusId) async =>
      const BankAccount(
        bankName: '카카오뱅크',
        accountNumber: '3333-01-1234567',
        holder: '회계',
      );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePushBrowser extends PushBrowser {
  @override
  PushSupport support() => PushSupport.unsupported;
}

class _FakePushRepo implements PushRepository {
  @override
  Future<String> fetchPublicKey() async => 'k';

  @override
  Future<void> save(DevicePushSubscription sub) async {}

  @override
  Future<bool> isSaved(String endpoint) async => false;

  @override
  Future<void> delete(String endpoint) async {}
}

class _Harness {
  _Harness({UserRole role = UserRole.centralAdmin})
    : profile = _profile('u1', role: role, name: '관리자');

  final Profile profile;
  final members = _FakeMembers();
  final deposits = _FakeDeposits();
  final feedback = _FakeFeedback();
  final textbooks = _FakeTextbooks();
  final events = _FakeEvents();
  final settings = _FakeSettings();
  final campuses = _FakeCampuses();

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    bool settle = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWith((ref) => profile.id),
          authRepositoryProvider.overrideWithValue(_FakeAuth(profile)),
          campusRepositoryProvider.overrideWithValue(campuses),
          memberRepositoryProvider.overrideWithValue(members),
          depositRepositoryProvider.overrideWithValue(deposits),
          feedbackRepositoryProvider.overrideWithValue(feedback),
          textbookRepositoryProvider.overrideWithValue(textbooks),
          eventRepositoryProvider.overrideWithValue(events),
          settingsRepositoryProvider.overrideWithValue(settings),
          pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
          pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: ref.watch(routerProvider),
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
            );
          },
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }
    return container;
  }
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  group('구 URL 리다이렉트 및 푸시 경로', () {
    testWidgets('4개의 구 관리자 URL 이 새 탭 경로로 리다이렉트된다', (tester) async {
      final h = _Harness(role: UserRole.centralAdmin);
      h.feedback.unresolved = [_feedback('f1')];
      final container = await h.pumpApp(tester);
      final router = container.read(routerProvider);

      router.go('/admin/textbooks');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/orders?tab=catalog',
      );
      expect(find.text('카테고리 추가'), findsOneWidget);

      router.go('/admin/settings');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/members?tab=account',
      );
      expect(find.text('송금 계좌'), findsOneWidget);

      router.go('/admin/campuses');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/central?tab=campuses',
      );
      expect(find.text('캠퍼스 추가'), findsOneWidget);

      // push edge function 이 보내는 admin/feedback 경로도 리다이렉트된다.
      router.go('/admin/feedback');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/central?tab=feedback',
      );
      expect(find.text('피드백 f1'), findsOneWidget);

      // push edge function 의 admin/members, admin/deposits 는 바로 열린다.
      router.go('/admin/members');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/members',
      );
      expect(find.text('승인회원'), findsOneWidget);

      router.go('/admin/deposits');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/deposits',
      );
      expect(find.text('자동 입금 설정'), findsWidgets);
    });
  });

  group('탭 쿼리 파라미터 (?tab=) 동기화 및 인라인 다이얼로그', () {
    testWidgets('교재 / 회원·계좌 / 총괄 관리 탭이 ?tab= 쿼리와 양방향 동기화된다', (
      tester,
    ) async {
      final h = _Harness(role: UserRole.centralAdmin);
      h.feedback.unresolved = [_feedback('f1')];
      final container = await h.pumpApp(tester);
      final router = container.read(routerProvider);

      // 교재: 기본(신청 현황) -> 교재·카테고리 전환 + 마감 변경 다이얼로그
      router.go('/admin/orders');
      await tester.pumpAndSettle();
      expect(find.text('마감 변경'), findsOneWidget);
      await tester.tap(find.text('마감 변경'));
      await tester.pumpAndSettle();
      expect(find.text('교재 신청 마감'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('교재·카테고리'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/orders?tab=catalog',
      );
      expect(find.text('카테고리 추가'), findsOneWidget);

      // 알 수 없는 tab 값은 첫 탭으로 폴백
      router.go('/admin/orders?tab=unknown');
      await tester.pumpAndSettle();
      expect(find.text('마감 변경'), findsOneWidget);

      // 회원·계좌: 회원 <-> 송금 계좌·알림
      router.go('/admin/members?tab=account');
      await tester.pumpAndSettle();
      expect(find.text('송금 계좌'), findsOneWidget);
      await tester.tap(find.text('회원'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/members?tab=members',
      );
      expect(find.text('승인회원'), findsOneWidget);

      // 입금 내역: 자동 입금 설정 다이얼로그
      router.go('/admin/deposits');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '자동 입금 설정').first);
      await tester.pumpAndSettle();
      expect(find.text('자동 입금 확인'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();

      // 총괄 관리: 캠퍼스 <-> 피드백
      router.go('/admin/central?tab=feedback');
      await tester.pumpAndSettle();
      expect(find.text('피드백 f1'), findsOneWidget);
      await tester.tap(find.text('캠퍼스'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/central?tab=campuses',
      );
      expect(find.text('캠퍼스 추가'), findsOneWidget);
    });
  });

  group('역할 분리 및 총괄 전용 메뉴', () {
    testWidgets('캠퍼스 관리자에게는 총괄 관리가 숨겨지고 접근 시 /admin 으로 이동한다', (tester) async {
      final h = _Harness(role: UserRole.campusAdmin);
      final container = await h.pumpApp(tester);
      final router = container.read(routerProvider);

      expect(find.text('총괄 관리'), findsNothing);
      expect(find.text('교재'), findsOneWidget);
      expect(find.text('이벤트'), findsWidgets); // 회원 메뉴와 관리자 메뉴에 모두 있다.
      expect(find.text('입금 내역'), findsOneWidget);
      expect(find.text('회원·계좌'), findsOneWidget);
      // 캠퍼스 관리자는 피드백 목록을 조회하지 않는다.
      expect(h.feedback.calls, 0);

      router.go('/admin/central');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.admin,
      );
      expect(find.text('총괄 관리'), findsNothing);
    });

    testWidgets('일반 회원은 관리자 배지용 provider 를 전혀 호출하지 않는다', (tester) async {
      final h = _Harness(role: UserRole.member);
      await h.pumpApp(tester);

      expect(h.members.calls, 0);
      expect(h.deposits.countCalls, 0);
      expect(h.feedback.calls, 0);
      expect(find.byType(AdminCountBadge), findsNothing);
    });
  });

  group('대기 작업 배지', () {
    testWidgets('로딩 중과 오류, 0건에서는 배지를 숨기고 양수일 때만 건수를 표시한다', (tester) async {
      final semantics = tester.ensureSemantics();

      final h = _Harness(role: UserRole.centralAdmin);
      final membersCompleter = Completer<List<Profile>>();
      final depositsCompleter = Completer<DepositCounts>();
      final feedbackCompleter = Completer<List<FeedbackEntry>>();
      h.members.pending = membersCompleter;
      h.deposits.pendingCounts = depositsCompleter;
      h.feedback.pending = feedbackCompleter;

      final container = await h.pumpApp(tester, settle: false);
      // 사이드바가 렌더링된 로딩 중 상태에서 배지를 숨긴다.
      expect(find.text('회원·계좌'), findsOneWidget);
      expect(find.byType(AdminCountBadge), findsNothing);

      // 0건으로 로드 완료 -> 여전히 배지 없음.
      membersCompleter.complete([_profile('m1', isApproved: true)]);
      depositsCompleter.complete(const DepositCounts(needsReview: 0, all: 2));
      feedbackCompleter.complete(const []);
      h.members.pending = null;
      h.deposits.pendingCounts = null;
      h.feedback.pending = null;
      await tester.pumpAndSettle();
      expect(find.byType(AdminCountBadge), findsNothing);

      // 오류 시 조용히 숨긴다.
      h.members.error = Exception('fail');
      h.deposits.countsError = Exception('fail');
      h.feedback.error = Exception('fail');
      container.invalidate(membersProvider);
      container.invalidate(depositCountsProvider);
      container.invalidate(feedbackListProvider(FeedbackFilter.unresolved));
      await tester.pumpAndSettle();
      expect(find.byType(AdminCountBadge), findsNothing);
      expect(find.byType(ErrorWidget), findsNothing);

      // 양수 건수 로드 -> 사이드 네비게이션에 배지 표시.
      h.members.error = null;
      h.deposits.countsError = null;
      h.feedback.error = null;
      h.members.byCampus = {
        'k': [
          _profile('p1', isApproved: false),
          _profile('p2', isApproved: false),
          _profile('a1', isApproved: true),
        ],
        's': [_profile('s1', campusId: 's', isApproved: false)],
      };
      h.deposits.countsByCampus = {
        'k': const DepositCounts(needsReview: 3, all: 5),
        's': const DepositCounts(needsReview: 0, all: 0),
      };
      h.feedback.unresolved = [
        _feedback('f1'),
        _feedback('f2'),
        _feedback('f3'),
        _feedback('f4'),
      ];
      container.invalidate(membersProvider);
      container.invalidate(depositCountsProvider);
      container.invalidate(feedbackListProvider(FeedbackFilter.unresolved));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCountBadge), findsNWidgets(3));
      expect(find.bySemanticsLabel(RegExp('2건 대기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('3건 대기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('4건 대기')), findsOneWidget);

      // 캠퍼스를 전환하면 새 캠퍼스 기준으로 배지가 갱신된다.
      container.read(centralCampusOverrideProvider.notifier).select('s');
      await tester.pumpAndSettle();
      expect(find.byType(AdminCountBadge), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('1건 대기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('3건 대기')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('4건 대기')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('모바일 허브 및 상단 섹션 전환기', () {
    testWidgets('모바일에서 허브 없이 섹션 전환기로 관리자 화면을 바로 오간다', (tester) async {
      final semantics = tester.ensureSemantics();

      final h = _Harness(role: UserRole.centralAdmin);
      h.members.byCampus['k'] = [_profile('p1', isApproved: false)];
      h.deposits.countsByCampus['k'] = const DepositCounts(
        needsReview: 2,
        all: 2,
      );
      final container = await h.pumpApp(tester, size: const Size(390, 844));
      final router = container.read(routerProvider);

      // 모바일 허브(/admin): 5개 메뉴 + 배지 표시, 상단 섹션 전환기는 숨김
      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();
      expect(find.text('교재'), findsOneWidget);
      expect(find.text('이벤트'), findsWidgets);
      expect(find.text('입금 내역'), findsOneWidget);
      expect(find.text('회원·계좌'), findsOneWidget);
      expect(find.text('총괄 관리'), findsOneWidget);
      expect(find.byType(AdminCountBadge), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('1건 대기')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('2건 대기')), findsOneWidget);

      // 교재로 진입하면 상단 섹션 전환기가 보인다.
      await tester.tap(find.text('교재'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/orders',
      );

      // 허브로 돌아가지 않고 전환기에서 바로 입금 내역 -> 회원·계좌 이동
      final depositsChip = find.text('입금 내역');
      await tester.ensureVisible(depositsChip);
      await tester.pumpAndSettle();
      await tester.tap(depositsChip);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/deposits',
      );
      expect(find.bySemanticsLabel(RegExp('2건 대기')), findsOneWidget);

      final membersChip = find.text('회원·계좌');
      await tester.ensureVisible(membersChip);
      await tester.pumpAndSettle();
      await tester.tap(membersChip);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/members',
      );
      expect(find.bySemanticsLabel(RegExp('1건 대기')), findsOneWidget);

      // 이벤트 상세에서는 뒤로가기가 이벤트으로 돌아가며 섹션 전환기가 숨겨진다.
      router.go(AppRoutes.adminEventDetail('e1'));
      await tester.pumpAndSettle();
      expect(find.text('이벤트 송금 현황 · KAIST'), findsOneWidget);
      expect(find.text('교재'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/admin/events',
      );
      semantics.dispose();
    });
  });
}
