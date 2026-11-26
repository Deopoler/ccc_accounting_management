import 'dart:async';

import 'package:ccc_accounting_management/core/push/web_push.dart';
import 'package:ccc_accounting_management/core/riverpod/cache_for.dart';
import 'package:ccc_accounting_management/core/router/app_router.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/widgets/state_views.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/member_providers.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
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
  Completer<List<TextbookOrder>>? pendingMyOrders;
  int myOrdersFetches = 0;
  final List<Map<String, int>> placedOrders = [];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [TextbookCategory(id: 'c1', name: '성경공부', sortOrder: 0)];

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => [
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

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [_round];

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
  Future<TextbookOrder?> fetchOrder(String orderId) async =>
      _order(orderId, 'u1', '수정 대상 교재', qty: 3);

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

  @override
  Future<List<Event>> fetchEvents(String campusId) {
    final pending = pendingEvents;
    if (pending != null) {
      pendingEvents = null;
      return pending.future;
    }
    return Future.value(const []);
  }

  @override
  Future<Map<String, EventSummary>> fetchSummaries() async => const {};

  @override
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) async =>
      const {};

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
  _Harness({Profile? initialProfile})
    : auth = _FakeAuth()..profile = initialProfile ?? _profile('u1');

  final _FakeAuth auth;
  final _FakeMembers members = _FakeMembers();
  final _FakeTextbooks textbooks = _FakeTextbooks();
  final _FakeEvents events = _FakeEvents();
  final _FakeSettings settings = _FakeSettings();
  final _FakeCampuses campuses = _FakeCampuses();

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
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
          settingsRepositoryProvider.overrideWithValue(settings),
          pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
          pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
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
    expect(find.byType(LoadingView), findsWidgets);

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
    expect(find.byType(LoadingView), findsOneWidget);
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
}
