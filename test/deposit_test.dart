// 자동 입금 확인: 도메인 파싱, 라우트 접근, 입금 내역 화면, 캠퍼스 설정 카드, 자동 확인 표시.
import 'package:ccc_accounting_management/core/router/auth_guard.dart';
import 'package:ccc_accounting_management/core/router/routes.dart';
import 'package:ccc_accounting_management/core/theme/app_theme.dart';
import 'package:ccc_accounting_management/core/utils/app_exception.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_event_detail_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_hub_page.dart';
import 'package:ccc_accounting_management/features/admin/presentation/admin_orders_page.dart';
import 'package:ccc_accounting_management/features/auth/domain/profile.dart';
import 'package:ccc_accounting_management/features/auth/presentation/auth_providers.dart';
import 'package:ccc_accounting_management/features/campus/domain/campus.dart';
import 'package:ccc_accounting_management/features/campus/presentation/campus_providers.dart';
import 'package:ccc_accounting_management/features/deposits/data/deposit_repository.dart';
import 'package:ccc_accounting_management/features/deposits/domain/bank_deposit.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/admin_deposits_page.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/deposit_providers.dart';
import 'package:ccc_accounting_management/features/deposits/presentation/deposit_settings_card.dart';
import 'package:ccc_accounting_management/features/events/data/event_repository.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/events/presentation/event_providers.dart';
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

String? _go(String location, Profile profile) => authRedirect(
  (signedIn: true, profile: profile),
  Uri.parse(location),
);

class _FakeDepositRepo implements DepositRepository {
  final calls = <String>[];
  Object? fetchError;
  CampusDepositSettings settings = CampusDepositSettings(
    campusId: 'k',
    enabled: true,
    accountLabel: 'KAIST CCC',
    tokenPrefix: 'dep_abcdef',
    tokenRotatedAt: DateTime(2026, 11, 20, 10),
    lastReceivedAt: DateTime(2026, 11, 26, 14, 30),
    lastDepositNotificationAt: DateTime(2026, 11, 26, 14, 20),
    lastIgnoredAt: DateTime(2026, 11, 26, 14, 15),
    lastIgnoredReason: 'no_account_label',
    ignoredCount: 4,
  );
  List<BankDeposit> deposits = [
    BankDeposit(
      id: 'd-amb',
      campusId: 'k',
      bankCode: 'toss',
      status: DepositStatus.ambiguous,
      depositorName: '홍길동',
      amount: 10000,
      depositedAt: DateTime(2026, 11, 26, 12),
      receivedAt: DateTime(2026, 11, 26, 12, 1),
      matchReason: 'same_name_members',
      candidates: const [
        DepositCandidate(
          kind: 'textbook_single',
          userId: 'u2',
          orderIds: ['o1'],
          label: '홍길동 교재 신청',
          amount: 10000,
        ),
      ],
    ),
    BankDeposit(
      id: 'd-unp',
      campusId: 'k',
      bankCode: 'toss',
      status: DepositStatus.unparsed,
      depositedAt: DateTime(2026, 11, 26, 11),
      receivedAt: DateTime(2026, 11, 26, 11, 1),
      rawTitle: '토스뱅크',
      rawText: 'KAIST CCC 새 알림 본문',
      rawPackage: 'viva.republica.toss',
      rawExpiresAt: DateTime(2026, 12, 10),
      matchReason: 'no_amount',
    ),
    BankDeposit(
      id: 'd-auto',
      campusId: 'k',
      bankCode: 'toss',
      status: DepositStatus.autoMatched,
      depositorName: '김철수',
      amount: 15000,
      depositedAt: DateTime(2026, 11, 26, 10),
      receivedAt: DateTime(2026, 11, 26, 10, 1),
      matchReason: 'exact_event',
      matchedAt: DateTime(2026, 11, 26, 10, 1),
    ),
  ];

