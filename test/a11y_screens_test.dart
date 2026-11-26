import 'dart:async';

import 'package:ccc_accounting_management/core/push/web_push.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/member_providers.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_event_detail_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_events_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_members_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_textbooks_page.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/auth/presentation/login_page.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/admin_campuses_page.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/widgets/event_widgets.dart';
import 'package:ccc_accounting_management/features/feedback/data/feedback_repository.dart';
import 'package:ccc_accounting_management/features/feedback/domain/feedback_entry.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/admin_feedback_page.dart';
import 'package:ccc_accounting_management/features/push/data/push_repository.dart';
import 'package:ccc_accounting_management/features/push/presentation/push_providers.dart';
import 'package:ccc_accounting_management/features/push/presentation/signup_push_card.dart';
import 'package:ccc_accounting_management/features/textbooks/data/textbook_repository.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbooks_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/widgets/order_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _admin = Profile(
  id: 'u1',
  campusId: 'k',
  studentId: '20240001',
  name: '홍길동',
  role: UserRole.centralAdmin,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026, 9, 1),
);

final _members = [
  _admin,
  Profile(
    id: 'u2',
    campusId: 'k',
    studentId: '20240002',
    name: '김민수',
    role: UserRole.member,
    mustChangePassword: false,
    isApproved: true,
    createdAt: DateTime(2026, 9, 2),
  ),
  Profile(
    id: 'p1',
    campusId: 'k',
    studentId: '20250001',
    name: '이서연',
    role: UserRole.member,
    mustChangePassword: false,
    isApproved: false,
    createdAt: DateTime(2026, 9, 3),
  ),
];

final _event = Event(
  id: 'e1',
  title: '겨울 수련회',
  amount: 30000,
  dueDate: DateTime(2026, 11, 30),
  description: '',
  createdAt: DateTime(2026, 9, 1),
);

final _payments = [
  EventPayment(
    id: 'pay1',
    eventId: 'e1',
    userId: 'u2',
    isPaid: false,
    paidAt: null,
    member: const EventMember(studentId: '20240002', name: '김민수'),
  ),
];

class _FakeAuth implements AuthRepository {
  Completer<void>? signInCompleter;

  @override
  String? get currentUserId => 'u1';

  @override
  Future<Profile?> fetchProfile(String userId) async => _admin;

