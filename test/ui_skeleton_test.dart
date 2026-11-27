import 'dart:async';

import 'package:ccc_accounting_management/core/push/web_push.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/widgets/state_views.dart';
import 'package:ccc_accounting_management/features/admin/data/member_repository.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_event_detail_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_events_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_members_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_orders_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_textbooks_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/member_providers.dart';
import 'package:ccc_accounting_management/features/auth/data/auth_repository.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/data/campus_repository.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/admin_campuses_page.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/deposits/data/deposit_repository.dart';
import 'package:ccc_accounting_management/features/deposits/domain/bank_deposit.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/admin_deposits_page.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/deposit_providers.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
import 'package:ccc_accounting_management/features/events/presentation/events_page.dart';
import 'package:ccc_accounting_management/features/feedback/data/feedback_repository.dart';
import 'package:ccc_accounting_management/features/feedback/domain/feedback_entry.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/admin_feedback_page.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_providers.dart';
import 'package:ccc_accounting_management/features/push/data/push_repository.dart';
import 'package:ccc_accounting_management/features/push/presentation/push_providers.dart';
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

final _member = Profile(
  id: 'u2',
  campusId: 'k',
  studentId: '20240002',
  name: '김민수',
  role: UserRole.member,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026, 9, 2),
);

final _book = Textbook(
  id: 'b1',
  title: '기초 성경공부',
  price: 12000,
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
  categoryId: 'c1',
  sortOrder: 0,
);

const _category = TextbookCategory(id: 'c1', name: '성경공부', sortOrder: 0);

final _order = TextbookOrder(
  id: 'o1',
  userId: 'u1',
  roundId: _round.id,
  round: _round,
  status: OrderStatus.requested,
  totalPrice: 24000,
  createdAt: DateTime(2026, 11, 1, 10),
  items: const [
    TextbookOrderItem(
      textbookId: 'b1',
      title: '기초 성경공부',
      quantity: 2,
      unitPrice: 12000,
    ),
  ],
  member: const OrderMember(studentId: '20240001', name: '홍길동'),
);

final _event = Event(
  id: 'e1',
  campusId: 'k',
  title: '겨울 수련회',
  amount: 35000,
  dueDate: DateTime(_now.year, _now.month, _now.day + 5),
  description: '평창 수련원',
  createdAt: DateTime(2026, 11, 1),
);

