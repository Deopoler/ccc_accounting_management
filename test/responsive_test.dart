// 모든 화면을 모바일 / 데스크톱 크기로 렌더링해 레이아웃 오류(overflow 등)가 없는지 확인한다.
// Supabase 대신 가짜 저장소를 주입하고, 넘치기 쉬운 긴 문자열을 일부러 사용한다.
import 'package:ccc_accounting_management/core/router/app_router.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/widgets/app_shell.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_event_detail_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_events_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_hub_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_members_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_orders_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_textbooks_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/member_providers.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/auth/presentation/change_password_page.dart';
import 'package:ccc_accounting_management/features/auth/presentation/login_page.dart';
import 'package:ccc_accounting_management/features/auth/presentation/pending_approval_page.dart';
import 'package:ccc_accounting_management/features/auth/presentation/signup_page.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/presentation/admin_campuses_page.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_switcher.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
import 'package:ccc_accounting_management/features/events/presentation/events_page.dart';
import 'package:ccc_accounting_management/features/home/presentation/home_page.dart';
import 'package:ccc_accounting_management/features/settings/data/settings_repository.dart';
import 'package:ccc_accounting_management/features/settings/domain/bank_account.dart';
import 'package:ccc_accounting_management/features/settings/presentation/admin_settings_page.dart';
import 'package:ccc_accounting_management/features/settings/presentation/settings_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/data/textbook_repository.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/my_orders_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/order_complete_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbooks_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// 가짜 데이터 (넘치기 쉬운 긴 문자열 포함)
// ---------------------------------------------------------------------------

const _longTitle = '신약 성경 개론 워크북 (개정 3판, 소그룹 리더용 해설 포함) 상·하권 세트';
const _longName = '남궁 아리따운 하늘별님프리티';

final _now = DateTime.now();
final _round = OrderRound(
  id: 'round',
  start: DateTime(_now.year, _now.month, _now.day, 9),
  deadline: DateTime(_now.year, _now.month, _now.day + 7, 9),
);
final _previousRound = OrderRound(
  id: 'previous',
  start: DateTime(_now.year, _now.month, _now.day - 7, 9),
  deadline: _round.start,
);

Profile _profile(
  String id, {
  UserRole role = UserRole.member,
  bool approved = true,
}) => Profile(
  id: id,
  studentId: '2024${id.padLeft(4, '0')}',
  name: id == 'u1' ? _longName : '회원$id',
  role: role,
  mustChangePassword: false,
  isApproved: approved,
  createdAt: DateTime(2026, 9, 1),
);

final _members = [
  _profile('u1', role: UserRole.campusAdmin),
  for (var i = 2; i < 8; i++) _profile('$i'),
  _profile('p1', approved: false),
  _profile('p2', approved: false),
];

const _categories = [
  TextbookCategory(id: 'c1', name: '성경공부 (소그룹 리더 과정 · 심화)', sortOrder: 0),
  TextbookCategory(id: 'c2', name: '전도', sortOrder: 1),
];

// b3 은 카테고리가 없어 "기타"로 묶인다. b4 는 c1 의 신청 불가 교재 (관리자 화면에서 ↑↓ 확인용).
final _textbooks = [
  Textbook(
    id: 'b4',
    title: '$_longTitle 해설집',
    price: 32000,
    isActive: false,
    createdAt: DateTime(2026),
    categoryId: 'c1',
    sortOrder: 1,
  ),
  Textbook(
    id: 'b1',
    title: _longTitle,
    price: 1234000,
    isActive: true,
    createdAt: DateTime(2026),
    categoryId: 'c1',
  ),
  Textbook(
    id: 'b2',
    title: '교재 B',
    price: 7000,
    isActive: true,
    createdAt: DateTime(2026),
    categoryId: 'c2',
  ),
  Textbook(
    id: 'b3',
    title: '비활성 교재',
    price: 5000,
    isActive: false,
    createdAt: DateTime(2026),
  ),
];

