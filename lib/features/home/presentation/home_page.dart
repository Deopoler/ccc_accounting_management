import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/event_providers.dart';
import '../../textbooks/domain/textbook_order.dart';
import '../../textbooks/presentation/textbook_providers.dart';
import '../../textbooks/presentation/widgets/order_widgets.dart';
import '../../campus/presentation/campus_providers.dart';

/// 대시보드: 내 교재 신청 상태 + 내 이벤트 송금 현황 요약.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final theme = Theme.of(context);

    return ScrollPageBody(
      maxWidth: 900,
      children: [
        if (profile != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              '${profile.name}님, 안녕하세요',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 640) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TextbookSummaryCard(),
                  SizedBox(height: 12),
                  _EventSummaryCard(),
                ],
              );
            }
            return const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _TextbookSummaryCard()),
                  SizedBox(width: 12),
                  Expanded(child: _EventSummaryCard()),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.child,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;

  /// 내야 할 금액처럼 행동이 필요한 값이면 강조색(파랑)
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: alert ? c.primary : c.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _TextbookSummaryCard extends ConsumerWidget {
  const _TextbookSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    final round = ref.watch(currentRoundProvider);

    Widget body;
    if (orders.hasError || round.hasError) {
      body = ErrorView(
        error: (orders.error ?? round.error)!,
        onRetry: () {
          ref.invalidate(myOrdersProvider);
          ref.invalidate(currentRoundProvider);
        },
      );
    } else if (!orders.hasValue || !round.hasValue) {
      body = const LoadingView();
    } else {
      final current = round.requireValue;
      final list = orders.requireValue;
      final thisRound = list
          .where(
            (o) => o.roundId == current.id && o.status != OrderStatus.cancelled,
          )
          .toList();
      final unpaid = list
          .where((o) => o.status == OrderStatus.requested)
          .fold(0, (s, o) => s + o.totalPrice);
      // 배송은 보통 마감 뒤에 되므로 회차와 관계없이 수령 대기 건을 보여준다.
      final awaiting = list.where((o) => o.canConfirmReceipt).toList();

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '이번 회차 ${current.label} · 마감 ${current.deadlineLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: '이번 회차 신청',
                  value: '${thisRound.length}건',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: '입금 대기',
                  value: formatWon(unpaid),
                  alert: unpaid > 0,
                ),
              ),
            ],
          ),
          for (final o in thisRound.take(3)) ...[
            const SizedBox(height: 10),
            _OrderRow(order: o),
          ],
          if (awaiting.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReceiptNotice(orders: awaiting),
          ],
        ],
      );
    }

    final hasOrders = orders.value?.isNotEmpty ?? false;
    final hasAwaiting = orders.value?.any((o) => o.canConfirmReceipt) ?? false;
    return _DashboardCard(
      icon: Icons.menu_book_outlined,
      title: '내 교재 신청',
      actionLabel: hasAwaiting
          ? '수령 확인하기'
          : hasOrders
          ? '신청 내역 보기'
          : '교재 신청하기',
      onAction: () =>
          context.go(hasOrders ? AppRoutes.myOrders : AppRoutes.textbooks),
      child: body,
    );
  }
}

/// 신청 품목 한 줄 + 배송/신청 상태 배지.
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final TextbookOrder order;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            order.items.map((i) => '${i.title} ×${i.quantity}').join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (order.status != OrderStatus.cancelled) ...[
          DeliveryStatusChip(order.delivery),
          const SizedBox(width: 6),
        ],
        OrderStatusChip(order.status),
      ],
    );
  }
}

/// 배송됐지만 아직 수령 확인하지 않은 신청 안내.
class _ReceiptNotice extends StatelessWidget {
  const _ReceiptNotice({required this.orders});

  final List<TextbookOrder> orders;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '배송된 교재 ${orders.length}건 · 받으셨다면 수령 확인해 주세요',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
            ],
          ),
          for (final o in orders.take(3)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    o.items.map((i) => '${i.title} ×${i.quantity}').join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  o.round == null
                      ? ''
                      : '${o.round!.start.month}/${o.round!.start.day} 회차',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EventSummaryCard extends ConsumerWidget {
  const _EventSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(CampusScope.member));
    final payments = ref.watch(myEventPaymentsProvider);
    final theme = Theme.of(context);

    Widget body;
    if (events.hasError || payments.hasError) {
      body = ErrorView(
        error: (events.error ?? payments.error)!,
        onRetry: () {
          ref.invalidate(eventsProvider);
          ref.invalidate(myEventPaymentsProvider);
        },
      );
    } else if (!events.hasValue || !payments.hasValue) {
      body = const LoadingView();
    } else {
      final mine = payments.requireValue;
      final targets = events.requireValue.where((e) => mine.containsKey(e.id));
      final unpaid = targets.where((e) => !mine[e.id]!.isPaid).toList();
      final unpaidTotal = unpaid.fold(
        0,
        (s, e) => s + mine[e.id]!.amountFor(e),
      );
      final today = DateTime.now();

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: '완납',
                  value: '${targets.length - unpaid.length}/${targets.length}건',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: '미납',
                  value: formatWon(unpaidTotal),
                  alert: unpaidTotal > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (targets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '송금 대상인 이벤트가 없습니다.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else if (unpaid.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '모든 이벤트 송금을 완료했습니다.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final Event e in unpaid.take(3)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  [
                    formatWon(mine[e.id]!.amountFor(e)),
                    ?dDayLabel(e.daysLeft(today)),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return _DashboardCard(
      icon: Icons.event_outlined,
      title: '내 이벤트 송금',
      actionLabel: '이벤트 보기',
      onAction: () => context.go(AppRoutes.events),
      child: body,
    );
  }
}
