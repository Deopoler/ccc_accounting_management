import 'package:ccc_accounting_management/features/textbooks/domain/order_filter.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _orderJson({
  String id = 'o1',
  String status = 'requested',
  String round = 'r1',
  String studentId = '20240001',
  String name = '홍길동',
  List<(String, String, int, int)> items = const [('b1', '교재 A', 2, 10000)],
}) => {
  'id': id,
  'user_id': 'u1',
  'round_id': round,
  'order_rounds': {
    'id': round,
    'starts_at': '2026-09-30T00:00:00+00:00',
    'deadline': '2026-10-07T00:00:00+00:00',
  },
  'status': status,
  'total_price': items.fold(0, (s, i) => s + i.$3 * i.$4),
  'created_at': '2026-09-30T01:00:00+00:00',
  'profiles': {'student_id': studentId, 'name': name},
  'textbook_order_items': [
    for (final i in items)
      {
        'textbook_id': i.$1,
        'quantity': i.$3,
        'unit_price': i.$4,
        'textbooks': {'title': i.$2},
      },
  ],
};

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'ko_KR';
    await initializeDateFormatting('ko_KR');
  });

  test('fromJson: 품목, 신청자, 상태를 읽는다', () {
    final o = TextbookOrder.fromJson(
      _orderJson(items: [('b2', '교재 B', 1, 7000), ('b1', '교재 A', 2, 10000)]),
    );
    expect(o.status, OrderStatus.requested);
    expect(o.items.map((i) => i.title), ['교재 A', '교재 B']);
    expect(o.totalPrice, 27000);
    expect(o.totalQuantity, 3);
    expect(o.member?.studentId, '20240001');
    expect(o.roundId, 'r1');
    expect(o.round?.start.toUtc(), DateTime.utc(2026, 9, 30));
  });

  test('회원 수정 가능 여부: 이번 회차 + 신청 상태만', () {
    const current = 'r1';
    final o = TextbookOrder.fromJson(_orderJson());
    expect(o.canMemberEdit(current), isTrue);
    expect(
      o.copyWith(status: OrderStatus.paid).canMemberEdit(current),
      isFalse,
    );
    expect(o.canMemberEdit('r2'), isFalse);
  });

  test('교재별 집계는 취소를 제외한다', () {
    final orders = [
      TextbookOrder.fromJson(_orderJson(id: 'a')),
      TextbookOrder.fromJson(_orderJson(id: 'b', status: 'paid')),
      TextbookOrder.fromJson(_orderJson(id: 'c', status: 'cancelled')),
    ];
    final tally = tallyByTextbook(orders);
    expect(tally['b1']!.quantity, 4);
    expect(tally['b1']!.amount, 40000);

    final summary = summarizeByStatus(orders);
    expect(summary[OrderStatus.cancelled]!.count, 1);
    expect(summary[OrderStatus.paid]!.amount, 20000);
  });

  test('필터: 상태 / 교재 / 학번·이름 검색', () {
    final orders = [
      TextbookOrder.fromJson(_orderJson(id: 'a')),
      TextbookOrder.fromJson(
        _orderJson(
          id: 'b',
          status: 'paid',
          studentId: '20230002',
          name: '김철수',
          items: [('b2', '교재 B', 1, 7000)],
        ),
      ),
    ];
    List<String> ids(OrderFilter f) =>
        f.apply(orders).map((o) => o.id).toList();

    expect(ids(const OrderFilter()), ['a', 'b']);
    expect(ids(const OrderFilter(status: OrderStatus.paid)), ['b']);
    expect(ids(const OrderFilter(textbookId: 'b1')), ['a']);
    expect(ids(const OrderFilter(query: '2023')), ['b']);
    expect(ids(const OrderFilter(query: '홍길')), ['a']);
  });

  test('배송 상태: 배송 전 → 배송됨 → 수령 완료', () {
    final o = TextbookOrder.fromJson(_orderJson());
    expect(o.delivery, DeliveryStatus.pending);
    expect(o.canConfirmReceipt, isFalse);

    final shipped = TextbookOrder.fromJson({
      ..._orderJson(),
      'is_shipped': true,
      'shipped_at': '2026-10-07T03:00:00+00:00',
      'received_at': null,
    });
    expect(shipped.delivery, DeliveryStatus.shipped);
    expect(shipped.shippedAt, DateTime.utc(2026, 10, 7, 3));
    expect(shipped.canConfirmReceipt, isTrue);
    // 배송된 신청은 이번 회차여도 회원이 수정/취소할 수 없다.
    expect(shipped.canMemberEdit('r1'), isFalse);

    final received = shipped.copyWith(
      receivedAt: () => DateTime.utc(2026, 10, 8),
      receivedBy: () => 'u1',
    );
    expect(received.delivery, DeliveryStatus.received);
    expect(received.canConfirmReceipt, isFalse);
    expect(received.receivedByAdmin, isFalse);
    expect(
      received.copyWith(receivedBy: () => 'admin').receivedByAdmin,
      isTrue,
    );

    final unshipped = received.copyWith(
      isShipped: false,
      shippedAt: () => null,
      receivedAt: () => null,
    );
    expect(unshipped.delivery, DeliveryStatus.pending);
  });

  test('배송 필터 / 건수는 취소를 제외한다', () {
    final orders = [
      TextbookOrder.fromJson(_orderJson(id: 'a')),
      TextbookOrder.fromJson({..._orderJson(id: 'b'), 'is_shipped': true}),
      TextbookOrder.fromJson({
        ..._orderJson(id: 'c', status: 'paid'),
        'is_shipped': true,
        'received_at': '2026-10-08T00:00:00+00:00',
      }),
      TextbookOrder.fromJson(_orderJson(id: 'd', status: 'cancelled')),
    ];
    List<String> ids(DeliveryStatus d) =>
        OrderFilter(delivery: d).apply(orders).map((o) => o.id).toList();

    expect(ids(DeliveryStatus.pending), ['a']);
    expect(ids(DeliveryStatus.shipped), ['b']);
    expect(ids(DeliveryStatus.received), ['c']);
    expect(countByDelivery(orders), {
      DeliveryStatus.pending: 1,
      DeliveryStatus.shipped: 1,
      DeliveryStatus.received: 1,
    });
  });

  test('회차 라벨과 마감 표시', () {
    final round = OrderRound(
      id: 'r',
      start: DateTime(2026, 9, 30, 9),
      deadline: DateTime(2026, 10, 7, 9),
    );
    expect(round.label, '9/30(수) ~ 10/7(수)');
    expect(round.deadlineLabel, '10/7(수) 오전 9시');

    // 관리자가 바꾼 마감
    final custom = OrderRound(
      id: 'r',
      start: DateTime(2026, 9, 30, 9),
      deadline: DateTime(2026, 10, 9, 15, 30),
    );
    expect(custom.label, '9/30(수) ~ 10/9(금)');
    expect(custom.deadlineLabel, '10/9(금) 오후 3시 30분');
  });

  test('시각 표시: 오전 / 오후, 0시 / 12시', () {
    expect(timeLabel(DateTime(2026, 1, 1, 0)), '오전 0시');
    expect(timeLabel(DateTime(2026, 1, 1, 9, 5)), '오전 9시 5분');
    expect(timeLabel(DateTime(2026, 1, 1, 12)), '오후 12시');
    expect(timeLabel(DateTime(2026, 1, 1, 23, 59)), '오후 11시 59분');
  });

  test('날짜로 회차 찾기: 시작일은 그날 시작하는 회차', () {
    OrderRound r(String id, DateTime start, DateTime deadline) =>
        OrderRound(id: id, start: start, deadline: deadline);
    // 최신순. 두 번째 회차는 관리자가 금요일 15시로 마감을 바꿨다.
    final rounds = [
      r('c', DateTime(2026, 10, 9, 15), DateTime(2026, 10, 16, 15)),
      r('b', DateTime(2026, 9, 30, 9), DateTime(2026, 10, 9, 15)),
      r('a', DateTime(2026, 9, 23, 9), DateTime(2026, 9, 30, 9)),
    ];
    String? on(DateTime d) => roundOnDate(rounds, d)?.id;
    expect(on(DateTime(2026, 10, 12)), 'c');
    expect(on(DateTime(2026, 10, 9)), 'c'); // 이번 회차 시작일
    expect(on(DateTime(2026, 10, 8)), 'b');
    expect(on(DateTime(2026, 9, 30)), 'b');
    expect(on(DateTime(2026, 9, 29)), 'a');
    expect(on(DateTime(2025, 1, 1)), 'a'); // 첫 회차보다 앞
    expect(roundOnDate(const [], DateTime(2026, 1, 1)), isNull);
  });
}
