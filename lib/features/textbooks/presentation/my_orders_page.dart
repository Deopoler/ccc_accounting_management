import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/presentation/bank_account_card.dart';
import '../domain/order_round.dart';
import '../domain/textbook_order.dart';
import 'textbook_providers.dart';
import 'widgets/order_widgets.dart';

class MyOrdersPage extends ConsumerWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    final round = ref.watch(currentRoundProvider);

    void retry() {
      ref.invalidate(myOrdersProvider);
      ref.invalidate(currentRoundProvider);
    }

    if (orders.hasError || round.hasError) {
      return ErrorView(error: (orders.error ?? round.error)!, onRetry: retry);
    }
    if (!orders.hasValue || !round.hasValue) return const LoadingView();

    final list = orders.requireValue;
    final current = round.requireValue;
    if (list.isEmpty) {
      return EmptyView(
        icon: Icons.receipt_long_outlined,
        message: '아직 신청한 교재가 없습니다.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.textbooks),
          child: const Text('교재 신청하러 가기'),
        ),
      );
    }

    final unpaid = list
        .where((o) => o.status == OrderStatus.requested)
        .fold(0, (sum, o) => sum + o.totalPrice);

    return ScrollPageBody(
      maxWidth: 800,
      children: [
        if (unpaid > 0) ...[
          BankAccountCard(amount: unpaid, title: '입금 대기 금액'),
          const SizedBox(height: 16),
        ],
        for (final order in list) ...[
          _OrderCard(order: order, currentRound: current),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order, required this.currentRound});

  final TextbookOrder order;
  final OrderRound currentRound;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await showConfirmDialog(
      context,
      title: '신청 취소',
      message: '이 신청을 취소하시겠습니까?',
      confirmLabel: '신청 취소',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(textbookRepositoryProvider).cancelOrder(widget.order.id);
      ref.invalidate(myOrdersProvider);
      if (mounted) showSnack(context, '신청이 취소되었습니다.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReceipt() async {
    final ok = await showConfirmDialog(
      context,
      title: '교재 수령 확인',
      message: '교재를 받으셨나요?\n수령 완료로 표시하면 되돌릴 수 없어요.',
      confirmLabel: '수령 완료',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(textbookRepositoryProvider)
          .confirmReceived(widget.order.id);
      ref.invalidate(myOrdersProvider);
      if (mounted) showSnack(context, '수령 완료로 표시했어요.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final theme = Theme.of(context);
    final editable = order.canMemberEdit(widget.currentRound.start);
    final closed =
        order.status == OrderStatus.requested &&
        !isSameDate(order.roundStart, widget.currentRound.start);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${roundLabel(order.roundStart)} 회차',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '신청일 ${formatDateTime(order.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (order.status != OrderStatus.cancelled) ...[
                  DeliveryStatusChip(order.delivery),
                  const SizedBox(width: 6),
                ],
                OrderStatusChip(order.status),
              ],
            ),
            const SizedBox(height: 16),
            OrderItemsSummary(items: order.items, total: order.totalPrice),
            if (order.isShipped && order.status != OrderStatus.cancelled) ...[
              const SizedBox(height: 16),
              _DeliveryPanel(
                order: order,
                busy: _busy,
                onConfirm: _confirmReceipt,
              ),
            ],
            if (editable) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('신청 취소'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () =>
                              context.go(AppRoutes.editTextbookOrder(order.id)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('수정'),
                  ),
                ],
              ),
            ] else if (closed) ...[
              const SizedBox(height: 12),
              Text(
                '신청이 마감된 회차라 수정·취소할 수 없습니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 배송된 신청의 배송/수령 안내. 미수령이면 수령 확인 버튼을 보여준다.
class _DeliveryPanel extends StatelessWidget {
  const _DeliveryPanel({
    required this.order,
    required this.busy,
    required this.onConfirm,
  });

  final TextbookOrder order;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final received = order.receivedAt;
    final waiting = order.canConfirmReceipt;
    final lines = [
      if (order.shippedAt != null) '배송 ${formatDateTime(order.shippedAt!)}',
      if (received != null)
        '수령 ${formatDateTime(received)}'
            '${order.receivedByAdmin ? ' (관리자 확인)' : ''}',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        // 해야 할 일(수령 확인)이 있을 때만 파란 면으로 강조한다.
        color: waiting ? c.primarySoft : c.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(
            received != null
                ? Icons.check_circle_outline
                : Icons.local_shipping_outlined,
            size: 22,
            color: waiting ? c.primary : c.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waiting ? '교재가 배송되었어요' : '교재를 받았어요',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                if (lines.isNotEmpty)
                  Text(
                    lines.join(' · '),
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
              ],
            ),
          ),
          if (waiting) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: busy ? null : onConfirm,
              child: const Text('수령 확인'),
            ),
          ],
        ],
      ),
    );
  }
}