TextbookOrder _order(
  String id,
  OrderStatus status,
  String userId, {
  bool shipped = false,
  bool received = false,
}) => TextbookOrder(
  isShipped: shipped,
  shippedAt: shipped ? DateTime(2026, 10, 7, 10) : null,
  receivedAt: received ? DateTime(2026, 10, 8, 18, 30) : null,
  receivedBy: received ? 'admin' : null,
  id: id,
  userId: userId,
  roundId: _round.id,
  round: _round,
  status: status,
  totalPrice: 2475000,
  createdAt: DateTime(2026, 9, 29, 13, 5),
  items: const [
    TextbookOrderItem(
      textbookId: 'b1',
      title: _longTitle,
      quantity: 2,
      unitPrice: 1234000,
    ),
    TextbookOrderItem(
      textbookId: 'b2',
      title: '교재 B',
      quantity: 1,
      unitPrice: 7000,
    ),
  ],
  member: OrderMember(
    studentId: '2024$userId',
    name: userId == 'u1' ? _longName : '회원$userId',
  ),
);

final _orders = [
  _order('o1', OrderStatus.requested, 'u1'),
  _order('o2', OrderStatus.paid, '2'),
  _order('o3', OrderStatus.cancelled, '3'),
  _order('o4', OrderStatus.paid, 'u1', shipped: true),
  _order('o5', OrderStatus.paid, '5', shipped: true, received: true),
];

final _events = [
  Event(
    id: 'e1',
    title: '$_longTitle 겨울 수련회',
    amount: 1500000,
    dueDate: DateTime(_now.year, _now.month, _now.day + 3),
    description: '장소: 강원도 평창 ○○수련원\n준비물: 성경, 필기구, 개인 세면도구, 침낭',
    createdAt: DateTime(2026, 9, 1),
  ),
  Event(
    id: 'e2',
    title: '지난 모임',
    amount: 5000,
    dueDate: DateTime(2026, 1, 1),
    description: '',
    createdAt: DateTime(2026),
  ),
];

List<EventPayment> _payments(String eventId) => [
  for (final m in _members.where((m) => m.isApproved))
    EventPayment(
      id: 'pay-${m.id}',
      eventId: eventId,
      userId: m.id,
      isPaid: m.id.hashCode.isEven,
      paidAt: m.id.hashCode.isEven ? DateTime(2026, 9, 29) : null,
      amountOverride: m.id == 'u1' ? 1234500 : null,
      member: EventMember(studentId: m.studentId, name: m.name),
    ),
];

// ---------------------------------------------------------------------------
// 가짜 저장소
// ---------------------------------------------------------------------------

/// 로그인한 사용자. null 이면 첫 번째 회원(캠퍼스 관리자).
Profile? _signedIn;

