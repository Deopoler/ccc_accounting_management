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
  start: DateTime(_now.year, _now.month, _now.day),
  deadline: DateTime(_now.year, _now.month, _now.day + 7),
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
  roundStart: _round.start,
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

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => 'u1';
  @override
  Future<Profile?> fetchProfile(String userId) async => _members.first;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  @override
  Future<List<Textbook>> fetchTextbooks() async => _textbooks;
  @override
  Future<List<TextbookCategory>> fetchCategories() async => _categories;
  @override
  Future<OrderRound> fetchCurrentRound() async => _round;
  @override
  Future<List<TextbookOrder>> fetchMyOrders(String userId) async => _orders;
  @override
  Future<TextbookOrder?> fetchOrder(String orderId) async => _orders.first;
  @override
  Future<List<TextbookOrder>> fetchAllOrders({DateTime? roundStart}) async =>
      _orders;
  @override
  Future<void> updateOrdersStatus(List<String> ids, OrderStatus status) async =>
      _calls.add('status ${status.name} ${ids.join(',')}');
  @override
  Future<void> setShippedMany(
    List<String> ids, {
    required bool shipped,
  }) async => _calls.add('shipped $shipped ${ids.join(',')}');
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
  Future<List<Event>> fetchEvents() async => _events;
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
  Future<BankAccount> fetchBankAccount() async => const BankAccount(
    bankName: '카카오뱅크',
    accountNumber: '3333-01-2345678',
    holder: '대학생선교회 회계',
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMembers implements MemberRepository {
  @override
  Future<List<Profile>> fetchMembers() async => _members;
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

  group('신청 현황 전체 체크', () {
    setUp(_calls.clear);

    // 데이터: o1 신청, o2 입금확인, o3 취소, o4 배송됨, o5 수령 완료
    Future<void> tapAndConfirm(
      WidgetTester tester,
      String tooltip,
      String confirmTitle,
    ) async {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.text(confirmTitle), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, confirmTitle.split(' (').first),
      );
      await tester.pumpAndSettle();
    }

    for (final sizeName in ['데스크톱', '모바일']) {
      testWidgets('$sizeName: 취소 건을 빼고 바뀌어야 할 신청만 처리한다', (tester) async {
        await _pump(
          tester,
          _sizes[sizeName]!,
          '/admin/orders',
          const AdminOrdersPage(),
          true,
        );

        // 배송: 4건 중 2건 배송 → 일부 체크 상태, 누르면 나머지(o1, o2)를 배송
        await tapAndConfirm(tester, '배송 전체 체크', '배송 체크 (2건)');
        // 입금확인: o2, o4, o5 입금확인 → o1 만
        await tapAndConfirm(tester, '입금확인 전체 체크', '입금확인 체크 (1건)');
        // 수령: 배송된 o4, o5 중 o4 만
        await tapAndConfirm(tester, '수령 전체 체크', '수령 체크 (1건)');

        expect(_calls, [
          'shipped true o1,o2',
          'status paid o1',
          'received true o4',
        ]);
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
      await tester.ensureVisible(find.byTooltip('배송 전체 체크'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('배송 전체 체크'));
      await tester.pumpAndSettle();
      expect(find.text('배송 체크 (2건)'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(_calls, isEmpty);
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
