import 'package:ccc_accounting_management/features/admin/domain/csv_exports.dart';
import 'package:ccc_accounting_management/features/events/domain/event.dart';
import 'package:ccc_accounting_management/features/textbooks/domain/textbook_order.dart';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

TextbookOrder _order({String status = 'requested', String name = '홍길동'}) =>
    TextbookOrder.fromJson({
      'id': 'o',
      'user_id': 'u',
      'round_start': '2026-09-30',
      'status': status,
      'total_price': 27000,
      'created_at': '2026-09-30T01:00:00Z',
      'profiles': {'student_id': '20240001', 'name': name},
      'textbook_order_items': [
        {
          'textbook_id': 'a',
          'quantity': 2,
          'unit_price': 10000,
          'textbooks': {'title': '교재 A'},
        },
        {
          'textbook_id': 'b',
          'quantity': 1,
          'unit_price': 7000,
          'textbooks': {'title': '교재 B'},
        },
      ],
    });

List<List<dynamic>> _decode(String s) => Csv().decode(s.substring(1));

void main() {
  test('UTF-8 BOM 으로 시작한다 (Excel 한글)', () {
    expect(
      encodeCsv([
        ['a'],
      ]).codeUnitAt(0),
      0xFEFF,
    );
  });

  test('수식으로 해석될 수 있는 값은 무력화한다', () {
    final rows = _decode(
      encodeCsv([
        ['=HYPERLINK("x")', '+1', '-a', '@b', '홍길동', 1000, -5],
      ]),
    );
    expect(rows.single, [
      "'=HYPERLINK(\"x\")",
      "'+1",
      "'-a",
      "'@b",
      '홍길동',
      '1000', // 숫자는 무력화하지 않는다 (디코더는 문자열로 읽음)
      '-5',
    ]);
  });

  test('신청 목록: 신청 1건 = 1행', () {
    final rows = textbookOrdersCsvRows([_order(), _order(status: 'paid')]);
    expect(rows, hasLength(3));
    expect(rows[1], [
      '20240001',
      '홍길동',
      '2026-09-30',
      '교재 A x2; 교재 B x1',
      3,
      27000,
      '신청',
      isA<String>(),
    ]);
    expect(rows[2][6], '입금확인');
  });

  test('교재별 집계는 취소를 제외한다', () {
    final rows = textbookTallyCsvRows([_order(), _order(status: 'cancelled')]);
    expect(rows, [
      ['교재', '수량', '금액'],
      ['교재 A', 2, 20000],
      ['교재 B', 1, 7000],
    ]);
  });

  test('미송금자 목록은 미송금만, 학번순', () {
    final event = Event.fromJson({
      'id': 'e',
      'title': '수련회',
      'amount': 50000,
      'due_date': '2026-10-10',
      'description': '',
      'created_at': '2026-09-01T00:00:00Z',
      'deposit_name': '{이름}MT',
    });
    EventPayment p(String sid, {bool paid = false, int? amount}) =>
        EventPayment.fromJson({
          'id': sid,
          'event_id': 'e',
          'user_id': sid,
          'is_paid': paid,
          'paid_at': null,
          'amount_override': amount,
          'member': {'student_id': sid, 'name': 'n$sid'},
        });
    final rows = unpaidCsvRows(event, [
      p('3', amount: 20000),
      p('1'),
      p('2', paid: true),
    ]);
    expect(rows.skip(1).map((r) => r[0]), ['1', '3']);
    expect(rows[1], ['1', 'n1', 'n1MT', '수련회', 50000, '2026-10-10']);
    expect(rows[2][4], 20000, reason: '개인별 금액');
  });

  test('파일명에서 사용할 수 없는 문자를 바꾼다', () {
    expect(safeFileName('미송금자_여름 수련회/1차.csv'), '미송금자_여름_수련회_1차.csv');
  });
}
