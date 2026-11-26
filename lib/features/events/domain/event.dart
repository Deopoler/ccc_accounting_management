import '../../textbooks/domain/order_round.dart';

class Event {
  const Event({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.description,
    required this.createdAt,
    this.depositName = '',
    this.autoEnrollNewMembers = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] as String,
    title: json['title'] as String,
    amount: json['amount'] as int,
    dueDate: switch (json['due_date']) {
      final String d => parseDateOnly(d),
      _ => null,
    },
    description: json['description'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    depositName: json['deposit_name'] as String? ?? '',
    autoEnrollNewMembers: json['auto_enroll_new_members'] as bool? ?? false,
  );

  final String id;
  final String title;
  final int amount;
  final DateTime? dueDate;
  final String description;
  final DateTime createdAt;

  /// 입금자명 형식. `{이름}`, `{학번}` 자리표시자를 쓸 수 있고, 비어 있으면 회원 이름.
  final String depositName;

  /// 켜 두면 가입이 승인된 같은 캠퍼스 회원이 마감 전까지 송금 대상에 자동 추가된다.
  final bool autoEnrollNewMembers;

  /// 회원에게 안내할 입금자명.
  String depositNameFor({required String name, required String studentId}) =>
      renderDepositName(depositName, name: name, studentId: studentId);

  /// 마감일까지 남은 일수 (오늘 마감이면 0, 지났으면 음수). 마감일이 없으면 null.
  int? daysLeft(DateTime today) {
    final due = dueDate;
    if (due == null) return null;
    final t = DateTime(today.year, today.month, today.day);
    return DateTime(due.year, due.month, due.day).difference(t).inDays;
  }
}

/// 입금자명 자리표시자
const depositNamePlaceholders = ['{이름}', '{학번}'];

String renderDepositName(
  String template, {
  required String name,
  required String studentId,
}) {
  final t = template.trim();
  if (t.isEmpty) return name;
  return t.replaceAll('{이름}', name).replaceAll('{학번}', studentId);
}

/// 진행 중(마감 임박순) → 마감일 없음(최신순) → 지난 이벤트(최근 마감순).
List<Event> sortEventsForDisplay(Iterable<Event> events, DateTime today) {
  int group(Event e) {
    final d = e.daysLeft(today);
    if (d == null) return 1;
    return d >= 0 ? 0 : 2;
  }

  return events.toList()..sort((a, b) {
    final g = group(a).compareTo(group(b));
    if (g != 0) return g;
    return switch (group(a)) {
      0 => a.dueDate!.compareTo(b.dueDate!),
      2 => b.dueDate!.compareTo(a.dueDate!),
      _ => b.createdAt.compareTo(a.createdAt),
    };
  });
}

/// `D-3`, `D-Day`, `마감`
String? dDayLabel(int? daysLeft) {
  if (daysLeft == null) return null;
  if (daysLeft > 0) return 'D-$daysLeft';
  if (daysLeft == 0) return 'D-Day';
  return '마감';
}

class EventInput {
  const EventInput({
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.description,
    this.depositName = '',
    this.autoEnrollNewMembers = false,
  });

  final String title;
  final int amount;
  final DateTime? dueDate;
  final String description;
  final String depositName;
  final bool autoEnrollNewMembers;

  Map<String, dynamic> toJson() => {
    'title': title,
    'amount': amount,
    'due_date': dueDate == null ? null : toDateOnly(dueDate!),
    'description': description,
    'deposit_name': depositName.trim(),
    'auto_enroll_new_members': autoEnrollNewMembers,
  };
}

class EventMember {
  const EventMember({required this.studentId, required this.name});

