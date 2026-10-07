import 'package:intl/intl.dart';

/// 교재 신청 회차. 캠퍼스마다 서버(public.order_rounds)에 저장된다.
///
/// 회차는 빈틈없이 이어진다. (다음 회차 시작 = 이전 회차 마감)
/// 관리자가 이번 회차의 마감 일시를 정하고, 다음 회차부터는 그 마감에서 1주일씩 이어진다.
/// 실제 마감은 서버가 강제한다.
class OrderRound {
  const OrderRound({
    required this.id,
    required this.start,
    required this.deadline,
  });

  factory OrderRound.fromJson(Map<String, dynamic> json) => OrderRound(
    id: json['id'] as String,
    start: DateTime.parse(json['starts_at'] as String).toLocal(),
    deadline: DateTime.parse(json['deadline'] as String).toLocal(),
  );

  final String id;

  /// 회차 시작 시각 (= 이전 회차 마감)
  final DateTime start;

  /// 마감 시각
  final DateTime deadline;

  /// `10/1(수) ~ 10/8(수)`
  String get label {
    final f = DateFormat('M/d(E)');
    return '${f.format(start)} ~ ${f.format(deadline)}';
  }

  /// `10/8(수) 오전 9시`
  String get deadlineLabel =>
      '${DateFormat('M/d(E)').format(deadline)} ${timeLabel(deadline)}';
}

/// 관리 중인 캠퍼스의 회차 목록.
class RoundList {
  const RoundList({
    required this.campusId,
    required this.current,
    required this.all,
  });

  final String campusId;

  /// 이번 회차
  final OrderRound current;

  /// 최신순. 관리자가 미리 만든 다음 회차가 있으면 맨 앞(이번 회차 앞)에 있다.
  final List<OrderRound> all;

  int get _currentIndex => all.indexWhere((r) => r.id == current.id);

  /// 미리 만든 다음 회차. 없으면 null.
  OrderRound? get next {
    final i = _currentIndex;
    return i > 0 ? all[i - 1] : null;
  }

  /// 이번 회차 기준 위치: 0 = 이번 회차, n = n회차 전, 음수 = 다음 회차.
  int offsetOf(OrderRound round) =>
      all.indexWhere((r) => r.id == round.id) - _currentIndex;

  /// `이번 회차`, `다음 회차`, `2회차 전`
  String describe(OrderRound round) {
    final o = offsetOf(round);
    return o == 0
        ? '이번 회차'
        : o < 0
        ? '다음 회차'
        : '$o회차 전';
  }
}

/// `오전 9시`, `오후 3시 30분`, `오전 0시`
String timeLabel(DateTime t) {
  final hour = t.hour % 12;
  final ampm = t.hour < 12 ? '오전' : '오후';
  final h = hour == 0 && t.hour >= 12 ? 12 : hour;
  return t.minute == 0 ? '$ampm $h시' : '$ampm $h시 ${t.minute}분';
}

/// [date] 가 속한 회차: 시작일이 [date] 이하인 가장 최근 회차. (시작일은 그날 시작하는 회차)
/// [rounds] 는 최신순. [date] 가 첫 회차보다 앞이면 가장 오래된 회차.
OrderRound? roundOnDate(List<OrderRound> rounds, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  for (final r in rounds) {
    if (!DateTime(r.start.year, r.start.month, r.start.day).isAfter(day)) {
      return r;
    }
  }
  return rounds.isEmpty ? null : rounds.last;
}

/// `2026-09-30` → 로컬 자정 DateTime (날짜 비교용)
DateTime parseDateOnly(String value) {
  final d = DateTime.parse(value);
  return DateTime(d.year, d.month, d.day);
}

/// DateTime → `2026-09-30`
String toDateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