final _eventPayment = EventPayment(
  id: 'ep1',
  eventId: 'e1',
  userId: 'u1',
  isPaid: false,
  paidAt: null,
  member: const EventMember(studentId: '20240001', name: '홍길동'),
);

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => 'u1';

  @override
  Future<Profile?> fetchProfile(String userId) async => _admin;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCampuses implements CampusRepository {
  Completer<List<Campus>>? pending;

  @override
  Future<List<Campus>> listCampuses() {
    if (pending != null) return pending!.future;
    return Future.value(const [
      Campus(id: 'k', code: 'kaist', name: 'KAIST', emailDomain: 'ccc.local'),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMembers implements MemberRepository {
  Completer<List<Profile>>? pending;

  @override
  Future<List<Profile>> fetchMembers(String campusId) {
    if (pending != null) return pending!.future;
    return Future.value([_admin, _member]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  Completer<List<TextbookCategory>>? pendingCategories;
  Completer<List<Textbook>>? pendingTextbooks;
  Completer<OrderRound>? pendingRound;
  Completer<List<OrderRound>>? pendingRounds;
  Completer<List<TextbookOrder>>? pendingMyOrders;
  Completer<List<TextbookOrder>>? pendingAllOrders;
  Completer<TextbookOrder?>? pendingOrder;

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) {
    if (pendingCategories != null) return pendingCategories!.future;
    return Future.value(const [_category]);
  }

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) {
    if (pendingTextbooks != null) return pendingTextbooks!.future;
    return Future.value([_book]);
  }

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) {
    if (pendingRound != null) return pendingRound!.future;
    return Future.value(_round);
  }

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) {
    if (pendingRounds != null) return pendingRounds!.future;
    return Future.value([_round]);
  }

  @override
  Future<List<TextbookOrder>> fetchMyOrders(String userId) {
    if (pendingMyOrders != null) return pendingMyOrders!.future;
    return Future.value([_order]);
  }

  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) {
    if (pendingAllOrders != null) return pendingAllOrders!.future;
    return Future.value([_order]);
  }

  @override
  Future<TextbookOrder?> fetchOrder(String orderId) {
    if (pendingOrder != null) return pendingOrder!.future;
    return Future.value(_order);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEvents implements EventRepository {
  Completer<List<Event>>? pendingEvents;
  Completer<Event?>? pendingEvent;
  Completer<Map<String, EventSummary>>? pendingSummaries;
  Completer<Map<String, EventPayment>>? pendingMyPayments;
  Completer<List<EventPayment>>? pendingPayments;

  @override
  Future<List<Event>> fetchEvents(String campusId) {
    if (pendingEvents != null) return pendingEvents!.future;
    return Future.value([_event]);
  }

  @override
  Future<Event?> fetchEvent(String id) {
    if (pendingEvent != null) return pendingEvent!.future;
    return Future.value(_event);
  }

  @override
  Future<Map<String, EventSummary>> fetchSummaries() {
    if (pendingSummaries != null) return pendingSummaries!.future;
    return Future.value({
      _event.id: EventSummary.fromPayments([_eventPayment], _event),
    });
  }

  @override
  Future<Map<String, EventPayment>> fetchMyPayments(String userId) {
    if (pendingMyPayments != null) return pendingMyPayments!.future;
    return Future.value({_event.id: _eventPayment});
  }

  @override
  Future<List<EventPayment>> fetchPayments(String eventId) {
    if (pendingPayments != null) return pendingPayments!.future;
    return Future.value([_eventPayment]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeposits implements DepositRepository {
  Completer<List<BankDeposit>>? pendingDeposits;
  Completer<DepositCounts>? pendingCounts;
  Completer<CampusDepositSettings>? pendingSettings;

  @override
  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) {
    if (pendingDeposits != null) return pendingDeposits!.future;
    return Future.value([
      BankDeposit(
        id: 'd1',
        campusId: campusId,
        bankCode: 'toss',
        status: DepositStatus.unmatched,
        depositorName: '홍길동',
        amount: 24000,
        depositedAt: DateTime(2026, 11, 10, 12),
        receivedAt: DateTime(2026, 11, 10, 12),
      ),
    ]);
  }

  @override
  Future<DepositCounts> fetchDepositCounts(String campusId) {
    if (pendingCounts != null) return pendingCounts!.future;
    return Future.value(const DepositCounts(needsReview: 1, all: 1));
  }

  @override
  Future<CampusDepositSettings> fetchSettings(String campusId) {
    if (pendingSettings != null) return pendingSettings!.future;
    return Future.value(
      CampusDepositSettings(campusId: campusId, enabled: true, accountLabel: 'KAIST CCC'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings implements SettingsRepository {
  Completer<BankAccount>? pendingAccount;

  @override
  Future<BankAccount> fetchBankAccount(String campusId) {
    if (pendingAccount != null) return pendingAccount!.future;
    return Future.value(
      const BankAccount(
        bankName: '카카오뱅크',
        accountNumber: '3333-01-1234567',
        holder: '회계',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFeedback implements FeedbackRepository {
  Completer<List<FeedbackEntry>>? pendingFeedback;

  @override
  Future<List<FeedbackEntry>> fetchFeedback({bool unresolvedOnly = false}) {
    if (pendingFeedback != null) return pendingFeedback!.future;
    return Future.value([
      FeedbackEntry(
        id: 'f1',
        userId: 'u2',
        content: '감사합니다',
        createdAt: DateTime(2026, 11, 18, 15, 30),
        senderName: '김민수',
        senderStudentId: '20240002',
        campusName: 'KAIST',
      ),
    ]);
  }

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
  final campuses = _FakeCampuses();
  final members = _FakeMembers();
  final textbooks = _FakeTextbooks();
  final events = _FakeEvents();
  final deposits = _FakeDeposits();
  final settings = _FakeSettings();
  final feedback = _FakeFeedback();

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(1280, 800),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWith((ref) => 'u1'),
          authRepositoryProvider.overrideWithValue(_FakeAuth()),
          campusRepositoryProvider.overrideWithValue(campuses),
          memberRepositoryProvider.overrideWithValue(members),
          textbookRepositoryProvider.overrideWithValue(textbooks),
          eventRepositoryProvider.overrideWithValue(events),
          depositRepositoryProvider.overrideWithValue(deposits),
          settingsRepositoryProvider.overrideWithValue(settings),
          feedbackRepositoryProvider.overrideWithValue(feedback),
          pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
          pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('TextbooksPage 새 신청 로딩 중에는 배너 틀/플레이스홀더를 보이고 제출을 막는다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.pendingRound = Completer<OrderRound>();
    h.textbooks.pendingCategories = Completer<List<TextbookCategory>>();
    h.textbooks.pendingTextbooks = Completer<List<Textbook>>();

    await h.pump(tester, const TextbooksPage());

    expect(find.text('이번 회차'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('선택 0권'), findsNothing);
    expect(find.text('0원'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '신청하기')).onPressed,
      isNull,
    );

    h.textbooks.pendingRound!.complete(_round);
    h.textbooks.pendingCategories!.complete(const [_category]);
    h.textbooks.pendingTextbooks!.complete([_book]);
    await tester.pumpAndSettle();

    expect(find.text('성경공부'), findsOneWidget);
    expect(find.text('선택 0권'), findsOneWidget);
    expect(find.text('0원'), findsOneWidget);
  });

  testWidgets('TextbooksPage 수정 모드에서 주문 로딩 중에는 0권 대신 스켈레톤을 보이고 스테퍼와 제출을 막는다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.pendingOrder = Completer<TextbookOrder?>();

    await h.pump(tester, const TextbooksPage(editOrderId: 'o1', categoryId: 'c1'));

    expect(find.text('신청 내역 수정 중'), findsOneWidget);
    expect(find.text('기초 성경공부'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('0'), findsNothing);
    expect(find.text('선택 0권'), findsNothing);

    final plus = find.ancestor(
      of: find.byTooltip('더하기'),
      matching: find.byType(IconButton),
    );
    final minus = find.ancestor(
      of: find.byTooltip('빼기'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    expect(tester.widget<IconButton>(minus).onPressed, isNull);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기')).onPressed,
      isNull,
    );

    h.textbooks.pendingOrder!.complete(_order);
    await tester.pumpAndSettle();

    expect(find.text('선택 2권'), findsOneWidget);
    expect(find.text('24,000원'), findsOneWidget);
    expect(tester.widget<IconButton>(plus).onPressed, isNotNull);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기')).onPressed,
      isNotNull,
    );
  });

  testWidgets('MyOrdersPage 로딩 중에는 알림 카드와 주문 플레이스홀더를 먼저 그린다', (tester) async {
    final h = _Harness();
    h.textbooks.pendingMyOrders = Completer<List<TextbookOrder>>();
    h.textbooks.pendingRound = Completer<OrderRound>();

    await h.pump(tester, const MyOrdersPage());

    expect(find.text('교재 도착 알림'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.textbooks.pendingMyOrders!.complete([_order]);
    h.textbooks.pendingRound!.complete(_round);
    await tester.pumpAndSettle();

    expect(find.textContaining('기초 성경공부'), findsOneWidget);
    expect(find.text('입금 대기 금액'), findsOneWidget);
    expect(find.text('24,000원'), findsNWidgets(3));
  });

  testWidgets('OrderCompletePage 로딩 중에도 완료 안내와 계좌/알림 영역을 먼저 그린다', (tester) async {
    final h = _Harness();
    h.textbooks.pendingOrder = Completer<TextbookOrder?>();
    h.settings.pendingAccount = Completer<BankAccount>();

    await h.pump(tester, const OrderCompletePage(orderId: 'o1'));

    expect(find.text('교재 신청이 완료되었습니다'), findsOneWidget);
    expect(find.text('송금 계좌 안내'), findsOneWidget);
    expect(find.text('교재 도착 알림'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.textbooks.pendingOrder!.complete(_order);
    h.settings.pendingAccount!.complete(
      const BankAccount(
        bankName: '카카오뱅크',
        accountNumber: '3333-01-1234567',
        holder: '회계',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('24,000원'), findsWidgets);
    expect(find.text('카카오뱅크'), findsOneWidget);
  });

  testWidgets('EventsPage 는 이벤트가 먼저 오면 제목을 그리고 결제 정보는 독립적으로 채운다', (tester) async {
    final h = _Harness();
    h.events.pendingEvents = Completer<List<Event>>();
    h.events.pendingMyPayments = Completer<Map<String, EventPayment>>();

    await h.pump(tester, const EventsPage());
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.events.pendingEvents!.complete([_event]);
    await tester.pumpAndSettle();
    expect(find.text('겨울 수련회'), findsOneWidget);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('대상 아님'), findsNothing);

    h.events.pendingMyPayments!.complete({_event.id: _eventPayment});
    await tester.pumpAndSettle();
    expect(find.text('35,000원'), findsWidgets);
    expect(find.text('미납'), findsOneWidget);
  });

  testWidgets('AdminOrdersPage 로딩 중에는 필터/통계/집계표 틀을 그리고 내보내기/회차이동을 비활성화한다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.pendingRound = Completer<OrderRound>();
    h.textbooks.pendingRounds = Completer<List<OrderRound>>();
    h.textbooks.pendingAllOrders = Completer<List<TextbookOrder>>();

    await h.pump(tester, const AdminOrdersPage());

    expect(find.text('전체 상태'), findsOneWidget);
    expect(find.text('전체 배송'), findsOneWidget);
    expect(find.text('교재별 집계 (취소 제외)'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('0건'), findsNothing);
    expect(find.text('0원'), findsNothing);

    final prevBtn = find.ancestor(
      of: find.byTooltip('이전 회차'),
      matching: find.byType(IconButton),
    );
    final exportBtn = find.widgetWithText(OutlinedButton, 'CSV 내보내기');
    expect(tester.widget<IconButton>(prevBtn).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(exportBtn).onPressed, isNull);

    h.textbooks.pendingRound!.complete(_round);
    h.textbooks.pendingRounds!.complete([_round]);
    h.textbooks.pendingAllOrders!.complete([_order]);
    await tester.pumpAndSettle();

    expect(find.text('신청 1건'), findsOneWidget);
    expect(find.text('24,000원'), findsWidgets);
    expect(tester.widget<OutlinedButton>(exportBtn).onPressed, isNotNull);
  });

  testWidgets('AdminEventsPage 로딩 중에는 추가 버튼을 비활성화하고 요약이 늦어도 이벤트 목록을 먼저 그린다', (
    tester,
  ) async {
    final h = _Harness();
    h.events.pendingEvents = Completer<List<Event>>();
    h.events.pendingSummaries = Completer<Map<String, EventSummary>>();

    await h.pump(tester, const AdminEventsPage());

    expect(find.text('이벤트'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '이벤트 추가')).onPressed,
      isNull,
    );

    h.events.pendingEvents!.complete([_event]);
    await tester.pumpAndSettle();

    expect(find.text('겨울 수련회'), findsOneWidget);
    expect(find.text('0/0명'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('불러오는 중')), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '이벤트 추가')).onPressed,
      isNotNull,
    );

    h.events.pendingSummaries!.complete({
      _event.id: EventSummary.fromPayments([_eventPayment], _event),
    });
    await tester.pumpAndSettle();

    expect(find.text('완납 0/1명'), findsOneWidget);
  });

  testWidgets('AdminEventDetailPage 로딩 중에는 액션 버튼들을 비활성화하고 스켈레톤을 보인다', (
    tester,
  ) async {
    final h = _Harness();
    h.events.pendingEvent = Completer<Event?>();
    h.events.pendingPayments = Completer<List<EventPayment>>();

    await h.pump(tester, const AdminEventDetailPage(eventId: 'e1'));

    expect(find.text('전체'), findsOneWidget);
    expect(find.text('미납'), findsOneWidget);
    expect(find.text('완납'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '대상 추가')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '미납자 복사')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '미납자 CSV')).onPressed,
      isNull,
    );

    h.events.pendingEvent!.complete(_event);
    h.events.pendingPayments!.complete([_eventPayment]);
    await tester.pumpAndSettle();

    expect(find.text('겨울 수련회'), findsOneWidget);
    expect(find.text('전체 1'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '대상 추가')).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '미납자 복사')).onPressed,
      isNotNull,
    );
  });

  testWidgets('AdminTextbooksPage 로딩 중에는 섹션과 비활성 추가 버튼을 먼저 그린다', (tester) async {
    final h = _Harness();
    h.textbooks.pendingCategories = Completer<List<TextbookCategory>>();
    h.textbooks.pendingTextbooks = Completer<List<Textbook>>();

    await h.pump(tester, const AdminTextbooksPage());

    expect(find.text('카테고리'), findsOneWidget);
    expect(find.text('교재'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '카테고리 추가')).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '교재 추가')).onPressed,
      isNull,
    );

    h.textbooks.pendingCategories!.complete(const [_category]);
    await tester.pumpAndSettle();
    // 카테고리는 먼저 보이지만 교재가 아직 로딩 중이면 '교재 0종'을 띄우지 않는다.
    expect(find.text('성경공부'), findsOneWidget);
    expect(find.text('교재 0종'), findsNothing);

    h.textbooks.pendingTextbooks!.complete([_book]);
    await tester.pumpAndSettle();
    expect(find.text('교재 1종'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '교재 추가')).onPressed,
      isNotNull,
    );
  });

  testWidgets('AdminFeedbackPage / AdminMembersPage / AdminDepositsPage / AdminSettingsPage / AdminCampusesPage 스켈레톤 및 다크 테마', (
    tester,
  ) async {
    final h = _Harness();
    h.feedback.pendingFeedback = Completer<List<FeedbackEntry>>();
    await h.pump(tester, const AdminFeedbackPage(), theme: AppTheme.dark());
    expect(find.text('미확인'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.members.pending = Completer<List<Profile>>();
    await h.pump(tester, const AdminMembersPage(), theme: AppTheme.dark());
    expect(find.text('가입 승인 대기'), findsOneWidget);
    expect(find.text('회원'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.deposits.pendingDeposits = Completer<List<BankDeposit>>();
    h.deposits.pendingCounts = Completer<DepositCounts>();
    await h.pump(tester, const AdminDepositsPage(), theme: AppTheme.dark());
    expect(find.text('검토 필요'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.settings.pendingAccount = Completer<BankAccount>();
    h.textbooks.pendingRound = Completer<OrderRound>();
    h.deposits.pendingSettings = Completer<CampusDepositSettings>();
    await h.pump(tester, const AdminSettingsPage(), theme: AppTheme.dark());
    expect(find.text('송금 계좌'), findsOneWidget);
    expect(find.text('교재 신청 마감'), findsOneWidget);
    expect(find.text('자동 입금 확인'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '마감 저장')).onPressed,
      isNull,
    );

    h.campuses.pending = Completer<List<Campus>>();
    await h.pump(tester, const AdminCampusesPage(), theme: AppTheme.dark());
    expect(find.text('캠퍼스'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '캠퍼스 추가')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
