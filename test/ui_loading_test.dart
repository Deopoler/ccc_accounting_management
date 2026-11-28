import 'dart:async';

import 'package:ccc_accounting_management/core/push/web_push.dart';
import 'package:ccc_accounting_management/core/riverpod/cache_for.dart';
import 'package:ccc_accounting_management/core/router/app_router.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/widgets/state_views.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_order_providers.dart';
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
import 'package:ccc_accounting_management/features/home/presentation/home_page.dart';
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
import 'package:ccc_accounting_management/features/textbooks/presentation/my_orders_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  UserRole role = UserRole.centralAdmin,
  String name = '홍길동',
}) => Profile(
  id: id,
  campusId: campusId,
  studentId: '2024$id',
  name: name,
  role: role,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026, 9, 1),
);

TextbookOrder _order(String id, String userId, String title, {int qty = 1}) =>
    TextbookOrder(
      id: id,
      userId: userId,
      roundId: _round.id,
      round: _round,
      status: OrderStatus.requested,
      totalPrice: 5000 * qty,
      createdAt: DateTime(2026, 11, 1),
      items: [
        TextbookOrderItem(
          textbookId: 'b1',
          title: title,
          quantity: qty,
          unitPrice: 5000,
        ),
      ],
    );

class _FakeAuth implements AuthRepository {
  Profile? profile;

  @override
  String? get currentUserId => profile?.id;

  @override
  Future<Profile?> fetchProfile(String userId) async => profile;

  @override
  Future<void> signOut() async {
    profile = null;
  }

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
  final Map<String, List<Profile>> byCampus = {
    'k': [_profile('m1', campusId: 'k', role: UserRole.member, name: 'KAIST 회원')],
    's': [_profile('m2', campusId: 's', role: UserRole.member, name: '서울대 회원')],
  };
  Completer<List<Profile>>? pendingFetch;
  final List<String> fetchedCampuses = [];

  @override
  Future<List<Profile>> fetchMembers(String campusId) {
    fetchedCampuses.add(campusId);
    final pending = pendingFetch;
    if (pending != null) {
      pendingFetch = null;
      return pending.future;
    }
    return Future.value(byCampus[campusId] ?? const []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  Map<String, List<TextbookOrder>> ordersByUser = {
    'u1': [_order('o1', 'u1', '기존 교재')],
    'u2': [_order('o2', 'u2', 'u2 전용 교재')],
  };
  List<Textbook> books = [
    Textbook(
      id: 'b1',
      title: '기초 교재',
      price: 5000,
      isActive: true,
      createdAt: DateTime(2026),
      categoryId: 'c1',
      sortOrder: 0,
    ),
  ];
  List<TextbookOrder> allOrders = [_order('o1', 'u1', '기존 교재')];
  int editOrderQty = 3;
  int fetchOrderCalls = 0;
  Completer<TextbookOrder?>? pendingFetchOrder;
  Completer<List<TextbookOrder>>? pendingMyOrders;
  int myOrdersFetches = 0;
  final List<Map<String, int>> placedOrders = [];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [TextbookCategory(id: 'c1', name: '성경공부', sortOrder: 0)];

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => books;

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [_round];

  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async => roundId == null
      ? List<TextbookOrder>.of(allOrders)
      : allOrders.where((o) => o.roundId == roundId).toList();

  @override
  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    required OrderStatus from,
  }) async {
    allOrders = [
      for (final o in allOrders)
        o.id == orderId ? o.copyWith(status: status) : o,
    ];
  }

  @override
  Future<List<TextbookOrder>> fetchMyOrders(String userId) {
    myOrdersFetches++;
    final pending = pendingMyOrders;
    if (pending != null) {
      pendingMyOrders = null;
      return pending.future;
    }
    return Future.value(ordersByUser[userId] ?? const []);
  }

  @override
  Future<TextbookOrder?> fetchOrder(String orderId) {
    fetchOrderCalls++;
    final pending = pendingFetchOrder;
    if (pending != null) {
      pendingFetchOrder = null;
      return pending.future;
    }
    return Future.value(_order(orderId, 'u1', '수정 대상 교재', qty: editOrderQty));
  }

