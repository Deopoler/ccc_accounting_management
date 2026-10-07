import 'order_round.dart';

enum OrderStatus {
  requested('신청'),
  paid('입금확인'),
  cancelled('취소');

  const OrderStatus(this.label);

  final String label;

  static OrderStatus parse(String value) =>
      OrderStatus.values.firstWhere((s) => s.name == value);
}

/// 배송 상태. 신청 → (관리자) 배송됨 → (회원) 수령 완료.
enum DeliveryStatus {
  pending('배송 전'),
  shipped('배송됨'),
  received('수령 완료');

  const DeliveryStatus(this.label);

  final String label;
}

class TextbookOrderItem {
  const TextbookOrderItem({
    required this.textbookId,
    required this.title,
    required this.quantity,
    required this.unitPrice,
  });

  factory TextbookOrderItem.fromJson(Map<String, dynamic> json) {
    final textbook = json['textbooks'] as Map<String, dynamic>?;
    return TextbookOrderItem(
      textbookId: json['textbook_id'] as String,
      title: textbook?['title'] as String? ?? '(삭제된 교재)',
      quantity: json['quantity'] as int,
      unitPrice: json['unit_price'] as int,
    );
  }

  final String textbookId;
  final String title;
  final int quantity;

  /// 신청 시점 가격
  final int unitPrice;

  int get subtotal => quantity * unitPrice;
}

/// 관리자 화면에서 함께 조회하는 신청자 정보.
class OrderMember {
  const OrderMember({required this.studentId, required this.name});

  final String studentId;
  final String name;
}

class TextbookOrder {
  const TextbookOrder({
    required this.id,
    required this.userId,
    required this.roundId,
    this.round,
    required this.status,
    required this.totalPrice,
    required this.createdAt,
    required this.items,
    this.member,
    this.isShipped = false,
    this.shippedAt,
    this.receivedAt,
    this.receivedBy,
  });

  factory TextbookOrder.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final items =
        (json['textbook_order_items'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TextbookOrderItem.fromJson)
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return TextbookOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      roundId: json['round_id'] as String,
      round: json['order_rounds'] == null
          ? null
          : OrderRound.fromJson(json['order_rounds'] as Map<String, dynamic>),
      status: OrderStatus.parse(json['status'] as String),
      totalPrice: json['total_price'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: items,
      isShipped: json['is_shipped'] as bool? ?? false,
      shippedAt: _parseTime(json['shipped_at']),
      receivedAt: _parseTime(json['received_at']),
      receivedBy: json['received_by'] as String?,
      member: profile == null
          ? null
          : OrderMember(
              studentId: profile['student_id'] as String,
              name: profile['name'] as String,
            ),
    );
  }

  final String id;
  final String userId;
  final String roundId;

  /// 신청이 속한 회차. 관리자가 다른 회차로 옮길 수 있다. (조회할 때 함께 불러온다)
  final OrderRound? round;
  final OrderStatus status;
  final int totalPrice;
  final DateTime createdAt;
  final List<TextbookOrderItem> items;
  final OrderMember? member;

  /// 관리자가 배송 처리했는지. 처리 시각은 서버가 기록한다.
  final bool isShipped;
  final DateTime? shippedAt;

  /// 수령 확인 시각. 배송됨 상태에서만 값이 있다.
  final DateTime? receivedAt;

  /// 수령을 체크한 사람 (회원 본인 또는 관리자).
  final String? receivedBy;

  /// 회원 본인이 아니라 관리자가 수령 처리했는지.
  bool get receivedByAdmin =>
      receivedAt != null && receivedBy != null && receivedBy != userId;

  DeliveryStatus get delivery => receivedAt != null
      ? DeliveryStatus.received
      : isShipped
      ? DeliveryStatus.shipped
      : DeliveryStatus.pending;

  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  /// 마감 전 회차(이번 회차, 또는 관리자가 옮긴 다음 회차)의 신청인지.
  bool isRoundOpen(OrderRound current) =>
      roundId == current.id ||
      (round != null && !round!.start.isBefore(current.deadline));

  /// 회원이 수정/취소할 수 있는지. 실제 제한은 서버 RPC 가 강제한다.
  bool canMemberEdit(OrderRound current) =>
      status == OrderStatus.requested && !isShipped && isRoundOpen(current);

  /// 회원이 수령 확인할 수 있는지 (배송됨 + 아직 미수령). 서버 RPC 가 강제한다.
  bool get canConfirmReceipt =>
      status != OrderStatus.cancelled && delivery == DeliveryStatus.shipped;

  TextbookOrder copyWith({
    OrderRound? round,
    OrderStatus? status,
    bool? isShipped,
    DateTime? Function()? shippedAt,
    DateTime? Function()? receivedAt,
    String? Function()? receivedBy,
  }) => TextbookOrder(
    id: id,
    userId: userId,
    roundId: round?.id ?? roundId,
    round: round ?? this.round,
    status: status ?? this.status,
    totalPrice: totalPrice,
    createdAt: createdAt,
    items: items,
    member: member,
    isShipped: isShipped ?? this.isShipped,
    shippedAt: shippedAt == null ? this.shippedAt : shippedAt(),
    receivedAt: receivedAt == null ? this.receivedAt : receivedAt(),
    receivedBy: receivedBy == null ? this.receivedBy : receivedBy(),
  );
}

DateTime? _parseTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// 교재별 집계 (취소 제외).
class TextbookTally {
  TextbookTally(this.title);

  final String title;
  int quantity = 0;
  int amount = 0;
}

Map<String, TextbookTally> tallyByTextbook(Iterable<TextbookOrder> orders) {
  final result = <String, TextbookTally>{};
  for (final order in orders) {
    if (order.status == OrderStatus.cancelled) continue;
    for (final item in order.items) {
      final t = result.putIfAbsent(
        item.textbookId,
        () => TextbookTally(item.title),
      );
      t.quantity += item.quantity;
      t.amount += item.subtotal;
    }
  }
  return result;
}
