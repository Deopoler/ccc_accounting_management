import 'package:ccc_accounting_management/features/textbooks/domain/order_filter.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/order_round.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _orderJson({
  String id = 'o1',
  String status = 'requested',
  String round = '2026-09-30',
  String studentId = '20240001',
  String name = '홍길동',
  List<(String, String, int, int)> items = const [('b1', '교재 A', 2, 10000)],
}) => {
  'id': id,
  'user_id': 'u1',
  'round_start': round,
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
    expect(o.roundStart, DateTime(2026, 9, 30));
  });

  test('회원 수정 가능 여부: 이번 회차 + 신청 상태만', () {
    final current = DateTime(2026, 9, 30);
    final o = TextbookOrder.fromJson(_orderJson());
    expect(o.canMemberEdit(current), isTrue);
    expect(
      o.copyWith(status: OrderStatus.paid).canMemberEdit(current),
      isFalse,
    );
    expect(o.canMemberEdit(DateTime(2026, 10, 7)), isFalse);
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

  test('회차 라벨과 마감 표시', () {
    final round = OrderRound(
      start: DateTime(2026, 9, 30),
      deadline: DateTime(2026, 10, 7),
    );
    expect(round.label, '9/30(수) ~ 10/6(화)');
    expect(round.deadlineLabel, '10/6(화) 24:00');
    expect(round.previousStart(1), DateTime(2026, 9, 23));
  });
}
