import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/textbook_order.dart';

/// 교재 신청 상태 배지. 신청(입금 대기)만 파랑으로 강조한다.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      status.label,
      tone: switch (status) {
        OrderStatus.requested => BadgeTone.accent,
        OrderStatus.paid => BadgeTone.neutral,
        OrderStatus.cancelled => BadgeTone.muted,
      },
    );
  }
}

/// 배송 상태 배지. 회원이 수령 확인해야 하는 "배송됨"만 파랑으로 강조한다.
class DeliveryStatusChip extends StatelessWidget {
  const DeliveryStatusChip(this.delivery, {super.key});

  final DeliveryStatus delivery;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      delivery.label,
      tone: switch (delivery) {
        DeliveryStatus.pending => BadgeTone.muted,
        DeliveryStatus.shipped => BadgeTone.accent,
        DeliveryStatus.received => BadgeTone.neutral,
      },
    );
  }
}

/// `- 1 +` 수량 선택.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.canIncrement = true,
    this.max = 99,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool canIncrement;
  final int max;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = IconButton.styleFrom(
      backgroundColor: c.background,
      foregroundColor: c.textPrimary,
      disabledBackgroundColor: c.background,
      disabledForegroundColor: c.textTertiary,
      minimumSize: const Size(36, 36),
      fixedSize: const Size(36, 36),
      padding: EdgeInsets.zero,
    );
    // 비활성 버튼(0에서 -, 최대에서 +)을 누른 탭이 뒤의 카드 InkWell 로
    // 새어 나가 수량이 토글되지 않도록 스테퍼 영역의 탭을 여기서 삼킨다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '빼기',
            style: style,
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: value > 0 ? c.textPrimary : c.textTertiary,
              ),
            ),
          ),
          IconButton(
            tooltip: '더하기',
            style: style,
            onPressed: canIncrement && value < max
                ? () => onChanged(value + 1)
                : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 신청 품목 목록 + 합계.
class OrderItemsSummary extends StatelessWidget {
  const OrderItemsSummary({
    super.key,
    required this.items,
    required this.total,
    this.emphasizeTotal = false,
  });

  final List<TextbookOrderItem> items;
  final int total;
  final bool emphasizeTotal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: item.title,
                      children: [
                        TextSpan(
                          text: '  ${item.quantity}권',
                          style: TextStyle(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatWon(item.subtotal),
                  style: TextStyle(color: c.textSecondary),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: c.surfaceStrong),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '합계',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ),
            // 좁은 화면에서 큰 금액이 넘치지 않도록 필요하면 줄인다.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AmountText(
                  total,
                  size: emphasizeTotal ? AmountSize.large : AmountSize.small,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
