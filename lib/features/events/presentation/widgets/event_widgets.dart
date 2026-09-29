import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/event.dart';

/// 납부 상태 배지: 미납(파랑, 해야 할 일) / 완납(회색) / 대상 아님(흐림).
/// [payment] 가 null 이면 대상이 아니다.
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({super.key, required this.payment});

  final EventPayment? payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    if (p == null) return const AppBadge('대상 아님', tone: BadgeTone.muted);
    return p.isPaid
        ? const AppBadge('완납', tone: BadgeTone.neutral)
        : const AppBadge('미납', tone: BadgeTone.accent);
  }
}

/// 금액(크게) + 마감일(D-day).
class EventMetaLine extends StatelessWidget {
  const EventMetaLine({super.key, required this.event, this.payment});

  final Event event;

  /// 회원 화면: 본인 송금 행. 개인 금액이 있으면 그 금액을 보여준다.
  final EventPayment? payment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final due = event.dueDate;
    final dDay = dDayLabel(event.daysLeft(DateTime.now()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AmountText(payment?.amountFor(event) ?? event.amount),
            if (payment?.hasCustomAmount ?? false)
              Text(
                '기본 ${formatWon(event.amount)}',
                style: TextStyle(
                  fontSize: 13,
                  color: c.textTertiary,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: c.textTertiary,
                ),
              ),
          ],
        ),
        if (due != null) ...[
          const SizedBox(height: 2),
          Text(
            '마감 ${formatDate(due)}${dDay == null ? '' : ' · $dDay'}',
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
        ],
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
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '완납 ${summary.paidCount}/${summary.targetCount}명',
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
            const Spacer(),
            Text(
              summary.rateLabel,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: summary.rate,
            minHeight: 6,
            backgroundColor: c.surfaceStrong,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '수금 ${formatWon(summary.collectedAmount)} / '
          '${formatWon(summary.expectedAmount)}',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
      ],
    );
  }
}
