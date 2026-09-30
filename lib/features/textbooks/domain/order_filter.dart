import 'textbook_order.dart';

/// 관리자 신청 현황 필터 (회차는 서버에서 거른다).
class OrderFilter {
  const OrderFilter({
    this.textbookId,
    this.status,
    this.delivery,
    this.query = '',
  });

  final String? textbookId;
  final OrderStatus? status;

  /// 배송 상태. 지정하면 취소된 신청은 제외한다.
  final DeliveryStatus? delivery;

  /// 학번 또는 이름 검색어
  final String query;

  bool matches(TextbookOrder order) {
    if (status != null && order.status != status) return false;
    if (delivery != null &&
        (order.status == OrderStatus.cancelled || order.delivery != delivery)) {
      return false;
    }
    if (textbookId != null &&
        !order.items.any((i) => i.textbookId == textbookId)) {
      return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final m = order.member;
      final hit =
          m != null &&
          (m.studentId.toLowerCase().contains(q) ||
              m.name.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return true;
  }

  List<TextbookOrder> apply(Iterable<TextbookOrder> orders) =>
      orders.where(matches).toList();

  OrderFilter withDelivery(DeliveryStatus? delivery) => OrderFilter(
    textbookId: textbookId,
    status: status,
    delivery: delivery,
    query: query,
  );
}

/// 배송 상태별 건수 (취소 제외).
Map<DeliveryStatus, int> countByDelivery(Iterable<TextbookOrder> orders) {
  final result = {for (final d in DeliveryStatus.values) d: 0};
  for (final o in orders) {
    if (o.status == OrderStatus.cancelled) continue;
    result[o.delivery] = result[o.delivery]! + 1;
  }
  return result;
}

/// 상태별 건수 / 금액.
typedef StatusSummary = ({int count, int amount});

Map<OrderStatus, StatusSummary> summarizeByStatus(
  Iterable<TextbookOrder> orders,
) {
  final result = {for (final s in OrderStatus.values) s: (count: 0, amount: 0)};
  for (final o in orders) {
    final cur = result[o.status]!;
    result[o.status] = (
      count: cur.count + 1,
      amount: cur.amount + o.totalPrice,
    );
  }
  return result;
}
