import 'dart:async';

import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_order_providers.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_orders_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/widgets/admin_order_widgets.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/textbooks/data/textbook_repository.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_filter.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_category.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:ccc_accounting_management/features/textbooks/presentation/textbook_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

final _now = DateTime.now();
final _round = OrderRound(
  id: 'r1',
  start: DateTime(_now.year, _now.month, _now.day, 9),
  deadline: DateTime(_now.year, _now.month, _now.day + 7, 9),
);

final _adminProfile = Profile(
  id: 'admin-1',
  campusId: 'k',
  studentId: '20240001',
  name: '관리자',
  role: UserRole.centralAdmin,
  mustChangePassword: false,
  isApproved: true,
  createdAt: DateTime(2026, 9, 1),
);

TextbookOrder _makeOrder({
  required String id,
  required OrderStatus status,
  String name = '홍길동',
  String studentId = '20240010',
  String textbookId = 'b1',
  String title = '교재 A',
  int quantity = 1,
  int unitPrice = 10000,
  bool isShipped = false,
  bool isReceived = false,
  String? confirmedDepositId,
  bool isAutoConfirmed = false,
}) => TextbookOrder(
  id: id,
  userId: 'u-$id',
  roundId: _round.id,
  round: _round,
  status: status,
  totalPrice: quantity * unitPrice,
  createdAt: DateTime(2026, 11, 20, 10, 30),
  items: [
    TextbookOrderItem(
      textbookId: textbookId,
      title: title,
      quantity: quantity,
      unitPrice: unitPrice,
    ),
  ],
  member: OrderMember(studentId: studentId, name: name),
  isShipped: isShipped,
  shippedAt: isShipped ? DateTime(2026, 11, 21, 14) : null,
  receivedAt: isReceived ? DateTime(2026, 11, 22, 16) : null,
  receivedBy: isReceived ? 'admin-1' : null,
  confirmedDepositId: confirmedDepositId,
  isAutoConfirmed: isAutoConfirmed,
);

class _MutableCampusNotifier extends Notifier<String?> {
  @override
  String? build() => 'k';

  void setCampus(String? campusId) => state = campusId;
}

final _mutableCampusProvider = NotifierProvider<_MutableCampusNotifier, String?>(
  _MutableCampusNotifier.new,
);

class _FakeOrdersRepo implements TextbookRepository {
  _FakeOrdersRepo(List<TextbookOrder> initial)
    : orders = List<TextbookOrder>.of(initial);

  List<TextbookOrder> orders;
  Object? fetchOrdersError;
  Completer<List<TextbookOrder>>? nextFetchOrders;
  Completer<void>? pendingUpdateStatus;
  Object? updateStatusError;
  Object? updateManyStatusError;
  int fetchAllCalls = 0;
  final List<String> calls = [];

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => [
    Textbook(
      id: 'b1',
      title: '교재 A',
      price: 10000,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      categoryId: 'c1',
      sortOrder: 0,
    ),
    Textbook(
      id: 'b2',
      title: '교재 B',
      price: 10000,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      categoryId: 'c1',
      sortOrder: 1,
    ),
  ];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [TextbookCategory(id: 'c1', name: '성경공부', sortOrder: 0)];

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [_round];

  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async {
    fetchAllCalls++;
    final pending = nextFetchOrders;
    if (pending != null) {
      nextFetchOrders = null;
      return pending.future;
    }
    if (fetchOrdersError != null) {
      throw fetchOrdersError!;
    }
    return List<TextbookOrder>.of(orders);
  }