  @override
  Future<String> placeOrder(Map<String, int> quantities) async {
    placedOrders.add(Map<String, int>.of(quantities));
    return 'o-new';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEvents implements EventRepository {
  Completer<List<Event>>? pendingEvents;
  Map<String, List<Event>> eventsByCampus = const {};
  Map<String, List<EventPayment>> paymentsByEvent = const {};
  int fetchEventsCalls = 0;
  int fetchEventCalls = 0;

  @override
  Future<List<Event>> fetchEvents(String campusId) {
    fetchEventsCalls++;
    final pending = pendingEvents;
    if (pending != null) {
      pendingEvents = null;
      return pending.future;
    }
    return Future.value(eventsByCampus[campusId] ?? const []);
  }

  @override
  Future<Event?> fetchEvent(String id) async {
    fetchEventCalls++;
    for (final list in eventsByCampus.values) {
      for (final e in list) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  @override
  Future<Map<String, EventSummary>> fetchSummaries() async => const {};

  @override
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) async =>
      const {};

  @override
  Future<List<EventPayment>> fetchPayments(String eventId) async =>
      paymentsByEvent[eventId] ?? const [];

  @override
  Future<void> setPaid(String paymentId, {required bool isPaid}) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeposits implements DepositRepository {
  List<BankDeposit> firstPage = const [];
  List<BankDeposit> secondPage = const [];
  DepositCounts counts = DepositCounts.empty;
  UnpaidLinkTargets unpaidTargets = UnpaidLinkTargets.empty;
  int unpaidFetches = 0;

  @override
  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) async {
    if (offset == 0) return List<BankDeposit>.of(firstPage);
    return List<BankDeposit>.of(secondPage);
  }

  @override
  Future<DepositCounts> fetchDepositCounts(String campusId) async => counts;

  @override
  Future<UnpaidLinkTargets> fetchUnpaidLinkTargets(String campusId) async {
    unpaidFetches++;
    return unpaidTargets;
  }

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

class _FakeFeedback implements FeedbackRepository {
  @override
  Future<List<FeedbackEntry>> fetchFeedback({bool unresolvedOnly = false}) async =>
      const [];

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

class _TestCampusNotifier extends Notifier<String?> {
  @override
  String? build() => 'k';

  void setCampus(String? campusId) => state = campusId;
}

final _testCampusProvider = NotifierProvider<_TestCampusNotifier, String?>(
  _TestCampusNotifier.new,
);

class _Harness {
  _Harness({Profile? initialProfile})
    : auth = _FakeAuth()..profile = initialProfile ?? _profile('u1');

  final _FakeAuth auth;
  final _FakeMembers members = _FakeMembers();
  final _FakeTextbooks textbooks = _FakeTextbooks();
  final _FakeEvents events = _FakeEvents();
  final _FakeDeposits deposits = _FakeDeposits();
  final _FakeSettings settings = _FakeSettings();
  final _FakeCampuses campuses = _FakeCampuses();
  final _FakeFeedback feedback = _FakeFeedback();

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWith((ref) => auth.profile?.id),
          authRepositoryProvider.overrideWithValue(auth),
          campusRepositoryProvider.overrideWithValue(campuses),
          memberRepositoryProvider.overrideWithValue(members),
          textbookRepositoryProvider.overrideWithValue(textbooks),
          eventRepositoryProvider.overrideWithValue(events),
          depositRepositoryProvider.overrideWithValue(deposits),
          feedbackRepositoryProvider.overrideWithValue(feedback),
          settingsRepositoryProvider.overrideWithValue(settings),
          pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
          pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
          ...extraOverrides,
        ],
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
    return container;
  }
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offstage IndexedStack 탭 재진입 시 스피너 없이 캐시를 보여 주고 백그라운드 새로고침한다', (
    tester,
  ) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    expect(find.textContaining('기존 교재'), findsOneWidget);
    final initialFetches = h.textbooks.myOrdersFetches;

    // 다른 탭으로 이동하면 홈 브랜치가 TickerMode(false)로 일시 정지된다.
    router.go('/events');
    await tester.pumpAndSettle();

    // 복귀 시 백그라운드 새로고침이 대기 중이어도 캐시가 즉시 보이고 얇은 진행 막대가 뜬다.
    final refreshCompleter = Completer<List<TextbookOrder>>();
    h.textbooks.pendingMyOrders = refreshCompleter;

    router.go('/home');
    await tester.pump();
    expect(find.textContaining('기존 교재'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump();
    await tester.pump();
    expect(h.textbooks.myOrdersFetches, initialFetches + 1);
    expect(find.textContaining('기존 교재'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    refreshCompleter.complete([_order('o1', 'u1', '갱신된 교재')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('갱신된 교재'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('언마운트된 관리자 하위 화면 재진입 시 캐시를 즉시 보여 주고 백그라운드 새로고침한다', (tester) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    router.go('/admin/members');
    await tester.pumpAndSettle();
    expect(find.text('KAIST 회원'), findsOneWidget);

    // 같은 관리자 브랜치의 다른 하위 화면으로 이동해 AdminMembersPage 를 언마운트한다.
    router.go('/admin/events');
    await tester.pumpAndSettle();

    final refreshCompleter = Completer<List<Profile>>();
    h.members.pendingFetch = refreshCompleter;

    router.go('/admin/members');
    await tester.pump();
    expect(find.text('KAIST 회원'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);

    await tester.pump();
    await tester.pump();
    expect(find.text('KAIST 회원'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    refreshCompleter.complete([
      _profile('m1', campusId: 'k', role: UserRole.member, name: 'KAIST 회원'),
      _profile('m3', campusId: 'k', role: UserRole.member, name: '신규 승인 회원'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('신규 승인 회원'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('cacheFor 는 TTL 안에서는 캐시를 재사용하고 TTL 이 지나면 폐기한다', (tester) async {
    var fetches = 0;
    final sampleProvider = FutureProvider.autoDispose<int>((ref) async {
      ref.cacheFor(const Duration(minutes: 5), userScoped: false);
      return ++fetches;
    });

    final show = ValueNotifier<bool>(true);
    addTearDown(show.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? Consumer(
                    builder: (_, ref, _) {
                      final v = ref.watch(sampleProvider);
                      return Text('v=${v.value}');
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetches, 1);
    expect(find.text('v=1'), findsOneWidget);

    // 언마운트 후 TTL(5분) 안에 다시 마운트하면 캐시를 그대로 쓴다.
    show.value = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    show.value = true;
    await tester.pumpAndSettle();
    expect(fetches, 1);
    expect(find.text('v=1'), findsOneWidget);

    // TTL 이 지나면 폐기되어 다시 불러온다.
    show.value = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 6));
    await tester.pump();
    show.value = true;
    await tester.pumpAndSettle();
    expect(fetches, 2);
    expect(find.text('v=2'), findsOneWidget);
  });

  testWidgets('로그아웃 후 다른 계정으로 로그인하면 이전 사용자 캐시가 노출되지 않는다', (tester) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    router.go('/my-orders');
    await tester.pumpAndSettle();
    expect(find.textContaining('기존 교재'), findsOneWidget);

    // 로그아웃: 셸이 언마운트되고 사용자 스코프 캐시가 즉시 폐기된다.
    h.auth.profile = null;
    container.invalidate(currentUserIdProvider);
    await tester.pumpAndSettle();
    expect(container.exists(myOrdersProvider), isFalse);

    // 다른 계정 로그인 후 내 신청 로딩 중에도 이전 계정 데이터가 보이지 않는다.
    final u2Completer = Completer<List<TextbookOrder>>();
    h.textbooks.pendingMyOrders = u2Completer;
    h.auth.profile = _profile('u2', name: '김철수');
    container.invalidate(currentUserIdProvider);
    await tester.pump();
    await tester.pump();

    router.go('/my-orders');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('기존 교재'), findsNothing);
    expect(find.byType(MyOrdersPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MyOrdersPage),
        matching: find.byType(LoadingView),
      ),
      findsNothing,
    );
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '불러오는 중'), findsWidgets);

    // 스플래시 -> 셸 전환 애니메이션(300ms)이 끝난 뒤에도 주문 로딩 중에는 LoadingView 가 남지 않는다.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('기존 교재'), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '불러오는 중'), findsWidgets);

    u2Completer.complete([_order('o2', 'u2', 'u2 전용 교재')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('u2 전용 교재'), findsOneWidget);
  });

  testWidgets('총괄 관리자가 캠퍼스를 바꾸면 이전 캠퍼스 데이터를 노출하지 않고 회원 캐시는 유지한다', (
    tester,
  ) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    router.go('/my-orders');
    await tester.pumpAndSettle();
    expect(container.exists(myOrdersProvider), isTrue);

    router.go('/admin/events');
    await tester.pumpAndSettle();
    expect(container.exists(eventsProvider(CampusScope.admin)), isTrue);

    router.go('/admin/members');
    await tester.pumpAndSettle();
    expect(find.text('KAIST 회원'), findsOneWidget);
    expect(container.exists(eventsProvider(CampusScope.admin)), isTrue);

    final snuCompleter = Completer<List<Profile>>();
    h.members.pendingFetch = snuCompleter;

    container.read(centralCampusOverrideProvider.notifier).select('s');
    await tester.pump();
    await tester.pump();

    // 서울대 로딩 중에는 KAIST 회원 목록이 보이면 안 되고, 언마운트된 이전 캠퍼스 캐시도 즉시 폐기된다.
    expect(find.text('KAIST 회원'), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(container.exists(eventsProvider(CampusScope.admin)), isFalse);

    snuCompleter.complete([
      _profile('m2', campusId: 's', role: UserRole.member, name: '서울대 회원'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('서울대 회원'), findsOneWidget);
    // 회원 화면 캐시는 본인 캠퍼스 기준이므로 유지된다.
    expect(container.exists(myOrdersProvider), isTrue);
  });

  testWidgets('교재 선택 수량은 탭 전환에도 유지되고 수정 모드와 분리되며 제출/로그아웃/캠퍼스 변경 시 초기화된다', (
    tester,
  ) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    router.go('/textbooks?category=c1');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();
    expect(find.text('선택 2권'), findsOneWidget);
    expect(container.read(textbookCartProvider), {'b1': 2});

    // 다른 탭을 다녀와도 장바구니 수량이 유지된다.
    router.go('/home');
    await tester.pumpAndSettle();
    router.go('/my-orders');
    await tester.pumpAndSettle();
    router.go('/textbooks');
    await tester.pumpAndSettle();
    expect(find.text('선택 2권'), findsOneWidget);
    expect(find.text('2권 선택'), findsOneWidget);

    // 수정 모드는 자체 수량을 쓰고 새 신청 장바구니를 덮어쓰지 않는다.
    router.go('/textbooks?edit=o1');
    await tester.pumpAndSettle();
    expect(find.text('선택 3권'), findsOneWidget);
    expect(container.read(textbookCartProvider), {'b1': 2});

    router.go('/textbooks');
    await tester.pumpAndSettle();
    expect(find.text('선택 2권'), findsOneWidget);

    // 신청을 제출하면 장바구니가 비워진다.
    await tester.tap(find.widgetWithText(FilledButton, '신청하기'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '신청하기'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.textbooks.placedOrders, [
      {'b1': 2},
    ]);
    expect(container.read(textbookCartProvider), isEmpty);

    // 로그아웃 시 초기화된다.
    container.read(textbookCartProvider.notifier).setQuantity('b1', 1);
    expect(container.read(textbookCartProvider), {'b1': 1});
    h.auth.profile = null;
    container.invalidate(currentUserIdProvider);
    await tester.pumpAndSettle();
    expect(container.read(textbookCartProvider), isEmpty);

    // 회원 캠퍼스 변경 시 초기화된다.
    h.auth.profile = _profile('u1', campusId: 'k');
    container.invalidate(currentUserIdProvider);
    await tester.pumpAndSettle();
    container.read(textbookCartProvider.notifier).setQuantity('b1', 1);
    expect(container.read(textbookCartProvider), {'b1': 1});

    h.auth.profile = _profile('u1', campusId: 's');
    container.invalidate(currentProfileProvider);
    await tester.pumpAndSettle();
    expect(container.read(textbookCartProvider), isEmpty);
  });

  testWidgets('HomePage 첫 로딩 시 카드 틀과 플레이스홀더를 스피너 없이 바로 렌더링한다', (tester) async {
    final ordersCompleter = Completer<List<TextbookOrder>>();
    final eventsCompleter = Completer<List<Event>>();
    final textbooks = _FakeTextbooks()..pendingMyOrders = ordersCompleter;
    final events = _FakeEvents()..pendingEvents = eventsCompleter;

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWith((ref) => 'u1'),
          currentProfileProvider.overrideWith((ref) async => _profile('u1')),
          textbookRepositoryProvider.overrideWithValue(textbooks),
          eventRepositoryProvider.overrideWithValue(events),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('내 교재 신청'), findsOneWidget);
    expect(find.text('내 이벤트 송금'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    ordersCompleter.complete([_order('o1', 'u1', '기존 교재')]);
    eventsCompleter.complete(const []);
    await tester.pumpAndSettle();
    expect(find.textContaining('기존 교재'), findsOneWidget);
  });

  testWidgets('관리자 이벤트 상세에서 캠퍼스를 바꾸면 목록으로 이동하고 이전 캠퍼스 이벤트를 노출하지 않는다', (
    tester,
  ) async {
    final h = _Harness();
    h.events.eventsByCampus = {
      'k': [
        Event(
          id: 'e-k',
          campusId: 'k',
          title: 'KAIST 수련회',
          amount: 10000,
          dueDate: null,
          description: '',
          createdAt: DateTime(2026, 11, 1),
        ),
      ],
      's': [
        Event(
          id: 'e-s',
          campusId: 's',
          title: '서울대 수련회',
          amount: 20000,
          dueDate: null,
          description: '',
          createdAt: DateTime(2026, 11, 2),
        ),
      ],
    };
    h.events.paymentsByEvent = {
      'e-k': const [
        EventPayment(
          id: 'p-k',
          eventId: 'e-k',
          userId: 'm1',
          isPaid: false,
          paidAt: null,
          member: EventMember(studentId: '20240001', name: 'KAIST 회원'),
        ),
      ],
    };
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);
    final eventsCallsBefore = h.events.fetchEventsCalls;

    router.go('/admin/events/e-k');
    await tester.pumpAndSettle();
    expect(find.text('KAIST 수련회'), findsOneWidget);
    expect(find.text('KAIST 회원'), findsOneWidget);
    // 상세 화면은 목록(fetchEvents)으로 소속을 확인하지 않는다. 목록 조회 1회는 중첩 경로의
    // 상위 화면(이벤트 관리 목록)이 함께 만들어지며 생긴다.
    expect(h.events.fetchEventsCalls, lessThanOrEqualTo(eventsCallsBefore + 1));
    expect(h.events.fetchEventCalls, 1);

    container.read(centralCampusOverrideProvider.notifier).select('s');
    await tester.pumpAndSettle();

    expect(find.text('서울대 수련회'), findsOneWidget);
    expect(find.text('KAIST 수련회'), findsNothing);
    expect(await container.read(eventProvider('e-k').future), isNull);
    expect(await container.read(eventPaymentsProvider('e-k').future), isEmpty);
  });

  testWidgets('AdminEventDetailPage 는 다른 탭에 있을 때 캠퍼스 전환으로 이동하지 않고 null 경유 전환도 감지한다', (
    tester,
  ) async {
    final h = _Harness();
    h.events.eventsByCampus = {
      'k': [
        Event(
          id: 'e-k',
          campusId: 'k',
          title: 'KAIST 수련회',
          amount: 10000,
          dueDate: null,
          description: '',
          createdAt: DateTime(2026, 11, 1),
        ),
      ],
      's': [
        Event(
          id: 'e-s',
          campusId: 's',
          title: '서울대 수련회',
          amount: 20000,
          dueDate: null,
          description: '',
          createdAt: DateTime(2026, 11, 2),
        ),
      ],
    };
    final container = await h.pumpApp(
      tester,
      extraOverrides: [
        adminCampusIdProvider.overrideWith(
          (ref) => ref.watch(_testCampusProvider),
        ),
      ],
    );
    final router = container.read(routerProvider);

    // 다른 탭(/home)으로 이동해 이벤트 상세가 offstage 일 때 캠퍼스를 바꿔도 /home 을 유지한다.
    router.go('/admin/events/e-k');
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();
    container.read(_testCampusProvider.notifier).setCampus('s');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');

    // 이벤트 상세가 현재 화면일 때 null 을 거쳐 다른 캠퍼스로 바뀌면 목록으로 이동한다.
    router.go('/admin/events/e-s');
    await tester.pumpAndSettle();
    expect(find.text('서울대 수련회'), findsOneWidget);

    container.read(_testCampusProvider.notifier).setCampus(null);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/admin/events/e-s',
    );

    container.read(_testCampusProvider.notifier).setCampus('k');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/admin/events',
    );
  });

  testWidgets('unpaidLinkTargetsProvider 는 캐시되지 않고 다이얼로그 오픈 및 상태 변경 시 갱신된다', (
    tester,
  ) async {
    final h = _Harness();
    h.deposits.firstPage = [
      BankDeposit(
        id: 'd1',
        campusId: 'k',
        bankCode: 'toss',
        status: DepositStatus.unmatched,
        depositorName: '홍길동',
        amount: 5000,
        depositedAt: DateTime(2026, 11, 10, 12),
        receivedAt: DateTime(2026, 11, 10, 12),
      ),
    ];
    h.deposits.counts = const DepositCounts(needsReview: 1, all: 1);
    h.deposits.unpaidTargets = UnpaidLinkTargets(
      orders: [
        UnpaidOrderTarget(
          orderId: 'o1',
          memberName: '홍길동',
          studentId: '20240001',
          roundLabel: '11/1',
          itemsSummary: '기초 교재 ×1',
          amount: 5000,
          createdAt: DateTime(2026, 11, 1),
        ),
      ],
      eventPayments: const [],
    );

    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);
    router.go('/admin/deposits');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '대상 연결'));
    await tester.pumpAndSettle();
    expect(h.deposits.unpaidFetches, 1);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(container.exists(unpaidLinkTargetsProvider), isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, '대상 연결'));
    await tester.pumpAndSettle();
    expect(h.deposits.unpaidFetches, 2);

    // 다이얼로그가 열려 있는 동안 주문 상태를 바꾸면 미납 대상이 즉시 무효화되어 다시 불러온다.
    final ordersSub = container.listen(adminOrdersProvider(_round.id), (_, _) {});
    addTearDown(ordersSub.close);
    await container.read(adminOrdersProvider(_round.id).future);
    await container
        .read(adminOrdersProvider(_round.id).notifier)
        .setStatus('o1', OrderStatus.paid, from: OrderStatus.requested);
    await tester.pumpAndSettle();
    expect(h.deposits.unpaidFetches, 3);
  });

  testWidgets('adminOrdersProvider 한 인스턴스 변경 시 다른 회차 캐시도 무효화된다', (
    tester,
  ) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);

    final roundSub = container.listen(adminOrdersProvider(_round.id), (_, _) {});
    final allSub = container.listen(adminOrdersProvider(null), (_, _) {});
    addTearDown(roundSub.close);
    addTearDown(allSub.close);

    expect(
      (await container.read(adminOrdersProvider(_round.id).future))
          .single
          .status,
      OrderStatus.requested,
    );
    expect(
      (await container.read(adminOrdersProvider(null).future)).single.status,
      OrderStatus.requested,
    );

    await container
        .read(adminOrdersProvider(_round.id).notifier)
        .setStatus('o1', OrderStatus.paid, from: OrderStatus.requested);
    expect(
      (await container.read(adminOrdersProvider(null).future)).single.status,
      OrderStatus.paid,
    );

    await container
        .read(adminOrdersProvider(null).notifier)
        .setStatus('o1', OrderStatus.requested, from: OrderStatus.paid);
    expect(
      (await container.read(adminOrdersProvider(_round.id).future))
          .single
          .status,
      OrderStatus.requested,
    );
  });

  testWidgets('비활성 또는 삭제된 교재는 새 신청 장바구니에서 정리되어 합계와 제출에 포함되지 않는다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.books = [
      Textbook(
        id: 'b1',
        title: '활성 교재',
        price: 5000,
        isActive: true,
        createdAt: DateTime(2026),
        categoryId: 'c1',
        sortOrder: 0,
      ),
      Textbook(
        id: 'b-off',
        title: '비활성 교재',
        price: 7000,
        isActive: false,
        createdAt: DateTime(2026),
        categoryId: 'c1',
        sortOrder: 1,
      ),
    ];

    final container = await h.pumpApp(tester);
    container.read(textbookCartProvider.notifier)
      ..setQuantity('b1', 1)
      ..setQuantity('b-off', 2)
      ..setQuantity('b-deleted', 3);

    final router = container.read(routerProvider);
    router.go('/textbooks?category=c1');
    await tester.pumpAndSettle();

    expect(find.text('선택 1권'), findsOneWidget);
    expect(find.text('비활성 교재'), findsNothing);
    expect(container.read(textbookCartProvider), {'b1': 1});
  });

  testWidgets('입금 내역 화면 재진입 시 첫 페이지 새로고침이 추가 페이지를 초기화하고 중복을 막는다', (
    tester,
  ) async {
    BankDeposit dep(int i, {String? name}) => BankDeposit(
      id: 'd$i',
      campusId: 'k',
      bankCode: 'toss',
      status: DepositStatus.unmatched,
      depositorName: name ?? '입금자$i',
      amount: 5000,
      depositedAt: DateTime(2026, 11, 10, 12),
      receivedAt: DateTime(2026, 11, 10, 12),
    );

    final h = _Harness();
    h.deposits.firstPage = [for (var i = 0; i < depositPageSize; i++) dep(i)];
    h.deposits.secondPage = [dep(50), dep(51)];
    h.deposits.counts = const DepositCounts(needsReview: 52, all: 52);

    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);
    router.go('/admin/deposits');
    await tester.pumpAndSettle();

    final loadMore = find.text('더 보기 (50 / 52)');
    await tester.ensureVisible(loadMore);
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.text('입금자50'), findsOneWidget);
    expect(find.text('입금자51'), findsOneWidget);

    // 다른 탭을 다녀오는 동안 첫 페이지가 갱신되어 d50 이 첫 페이지로 올라왔다.
    router.go('/home');
    await tester.pumpAndSettle();
    h.deposits.firstPage = [dep(50, name: '갱신입금자50')];
    h.deposits.counts = const DepositCounts(needsReview: 1, all: 1);

    router.go('/admin/deposits');
    await tester.pumpAndSettle();
    expect(find.text('갱신입금자50'), findsOneWidget);
    expect(find.text('입금자50'), findsNothing);
    expect(find.text('입금자51'), findsNothing);
  });

  testWidgets('교재 신청 수정은 다른 탭으로 나가면 그만둔 것으로 보고, 취소 시 브랜치 리셋, 재진입 시 최신 주문으로만 채운다', (
    tester,
  ) async {
    final h = _Harness();
    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);

    router.go('/textbooks?edit=o1&category=c1');
    await tester.pumpAndSettle();
    expect(find.text('선택 3권'), findsOneWidget);
    final initialFetches = h.textbooks.fetchOrderCalls;

    await tester.tap(find.byTooltip('더하기'));
    await tester.pumpAndSettle();
    expect(find.text('선택 4권'), findsOneWidget);

    // 다른 탭으로 나갔다 오면 제출 안 한 수정은 버리고 서버의 최신 신청으로 다시 채운다.
    router.go('/home');
    await tester.pumpAndSettle();
    router.go('/textbooks?edit=o1&category=c1');
    await tester.pumpAndSettle();
    expect(find.text('선택 4권'), findsNothing);
    expect(find.text('선택 3권'), findsOneWidget);

    // 수정 취소 시 /my-orders 로 이동하고 교재 탭 브랜치도 /textbooks 로 초기화된다.
    await tester.tap(find.widgetWithText(TextButton, '수정 취소'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/my-orders');

    // 재진입 시 최신 주문 응답이 오기 전에는 캐시 수량으로 확정하지 않고 편집을 막는다.
    final editCompleter = Completer<TextbookOrder?>();
    h.textbooks.editOrderQty = 2;
    h.textbooks.pendingFetchOrder = editCompleter;
    router.go('/textbooks?edit=o1&category=c1');
    await tester.pump();
    await tester.pump();

    final plusButton = find.ancestor(
      of: find.byTooltip('더하기'),
      matching: find.byType(IconButton),
    );
    // 최신 응답 전에는 이전 수량(3권)이나 0권을 보여 주지 않고 비활성 스켈레톤으로 기다린다.
    expect(find.text('선택 3권'), findsNothing);
    expect(find.text('선택 0권'), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.byTooltip('더하기'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기'))
          .onPressed,
      isNull,
    );

    editCompleter.complete(_order('o1', 'u1', '수정 대상 교재', qty: 2));
    await tester.pumpAndSettle();

    expect(h.textbooks.fetchOrderCalls, greaterThan(initialFetches));
    expect(find.text('선택 2권'), findsOneWidget);
    expect(tester.widget<IconButton>(plusButton).onPressed, isNotNull);
  });

  testWidgets('입금 연결 다이얼로그는 최신 미납 목록에 모든 대상이 있는 후보만 연결 가능하고 사라진 선택을 정리한다', (
    tester,
  ) async {
    final h = _Harness();
    h.deposits.firstPage = [
      BankDeposit(
        id: 'd-multi',
        campusId: 'k',
        bankCode: 'toss',
        status: DepositStatus.ambiguous,
        depositorName: '홍길동',
        amount: 10000,
        depositedAt: DateTime(2026, 11, 10, 12),
        receivedAt: DateTime(2026, 11, 10, 12),
        candidates: const [
          DepositCandidate(
            kind: 'orders',
            userId: 'u1',
            label: '멀티 후보',
            amount: 10000,
            orderIds: ['o1', 'o2'],
          ),
          DepositCandidate(
            kind: 'event',
            userId: 'u1',
            label: '완납 이벤트 후보',
            amount: 10000,
            eventId: 'e1',
            eventPaymentId: 'ep-paid',
          ),
        ],
      ),
    ];
    h.deposits.counts = const DepositCounts(needsReview: 1, all: 1);
    h.deposits.unpaidTargets = UnpaidLinkTargets(
      orders: [
        UnpaidOrderTarget(
          orderId: 'o1',
          memberName: '홍길동',
          studentId: '20240001',
          roundLabel: '11/1',
          itemsSummary: '교재A ×1',
          amount: 5000,
          createdAt: DateTime(2026, 11, 1),
        ),
      ],
      eventPayments: const [],
    );

    final container = await h.pumpApp(tester);
    final router = container.read(routerProvider);
    router.go('/admin/deposits');
    await tester.pumpAndSettle();

    // o2 와 ep-paid 가 미납 목록에 없으므로 두 후보 모두 연결 불가(숨김)여야 한다.
    await tester.tap(find.widgetWithText(OutlinedButton, '대상 연결'));
    await tester.pumpAndSettle();
    expect(find.text('추천 후보'), findsNothing);
    expect(find.text('멀티 후보'), findsNothing);
    expect(find.text('완납 이벤트 후보'), findsNothing);

    // 수동 선택한 o1 이 미납 목록 새로고침으로 사라지면 선택이 정리되고 연결 버튼이 비활성화된다.
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('선택 합계 5,000원 (1건)'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '연결')).onPressed,
      isNotNull,
    );

    h.deposits.unpaidTargets = UnpaidLinkTargets.empty;
    container.invalidate(unpaidLinkTargetsProvider);
    await tester.pumpAndSettle();
    expect(find.textContaining('선택 합계'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '연결')).onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    // o1(5,000원) + o2(7,000원)가 모두 미납이면 최신 합계 12,000원으로 후보가 열리고 불일치 확인이 뜬다.
    h.deposits.unpaidTargets = UnpaidLinkTargets(
      orders: [
        UnpaidOrderTarget(
          orderId: 'o1',
          memberName: '홍길동',
          studentId: '20240001',
          roundLabel: '11/1',
          itemsSummary: '교재A ×1',
          amount: 5000,
          createdAt: DateTime(2026, 11, 1),
        ),
        UnpaidOrderTarget(
          orderId: 'o2',
          memberName: '홍길동',
          studentId: '20240001',
          roundLabel: '11/8',
          itemsSummary: '교재B ×1',
          amount: 7000,
          createdAt: DateTime(2026, 11, 8),
        ),
      ],
      eventPayments: const [],
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '대상 연결'));
    await tester.pumpAndSettle();
    expect(find.text('추천 후보'), findsOneWidget);
    expect(find.text('멀티 후보'), findsOneWidget);
    expect(find.text('12,000원'), findsOneWidget);
    expect(find.text('완납 이벤트 후보'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, '연결'));
    await tester.pumpAndSettle();
    expect(find.text('금액 불일치 확인'), findsOneWidget);
    expect(find.textContaining('12,000원'), findsOneWidget);
  });

  testWidgets('백그라운드 새로고침 실패 후 재시도 시 ErrorView 대신 LoadingView 를 표시한다', (
    tester,
  ) async {
    var calls = 0;
    final retryCompleter = Completer<String>();
    final sampleProvider = FutureProvider.autoDispose<String>((ref) async {
      calls++;
      if (calls == 1) return '초기값';
      if (calls == 2) throw Exception('일시 오류');
      return retryCompleter.future;
    });

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                final value = ref.watch(sampleProvider);
                return AsyncValueView<String>(
                  value: value,
                  onRetry: () => ref.invalidate(sampleProvider),
                  data: Text.new,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('초기값'), findsOneWidget);

    // 백그라운드 새로고침이 실패하면 hasValue 와 hasError 가 동시에 참이지만 hasUsableValue 는 거짓이다.
    container.invalidate(sampleProvider);
    await tester.pumpAndSettle();
    final errored = container.read(sampleProvider);
    expect(errored.hasValue, isTrue);
    expect(errored.hasError, isTrue);
    expect(errored.hasUsableValue, isFalse);
    expect(find.byType(ErrorView), findsOneWidget);

    // 다시 시도 중에는 ErrorView 가 고정되지 않고 LoadingView 가 표시된다.
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);

    retryCompleter.complete('복구됨');
    await tester.pumpAndSettle();
    expect(find.text('복구됨'), findsOneWidget);
  });
}
