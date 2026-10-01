import 'package:intl/intl.dart';

/// 교재 신청 회차. 수요일 오전 9시(KST)에 시작해 다음 주 수요일 오전 9시에 마감된다.
/// 서버(public.current_order_round)와 같은 규칙이며, 실제 마감은 서버가 강제한다.
class OrderRound {
  const OrderRound({required this.start, required this.deadline});

  factory OrderRound.fromJson(Map<String, dynamic> json) => OrderRound(
    start: parseDateOnly(json['round_start'] as String),
    deadline: DateTime.parse(json['deadline'] as String).toLocal(),
  );

  /// 회차 시작일 (수요일, 날짜만 의미 있음)
  final DateTime start;

  /// 마감 시각 (다음 수요일 00:00 KST)
  final DateTime deadline;

  /// 마감일 (다음 수요일)
  DateTime get endDay => roundEndDay(start);

  /// `10/1(수) ~ 10/7(화)`
  String get label => roundLabel(start);

  /// `10/7(수) 오전 9시`
  String get deadlineLabel =>
      '${DateFormat('M/d(E)').format(endDay)} $roundCutoffLabel';

  /// [n] 회차 이전 회차의 시작일.
  DateTime previousStart(int n) =>
      DateTime(start.year, start.month, start.day - 7 * n);

  /// [date] 가 속한 회차가 이번 회차로부터 몇 회차 전인지. (수요일은 그날 시작하는 회차)
  /// 이번 회차 이후 날짜는 0.
  int offsetOf(DateTime date) {
    // 날짜만 비교한다. (UTC 로 바꿔 일광절약시간 영향을 없앤다)
    final days = DateTime.utc(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
    return days <= 0 ? 0 : (days + 6) ~/ 7;
  }
}

String roundLabel(DateTime start) {
  final end = roundEndDay(start);
  final f = DateFormat('M/d(E)');
  return '${f.format(start)} ~ ${f.format(end)}';
}

/// 마감 시각 표시 (KST)
const roundCutoffLabel = '오전 9시';

/// 회차 시작 수요일 → 마감일(다음 수요일)
DateTime roundEndDay(DateTime start) =>
    DateTime(start.year, start.month, start.day + 7);

/// `2026-09-30` → 로컬 자정 DateTime (날짜 비교용)
DateTime parseDateOnly(String value) {
  final d = DateTime.parse(value);
  return DateTime(d.year, d.month, d.day);
}

/// DateTime → `2026-09-30`
String toDateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
