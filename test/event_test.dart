import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';

Event _event(String id, {String? due, String created = '2026-09-01'}) =>
    Event.fromJson({
      'id': id,
      'title': id,
      'amount': 10000,
      'due_date': due,
      'description': null,
      'created_at': '${created}T00:00:00Z',
    });

EventPayment _payment(String id, {bool paid = false, int? amount}) =>
    EventPayment.fromJson({
      'id': id,
      'event_id': 'e1',
      'user_id': 'u$id',
      'is_paid': paid,
      'paid_at': paid ? '2026-09-29T03:00:00Z' : null,
      'amount_override': amount,
      'member': {'student_id': '2024000$id', 'name': '회원$id'},
    });

void main() {
  final today = DateTime(2026, 9, 29);

  test('D-day 계산', () {
    expect(dDayLabel(_event('a', due: '2026-10-02').daysLeft(today)), 'D-3');
    expect(dDayLabel(_event('a', due: '2026-09-29').daysLeft(today)), 'D-Day');
    expect(dDayLabel(_event('a', due: '2026-09-28').daysLeft(today)), '마감');
    expect(dDayLabel(_event('a').daysLeft(today)), isNull);
  });

  test('정렬: 진행 중(임박순) → 마감일 없음 → 지난 이벤트', () {
    final sorted = sortEventsForDisplay([
      _event('past-old', due: '2026-08-01'),
      _event('none', created: '2026-09-10'),
      _event('soon2', due: '2026-10-10'),
      _event('past-recent', due: '2026-09-20'),
      _event('soon1', due: '2026-09-30'),
    ], today);
    expect(sorted.map((e) => e.id), [
      'soon1',
      'soon2',
      'none',
      'past-recent',
      'past-old',
    ]);
  });

  test('송금 요약: 송금률과 수금액', () {
    final payments = [
      _payment('1', paid: true),
      _payment('2'),
      _payment('3', paid: true),
      _payment('4'),
    ];
    final s = EventSummary.fromPayments(payments, _event('e1'));
    expect(s.targetCount, 4);
    expect(s.paidCount, 2);
    expect(s.unpaidCount, 2);
    expect(s.collectedAmount, 20000);
    expect(s.rateLabel, '50%');
    expect(EventSummary.empty.rateLabel, '0%');
  });

  test('개인별 금액: 조정된 회원은 그 금액으로 집계한다', () {
    final event = _event('e1'); // 기본 10,000원
    final payments = [
      _payment('1', paid: true, amount: 5000),
      _payment('2', amount: 0),
      _payment('3', paid: true),
      _payment('4'),
    ];
    expect(payments.first.hasCustomAmount, isTrue);
    expect(payments.first.amountFor(event), 5000);
    expect(payments[2].amountFor(event), 10000);

    final s = EventSummary.fromPayments(payments, event);
    expect(s.expectedAmount, 25000);
    expect(s.collectedAmount, 15000);
    expect(s.outstandingAmount, 10000);

    final reset = payments.first.copyWith(amountOverride: () => null);
    expect(reset.amountFor(event), 10000);
    expect(reset.isPaid, isTrue);
  });

  test('송금 행: 회원 정보와 토글', () {
    final p = _payment('1');
    expect(p.member?.name, '회원1');
    final paid = p.copyWith(isPaid: true);
    expect(paid.isPaid, isTrue);
    expect(paid.paidAt, isNotNull);
    expect(paid.copyWith(isPaid: false).paidAt, isNull);
  });

  test('EventInput: 마감일은 날짜 문자열로 저장', () {
    final json = EventInput(
      title: 't',
      amount: 1,
      dueDate: DateTime(2026, 10, 3),
      description: '',
    ).toJson();
    expect(json['due_date'], '2026-10-03');
  });

  test('입금자명: 자리표시자 치환, 비어 있으면 이름', () {
    expect(renderDepositName('', name: '홍길동', studentId: '2024'), '홍길동');
    expect(renderDepositName('  ', name: '홍길동', studentId: '2024'), '홍길동');
    expect(
      renderDepositName('{이름}MT', name: '홍길동', studentId: '2024'),
      '홍길동MT',
    );
    expect(
      renderDepositName('{학번}{이름}', name: '홍길동', studentId: '2024'),
      '2024홍길동',
    );
    final e = Event.fromJson({
      'id': 'e',
      'title': 't',
      'amount': 1,
      'due_date': null,
      'description': '',
      'created_at': '2026-09-01T00:00:00Z',
      'deposit_name': '수련회{이름}',
    });
    expect(e.depositNameFor(name: '김', studentId: '1'), '수련회김');
    expect(
      const EventInput(
        title: 't',
        amount: 1,
        dueDate: null,
        description: '',
        depositName: ' {이름}MT ',
      ).toJson()['deposit_name'],
      '{이름}MT',
    );
  });
}
