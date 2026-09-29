import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../../events/domain/event.dart';
import '../../textbooks/domain/order_round.dart';
import '../../textbooks/domain/textbook_order.dart';

/// Excel 에서 한글이 깨지지 않도록 UTF-8 BOM 을 붙인다.
final _codec = Csv(addBom: true);

String encodeCsv(List<List<Object?>> rows) =>
    _codec.encode([for (final r in rows) r.map(_cell).toList()]);

/// 스프레드시트가 수식으로 실행하지 않도록 위험한 첫 글자를 무력화한다. (CSV injection)
/// 이름·교재명 등은 회원/관리자가 자유롭게 입력한 값이다.
Object _cell(Object? value) {
  if (value == null) return '';
  if (value is num) return value;
  final s = value.toString();
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) return "'$s";
  return s;
}

String _dateTime(DateTime d) =>
    DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());

/// 교재 신청 현황: 신청 1건 = 1행.
List<List<Object?>> textbookOrdersCsvRows(Iterable<TextbookOrder> orders) => [
  ['학번', '이름', '회차 시작일', '교재', '총 수량', '금액', '상태', '신청일시'],
  for (final o in orders)
    [
      o.member?.studentId,
      o.member?.name,
      toDateOnly(o.roundStart),
      o.items.map((i) => '${i.title} x${i.quantity}').join('; '),
      o.totalQuantity,
      o.totalPrice,
      o.status.label,
      _dateTime(o.createdAt),
    ],
];

/// 교재별 집계 (취소 제외).
List<List<Object?>> textbookTallyCsvRows(Iterable<TextbookOrder> orders) {
  final tallies = tallyByTextbook(orders).values.toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  return [
    ['교재', '수량', '금액'],
    for (final t in tallies) [t.title, t.quantity, t.amount],
  ];
}

/// 이벤트 미송금자 목록.
List<List<Object?>> unpaidCsvRows(
  Event event,
  Iterable<EventPayment> payments,
) {
  final unpaid = payments.where((p) => !p.isPaid).toList()
    ..sort(
      (a, b) =>
          (a.member?.studentId ?? '').compareTo(b.member?.studentId ?? ''),
    );
  return [
    ['학번', '이름', '입금자명', '이벤트', '금액', '마감일'],
    for (final p in unpaid)
      [
        p.member?.studentId,
        p.member?.name,
        p.member == null
            ? ''
            : event.depositNameFor(
                name: p.member!.name,
                studentId: p.member!.studentId,
              ),
        event.title,
        p.amountFor(event),
        event.dueDate == null ? '' : toDateOnly(event.dueDate!),
      ],
  ];
}

/// 파일명에 쓸 수 없는 문자를 제거한다.
String safeFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');

String todayStamp() => DateFormat('yyyyMMdd').format(DateTime.now());
