import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/textbook_order.dart';

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      OrderStatus.requested => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      OrderStatus.paid => (scheme.primaryContainer, scheme.onPrimaryContainer),
      OrderStatus.cancelled => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return StatusBadge(label: status.label, background: bg, foreground: fg);
  }
}

/// 작은 둥근 상태 표시.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: '빼기',
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.outlined(
          tooltip: '더하기',
          visualDensity: VisualDensity.compact,
          onPressed: canIncrement && value < max
              ? () => onChanged(value + 1)
              : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
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
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: item.title,
                      children: [
                        TextSpan(text: '  × ${item.quantity}', style: muted),
                      ],
                    ),
                  ),
                ),
                Text(formatWon(item.subtotal)),
              ],
            ),
          ),
        const Divider(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                '합계',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatWon(total),
              style:
                  (emphasizeTotal
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: emphasizeTotal
                            ? theme.colorScheme.primary
                            : null,
                      ),
            ),
          ],
        ),
      ],
    );
  }
}