  @override
  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    required OrderStatus from,
  }) async {
    calls.add('updateStatus $orderId ${from.name}->${status.name}');
    final pending = pendingUpdateStatus;
    if (pending != null) {
      pendingUpdateStatus = null;
      await pending.future;
    }
    if (updateStatusError != null) {
      final err = updateStatusError!;
      updateStatusError = null;
      throw err;
    }
    final idx = orders.indexWhere((o) => o.id == orderId && o.status == from);
    if (idx < 0) {
      throw const OrderStatusConflictException();
    }
    orders[idx] = orders[idx].copyWith(status: status);
  }

  @override
  Future<void> updateOrdersStatus(
    List<String> orderIds,
    OrderStatus status, {
    required Set<OrderStatus> from,
  }) async {
    calls.add(
      'updateMany ${orderIds.join(',')} ${from.map((e) => e.name).join('|')}->${status.name}',
    );
    if (updateManyStatusError != null) {
      final err = updateManyStatusError!;
      updateManyStatusError = null;
      throw err;
    }
    final matching = orders
        .where((o) => orderIds.contains(o.id) && from.contains(o.status))
        .length;
    if (matching != orderIds.toSet().length) {
      throw const OrderStatusConflictException();
    }
    orders = [
      for (final o in orders)
        orderIds.contains(o.id) ? o.copyWith(status: status) : o,
    ];
  }

  @override
  Future<void> setShippedMany(
    List<String> orderIds, {
    required bool shipped,
  }) async {
    calls.add('shippedMany $shipped ${orderIds.join(',')}');
    orders = [
      for (final o in orders)
        orderIds.contains(o.id) ? o.copyWith(isShipped: shipped) : o,
    ];
  }

  @override
  Future<void> shiftOrders(List<String> orderIds, int offset) async {
    calls.add('shift $offset ${orderIds.join(',')}');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<ProviderContainer> _pumpOrders(
  WidgetTester tester,
  _FakeOrdersRepo repo, {
  Size size = const Size(1280, 800),
  ThemeData? theme,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        currentUserIdProvider.overrideWith((ref) => _adminProfile.id),
        currentProfileProvider.overrideWith((ref) async => _adminProfile),
        campusesProvider.overrideWith(
          (ref) async => const [
            Campus(id: 'k', code: 'kaist', name: 'KAIST', emailDomain: 'k.local'),
            Campus(id: 's', code: 'snu', name: '서울대', emailDomain: 's.local'),
          ],
        ),
        textbookRepositoryProvider.overrideWithValue(repo),
        ...extraOverrides,
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: theme ?? AppTheme.light(),
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: AdminOrdersPage()),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _selectRowStatus(
  WidgetTester tester,
  OrderStatus target, {
  int menuIndex = 0,
}) async {
  final menu = find.byType(PopupMenuButton<OrderStatus>).at(menuIndex);
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(PopupMenuItem<OrderStatus>),
      matching: find.text(target.label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
    final pretendard = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.ttf'));
    await pretendard.load();
  });

  group('OrderFilter.withStatus', () {
    test('status 만 교체하고 나머지 필터 조건을 유지한다', () {
      const base = OrderFilter(
        textbookId: 'b1',
        status: OrderStatus.paid,
        delivery: DeliveryStatus.shipped,
        query: '홍길동',
      );
      final cleared = base.withStatus(null);
      expect(cleared.status, isNull);
      expect(cleared.textbookId, 'b1');
      expect(cleared.delivery, DeliveryStatus.shipped);
      expect(cleared.query, '홍길동');

      final changed = cleared.withStatus(OrderStatus.cancelled);
      expect(changed.status, OrderStatus.cancelled);
      expect(changed.textbookId, 'b1');
      expect(changed.delivery, DeliveryStatus.shipped);
      expect(changed.query, '홍길동');
    });
  });

  group('상태 요약 칩', () {
    testWidgets('상태를 골라도 다른 상태 칩의 건수와 금액이 0이 되지 않고 전체 상태는 취소를 제외한다', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested, unitPrice: 10000),
        _makeOrder(
          id: 'o2',
          status: OrderStatus.paid,
          name: '김철수',
          unitPrice: 20000,
        ),
        _makeOrder(
          id: 'o3',
          status: OrderStatus.cancelled,
          name: '이영희',
          unitPrice: 30000,
        ),
      ]);
      await _pumpOrders(tester, repo);

      final chips = find.byType(OrderStatusSummaryChips);
      expect(
        find.descendant(of: chips, matching: find.text('취소 제외')),
        findsOneWidget,
      );
      // 전체 상태(취소 제외): 2건, 30,000원
      expect(
        find.descendant(of: chips, matching: find.text('2건')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('10,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('20,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('30,000원')),
        findsNWidgets(2), // 전체 상태 + 취소
      );

      // 입금확인 칩 선택 -> 목록은 1건으로 줄지만 모든 상태 칩 숫자는 유지된다.
      await tester.tap(
        find.descendant(of: chips, matching: find.text('입금확인')),
      );
      await tester.pumpAndSettle();

      expect(find.text('신청 1건'), findsOneWidget);
      expect(
        find.descendant(of: chips, matching: find.text('2건')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('10,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('20,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('30,000원')),
        findsNWidgets(2),
      );
    });

    testWidgets('조회 실패 시 상태 칩은 라벨만 보이고 0건/0원을 표시하지 않는다', (tester) async {
      final repo = _FakeOrdersRepo(const [])
        ..fetchOrdersError = Exception('network error');
      await _pumpOrders(tester, repo);

      final chips = find.byType(OrderStatusSummaryChips);
      expect(
        find.descendant(of: chips, matching: find.text('전체 상태')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('취소 제외')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('0건')),
        findsNothing,
      );
      expect(
        find.descendant(of: chips, matching: find.text('0원')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.bySemanticsLabel('불러오는 중'),
        ),
        findsNothing,
      );
    });
  });

  group('교재별 집계 아코디언', () {
    testWidgets('기본 접힘, 취소 제외 합계, 탭 및 키보드 Enter/Space 토글과 시맨틱', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(
          id: 'o1',
          status: OrderStatus.requested,
          textbookId: 'b1',
          title: '교재 A',
          quantity: 1,
          unitPrice: 10000,
        ),
        _makeOrder(
          id: 'o2',
          status: OrderStatus.paid,
          textbookId: 'b2',
          title: '교재 B',
          quantity: 2,
          unitPrice: 10000,
        ),
        _makeOrder(
          id: 'o3',
          status: OrderStatus.cancelled,
          textbookId: 'b3',
          title: '취소 교재',
          quantity: 5,
          unitPrice: 10000,
        ),
      ]);
      await _pumpOrders(tester, repo);

      final accordion = find.byType(TextbookTallyAccordion);
      expect(accordion, findsOneWidget);
      expect(
        find.descendant(of: accordion, matching: find.text('총 3권 · 30,000원')),
        findsOneWidget,
      );
      // 기본 접힘 상태
      expect(
        find.descendant(of: accordion, matching: find.text('합계')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: accordion,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                w.properties.expanded == false,
          ),
        ),
        findsOneWidget,
      );

      // 탭으로 펼치기
      await tester.tap(find.text('교재별 집계 (취소 제외)'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: accordion, matching: find.text('합계')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: accordion, matching: find.text('취소 교재')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: accordion,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.button == true &&
                w.properties.expanded == true,
          ),
        ),
        findsOneWidget,
      );

      // 키보드 Enter 로 접고 Space 로 다시 펼친다.
      Focus.of(tester.element(find.text('교재별 집계 (취소 제외)'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: accordion, matching: find.text('합계')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: accordion, matching: find.text('합계')),
        findsOneWidget,
      );
    });

    testWidgets('로딩 아코디언은 스켈레톤을 보이고 0권/0원을 표시하지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TextbookTallyAccordion.loading()),
        ),
      );
      expect(find.text('교재별 집계 (취소 제외)'), findsOneWidget);
      expect(find.bySemanticsLabel('불러오는 중'), findsWidgets);
      expect(find.textContaining('0권'), findsNothing);
      expect(find.textContaining('0원'), findsNothing);
    });
  });

  group('일괄 막대 표시 및 단일 상태 컨트롤', () {
    testWidgets('데스크톱/모바일에서 0건 선택 시 일괄 버튼 숨김, 선택 시 표시, 중복 입금 체크박스 없음', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(
          id: 'o1',
          status: OrderStatus.paid,
          confirmedDepositId: 'd1',
          isAutoConfirmed: true,
        ),
      ]);

      // 데스크톱
      await _pumpOrders(tester, repo, size: const Size(1280, 800));
      expect(find.widgetWithText(OutlinedButton, '이전 회차로'), findsNothing);
      expect(find.text('자동 확인'), findsOneWidget);
      // 표 헤더 7열(입금확인 열 없음)
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.columns.length, 7);
      // 전체선택 1 + 행 선택 1 + 배송 1 + 수령 1 = 4 (입금확인 체크박스 없음)
      expect(find.byType(Checkbox), findsNWidgets(4));

      // 메뉴에 취소 항목이 구분선 뒤에 마지막으로 나온다.
      await tester.tap(find.byType(PopupMenuButton<OrderStatus>));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      final menuItems = tester
          .widgetList<PopupMenuItem<OrderStatus>>(
            find.byType(PopupMenuItem<OrderStatus>),
          )
          .toList();
      expect(
        menuItems.map((e) => e.value).toList(),
        [OrderStatus.requested, OrderStatus.paid, OrderStatus.cancelled],
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // 행 선택 -> 일괄 막대 표시 -> 선택 해제 -> 다시 숨김
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1건 선택'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '이전 회차로'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '선택 해제'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, '이전 회차로'), findsNothing);

      // 모바일: 0건 선택 시 '전체 선택'만 보이고 일괄 버튼은 숨김, 카드 체크박스 3개(선택+배송+수령)
      await _pumpOrders(tester, repo, size: const Size(360, 800));
      expect(find.text('전체 선택'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '이전 회차로'), findsNothing);
      expect(find.text('자동 확인'), findsOneWidget);
      // 전체선택 1 + 카드 선택 1 + 배송 1 + 수령 1 = 4
      expect(find.byType(Checkbox), findsNWidgets(4));
    });
  });

  group('금액 안전성: 재조회, 확인창, 충돌, 잠금', () {
    testWidgets('작업 전 재조회로 이미 변경된 신청을 감지해 중단한다', (tester) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested),
      ]);
      await _pumpOrders(tester, repo);

      // 서버에서 다른 관리자가 먼저 취소 처리함
      repo.orders = [
        _makeOrder(id: 'o1', status: OrderStatus.cancelled),
      ];

      await _selectRowStatus(tester, OrderStatus.paid);
      expect(repo.calls, isEmpty);
      expect(find.textContaining('변경됨, 다시 확인'), findsOneWidget);
    });

    testWidgets('재조회 중 캠퍼스가 바뀌면 작업을 중단하고 이전 캠퍼스 데이터로 덮어쓰지 않는다', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested),
      ]);
      final container = await _pumpOrders(
        tester,
        repo,
        extraOverrides: [
          adminCampusIdProvider.overrideWith(
            (ref) => ref.watch(_mutableCampusProvider),
          ),
        ],
      );

      final pendingFetch = Completer<List<TextbookOrder>>();
      repo.nextFetchOrders = pendingFetch;

      // 상태 변경 시작 -> refetchFresh 대기
      await tester.tap(find.byType(PopupMenuButton<OrderStatus>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<OrderStatus>),
          matching: find.text('입금확인'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(repo.nextFetchOrders, isNull);

      // 대기 중 캠퍼스 전환
      container.read(_mutableCampusProvider.notifier).setCampus('s');
      await tester.pump();

      pendingFetch.complete([
        _makeOrder(id: 'o1', status: OrderStatus.requested),
      ]);
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
    });

    testWidgets('CAS 충돌 시 스낵바를 띄우고 최신 목록으로 새로고침한다 (단건 및 일괄)', (tester) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested),
      ]);
      await _pumpOrders(tester, repo);

      repo.updateStatusError = const OrderStatusConflictException();
      final callsBefore = repo.fetchAllCalls;

      await _selectRowStatus(tester, OrderStatus.paid);

      expect(find.textContaining('변경됨, 다시 확인'), findsOneWidget);
      // 사전 재조회 + 충돌 후 재조회
      expect(repo.fetchAllCalls, greaterThanOrEqualTo(callsBefore + 2));

      // 일괄 입금확인 CAS 충돌
      repo.updateManyStatusError = const OrderStatusConflictException();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '입금확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('입금확인 체크').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '입금확인 체크'));
      await tester.pumpAndSettle();
      expect(find.textContaining('변경됨, 다시 확인'), findsOneWidget);
    });

    testWidgets('requested→paid 는 확인창 없이 처리, paid→해제/취소는 확인창과 입금 연결 해제 경고 표시', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o-req', status: OrderStatus.requested, name: '신청회원'),
        _makeOrder(
          id: 'o-auto',
          status: OrderStatus.paid,
          name: '자동회원',
          confirmedDepositId: 'dep-1',
          isAutoConfirmed: true,
        ),
      ]);
      await _pumpOrders(tester, repo);

      // 1) requested -> paid: 확인창 없이 바로 저장
      await _selectRowStatus(tester, OrderStatus.paid, menuIndex: 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.calls, ['updateStatus o-req requested->paid']);

      // 2) auto-confirmed paid -> requested: 확인창 + 입금 연결 해제 경고
      await _selectRowStatus(tester, OrderStatus.requested, menuIndex: 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('입금 연결 해제'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '신청으로 변경'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'updateStatus o-auto paid->requested');

      // 3) requested -> cancelled: 확인창 필수
      await _selectRowStatus(tester, OrderStatus.cancelled, menuIndex: 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '신청 취소'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'updateStatus o-auto requested->cancelled');
    });

    testWidgets('확인창이 열린 사이 상태가 바뀌면 확인 후 재조회로 감지해 중단한다', (tester) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.paid, name: '홍길동'),
      ]);
      await _pumpOrders(tester, repo);

      await _selectRowStatus(tester, OrderStatus.requested);
      expect(find.byType(AlertDialog), findsOneWidget);

      // 확인창이 떠 있는 동안 서버 상태가 바뀜
      repo.orders = [
        _makeOrder(id: 'o1', status: OrderStatus.cancelled, name: '홍길동'),
      ];

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '신청으로 변경'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(find.textContaining('변경됨, 다시 확인'), findsOneWidget);
    });

    testWidgets('백그라운드 새로고침 중과 작업 진행 중에는 모든 금액 컨트롤이 비활성화된다', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested, name: '회원1'),
        _makeOrder(id: 'o2', status: OrderStatus.requested, name: '회원2'),
      ]);
      final container = await _pumpOrders(tester, repo);

      void expectAllLocked() {
        expect(
          tester.widget<DataTable>(find.byType(DataTable)).onSelectAll,
          isNull,
        );
        for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
          expect(cb.onChanged, isNull);
        }
        for (final m in tester.widgetList<PopupMenuButton<OrderStatus>>(
          find.byType(PopupMenuButton<OrderStatus>),
        )) {
          expect(m.enabled, isFalse);
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
      }

      // 1) 백그라운드 새로고침 중 잠금
      final bgRefresh = Completer<List<TextbookOrder>>();
      repo.nextFetchOrders = bgRefresh;
      container.invalidate(adminOrdersProvider(_round.id));
      await tester.pump();
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expectAllLocked();

      bgRefresh.complete(List<TextbookOrder>.of(repo.orders));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).onSelectAll,
        isNotNull,
      );

      // 2) 한 행 작업 진행 중(busy) 다른 행과 모든 컨트롤 잠금
      final pendingUpdate = Completer<void>();
      repo.pendingUpdateStatus = pendingUpdate;
      await tester.tap(find.byType(PopupMenuButton<OrderStatus>).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<OrderStatus>),
          matching: find.text('입금확인'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expectAllLocked();

      pendingUpdate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).onSelectAll,
        isNotNull,
      );
    });

    testWidgets('회차 이동(_shift)은 최신 목록과 현재 필터 교집합만 대상으로 하고 확인 중 변경 시 중단한다', (
      tester,
    ) async {
      final repo = _FakeOrdersRepo([
        _makeOrder(id: 'o1', status: OrderStatus.requested, name: '홍길동'),
        _makeOrder(id: 'o2', status: OrderStatus.paid, name: '김철수'),
      ]);
      await _pumpOrders(tester, repo);

      // 전체 선택 후 '신청' 필터 -> o1 만 보임
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(OrderStatusSummaryChips),
          matching: find.text('신청'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '다음 회차로'));
      await tester.pumpAndSettle();
      expect(find.text('다음 회차로 이동 (1건)'), findsOneWidget);

      // 확인창이 열린 사이 o1 이 입금확인으로 바뀌어 현재 필터('신청') 대상에서 빠짐
      repo.orders = [
        _makeOrder(id: 'o1', status: OrderStatus.paid, name: '홍길동'),
        _makeOrder(id: 'o2', status: OrderStatus.paid, name: '김철수'),
      ];
      await tester.tap(find.widgetWithText(FilledButton, '다음 회차로 이동'));
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(find.textContaining('변경됨, 다시 확인'), findsOneWidget);
    });
  });

  group('반응형 360/430/700/1280 라이트/다크 오버플로 없음', () {
    for (final width in [360.0, 430.0, 700.0, 1280.0]) {
      for (final dark in [false, true]) {
        testWidgets('${width.toInt()}px ${dark ? '다크' : '라이트'}', (
          tester,
        ) async {
          final repo = _FakeOrdersRepo([
            _makeOrder(
              id: 'o1',
              status: OrderStatus.paid,
              name: '남궁 아리따운 하늘별님프리티',
              title: '신약 성경 개론 워크북 (개정 3판, 소그룹 리더용 해설 포함)',
              quantity: 2,
              unitPrice: 1234000,
              confirmedDepositId: 'd1',
              isAutoConfirmed: true,
              isShipped: true,
            ),
            _makeOrder(
              id: 'o2',
              status: OrderStatus.requested,
              name: '김민수',
              textbookId: 'b2',
              title: '교재 B',
              quantity: 1,
              unitPrice: 7000,
            ),
            _makeOrder(
              id: 'o3',
              status: OrderStatus.cancelled,
              name: '박영희',
              unitPrice: 15000,
            ),
          ]);
          await _pumpOrders(
            tester,
            repo,
            size: Size(width, 900),
            theme: dark ? AppTheme.dark() : AppTheme.light(),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);

          // 아코디언 펼침 상태도 오버플로 없음
          await tester.tap(find.text('교재별 집계 (취소 제외)'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          if (width >= 1280) {
            final scrollable = find.descendant(
              of: find.ancestor(
                of: find.byType(DataTable),
                matching: find.byType(SingleChildScrollView),
              ),
              matching: find.byType(Scrollable),
            );
            final position = tester
                .state<ScrollableState>(scrollable.first)
                .position;
            expect(position.maxScrollExtent, 0);
          }
        });
      }
    }
  });
}