  UnpaidLinkTargets targets = UnpaidLinkTargets(
    orders: [
      UnpaidOrderTarget(
        orderId: 'o1',
        memberName: '홍길동',
        studentId: '20240001',
        roundLabel: '11/25',
        itemsSummary: '교재A ×1',
        amount: 10000,
        createdAt: DateTime(2026, 11, 25),
      ),
    ],
    eventPayments: const [
      UnpaidEventTarget(
        paymentId: 'ep1',
        eventId: 'e1',
        eventTitle: '겨울 수련회',
        memberName: '홍길동',
        studentId: '20240001',
        amount: 30000,
        expectedDepositName: '홍길동수련회',
      ),
    ],
  );

  @override
  Future<CampusDepositSettings> fetchSettings(String campusId) async {
    if (fetchError != null) throw fetchError!;
    return settings;
  }

  @override
  Future<void> updateSettings(
    String campusId, {
    required bool enabled,
    required String bankCode,
    required String accountLabel,
  }) async {
    calls.add('updateSettings $campusId enabled=$enabled label=$accountLabel');
    settings = CampusDepositSettings(
      campusId: campusId,
      enabled: enabled,
      bankCode: bankCode,
      accountLabel: accountLabel.trim(),
      tokenPrefix: settings.tokenPrefix,
      tokenRotatedAt: settings.tokenRotatedAt,
      lastReceivedAt: settings.lastReceivedAt,
      lastIgnoredAt: settings.lastIgnoredAt,
      lastIgnoredReason: settings.lastIgnoredReason,
      ignoredCount: settings.ignoredCount,
    );
  }

  @override
  Future<String> rotateToken(String campusId) async {
    calls.add('rotateToken $campusId');
    return 'dep_secret_token_once_only_123456';
  }

  @override
  Future<List<BankDeposit>> fetchDeposits(String campusId) async {
    if (fetchError != null) throw fetchError!;
    return deposits;
  }

  @override
  Future<UnpaidLinkTargets> fetchUnpaidLinkTargets(String campusId) async =>
      targets;

  @override
  Future<void> linkToEvent(String depositId, String eventPaymentId) async =>
      calls.add('linkEvent $depositId $eventPaymentId');

  @override
  Future<void> linkToOrders(String depositId, List<String> orderIds) async =>
      calls.add('linkOrders $depositId ${orderIds.join(',')}');

  @override
  Future<void> undoDeposit(String depositId) async =>
      calls.add('undo $depositId');

  @override
  Future<void> ignoreDeposit(String depositId, {required bool ignore}) async =>
      calls.add('ignore $depositId $ignore');

  @override
  Future<DepositStatus> rematchDeposit(String depositId) async {
    calls.add('rematch $depositId');
    return DepositStatus.autoMatched;
  }