final _central = Profile(
  id: 'u1',
  campusId: 'k',
  studentId: '20250133',
  name: _longName,
  role: UserRole.centralAdmin,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026),
);

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => 'u1';
  @override
  Future<Profile?> fetchProfile(String userId) async =>
      _signedIn ?? _members.first;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => _textbooks;
  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      _categories;
  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;
  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [
    _round,
    _previousRound,
  ];
  @override
  Future<List<TextbookOrder>> fetchMyOrders(String userId) async => _orders;
  @override
  Future<TextbookOrder?> fetchOrder(String orderId) async => _orders.first;
  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async => _orders;
  @override
  Future<void> updateOrdersStatus(List<String> ids, OrderStatus status) async =>
      _calls.add('status ${status.name} ${ids.join(',')}');
  @override
  Future<void> setShippedMany(
    List<String> ids, {
    required bool shipped,
  }) async => _calls.add('shipped $shipped ${ids.join(',')}');
  @override
  Future<void> shiftOrders(List<String> ids, int offset) async =>
      _calls.add('shift $offset ${ids.join(',')}');
  @override
  Future<void> setRoundDeadline(String roundId, DateTime deadline) async =>
      _calls.add('deadline $roundId ${deadline.toIso8601String()}');
  @override
  Future<DateTime?> setReceived(String id, {required bool received}) async {
    _calls.add('received $received $id');
    return received ? DateTime(2026, 10, 9) : null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// 관리자 일괄 처리 테스트에서 저장소에 보낸 요청 기록.
final _calls = <String>[];

class _FakeEvents implements EventRepository {
  @override
  Future<List<Event>> fetchEvents(String campusId) async => _events;
  @override
  Future<Event?> fetchEvent(String id) async => _events.first;
  @override
  Future<Map<String, EventSummary>> fetchSummaries() async => {
    for (final e in _events)
      e.id: EventSummary.fromPayments(_payments(e.id), e),
  };
  @override
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) async => {
    'e1': EventPayment(
      id: 'x',
      eventId: 'e1',
      userId: 'u1',
      isPaid: false,
      paidAt: null,
      amountOverride: 1234500,
    ),
    'e2': EventPayment(
      id: 'y',
      eventId: 'e2',
      userId: 'u1',
      isPaid: true,
      paidAt: DateTime(2026),
    ),
  };
  @override
  Future<List<EventPayment>> fetchPayments(String eventId) async =>
      _payments(eventId);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings implements SettingsRepository {
  @override
  Future<BankAccount> fetchBankAccount(String campusId) async =>
      const BankAccount(
        bankName: '카카오뱅크',
        accountNumber: '3333-01-2345678',
        holder: '대학생선교회 회계',
      );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMembers implements MemberRepository {
  @override
  Future<List<Profile>> fetchMembers(String campusId) async => _members;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ---------------------------------------------------------------------------
// 테스트
// ---------------------------------------------------------------------------

const _sizes = {
  '작은 모바일': Size(320, 640),
  '모바일': Size(360, 740),
  '태블릿 경계': Size(840, 1024),
  '데스크톱': Size(1280, 800),
};

/// (경로, 화면, 셸 안에서 보이는지)
final _pages = <(String, Widget, bool)>[
  ('/home', const HomePage(), true),
  ('/textbooks', const TextbooksPage(), true),
  ('/textbooks', const TextbooksPage(editOrderId: 'o1'), true),
  ('/textbooks?category=c1', const TextbooksPage(categoryId: 'c1'), true),
  (
    '/textbooks?category=_uncategorized',
    const TextbooksPage(categoryId: uncategorizedId),
    true,
  ),
  ('/textbooks/complete/o1', const OrderCompletePage(orderId: 'o1'), true),
  ('/my-orders', const MyOrdersPage(), true),
  ('/events', const EventsPage(), true),
  ('/admin', const AdminHubPage(), true),
  ('/admin/members', const AdminMembersPage(), true),
  ('/admin/textbooks', const AdminTextbooksPage(), true),
  ('/admin/orders', const AdminOrdersPage(), true),
  ('/admin/events', const AdminEventsPage(), true),
  ('/admin/events/e1', const AdminEventDetailPage(eventId: 'e1'), true),
  ('/admin/settings', const AdminSettingsPage(), true),
  ('/login', const LoginPage(), false),
  ('/signup', const SignupPage(), false),
  ('/change-password', const ChangePasswordPage(), false),
  ('/pending', const PendingApprovalPage(), false),
];

class _FakeCampuses implements CampusRepository {
  @override
  Future<List<Campus>> listCampuses() async => const [
    Campus(id: 'k', code: 'kaist', name: 'KAIST', emailDomain: 'ccc.local'),
    Campus(
      id: 's',
      code: 'snu',
      name: '아주 긴 이름의 캠퍼스 (제2캠퍼스 · 국제관)',
      emailDomain: 'snu.ccc.local',
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<Override> get _overrides => [
  currentUserIdProvider.overrideWithValue('u1'),
  authRepositoryProvider.overrideWithValue(_FakeAuth()),
  textbookRepositoryProvider.overrideWithValue(_FakeTextbooks()),
  eventRepositoryProvider.overrideWithValue(_FakeEvents()),
  settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
  memberRepositoryProvider.overrideWithValue(_FakeMembers()),
  campusRepositoryProvider.overrideWithValue(_FakeCampuses()),
];

Future<void> _pump(
  WidgetTester tester,
  Size size,
  String path,
  Widget page,
  bool inShell, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: _overrides,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: inShell ? AppShell(location: path, child: page) : page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
    // 테스트 기본 폰트는 모든 글자를 정사각형으로 그려 폭이 실제보다 훨씬 넓다.
    // 앱에 포함한 Pretendard 를 실제로 로드해 넘침 / 폭 검사를 현실에 맞춘다.
    final pretendard = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.ttf'));
    await pretendard.load();
  });

  for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
    group(sizeName, () {
      for (final (path, page, inShell) in _pages) {
        testWidgets('$path ${page.runtimeType}', (tester) async {
          await _pump(tester, size, path, page, inShell);
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
        });
      }

      testWidgets('네비게이션: ${size.width < 840 ? '하단' : '사이드'}', (tester) async {
        await _pump(tester, size, '/home', const HomePage(), true);
        if (size.width < 840) {
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('관리'), findsOneWidget);
        } else {
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('관리자'), findsOneWidget);
          expect(find.text('교재 신청 현황'), findsOneWidget);
        }
      });
    });
  }

  // 다크 테마: 모든 화면이 색 토큰(AppColors)을 찾지 못해 깨지지 않는지
  for (final sizeName in ['모바일', '데스크톱']) {
    group('다크 $sizeName', () {
      for (final (path, page, inShell) in _pages) {
        testWidgets('$path ${page.runtimeType}', (tester) async {
          await _pump(
            tester,
            _sizes[sizeName]!,
            path,
            page,
            inShell,
            theme: AppTheme.dark(),
          );
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  group('신청 현황 선택 처리', () {
    setUp(_calls.clear);

    // 데이터: o1 신청, o2 입금확인, o3 취소, o4 배송됨, o5 수령 완료
    // 데스크톱은 표 머리행, 모바일은 선택 막대의 첫 체크박스가 전체 선택이다.
    Future<void> pickAll(WidgetTester tester) async {
      final all = find.byType(Checkbox).first;
      await tester.ensureVisible(all);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
    }

    Future<void> tapAndConfirm(
      WidgetTester tester,
      String button,
      String menuItem,
      String confirmTitle,
    ) async {
      final b = find.widgetWithText(OutlinedButton, button);
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.pumpAndSettle();
      if (menuItem.isNotEmpty) {
        await tester.tap(find.text(menuItem).last);
        await tester.pumpAndSettle();
      }
      expect(find.text(confirmTitle), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, confirmTitle.split(' (').first),
      );
      await tester.pumpAndSettle();
    }

    for (final sizeName in ['데스크톱', '모바일']) {
      testWidgets('$sizeName: 선택한 신청 중 바뀌어야 할 신청만 체크한다', (tester) async {
        await _pump(
          tester,
          _sizes[sizeName]!,
          '/admin/orders',
          const AdminOrdersPage(),
          true,
        );
        // 선택 전에는 처리 버튼을 쓸 수 없다.
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '이전 회차로'),
              )
              .onPressed,
          isNull,
        );

        await pickAll(tester);
        expect(find.text('5건 선택'), findsOneWidget);
        // 배송: 취소 건 빼고 아직 배송 안 된 o1, o2
        await tapAndConfirm(tester, '배송', '배송 체크', '배송 체크 (2건)');
        // 입금확인: o1 만
        await tapAndConfirm(tester, '입금확인', '입금확인 체크', '입금확인 체크 (1건)');
        // 수령: 배송된 o4, o5 중 o4 만
        await tapAndConfirm(tester, '수령', '수령 체크', '수령 체크 (1건)');

        expect(_calls, [
          'shipped true o1,o2',
          'status paid o1',
          'received true o4',
        ]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$sizeName: 선택한 신청을 이전 / 다음 회차로 옮긴다', (tester) async {
        await _pump(
          tester,
          _sizes[sizeName]!,
          '/admin/orders',
          const AdminOrdersPage(),
          true,
        );
        await pickAll(tester);
        await tapAndConfirm(tester, '이전 회차로', '', '이전 회차로 이동 (5건)');
        expect(_calls, ['shift -1 o1,o2,o3,o4,o5']);

        // 하나만 골라 다음 회차로 (전체 선택 다음 체크박스가 첫 신청)
        final first = find.byType(Checkbox).at(1);
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        await tester.tap(first);
        await tester.pumpAndSettle();
        await tapAndConfirm(tester, '다음 회차로', '', '다음 회차로 이동 (1건)');
        expect(_calls.last, 'shift 1 o1');
        expect(tester.takeException(), isNull);
      });
    }

    for (final sizeName in ['작은 모바일', '모바일']) {
      testWidgets('$sizeName: 입금확인 · 배송 · 수령 / 이전 · 다음 회차가 각각 한 줄', (
        tester,
      ) async {
        await _pump(
          tester,
          _sizes[sizeName]!,
          '/admin/orders',
          const AdminOrdersPage(),
          true,
        );
        await pickAll(tester);
        double top(String text) =>
            tester.getTopLeft(find.widgetWithText(OutlinedButton, text)).dy;
        expect(top('배송'), top('입금확인'));
        expect(top('수령'), top('입금확인'));
        expect(top('다음 회차로'), top('이전 회차로'));
        expect(top('이전 회차로'), greaterThan(top('입금확인')));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('확인창에서 취소하면 아무것도 바꾸지 않는다', (tester) async {
      await _pump(
        tester,
        _sizes['데스크톱']!,
        '/admin/orders',
        const AdminOrdersPage(),
        true,
      );
      await pickAll(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '배송'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('배송 체크').last);
      await tester.pumpAndSettle();
      expect(find.text('배송 체크 (2건)'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(_calls, isEmpty);
    });
  });

  group('회차', () {
    setUp(_calls.clear);

    testWidgets('설정: 이번 회차 마감 일시를 저장한다', (tester) async {
      await _pump(
        tester,
        _sizes['데스크톱']!,
        '/admin/settings',
        const AdminSettingsPage(),
        true,
      );
      final save = find.widgetWithText(FilledButton, '마감 저장');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // 달력에서 날짜를 확인하면 바뀐 것으로 보고 저장할 수 있다.
      await tester.tap(find.byIcon(Icons.event));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(_calls, ['deadline round ${_round.deadline.toIso8601String()}']);
      expect(tester.takeException(), isNull);
    });
  });

  group('총괄 관리자', () {
    setUp(() => _signedIn = _central);
    tearDown(() => _signedIn = null);

    for (final (sizeName, dark) in [
      ('작은 모바일', false),
      ('모바일', true),
      ('태블릿 경계', false),
      ('데스크톱', false),
      ('데스크톱', true),
    ]) {
      final label = '${dark ? '다크 ' : ''}$sizeName';
      for (final (path, page) in [
        ('/admin', const AdminHubPage() as Widget),
        ('/admin/campuses', const AdminCampusesPage()),
        ('/admin/members', const AdminMembersPage()),
      ]) {
        testWidgets('$label $path', (tester) async {
          await _pump(
            tester,
            _sizes[sizeName]!,
            path,
            page,
            true,
            theme: dark ? AppTheme.dark() : null,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('캠퍼스를 바꾸면 관리자 화면 제목에 그 캠퍼스가 붙는다', (tester) async {
      await _pump(
        tester,
        _sizes['데스크톱']!,
        '/admin/members',
        const AdminMembersPage(),
        true,
      );
      expect(find.text('회원 관리 · KAIST'), findsOneWidget);
      // 사이드 메뉴의 캠퍼스 전환
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('아주 긴 이름의 캠퍼스 (제2캠퍼스 · 국제관)').last);
      await tester.pumpAndSettle();
      expect(find.text('회원 관리 · 아주 긴 이름의 캠퍼스 (제2캠퍼스 · 국제관)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('캠퍼스 관리자에게는 전환 / 캠퍼스 관리 메뉴가 없다', (tester) async {
      _signedIn = null;
      await _pump(
        tester,
        _sizes['데스크톱']!,
        '/admin/members',
        const AdminMembersPage(),
        true,
      );
      expect(find.byType(CampusSwitcher), findsNothing);
      expect(find.text('캠퍼스 관리'), findsNothing);
      expect(find.text('회원 관리'), findsWidgets);
    });
  });

  testWidgets('데스크톱 신청 현황 표는 가로 스크롤 없이 모든 열이 보인다', (tester) async {
    await _pump(
      tester,
      _sizes['데스크톱']!,
      '/admin/orders',
      const AdminOrdersPage(),
      true,
    );
    final scrollable = find.descendant(
      of: find.ancestor(
        of: find.byType(DataTable),
        matching: find.byType(SingleChildScrollView),
      ),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.axis, Axis.horizontal);
    expect(
      position.maxScrollExtent,
      0,
      reason: '넘친 폭 ${position.maxScrollExtent}',
    );
  });

  testWidgets('데스크톱 신청 현황은 표, 모바일은 카드', (tester) async {
    await _pump(
      tester,
      _sizes['데스크톱']!,
      '/admin/orders',
      const AdminOrdersPage(),
      true,
    );
    expect(find.byType(DataTable), findsOneWidget);
    await _pump(
      tester,
      _sizes['모바일']!,
      '/admin/orders',
      const AdminOrdersPage(),
      true,
    );
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('교재 신청: 카테고리를 오가도 고른 수량이 유지된다 (실제 라우터)', (tester) async {
    tester.view.physicalSize = const Size(1280, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: _overrides,
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
              theme: AppTheme.light(),
              locale: const Locale('ko', 'KR'),
              supportedLocales: const [Locale('ko', 'KR')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: ref.watch(routerProvider),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final router = container.read(routerProvider);

    Future<void> go(String location) async {
      router.go(location);
      await tester.pumpAndSettle();
    }

    await go('/textbooks');
    expect(find.text('선택 0권'), findsOneWidget);
    expect(find.textContaining('성경공부'), findsOneWidget);
    expect(find.text('전도'), findsOneWidget);
    // "기타"의 교재는 신청 불가뿐이라 회원 화면에서 카테고리째 숨겨진다.
    expect(find.text('기타'), findsNothing);

    // 성경공부에서 2권
    await go('/textbooks?category=c1');
    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();

    // 전도로 이동해서 1권
    await go('/textbooks?category=c2');
    expect(find.text('선택 2권'), findsOneWidget, reason: '다른 카테고리로 가도 유지');
    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();

    // 카테고리 목록: 합계와 카테고리별 선택 수
    await go('/textbooks');
    expect(find.text('선택 3권'), findsOneWidget);
    expect(find.text('2권 선택'), findsOneWidget);
    expect(find.text('1권 선택'), findsOneWidget);

    // 검색: 카테고리를 건너뛰고 교재를 바로 찾는다
    await tester.enterText(find.byType(TextField), '교재 B');
    await tester.pumpAndSettle();
    expect(find.text('7,000원'), findsOneWidget, reason: '교재 B 카드');
    expect(find.text('전도'), findsNothing);
  });
}