  final String studentId;
  final String name;
}

class EventPayment {
  const EventPayment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.isPaid,
    required this.paidAt,
    this.amountOverride,
    this.member,
  });

  factory EventPayment.fromJson(Map<String, dynamic> json) {
    final profile = json['member'] as Map<String, dynamic>?;
    return EventPayment(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      isPaid: json['is_paid'] as bool,
      paidAt: switch (json['paid_at']) {
        final String t => DateTime.parse(t),
        _ => null,
      },
      amountOverride: json['amount_override'] as int?,
      member: profile == null
          ? null
          : EventMember(
              studentId: profile['student_id'] as String,
              name: profile['name'] as String,
            ),
    );
  }

  final String id;
  final String eventId;
  final String userId;
  final bool isPaid;
  final DateTime? paidAt;

  /// 이 회원에게만 적용되는 금액. null 이면 이벤트 기본 금액.
  final int? amountOverride;
  final EventMember? member;

  bool get hasCustomAmount => amountOverride != null;

  /// 실제로 내야 하는 금액.
  int amountFor(Event event) => amountOverride ?? event.amount;

  EventPayment copyWith({bool? isPaid, int? Function()? amountOverride}) {
    final paid = isPaid ?? this.isPaid;
    return EventPayment(
      id: id,
      eventId: eventId,
      userId: userId,
      isPaid: paid,
      paidAt: paid ? (paidAt ?? DateTime.now()) : null,
      amountOverride: amountOverride == null
          ? this.amountOverride
          : amountOverride(),
      member: member,
    );
  }
}

/// 이벤트별 송금 요약 (event_payment_summaries 뷰 또는 목록에서 계산).
class EventSummary {
  const EventSummary({
    required this.targetCount,
    required this.paidCount,
    required this.collectedAmount,
    required this.expectedAmount,
  });

  factory EventSummary.fromJson(Map<String, dynamic> json) => EventSummary(
    targetCount: json['target_count'] as int,
    paidCount: json['paid_count'] as int,
    collectedAmount: (json['collected_amount'] as num).toInt(),
    expectedAmount: (json['expected_amount'] as num? ?? 0).toInt(),
  );

  /// 개인별 금액을 반영해 계산한다.
  factory EventSummary.fromPayments(
    Iterable<EventPayment> payments,
    Event event,
  ) {
    var paid = 0;
    var collected = 0;
    var expected = 0;
    var count = 0;
    for (final p in payments) {
      final amount = p.amountFor(event);
      count++;
      expected += amount;
      if (p.isPaid) {
        paid++;
        collected += amount;
      }
    }
    return EventSummary(
      targetCount: count,
      paidCount: paid,
      collectedAmount: collected,
      expectedAmount: expected,
    );
  }

  static const empty = EventSummary(
    targetCount: 0,
    paidCount: 0,
    collectedAmount: 0,
    expectedAmount: 0,
  );

  final int targetCount;
  final int paidCount;
  final int collectedAmount;

  /// 대상 전원의 금액 합계 (개인별 금액 반영).
  final int expectedAmount;

  int get unpaidCount => targetCount - paidCount;

  int get outstandingAmount => expectedAmount - collectedAmount;

  /// 0.0 ~ 1.0
  double get rate => targetCount == 0 ? 0 : paidCount / targetCount;

  String get rateLabel => '${(rate * 100).round()}%';
}

/// 관리자 송금 현황 목록의 정렬 기준.
enum EventPaymentSort {
  studentId('학번순'),
  name('이름순'),
  paidAt('확인일순');

  const EventPaymentSort(this.label);
  final String label;
}

/// [sort] 기준으로 정렬한 새 목록. 같은 값이면 학번순.
/// 확인일순은 최근 확인이 위, 미납은 맨 아래.
List<EventPayment> sortEventPayments(
  Iterable<EventPayment> payments,
  EventPaymentSort sort,
) {
  int byStudentId(EventPayment a, EventPayment b) =>
      (a.member?.studentId ?? '').compareTo(b.member?.studentId ?? '');

  int compare(EventPayment a, EventPayment b) {
    switch (sort) {
      case EventPaymentSort.studentId:
        return byStudentId(a, b);
      case EventPaymentSort.name:
        final c = (a.member?.name ?? '').compareTo(b.member?.name ?? '');
        return c != 0 ? c : byStudentId(a, b);
      case EventPaymentSort.paidAt:
        final pa = a.paidAt, pb = b.paidAt;
        if (pa == null && pb == null) return byStudentId(a, b);
        if (pa == null) return 1;
        if (pb == null) return -1;
        final c = pb.compareTo(pa);
        return c != 0 ? c : byStudentId(a, b);
    }
  }

  return payments.toList()..sort(compare);
}
