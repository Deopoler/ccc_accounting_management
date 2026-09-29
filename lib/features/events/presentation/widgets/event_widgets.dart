import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/formatters.dart';
import '../../../textbooks/presentation/widgets/order_widgets.dart';
import '../../domain/event.dart';

/// 내 송금 상태 배지. [payment] 가 null 이면 대상이 아니다.
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({super.key, required this.payment});

  final EventPayment? payment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = payment;
    if (p == null) {
      return StatusBadge(
        label: '대상 아님',
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      );
    }
    return p.isPaid
        ? StatusBadge(
            label: '송금완료',
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
          )
        : StatusBadge(
            label: '미송금',
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          );
  }
}

/// 금액 · 마감일(D-day) 한 줄.
class EventMetaLine extends StatelessWidget {
  const EventMetaLine({super.key, required this.event, this.payment});

  final Event event;

  /// 회원 화면: 본인 송금 행. 개인 금액이 있으면 그 금액을 보여준다.
  final EventPayment? payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = event.dueDate;
    final dDay = dDayLabel(event.daysLeft(DateTime.now()));
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          formatWon(payment?.amountFor(event) ?? event.amount),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (payment?.hasCustomAmount ?? false)
          Text(
            '(기본 ${formatWon(event.amount)})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (due != null)
          Text(
            '마감 ${formatDate(due)}${dDay == null ? '' : ' ($dDay)'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 송금률 막대 + 숫자.
class PaymentProgress extends StatelessWidget {
  const PaymentProgress({super.key, required this.summary});

  final EventSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '송금 ${summary.paidCount}/${summary.targetCount}명',
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              summary.rateLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: summary.rate, minHeight: 8),
        ),
        const SizedBox(height: 6),
        Text(
          '수금 ${formatWon(summary.collectedAmount)} / '
          '${formatWon(summary.expectedAmount)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