  @override
  Future<void> signIn({
    required Campus campus,
    required String studentId,
    required String password,
  }) async {
    if (signInCompleter != null) {
      await signInCompleter!.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCampuses implements CampusRepository {
  _FakeCampuses(this.campuses);

  final List<Campus> campuses;

  @override
  Future<List<Campus>> listCampuses() async => campuses;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMembers implements MemberRepository {
  @override
  Future<List<Profile>> fetchMembers(String campusId) async => _members;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEvents implements EventRepository {
  @override
  Future<List<Event>> fetchEvents(String campusId) async => [_event];

  @override
  Future<Event?> fetchEvent(String id) async => _event;

  @override
  Future<Map<String, EventSummary>> fetchSummaries() async => {
    _event.id: EventSummary.fromPayments(_payments, _event),
  };

  @override
  Future<List<EventPayment>> fetchPayments(String eventId) async => _payments;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [
        TextbookCategory(id: 'c1', name: '성경공부', sortOrder: 0),
        TextbookCategory(id: 'c2', name: '전도', sortOrder: 1),
      ];

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => [
    Textbook(
      id: 'b1',
      title: '교재 A',
      price: 5000,
      isActive: true,
      createdAt: DateTime(2026),
      categoryId: 'c1',
      sortOrder: 0,
    ),
    Textbook(
      id: 'b2',
      title: '교재 B',
      price: 7000,
      isActive: true,
      createdAt: DateTime(2026),
      categoryId: 'c1',
      sortOrder: 1,
    ),
  ];

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => OrderRound(
    id: 'r1',
    start: DateTime(2026, 11, 20),
    deadline: DateTime(2026, 11, 27),
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFeedback implements FeedbackRepository {
  @override
  Future<List<FeedbackEntry>> fetchFeedback({
    bool unresolvedOnly = false,
  }) async => [
    FeedbackEntry(
      id: 'f1',
      userId: 'u2',
      content: '테스트 피드백',
      createdAt: DateTime(2026, 11, 18, 15, 30),
      senderName: '김민수',
      senderStudentId: '20240002',
      campusName: 'KAIST',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePushBrowser extends PushBrowser {
  @override
  PushSupport support() => PushSupport.available;

  @override
  bool isGranted() => false;

  @override
  bool isDenied() => false;

  @override
  Future<DevicePushSubscription?> currentSubscription() async => null;
}

class _FakePushRepo implements PushRepository {
  @override
  Future<String> fetchPublicKey() async => 'key';

  @override
  Future<void> save(DevicePushSubscription sub) async {}

  @override
  Future<bool> isSaved(String endpoint) async => false;

  @override
  Future<void> delete(String endpoint) async {}
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 812),
  AuthRepository? authRepo,
  CampusRepository? campusRepo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        currentUserIdProvider.overrideWith((ref) => 'u1'),
        authRepositoryProvider.overrideWithValue(authRepo ?? _FakeAuth()),
        campusRepositoryProvider.overrideWithValue(
          campusRepo ??
              _FakeCampuses(const [
                Campus(
                  id: 'k',
                  code: 'kaist',
                  name: 'KAIST',
                  emailDomain: 'ccc.local',
                ),
              ]),
        ),
        memberRepositoryProvider.overrideWithValue(_FakeMembers()),
        eventRepositoryProvider.overrideWithValue(_FakeEvents()),
        textbookRepositoryProvider.overrideWithValue(_FakeTextbooks()),
        feedbackRepositoryProvider.overrideWithValue(_FakeFeedback()),
        pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
        pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('QuantityStepper 버튼은 44x44 이상이고 수량 시맨틱 라벨을 가진다', (tester) async {
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QuantityStepper(value: 2, onChanged: (_) => changed++),
        ),
      ),
    );
    expect(
      tester.getSize(find.byTooltip('빼기')).width,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byTooltip('빼기')).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byTooltip('더하기')).width,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byTooltip('더하기')).height,
      greaterThanOrEqualTo(44),
    );
    expect(find.bySemanticsLabel('수량 2권'), findsOneWidget);

    await tester.tap(find.text('2'));
    expect(changed, 0);
  });

  testWidgets('지난 이벤트 마감일은 중복 없이 표시된다', (tester) async {
    final pastEvent = Event(
      id: 'past',
      title: '순장 수련회',
      amount: 10000,
      dueDate: DateTime(2020, 10, 10),
      description: '',
      createdAt: DateTime(2020, 9, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: EventMetaLine(event: pastEvent)),
      ),
    );
    expect(find.text('2020.10.10 마감'), findsOneWidget);
    expect(find.textContaining('· 마감'), findsNothing);
  });

  testWidgets('AdminEventsPage 카드는 버튼 시맨틱을 가지고 진행 막대는 숨긴다', (tester) async {
    await _pumpPage(tester, const AdminEventsPage());
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == '겨울 수련회 송금 현황 보기',
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(LinearProgressIndicator),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });

  testWidgets('AdminCampusesPage 빈 상태와 캠퍼스 추가 다이얼로그 작은 화면 처리', (tester) async {
    await _pumpPage(
      tester,
      const AdminCampusesPage(),
      size: const Size(375, 420),
      campusRepo: _FakeCampuses(const []),
    );
    expect(find.text('등록된 캠퍼스가 없습니다.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '캠퍼스 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdminMembersPage 좁은 화면 레이아웃과 거절/승인 분리 시맨틱', (tester) async {
    await _pumpPage(
      tester,
      const AdminMembersPage(),
      size: const Size(360, 812),
    );

    expect(find.bySemanticsLabel('이서연 (20250001) 선택'), findsOneWidget);
    expect(find.bySemanticsLabel('이서연 거절'), findsOneWidget);
    expect(find.bySemanticsLabel('이서연 승인'), findsOneWidget);

    final infoTop = tester.getTopLeft(find.text('이서연  20250001')).dy;
    final rejectTop = tester
        .getTopLeft(find.widgetWithText(TextButton, '거절'))
        .dy;
    expect(rejectTop, greaterThan(infoTop));

    final sectionTop = tester.getTopLeft(find.text('회원 2명')).dy;
    final searchTop = tester.getTopLeft(find.byType(TextField)).dy;
    expect(searchTop, greaterThan(sectionTop));
  });

  testWidgets('AdminEventDetailPage 좁은 화면 2줄 카드, 스위치 라벨, 작은 화면 다이얼로그', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const AdminEventDetailPage(eventId: 'e1'),
      size: const Size(360, 812),
    );
    expect(find.bySemanticsLabel('김민수 납부 완료'), findsOneWidget);
    final nameTop = tester.getTopLeft(find.text('김민수')).dy;
    final switchTop = tester.getTopLeft(find.byType(Switch)).dy;
    expect(switchTop, greaterThan(nameTop));

    await _pumpPage(
      tester,
      const AdminEventDetailPage(eventId: 'e1'),
      size: const Size(375, 420),
    );
    final addTargets = find.widgetWithText(OutlinedButton, '대상 추가');
    await tester.ensureVisible(addTargets);
    await tester.pumpAndSettle();
    await tester.tap(addTargets);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdminTextbooksPage 순서 버튼 라벨, 스위치 라벨, 작은 화면 다이얼로그', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const AdminTextbooksPage(),
      size: const Size(375, 420),
    );
    expect(find.byTooltip('성경공부 위로 이동'), findsOneWidget);
    expect(find.byTooltip('성경공부 아래로 이동'), findsOneWidget);
    expect(find.byTooltip('교재 A 위로 이동'), findsOneWidget);
    expect(find.byTooltip('교재 A 아래로 이동'), findsOneWidget);
    expect(find.bySemanticsLabel('교재 A 신청 가능'), findsOneWidget);

    final addBook = find.widgetWithText(FilledButton, '교재 추가');
    await tester.ensureVisible(addBook);
    await tester.pumpAndSettle();
    await tester.tap(addBook);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TextbooksPage 검색 칸에 labelText 가 설정되어 있다', (tester) async {
    await _pumpPage(tester, const TextbooksPage());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.labelText, '교재명으로 찾기');
  });

  testWidgets('AdminFeedbackPage 와 SignupPushCard 스위치에 시맨틱 라벨이 있다', (
    tester,
  ) async {
    await _pumpPage(tester, const AdminFeedbackPage());
    expect(find.bySemanticsLabel('김민수 (20240002) 확인'), findsOneWidget);

    await _pumpPage(tester, const SignupPushCard());
    final semantics = tester.ensureSemantics();
    try {
      expect(tester.getSemantics(find.byType(Switch)).label, '가입 신청 알림');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('LoginPage 로그인 중 인디케이터에 시맨틱 라벨이 있다', (tester) async {
    final auth = _FakeAuth()..signInCompleter = Completer<void>();
    await _pumpPage(tester, const LoginPage(), authRepo: auth);
    await tester.enterText(
      find.widgetWithText(TextFormField, '학번'),
      '20240001',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      'abcd1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, '로그인'));
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.semanticsLabel, '로그인 중');
    auth.signInCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