  @override
  Future<List<({String depositId, DepositStatus status})>> reparse({
    String? depositId,
    String? campusId,
  }) async {
    calls.add('reparse deposit=$depositId campus=$campusId');
    return [
      (
        depositId: depositId ?? 'd-unp',
        status: DepositStatus.autoMatched,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTextbooks implements TextbookRepository {
  _FakeTextbooks(this.orders);

  final List<TextbookOrder> orders;
  final _round = OrderRound(
    id: 'r1',
    start: DateTime(2026, 11, 25, 9),
    deadline: DateTime(2026, 12, 2, 9),
  );

  @override
  Future<List<Textbook>> fetchTextbooks(String campusId) async => const [];

  @override
  Future<List<TextbookCategory>> fetchCategories(String campusId) async =>
      const [];

  @override
  Future<OrderRound> fetchCurrentRound({String? campusId}) async => _round;

  @override
  Future<List<OrderRound>> fetchRounds(String campusId) async => [_round];

  @override
  Future<List<TextbookOrder>> fetchAllOrders(
    String campusId, {
    String? roundId,
  }) async => orders;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEvents implements EventRepository {
  _FakeEvents(this.event, this.payments);

  final Event event;
  final List<EventPayment> payments;

  @override
  Future<Event?> fetchEvent(String id) async => event;

  @override
  Future<List<EventPayment>> fetchPayments(String eventId) async => payments;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(375, 812),
  Profile? profile,
  _FakeDepositRepo? depositRepo,
  TextbookRepository? textbookRepo,
  EventRepository? eventRepo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (_, _) => null,
      overrides: [
        currentProfileProvider.overrideWith(
          (ref) async => profile ?? _profile(UserRole.campusAdmin),
        ),
        campusesProvider.overrideWith((ref) async => const <Campus>[]),
        currentUserIdProvider.overrideWith((ref) => 'u1'),
        if (depositRepo != null)
          depositRepositoryProvider.overrideWithValue(depositRepo),
        if (textbookRepo != null)
          textbookRepositoryProvider.overrideWithValue(textbookRepo),
        if (eventRepo != null)
          eventRepositoryProvider.overrideWithValue(eventRepo),
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
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  group('도메인 파싱', () {
    test('BankDeposit.fromJson 은 상태, 후보 스냅샷, 원문 필드를 파싱한다', () {
      final dep = BankDeposit.fromJson({
        'id': 'd1',
        'campus_id': 'k',
        'bank_code': 'toss',
        'status': 'ambiguous',
        'depositor_name': '홍길동',
        'amount': 25000,
        'deposited_at': '2026-11-26T03:00:00Z',
        'received_at': '2026-11-26T03:00:02Z',
        'match_reason': 'multiple_candidates',
        'candidate_snapshot': [
          {
            'kind': 'textbook_round_sum',
            'user_id': 'u1',
            'order_ids': ['o1', 'o2'],
            'label': '홍길동 교재 합산 (2건)',
            'amount': 25000,
          },
          {
            'kind': 'event',
            'user_id': 'u1',
            'event_id': 'e1',
            'event_payment_id': 'ep1',
            'label': '수련회 (홍길동)',
            'amount': 25000,
          },
        ],
      });

      expect(dep.status, DepositStatus.ambiguous);
      expect(dep.isParsed, isTrue);
      expect(dep.candidates.length, 2);
      expect(dep.candidates.first.orderIds, ['o1', 'o2']);
      expect(dep.candidates.first.isEvent, isFalse);
      expect(dep.candidates.last.eventPaymentId, 'ep1');
      expect(dep.candidates.last.isEvent, isTrue);
      expect(dep.reasonLabel, '이름과 금액이 같은 미납 후보가 여러 건입니다.');
    });

    test('DepositFilter 는 검토 필요(unmatched+ambiguous+unparsed)와 각 상태를 분류한다', () {
      expect(DepositFilter.needsReview.matches(DepositStatus.unmatched), isTrue);
      expect(DepositFilter.needsReview.matches(DepositStatus.ambiguous), isTrue);
      expect(DepositFilter.needsReview.matches(DepositStatus.unparsed), isTrue);
      expect(
        DepositFilter.needsReview.matches(DepositStatus.autoMatched),
        isFalse,
      );
      expect(DepositFilter.needsReview.matches(DepositStatus.undone), isFalse);
      expect(DepositFilter.all.matches(DepositStatus.ignored), isTrue);
    });

    test('CampusDepositSettings 와 depositIngestUrl, 무시 사유 한글 변환', () {
      final s = CampusDepositSettings.fromJson({
        'campus_id': 'k',
        'enabled': true,
        'bank_code': 'toss',
        'account_label': 'KAIST CCC',
        'token_prefix': 'dep_123456',
        'token_rotated_at': '2026-11-20T01:00:00Z',
        'last_received_at': '2026-11-26T05:00:00Z',
        'last_deposit_notification_at': '2026-11-26T04:50:00Z',
        'last_ignored_at': '2026-11-26T04:00:00Z',
        'last_ignored_reason': 'no_account_label',
        'ignored_count': 7,
      });
      expect(s.hasToken, isTrue);
      expect(s.lastDepositNotificationAt, isNotNull);
      expect(s.ignoredCount, 7);
      expect(s.lastIgnoredReasonLabel, '계좌 별칭 없음 (개인 계좌 등)');
      expect(ignoredReasonLabel('withdrawal'), '출금 · 결제 알림');
      expect(ignoredReasonLabel('ad'), '광고 · 혜택 알림');
      expect(
        depositReasonLabel('possible_duplicate'),
        '60초 안에 같은 내용의 입금 알림이 있어 중복 여부를 확인해야 합니다.',
      );
      expect(
        depositReasonLabel('match_error'),
        '자동 매칭 중 오류가 발생해 수동 확인이 필요합니다.',
      );
      expect(
        validateDepositAccountLabel('CCC', enabled: true),
        isNotNull,
      );
      expect(
        validateDepositAccountLabel('모임통장', enabled: true),
        isNotNull,
      );
      expect(
        validateDepositAccountLabel('KAIST CCC', enabled: true),
        isNull,
      );
      expect(
        validateDepositAccountLabel('', enabled: false),
        isNull,
      );
      expect(
        depositIngestUrl('https://abc.supabase.co/'),
        'https://abc.supabase.co/functions/v1/deposit-ingest',
      );
      expect(depositIngestUrl(''), isEmpty);
    });

    test('TextbookOrder 와 EventPayment 의 isAutoConfirmed 판별', () {
      final autoOrder = TextbookOrder.fromJson({
        'id': 'o1',
        'user_id': 'u1',
        'round_id': 'r1',
        'status': 'paid',
        'total_price': 10000,
        'created_at': '2026-11-26T00:00:00Z',
        'confirmed_deposit_id': 'd1',
        'bank_deposits': {'status': 'auto_matched', 'matched_by': null},
      });
      expect(autoOrder.isAutoConfirmed, isTrue);
      expect(autoOrder.copyWith(status: OrderStatus.requested).isAutoConfirmed, isFalse);

      final manualOrder = TextbookOrder.fromJson({
        'id': 'o2',
        'user_id': 'u1',
        'round_id': 'r1',
        'status': 'paid',
        'total_price': 10000,
        'created_at': '2026-11-26T00:00:00Z',
        'confirmed_deposit_id': 'd2',
        'bank_deposits': {'status': 'manual_matched', 'matched_by': 'admin-1'},
      });
      expect(manualOrder.isAutoConfirmed, isFalse);

      final autoEvent = EventPayment.fromJson({
        'id': 'ep1',
        'event_id': 'e1',
        'user_id': 'u1',
        'is_paid': true,
        'paid_at': '2026-11-26T00:00:00Z',
        'confirmed_by': null,
        'confirmed_deposit_id': 'd1',
      });
      expect(autoEvent.isAutoConfirmed, isTrue);
      expect(autoEvent.copyWith(isPaid: false).isAutoConfirmed, isFalse);

      final manualEvent = EventPayment.fromJson({
        'id': 'ep2',
        'event_id': 'e1',
        'user_id': 'u1',
        'is_paid': true,
        'paid_at': '2026-11-26T00:00:00Z',
        'confirmed_by': 'admin-1',
        'confirmed_deposit_id': 'd2',
      });
      expect(manualEvent.isAutoConfirmed, isFalse);
    });
  });

  group('라우트 및 접근 권한', () {
    test('/admin/deposits 는 캠퍼스/총괄 관리자만 접근 가능하고 메뉴에 포함된다', () {
      expect(_go('/admin/deposits', _profile(UserRole.member)), AppRoutes.home);
      expect(_go('/admin/deposits', _profile(UserRole.campusAdmin)), isNull);
      expect(_go('/admin/deposits', _profile(UserRole.centralAdmin)), isNull);
      expect(
        adminDestinations.map((d) => d.path),
        contains(AppRoutes.adminDeposits),
      );
      final meta = routeMetaFor('/admin/deposits');
      expect(meta.title, '입금 내역');
      expect(meta.parent, AppRoutes.admin);
    });

    testWidgets('관리자 허브에 입금 내역 메뉴가 보인다', (tester) async {
      await _pump(tester, const AdminHubPage());
      expect(find.text('입금 내역'), findsOneWidget);
    });
  });

  group('AdminDepositsPage (375px)', () {
    testWidgets('기본 검토 필요 필터, 원문 표시, 재해석, 수동 연결, 확인 취소, 무시 동작', (
      tester,
    ) async {
      final repo = _FakeDepositRepo();
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      // 기본 필터 '검토 필요'에는 ambiguous + unparsed 2건이 보이고 autoMatched 는 안 보인다.
      expect(find.text('홍길동'), findsOneWidget);
      expect(find.text('내용: KAIST CCC 새 알림 본문'), findsOneWidget);
      expect(find.text('김철수'), findsNothing);
      expect(tester.takeException(), isNull);

      // 다시 해석 호출
      final reparseBtn = find.widgetWithText(OutlinedButton, '다시 해석');
      await tester.ensureVisible(reparseBtn);
      await tester.pumpAndSettle();
      await tester.tap(reparseBtn);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('reparse deposit=d-unp campus=null'));

      // 대상 연결 다이얼로그 -> 추천 후보 바로 연결
      final linkBtn = find.widgetWithText(OutlinedButton, '대상 연결');
      await tester.ensureVisible(linkBtn);
      await tester.pumpAndSettle();
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();
      expect(find.text('추천 후보'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '연결').first);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('linkOrders d-amb o1'));

      // 자동 확인 탭 -> 확인 취소 다이얼로그 확인 -> undoDeposit 호출
      final autoTab = find.text('자동 확인 1');
      await tester.ensureVisible(autoTab);
      await tester.pumpAndSettle();
      await tester.tap(autoTab);
      await tester.pumpAndSettle();
      expect(find.text('김철수'), findsOneWidget);
      final undoBtn = find.widgetWithText(OutlinedButton, '확인 취소');
      await tester.ensureVisible(undoBtn);
      await tester.pumpAndSettle();
      await tester.tap(undoBtn);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '확인 취소'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('undo d-auto'));
    });

    testWidgets('빈 상태와 오류 상태를 표시한다', (tester) async {
      final emptyRepo = _FakeDepositRepo()..deposits = [];
      await _pump(tester, const AdminDepositsPage(), depositRepo: emptyRepo);
      expect(find.textContaining('수집된 입금 내역이 아직 없습니다'), findsOneWidget);

      final errRepo = _FakeDepositRepo()
        ..fetchError = const AppException('입금 내역 조회 오류');
      await _pump(tester, const AdminDepositsPage(), depositRepo: errRepo);
      expect(find.text('입금 내역 조회 오류'), findsOneWidget);
    });
  });

  group('DepositSettingsCard (375px)', () {
    testWidgets('설정 저장, 토큰 1회 표시 및 닫기, 무시 진단 표시', (tester) async {
      final repo = _FakeDepositRepo();
      await _pump(
        tester,
        const SingleChildScrollView(child: DepositSettingsCard()),
        depositRepo: repo,
      );

      expect(find.text('자동 입금 확인'), findsOneWidget);
      expect(find.textContaining('마지막 수신 (연결 확인 포함)'), findsOneWidget);
      expect(find.textContaining('마지막 알림 수신'), findsOneWidget);
      expect(find.textContaining('계좌 별칭 없음 (개인 계좌 등)'), findsOneWidget);
      expect(find.textContaining('누적 4건'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 설정 저장
      await tester.tap(find.widgetWithText(OutlinedButton, '설정 저장'));
      await tester.pumpAndSettle();
      expect(
        repo.calls,
        contains('updateSettings k enabled=true label=KAIST CCC'),
      );

      // 토큰 재발급 -> 확인 다이얼로그 -> 1회 표시 후 닫기
      final rotateBtn = find.widgetWithText(OutlinedButton, '토큰 재발급');
      await tester.ensureVisible(rotateBtn);
      await tester.pumpAndSettle();
      await tester.tap(rotateBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '재발급'));
      await tester.pumpAndSettle();

      expect(find.text('dep_secret_token_once_only_123456'), findsOneWidget);
      expect(find.textContaining('지금 한 번만 표시됩니다'), findsOneWidget);

      final dismissBtn = find.widgetWithText(TextButton, '확인했어요');
      await tester.ensureVisible(dismissBtn);
      await tester.pumpAndSettle();
      await tester.tap(dismissBtn);
      await tester.pumpAndSettle();
      expect(find.text('dep_secret_token_once_only_123456'), findsNothing);
    });
  });

  group('관리자 화면 자동 확인 표시', () {
    testWidgets('교재 신청 현황과 이벤트 상세에서 자동 확인된 항목에만 "자동 확인"을 표시한다', (
      tester,
    ) async {
      final round = OrderRound(
        id: 'r1',
        start: DateTime(2026, 11, 25, 9),
        deadline: DateTime(2026, 12, 2, 9),
      );
      final orders = [
        TextbookOrder(
          id: 'o-auto',
          userId: 'u2',
          roundId: 'r1',
          round: round,
          status: OrderStatus.paid,
          totalPrice: 10000,
          createdAt: DateTime(2026, 11, 26),
          items: const [
            TextbookOrderItem(
              textbookId: 'b1',
              title: '교재A',
              quantity: 1,
              unitPrice: 10000,
            ),
          ],
          member: const OrderMember(studentId: '20240002', name: '자동회원'),
          confirmedDepositId: 'd1',
          isAutoConfirmed: true,
        ),
        TextbookOrder(
          id: 'o-manual',
          userId: 'u3',
          roundId: 'r1',
          round: round,
          status: OrderStatus.paid,
          totalPrice: 10000,
          createdAt: DateTime(2026, 11, 26),
          items: const [
            TextbookOrderItem(
              textbookId: 'b1',
              title: '교재A',
              quantity: 1,
              unitPrice: 10000,
            ),
          ],
          member: const OrderMember(studentId: '20240003', name: '수동회원'),
        ),
      ];
      await _pump(
        tester,
        const AdminOrdersPage(),
        size: const Size(1280, 800),
        textbookRepo: _FakeTextbooks(orders),
      );
      expect(find.text('자동 확인'), findsOneWidget);

      final event = Event(
        id: 'e1',
        title: '겨울 수련회',
        amount: 30000,
        dueDate: null,
        description: '',
        createdAt: DateTime(2026, 11, 1),
      );
      final payments = [
        EventPayment(
          id: 'ep-auto',
          eventId: 'e1',
          userId: 'u2',
          isPaid: true,
          paidAt: DateTime(2026, 11, 26, 12),
          confirmedDepositId: 'd1',
          member: const EventMember(studentId: '20240002', name: '자동회원'),
        ),
        EventPayment(
          id: 'ep-manual',
          eventId: 'e1',
          userId: 'u3',
          isPaid: true,
          paidAt: DateTime(2026, 11, 26, 12),
          confirmedBy: 'u1',
          member: const EventMember(studentId: '20240003', name: '수동회원'),
        ),
      ];
      await _pump(
        tester,
        const AdminEventDetailPage(eventId: 'e1'),
        size: const Size(900, 800),
        eventRepo: _FakeEvents(event, payments),
      );
      expect(
        find.textContaining('자동 확인', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
