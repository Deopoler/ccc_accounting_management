// 자동 입금 확인: 도메인 파싱, 라우트 접근, 입금 내역 화면, 캠퍼스 설정 카드, 자동 확인 표시.
import 'dart:async';

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

String? _go(String location, Profile profile) =>
    authRedirect((signedIn: true, profile: profile), Uri.parse(location));

class _FakeDepositRepo implements DepositRepository {
  final calls = <String>[];
  Object? fetchError;
  Object? countsError;
  Completer<DepositCounts>? pendingCounts;
  Completer<List<BankDeposit>>? pendingLoadMore;
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
  Future<List<BankDeposit>> fetchDeposits(
    String campusId, {
    DepositFilter filter = DepositFilter.all,
    int limit = 50,
    int offset = 0,
  }) async {
    if (fetchError != null) throw fetchError!;
    calls.add('fetchDeposits ${filter.dbGroup} limit=$limit offset=$offset');
    if (offset > 0 && pendingLoadMore != null) {
      return pendingLoadMore!.future;
    }
    return deposits
        .where((d) => filter.matches(d.status))
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<DepositCounts> fetchDepositCounts(String campusId) async {
    if (countsError != null) throw countsError!;
    if (fetchError != null) throw fetchError!;
    if (pendingCounts != null) return pendingCounts!.future;
    return DepositCounts(
      needsReview: deposits
          .where((d) => DepositFilter.needsReview.matches(d.status))
          .length,
      autoMatched: deposits
          .where((d) => d.status == DepositStatus.autoMatched)
          .length,
      manualMatched: deposits
          .where((d) => d.status == DepositStatus.manualMatched)
          .length,
      ignored: deposits.where((d) => d.status == DepositStatus.ignored).length,
      undone: deposits.where((d) => d.status == DepositStatus.undone).length,
      all: deposits.length,
      unparsedWithRaw: deposits
          .where((d) => d.status == DepositStatus.unparsed && d.hasRawText)
          .length,
    );
  }

  @override
  Future<UnpaidLinkTargets> fetchUnpaidLinkTargets(String campusId) async =>
      targets;

  @override
  Future<void> linkToEvent(
    String depositId,
    String eventPaymentId, {
    bool allowAmountMismatch = false,
  }) async => calls.add(
    'linkEvent $depositId $eventPaymentId mismatch=$allowAmountMismatch',
  );

  @override
  Future<void> linkToOrders(
    String depositId,
    List<String> orderIds, {
    bool allowAmountMismatch = false,
  }) async => calls.add(
    'linkOrders $depositId ${orderIds.join(',')} mismatch=$allowAmountMismatch',
  );

  @override
  Future<void> undoDeposit(String depositId) async =>
      calls.add('undo $depositId');

  @override
  Future<void> clearPossibleDuplicate(String depositId) async =>
      calls.add('clearDuplicate $depositId');

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
      (depositId: depositId ?? 'd-unp', status: DepositStatus.autoMatched),
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
  Future<List<Event>> fetchEvents(String campusId) async => [event];

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
      expect(
        DepositFilter.needsReview.matches(DepositStatus.unmatched),
        isTrue,
      );
      expect(
        DepositFilter.needsReview.matches(DepositStatus.ambiguous),
        isTrue,
      );
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
      expect(validateDepositAccountLabel('CCC', enabled: true), isNotNull);
      expect(validateDepositAccountLabel('모임통장', enabled: true), isNotNull);
      expect(validateDepositAccountLabel('KAIST CCC', enabled: true), isNull);
      expect(validateDepositAccountLabel('', enabled: false), isNull);
      expect(
        depositIngestUrl('https://abc.supabase.co/'),
        'https://abc.supabase.co/functions/v1/deposit-ingest',
      );
      expect(depositIngestUrl(''), isEmpty);
    });

    test('DepositStatus 와 사유 라벨이 모든 SQL 상태 · 사유 코드를 빠짐없이 덮는다', () {
      const sqlStatuses = [
        'unparsed',
        'unmatched',
        'ambiguous',
        'auto_matched',
        'manual_matched',
        'ignored',
        'undone',
      ];
      expect(
        DepositStatus.values.map((s) => s.dbValue).toSet(),
        sqlStatuses.toSet(),
      );
      for (final code in sqlStatuses) {
        final parsed = DepositStatus.parse(code);
        expect(parsed.dbValue, code);
        expect(parsed.label, isNotEmpty);
        expect(parsed.label, isNot(code));
      }

      const sqlMatchReasons = [
        'exact_event',
        'prefix_event',
        'exact_textbook_single',
        'prefix_textbook_single',
        'exact_textbook_round_sum',
        'prefix_textbook_round_sum',
        'no_candidate',
        'multiple_candidates',
        'cross_type_conflict',
        'same_name_members',
        'possible_duplicate',
        'duplicate_cleared',
        'match_error',
        'masked_depositor',
        'empty_depositor_name',
        'manual_link_event',
        'manual_link_orders',
        'no_amount',
        'multiple_amounts',
        'invalid_amount',
        'no_depositor',
        'parse_failed',
        'raw_expired',
        'unsupported_bank',
        'no_account_label',
        'config_missing_label',
        'withdrawal',
        'outgoing_transfer',
        'ad',
        'empty',
        'ignored',
      ];
      for (final reason in sqlMatchReasons) {
        final label = depositReasonLabel(reason);
        expect(label, isNotEmpty, reason: 'empty label for $reason');
        expect(label, isNot(reason), reason: 'unmapped match_reason: $reason');
      }

      const sqlIgnoredReasons = [
        'no_account_label',
        'config_missing_label',
        'withdrawal',
        'outgoing_transfer',
        'ad',
        'empty',
        'ignored',
      ];
      for (final reason in sqlIgnoredReasons) {
        final label = ignoredReasonLabel(reason);
        expect(label, isNotEmpty, reason: 'empty label for $reason');
        expect(
          label,
          isNot(reason),
          reason: 'unmapped ignored_reason: $reason',
        );
      }
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
      expect(
        autoOrder.copyWith(status: OrderStatus.requested).isAutoConfirmed,
        isFalse,
      );

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
    testWidgets('기본 검토 필요 필터, 원문 표시, 재해석, 수동 연결, 확인 취소, 무시 동작', (tester) async {
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
      expect(repo.calls, contains('linkOrders d-amb o1 mismatch=false'));

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

    testWidgets('중복 의심 입금의 중복 아님 확인과 금액 불일치 수동 연결 확인 다이얼로그가 동작한다', (
      tester,
    ) async {
      final repo = _FakeDepositRepo()
        ..deposits = [
          BankDeposit(
            id: 'd-dup',
            campusId: 'k',
            bankCode: 'toss',
            status: DepositStatus.ambiguous,
            depositorName: '홍길동',
            amount: 10000,
            depositedAt: DateTime(2026, 11, 26, 12),
            receivedAt: DateTime(2026, 11, 26, 12, 1),
            matchReason: 'possible_duplicate',
            duplicateOfId: 'd-orig',
          ),
        ];
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      // 중복 의심 상태에서는 다시 매칭 대신 중복 아님 버튼이 보인다.
      expect(find.widgetWithText(OutlinedButton, '다시 매칭'), findsNothing);
      final clearBtn = find.widgetWithText(OutlinedButton, '중복 아님');
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
      expect(find.text('중복 아님 확인'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '중복 아님'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('clearDuplicate d-dup'));

      // 10,000원 입금을 30,000원 이벤트에 수동 연결 -> 금액 불일치 확인 다이얼로그 표시
      await tester.tap(find.widgetWithText(OutlinedButton, '대상 연결'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('미납 이벤트'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('겨울 수련회'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '연결'));
      await tester.pumpAndSettle();

      expect(find.text('금액 불일치 확인'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('10,000원'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('30,000원'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, '금액 달라도 연결'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('linkEvent d-dup ep1 mismatch=true'));
    });

    testWidgets('50건을 초과하는 목록은 더 보기로 다음 페이지를 불러온다', (tester) async {
      final repo = _FakeDepositRepo()
        ..deposits = [
          for (var i = 0; i < 55; i++)
            BankDeposit(
              id: 'd-$i',
              campusId: 'k',
              bankCode: 'toss',
              status: DepositStatus.unmatched,
              depositorName: '입금자$i',
              amount: 10000,
              depositedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              receivedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              matchReason: 'no_candidate',
            ),
        ];
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      expect(find.text('검토 필요 55'), findsOneWidget);
      expect(find.text('입금 50 / 55건'), findsOneWidget);
      final loadMoreBtn = find.widgetWithText(OutlinedButton, '더 보기 (50 / 55)');
      await tester.scrollUntilVisible(
        loadMoreBtn,
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(loadMoreBtn);
      await tester.pumpAndSettle();
      await tester.tap(loadMoreBtn);
      await tester.pumpAndSettle();

      expect(
        repo.calls,
        contains('fetchDeposits needs_review limit=50 offset=50'),
      );
      expect(find.text('입금자54'), findsOneWidget);
      expect(find.textContaining('더 보기'), findsNothing);
    });

    testWidgets('검색 결과가 첫 페이지에 없어도 더 보기가 유지되어 이전 항목을 불러올 수 있다', (tester) async {
      final repo = _FakeDepositRepo()
        ..deposits = [
          for (var i = 0; i < 55; i++)
            BankDeposit(
              id: 'd-$i',
              campusId: 'k',
              bankCode: 'toss',
              status: DepositStatus.unmatched,
              depositorName: '입금자$i',
              amount: 10000,
              depositedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              receivedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              matchReason: 'no_candidate',
            ),
        ];
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      await tester.enterText(find.byType(TextField), '입금자54');
      await tester.pumpAndSettle();
      // 검색창(EditableText)이 아닌 목록 행의 Text 만 센다.
      final row54 = find.byWidgetPredicate(
        (w) => w is Text && w.data == '입금자54',
      );

      expect(row54, findsNothing);
      final loadMoreBtn = find.widgetWithText(OutlinedButton, '더 보기 (50 / 55)');
      expect(loadMoreBtn, findsOneWidget);

      await tester.tap(loadMoreBtn);
      await tester.pumpAndSettle();
      expect(row54, findsOneWidget);
    });

    testWidgets('새로고침 후 늦게 도착한 이전 더 보기 응답은 무시한다', (tester) async {
      final completer = Completer<List<BankDeposit>>();
      final repo = _FakeDepositRepo()
        ..pendingLoadMore = completer
        ..deposits = [
          for (var i = 0; i < 55; i++)
            BankDeposit(
              id: 'd-$i',
              campusId: 'k',
              bankCode: 'toss',
              status: DepositStatus.unmatched,
              depositorName: '입금자$i',
              amount: 10000,
              depositedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              receivedAt: DateTime(
                2026,
                11,
                26,
                12,
              ).subtract(Duration(minutes: i)),
              matchReason: 'no_candidate',
            ),
        ];
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      final loadMoreBtn = find.widgetWithText(OutlinedButton, '더 보기 (50 / 55)');
      await tester.scrollUntilVisible(
        loadMoreBtn,
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(loadMoreBtn);
      await tester.pumpAndSettle();
      await tester.tap(loadMoreBtn);
      await tester.pump();

      final refreshBtn = find.text('새로고침');
      await tester.scrollUntilVisible(
        refreshBtn,
        -600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(refreshBtn);
      await tester.pumpAndSettle();
      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      completer.complete([
        BankDeposit(
          id: 'd-stale',
          campusId: 'k',
          bankCode: 'toss',
          status: DepositStatus.unmatched,
          depositorName: '오래된응답',
          amount: 99000,
          depositedAt: DateTime(2026, 11, 20),
          receivedAt: DateTime(2026, 11, 20),
          matchReason: 'no_candidate',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('오래된응답'), findsNothing);
    });

    testWidgets('건수 로딩 중에는 0을 표시하지 않고, 건수 조회 실패 시 오류와 재시도를 표시한다', (
      tester,
    ) async {
      final pending = Completer<DepositCounts>();
      final loadingRepo = _FakeDepositRepo()..pendingCounts = pending;
      await _pump(tester, const AdminDepositsPage(), depositRepo: loadingRepo);

      expect(find.text('검토 필요'), findsOneWidget);
      expect(find.text('검토 필요 0'), findsNothing);
      pending.complete(const DepositCounts(needsReview: 2, all: 3));
      await tester.pumpAndSettle();
      expect(find.text('검토 필요 2'), findsOneWidget);

      final errRepo = _FakeDepositRepo()
        ..countsError = const AppException('건수 조회 실패');
      await _pump(tester, const AdminDepositsPage(), depositRepo: errRepo);
      expect(find.text('상태별 건수를 불러오지 못했습니다.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '다시 시도'), findsOneWidget);
      expect(find.text('검토 필요 0'), findsNothing);
    });

    testWidgets('추천 후보 연결 시 스냅샷이 아닌 최신 미납 금액으로 금액 불일치를 검사한다', (tester) async {
      final repo = _FakeDepositRepo()
        ..targets = UnpaidLinkTargets(
          orders: [
            UnpaidOrderTarget(
              orderId: 'o1',
              memberName: '홍길동',
              studentId: '20240001',
              roundLabel: '11/25',
              itemsSummary: '교재A ×1',
              amount: 12000,
              createdAt: DateTime(2026, 11, 25),
            ),
          ],
          eventPayments: const [],
        );
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      final linkBtn = find.widgetWithText(OutlinedButton, '대상 연결');
      await tester.ensureVisible(linkBtn);
      await tester.pumpAndSettle();
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '연결').first);
      await tester.pumpAndSettle();

      expect(find.text('금액 불일치 확인'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('12,000원'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, '금액 달라도 연결'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('linkOrders d-amb o1 mismatch=true'));
    });

    testWidgets('입금자 이름이 가려진 입금은 금액 · 원문과 함께 수동 연결/무시 버튼이 보인다', (
      tester,
    ) async {
      final repo = _FakeDepositRepo()
        ..deposits = [
          BankDeposit(
            id: 'd-masked',
            campusId: 'k',
            bankCode: 'toss',
            status: DepositStatus.unmatched,
            amount: 1,
            depositedAt: DateTime(2026, 11, 27, 0, 10),
            receivedAt: DateTime(2026, 11, 27, 0, 10),
            rawTitle: '1원 입금',
            rawText: '**** → 내 KAIST CCC 모임통장',
            rawPackage: 'viva.republica.toss',
            rawExpiresAt: DateTime(2026, 12, 11),
            matchReason: 'masked_depositor',
          ),
        ];
      await _pump(tester, const AdminDepositsPage(), depositRepo: repo);

      expect(find.text('입금자 미확인 (이름 가려짐)'), findsOneWidget);
      expect(find.text('1원'), findsOneWidget);
      expect(find.text('내용: **** → 내 KAIST CCC 모임통장'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '대상 연결'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '무시'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '다시 매칭'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '다시 해석'), findsNothing);
      expect(tester.takeException(), isNull);
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
    testWidgets('교재 신청 현황과 이벤트 상세에서 자동 확인된 항목에만 "자동 확인"을 표시한다', (tester) async {
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
      expect(find.textContaining('자동 확인', findRichText: true), findsOneWidget);
    });
  });
}
