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
import 'package:ccc_accounting_management/features/deposits/presentation/deposit_settings_card.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
import 'package:ccc_accounting_management/features/events/presentation/events_page.dart';
import 'package:ccc_accounting_management/features/feedback/data/feedback_repository.dart';
import 'package:ccc_accounting_management/features/feedback/domain/feedback_entry.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/admin_feedback_page.dart';
import 'package:ccc_accounting_management/features/feedback/presentation/feedback_providers.dart';
import 'package:ccc_accounting_management/features/home/presentation/home_page.dart';
import 'package:ccc_accounting_management/features/push/data/push_repository.dart';
import 'package:ccc_accounting_management/features/push/presentation/push_providers.dart';
import 'package:ccc_accounting_management/features/settings/data/settings_repository.dart';
import 'package:ccc_accounting_management/features/settings/domain/bank_account.dart';
import 'package:ccc_accounting_management/features/settings/presentation/bank_account_card.dart';
import 'package:ccc_accounting_management/features/settings/presentation/settings_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/data/textbook_repository.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/my_orders_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/order_complete_page.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/round_deadline_form.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbooks_page.dart';
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
  String userId = 'u1';
  Completer<Profile?>? pendingProfile;
  Profile? profileResult = _admin;
  Object? profileError;

  @override
  String? get currentUserId => userId;

  @override
  Future<Profile?> fetchProfile(String userId) {
    if (pendingProfile != null) return pendingProfile!.future;
    if (profileError != null) return Future.error(profileError!);
    return Future.value(profileResult);
  }

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

  List<TextbookCategory> categoriesResult = const [_category];
  List<OrderRound>? roundsResult;
  Object? roundsError;
  Map<String?, List<TextbookOrder>> ordersByRound = {};
  TextbookOrder? orderResult = _order;
  final List<List<String>> reorderedCategories = [];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) {
    if (pendingCategories != null) return pendingCategories!.future;
    return Future.value(categoriesResult);
  }

  @override
  Future<void> reorderCategories(List<String> orderedIds) async {
    reorderedCategories.add(orderedIds);
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
    if (roundsError != null) return Future.error(roundsError!);
    return Future.value(roundsResult ?? [_round]);
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
    if (ordersByRound.isNotEmpty) {
      return Future.value(ordersByRound[roundId] ?? const []);
    }
    return Future.value([_order]);
  }

  @override
  Future<TextbookOrder?> fetchOrder(String orderId) {
    if (pendingOrder != null) return pendingOrder!.future;
    return Future.value(orderResult);
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
  Completer<List<({String depositId, DepositStatus status})>>? pendingReparse;
  Completer<void>? pendingIgnore;
  Object? depositsError;
  DepositCounts countsResult = const DepositCounts(needsReview: 1, all: 1);

  @override
  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) {
    if (pendingDeposits != null) return pendingDeposits!.future;
    if (depositsError != null) return Future.error(depositsError!);
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
    return Future.value(countsResult);
  }

  @override
  Future<CampusDepositSettings> fetchSettings(String campusId) {
    if (pendingSettings != null) return pendingSettings!.future;
    return Future.value(
      CampusDepositSettings(campusId: campusId, enabled: true, accountLabel: 'KAIST CCC'),
    );
  }

  @override
  Future<void> ignoreDeposit(String depositId, {required bool ignore}) {
    if (pendingIgnore != null) return pendingIgnore!.future;
    return Future.value();
  }

  @override
  Future<List<({String depositId, DepositStatus status})>> reparse({
    String? depositId,
    String? campusId,
  }) {
    if (pendingReparse != null) return pendingReparse!.future;
    return Future.value(const []);
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
  final auth = _FakeAuth();
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
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        retry: (_, _) => null,
        overrides: [
          currentUserIdProvider.overrideWith((ref) => auth.currentUserId),
          authRepositoryProvider.overrideWithValue(auth),
          campusRepositoryProvider.overrideWithValue(campuses),
          memberRepositoryProvider.overrideWithValue(members),
          textbookRepositoryProvider.overrideWithValue(textbooks),
          eventRepositoryProvider.overrideWithValue(events),
          depositRepositoryProvider.overrideWithValue(deposits),
          settingsRepositoryProvider.overrideWithValue(settings),
          feedbackRepositoryProvider.overrideWithValue(feedback),
          pushBrowserProvider.overrideWithValue(_FakePushBrowser()),
          pushRepositoryProvider.overrideWithValue(_FakePushRepo()),
          ...extraOverrides,
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
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.byTooltip('더하기'), findsNothing);
    expect(find.byTooltip('빼기'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('선택 0권'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기')).onPressed,
      isNull,
    );

    h.textbooks.pendingOrder!.complete(_order);
    await tester.pumpAndSettle();

    final plus = find.ancestor(
      of: find.byTooltip('더하기'),
      matching: find.byType(IconButton),
    );
    expect(find.text('기초 성경공부'), findsOneWidget);
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

  testWidgets('AdminOrdersPage 로딩 중에는 상태 칩/집계 아코디언 스켈레톤을 그리고 변경 컨트롤을 비활성화한다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.pendingRound = Completer<OrderRound>();
    h.textbooks.pendingRounds = Completer<List<OrderRound>>();
    h.textbooks.pendingAllOrders = Completer<List<TextbookOrder>>();

    await h.pump(tester, const AdminOrdersPage());

    expect(find.text('전체 상태'), findsOneWidget);
    expect(find.text('취소 제외'), findsOneWidget);
    expect(find.text('전체 배송'), findsOneWidget);
    expect(find.text('교재별 집계 (취소 제외)'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('0건'), findsNothing);
    expect(find.text('0원'), findsNothing);
    expect(find.text('0권'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '이전 회차로'), findsNothing);

    final prevBtn = find.ancestor(
      of: find.byTooltip('이전 회차'),
      matching: find.byType(IconButton),
    );
    final deadlineChip = find.widgetWithText(ActionChip, '마감 변경');
    final exportBtn = find.widgetWithText(OutlinedButton, 'CSV 내보내기');
    expect(tester.widget<IconButton>(prevBtn).onPressed, isNull);
    expect(tester.widget<ActionChip>(deadlineChip).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(exportBtn).onPressed, isNull);

    h.textbooks.pendingRound!.complete(_round);
    h.textbooks.pendingRounds!.complete([_round]);
    h.textbooks.pendingAllOrders!.complete([_order]);
    await tester.pumpAndSettle();

    expect(find.text('신청 1건'), findsOneWidget);
    expect(find.text('24,000원'), findsWidgets);
    expect(find.text('총 2권 · 24,000원'), findsOneWidget);
    expect(tester.widget<ActionChip>(deadlineChip).onPressed, isNotNull);
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

  testWidgets('AdminFeedbackPage / AdminMembersPage / AdminDepositsPage / 설정 카드 / AdminCampusesPage 스켈레톤 및 다크 테마', (
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
    expect(find.text('회원'), findsWidgets);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.deposits.pendingDeposits = Completer<List<BankDeposit>>();
    h.deposits.pendingCounts = Completer<DepositCounts>();
    await h.pump(tester, const AdminDepositsPage(), theme: AppTheme.dark());
    expect(find.text('검토 필요'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.settings.pendingAccount = Completer<BankAccount>();
    await h.pump(
      tester,
      const AdminMembersPage(tab: AdminMembersPage.accountTab),
      theme: AppTheme.dark(),
    );
    expect(find.text('송금 계좌'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed,
      isNull,
    );

    h.textbooks.pendingRound = Completer<OrderRound>();
    await h.pump(tester, const RoundDeadlineForm(), theme: AppTheme.dark());
    expect(find.text('교재 신청 마감'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '마감 저장')).onPressed,
      isNull,
    );

    h.deposits.pendingSettings = Completer<CampusDepositSettings>();
    await h.pump(
      tester,
      const SingleChildScrollView(child: DepositSettingsCard()),
      theme: AppTheme.dark(),
    );
    expect(find.text('자동 입금 확인'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

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

  testWidgets('TextbooksPage 수정 모드에서 currentRoundProvider 로딩 중에는 입금확인 주문을 편집할 수 없다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.pendingRound = Completer<OrderRound>();
    h.textbooks.pendingOrder = Completer<TextbookOrder?>();

    await h.pump(tester, const TextbooksPage(editOrderId: 'o_paid', categoryId: 'c1'));

    final paidOrder = TextbookOrder(
      id: 'o_paid',
      userId: 'u1',
      roundId: _round.id,
      round: _round,
      status: OrderStatus.paid,
      totalPrice: 24000,
      createdAt: _order.createdAt,
      items: _order.items,
      member: _order.member,
    );
    h.textbooks.pendingOrder!.complete(paidOrder);
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.byTooltip('더하기'), findsNothing);
    expect(find.text('기초 성경공부'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기')).onPressed,
      isNull,
    );

    h.textbooks.pendingRound!.complete(_round);
    await tester.pumpAndSettle();

    expect(find.text('입금확인되었거나 마감된 신청은 수정할 수 없습니다.'), findsOneWidget);
  });

  testWidgets('TextbooksPage 수정 모드에서 새로고침된 주문이 null 이 되면 잠금 스켈레톤에 갇히지 않고 빈 화면을 보인다', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, const TextbooksPage(editOrderId: 'o1', categoryId: 'c1'));
    await tester.pumpAndSettle();

    expect(find.text('선택 2권'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정하기')).onPressed,
      isNotNull,
    );

    h.textbooks.orderResult = null;
    ProviderScope.containerOf(
      tester.element(find.byType(TextbooksPage)),
    ).invalidate(orderProvider('o1'));
    await tester.pumpAndSettle();

    expect(find.text('신청 내역을 찾을 수 없습니다.'), findsOneWidget);
    expect(find.bySemanticsLabel('불러오는 중'), findsNothing);
  });

  testWidgets('프로필 로딩으로 campusId 가 아직 null 인 동안 각 화면은 빈 상태나 0건 대신 스켈레톤을 보인다', (
    tester,
  ) async {
    final h = _Harness();
    h.auth.pendingProfile = Completer<Profile?>();

    await h.pump(tester, const TextbooksPage());
    expect(find.byType(EmptyView), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.text('0원'), findsNothing);

    await h.pump(tester, const MyOrdersPage());
    expect(find.byType(EmptyView), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    await h.pump(tester, const AdminOrdersPage());
    expect(find.byType(EmptyView), findsNothing);
    expect(find.text('신청 회차가 없습니다.'), findsNothing);
    expect(find.text('0건'), findsNothing);
    expect(find.text('0원'), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    await h.pump(tester, const AdminEventDetailPage(eventId: 'e1'));
    expect(find.byType(EmptyView), findsNothing);
    expect(find.text('0/0명'), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    await h.pump(tester, const HomePage());
    expect(find.byType(EmptyView), findsNothing);
    expect(find.text('0건'), findsNothing);
    expect(find.text('0원'), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);

    h.auth.pendingProfile!.complete(_admin);
    await tester.pumpAndSettle();

    expect(find.text('홍길동님, 안녕하세요'), findsOneWidget);
  });

  testWidgets('AdminDepositsPage 에서 입금 목록이 로딩 중이거나 오류일 때는 해석 실패 일괄 재실행 버튼을 비활성화한다', (
    tester,
  ) async {
    final h = _Harness();
    h.deposits.countsResult = const DepositCounts(
      needsReview: 1,
      unparsedWithRaw: 2,
      all: 3,
    );
    h.deposits.pendingDeposits = Completer<List<BankDeposit>>();

    await h.pump(tester, const AdminDepositsPage());

    final bulkBtn = find.ancestor(
      of: find.text('해석 실패 일괄 재실행 (2)'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(bulkBtn).onPressed, isNull);

    h.deposits.pendingDeposits!.completeError(Exception('boom'));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(bulkBtn).onPressed, isNull);

    h.deposits.pendingDeposits = null;
    ProviderScope.containerOf(
      tester.element(find.byType(AdminDepositsPage)),
    ).invalidate(bankDepositsProvider(DepositFilter.needsReview));
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(bulkBtn).onPressed, isNotNull);
  });

  testWidgets('AdminTextbooksPage 는 카테고리를 sortOrder 와 이름 순으로 정렬해 표시하고 재정렬 요청에도 반영한다', (
    tester,
  ) async {
    final h = _Harness();
    h.textbooks.categoriesResult = const [
      TextbookCategory(id: 'c3', name: '다과목', sortOrder: 1),
      TextbookCategory(id: 'c1', name: '가과목', sortOrder: 0),
      TextbookCategory(id: 'c2', name: '나과목', sortOrder: 1),
    ];

    await h.pump(tester, const AdminTextbooksPage());
    await tester.pumpAndSettle();

    final y1 = tester.getTopLeft(find.text('가과목')).dy;
    final y2 = tester.getTopLeft(find.text('나과목')).dy;
    final y3 = tester.getTopLeft(find.text('다과목')).dy;
    expect(y1, lessThan(y2));
    expect(y2, lessThan(y3));

    await tester.tap(find.byTooltip('다과목 위로 이동'));
    await tester.pumpAndSettle();

    expect(h.textbooks.reorderedCategories, [
      ['c1', 'c3', 'c2'],
    ]);
  });

  testWidgets('OrderCompletePage 는 주문 새로고침 중 이전 금액과 복사 버튼을 숨기고 스켈레톤을 보인다', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, const OrderCompletePage(orderId: 'o1', edited: true));
    await tester.pumpAndSettle();

    expect(find.text('24,000원'), findsWidgets);
    // 송금 금액 + 계좌번호 복사 버튼 2개
    expect(find.widgetWithText(TextButton, '복사'), findsNWidgets(2));

    final refreshCompleter = Completer<TextbookOrder?>();
    h.textbooks.pendingOrder = refreshCompleter;
    ProviderScope.containerOf(
      tester.element(find.byType(OrderCompletePage)),
    ).invalidate(orderProvider('o1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('24,000원'), findsNothing);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    // 송금 금액 행은 스켈레톤이므로 계좌번호 복사 버튼 1개만 남는다.
    expect(find.widgetWithText(TextButton, '복사'), findsOneWidget);

    refreshCompleter.complete(
      TextbookOrder(
        id: 'o1',
        userId: 'u1',
        roundId: _round.id,
        round: _round,
        status: OrderStatus.requested,
        totalPrice: 36000,
        createdAt: _order.createdAt,
        items: const [
          TextbookOrderItem(
            textbookId: 'b1',
            title: '기초 성경공부',
            quantity: 3,
            unitPrice: 12000,
          ),
        ],
        member: _order.member,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('36,000원'), findsWidgets);
    expect(find.widgetWithText(TextButton, '복사'), findsNWidgets(2));
  });

  testWidgets('HomePage 는 currentRound 가 null 로 확정되면 미납/안내 정보를 표시한다', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(
      tester,
      const HomePage(),
      extraOverrides: [
        currentRoundProvider.overrideWith((ref) async => null),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 신청 가능한 회차가 없습니다.'), findsOneWidget);
    expect(find.text('0건'), findsOneWidget);
    expect(find.text('24,000원'), findsOneWidget);
    expect(find.bySemanticsLabel('불러오는 중'), findsNothing);
  });

  testWidgets('계정 전환 재로딩 중 campusId 는 이전 사용자 캠퍼스를 노출하지 않는다', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, const MyOrdersPage());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyOrdersPage)),
    );
    expect(container.read(myCampusIdProvider), 'k');
    expect(container.read(adminCampusIdProvider), 'k');
    expect(find.textContaining('기초 성경공부'), findsOneWidget);

    h.auth.userId = 'u2';
    final profileCompleter = Completer<Profile?>();
    h.auth.pendingProfile = profileCompleter;
    container.invalidate(currentUserIdProvider);
    await tester.pump();
    await tester.pump();

    expect(container.read(myCampusIdProvider), isNull);
    expect(container.read(adminCampusIdProvider), isNull);
    expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
    expect(find.textContaining('기초 성경공부'), findsNothing);

    profileCompleter.complete(_member);
    await tester.pumpAndSettle();
    expect(container.read(myCampusIdProvider), 'k');
  });

  testWidgets('프로필 조회 오류 시 ErrorView 를 보이고 다시 시도로 복구한다', (tester) async {
    final h = _Harness();
    h.auth.profileError = Exception('profile failed');

    await h.pump(tester, const HomePage());
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.bySemanticsLabel('불러오는 중'), findsNothing);

    h.auth.profileError = null;
    await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('홍길동님, 안녕하세요'), findsOneWidget);
  });

  testWidgets('프로필에 캠퍼스가 없으면 빈 캠퍼스 안내 EmptyView 를 보인다', (tester) async {
    final h = _Harness();
    h.auth.profileResult = Profile(
      id: 'u_empty',
      campusId: '',
      studentId: '20249999',
      name: '미배정',
      role: UserRole.member,
      mustChangePassword: false,
      isApproved: true,
      createdAt: DateTime(2026, 9, 1),
    );

    for (final widget in const [
      TextbooksPage(),
      MyOrdersPage(),
      HomePage(),
      BankAccountCard(),
      AdminDepositsPage(),
    ]) {
      await h.pump(tester, widget);
      await tester.pumpAndSettle();
      expect(find.text(missingCampusMessage), findsOneWidget);
      expect(find.bySemanticsLabel('불러오는 중'), findsNothing);
    }
  });

  testWidgets('AdminOrdersPage 는 과거 회차 선택 중 회차 목록이 실패해도 선택 회차를 유지하고 변경을 잠근다', (
    tester,
  ) async {
    final pastRound = OrderRound(
      id: 'r_past',
      start: DateTime(_now.year, _now.month, _now.day - 7, 9),
      deadline: DateTime(_now.year, _now.month, _now.day - 1, 9),
    );
    final pastOrder = TextbookOrder(
      id: 'o_past',
      userId: 'u2',
      roundId: pastRound.id,
      round: pastRound,
      status: OrderStatus.requested,
      totalPrice: 15000,
      createdAt: DateTime(2026, 10, 20, 10),
      items: const [
        TextbookOrderItem(
          textbookId: 'b2',
          title: '지난 회차 교재',
          quantity: 1,
          unitPrice: 15000,
        ),
      ],
      member: const OrderMember(studentId: '20240002', name: '김민수'),
    );

    final h = _Harness();
    h.textbooks.roundsResult = [_round, pastRound];
    h.textbooks.ordersByRound = {
      _round.id: [_order],
      pastRound.id: [pastOrder],
    };

    await h.pump(tester, const AdminOrdersPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('이전 회차'));
    await tester.pumpAndSettle();

    expect(find.text('지난 회차 교재 ×1'), findsOneWidget);
    expect(find.text('기초 성경공부 ×2'), findsNothing);
    expect(tester.widget<DataTable>(find.byType(DataTable)).onSelectAll, isNotNull);

    h.textbooks.roundsError = Exception('rounds failed');
    ProviderScope.containerOf(
      tester.element(find.byType(AdminOrdersPage)),
    ).invalidate(adminRoundsProvider);
    await tester.pumpAndSettle();

    expect(find.text('지난 회차 교재 ×1'), findsOneWidget);
    expect(find.text('기초 성경공부 ×2'), findsNothing);
    expect(find.text('지난 회차 목록을 불러오지 못했습니다.'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).onSelectAll, isNull);
    for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(cb.onChanged, isNull);
    }
    for (final menu in tester.widgetList<PopupMenuButton<OrderStatus>>(
      find.byType(PopupMenuButton<OrderStatus>),
    )) {
      expect(menu.enabled, isFalse);
    }
    expect(
      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, '마감 변경'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'CSV 내보내기'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('AdminDepositsPage 에서 일괄 재해석과 개별 입금 처리가 서로 잠긴다', (tester) async {
    final h = _Harness();
    h.deposits.countsResult = const DepositCounts(
      needsReview: 1,
      unparsedWithRaw: 2,
      all: 3,
    );

    await h.pump(tester, const AdminDepositsPage());
    await tester.pumpAndSettle();

    final bulkBtn = find.ancestor(
      of: find.text('해석 실패 일괄 재실행 (2)'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    final linkBtn = find.widgetWithText(OutlinedButton, '대상 연결');
    final ignoreBtn = find.widgetWithText(TextButton, '무시');

    // 1. 일괄 재실행 중에는 개별 카드 액션이 비활성화된다.
    final reparseCompleter =
        Completer<List<({String depositId, DepositStatus status})>>();
    h.deposits.pendingReparse = reparseCompleter;
    await tester.tap(bulkBtn);
    await tester.pump();

    expect(tester.widget<OutlinedButton>(linkBtn).onPressed, isNull);
    expect(tester.widget<TextButton>(ignoreBtn).onPressed, isNull);

    reparseCompleter.complete(const []);
    h.deposits.pendingReparse = null;
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(linkBtn).onPressed, isNotNull);

    // 2. 개별 입금 처리 중에는 일괄 재실행 버튼이 비활성화된다.
    final ignoreCompleter = Completer<void>();
    h.deposits.pendingIgnore = ignoreCompleter;
    await tester.tap(ignoreBtn);
    await tester.pump();

    expect(tester.widget<OutlinedButton>(bulkBtn).onPressed, isNull);

    ignoreCompleter.complete();
    h.deposits.pendingIgnore = null;
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(bulkBtn).onPressed, isNotNull);
  });
}
