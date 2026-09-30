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
    required this.roundStart,
    required this.status,
    required this.totalPrice,
    required this.createdAt,
    required this.items,
    this.member,
    this.isShipped = false,
    this.shippedAt,
    this.receivedAt,
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
      roundStart: parseDateOnly(json['round_start'] as String),
      status: OrderStatus.parse(json['status'] as String),
      totalPrice: json['total_price'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: items,
      isShipped: json['is_shipped'] as bool? ?? false,
      shippedAt: _parseTime(json['shipped_at']),
      receivedAt: _parseTime(json['received_at']),
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
  final DateTime roundStart;
  final OrderStatus status;
  final int totalPrice;
  final DateTime createdAt;
  final List<TextbookOrderItem> items;
  final OrderMember? member;

  /// 관리자가 배송 처리했는지. 처리 시각은 서버가 기록한다.
  final bool isShipped;
  final DateTime? shippedAt;

  /// 회원이 수령을 확인한 시각. 배송됨 상태에서만 값이 있다.
  final DateTime? receivedAt;

  DeliveryStatus get delivery => receivedAt != null
      ? DeliveryStatus.received
      : isShipped
      ? DeliveryStatus.shipped
      : DeliveryStatus.pending;

  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  /// 회원이 수정/취소할 수 있는지. 실제 제한은 서버 RPC 가 강제한다.
  bool canMemberEdit(DateTime currentRoundStart) =>
      status == OrderStatus.requested &&
      !isShipped &&
      isSameDate(roundStart, currentRoundStart);

  /// 회원이 수령 확인할 수 있는지 (배송됨 + 아직 미수령). 서버 RPC 가 강제한다.
  bool get canConfirmReceipt =>
      status != OrderStatus.cancelled && delivery == DeliveryStatus.shipped;

  TextbookOrder copyWith({
    OrderStatus? status,
    bool? isShipped,
    DateTime? Function()? shippedAt,
    DateTime? Function()? receivedAt,
  }) => TextbookOrder(
    id: id,
    userId: userId,
    roundStart: roundStart,
    status: status ?? this.status,
    totalPrice: totalPrice,
    createdAt: createdAt,
    items: items,
    member: member,
    isShipped: isShipped ?? this.isShipped,
    shippedAt: shippedAt == null ? this.shippedAt : shippedAt(),
    receivedAt: receivedAt == null ? this.receivedAt : receivedAt(),
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
