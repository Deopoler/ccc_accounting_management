import 'package:intl/intl.dart';

/// 교재 신청 회차. 수요일 00:00(KST) 에 시작해 다음 주 화요일 24:00 에 마감된다.
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

  /// 마감일 (화요일)
  DateTime get lastDay => start.add(const Duration(days: 6));

  /// `10/1(수) ~ 10/7(화)`
  String get label => roundLabel(start);

  /// `10/7(화) 24:00`
  String get deadlineLabel => '${DateFormat('M/d(E)').format(lastDay)} 24:00';

  /// [n] 회차 이전 회차의 시작일.
  DateTime previousStart(int n) =>
      DateTime(start.year, start.month, start.day - 7 * n);
}

String roundLabel(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  final f = DateFormat('M/d(E)');
  return '${f.format(start)} ~ ${f.format(end)}';
}

/// `2026-09-30` → 로컬 자정 DateTime (날짜 비교용)
DateTime parseDateOnly(String value) {
  final d = DateTime.parse(value);
  return DateTime(d.year, d.month, d.day);
}

/// DateTime → `2026-09-30`
String toDateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
