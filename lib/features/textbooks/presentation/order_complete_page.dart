import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/presentation/bank_account_card.dart';
import 'textbook_providers.dart';
import 'widgets/order_widgets.dart';

/// 신청(수정) 완료: 총 금액과 송금 계좌 안내.
class OrderCompletePage extends ConsumerWidget {
  const OrderCompletePage({
    super.key,
    required this.orderId,
    this.edited = false,
  });

  final String orderId;
  final bool edited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    final theme = Theme.of(context);

    return AsyncValueView(
      value: order,
      onRetry: () => ref.invalidate(orderProvider(orderId)),
      isEmpty: (o) => o == null,
      empty: const EmptyView(message: '신청 내역을 찾을 수 없습니다.'),
      data: (o) => ScrollPageBody(
        maxWidth: 640,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            edited ? '신청이 수정되었습니다' : '교재 신청이 완료되었습니다',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '아래 계좌로 합계 금액을 송금해 주세요.\n회계 담당자가 입금을 확인하면 상태가 "입금확인"으로 바뀝니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: OrderItemsSummary(
                items: o!.items,
                total: o.totalPrice,
                emphasizeTotal: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          BankAccountCard(amount: o.totalPrice),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go(AppRoutes.myOrders),
            child: const Text('내 신청 내역 보기'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('홈으로'),
          ),
        ],
      ),
    );
  }
}
