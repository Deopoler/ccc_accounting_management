import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/presentation/bank_account_card.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/event.dart';
import 'event_providers.dart';
import 'widgets/event_widgets.dart';
import '../../campus/presentation/campus_providers.dart';

/// 회원: 이벤트 목록과 내 송금 여부. 송금은 이벤트마다 따로 한다.
class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(CampusScope.member));
    final payments = ref.watch(myEventPaymentsProvider);

    if (events.hasError || payments.hasError) {
      return ErrorView(
        error: (events.error ?? payments.error)!,
        onRetry: () {
          ref.invalidate(eventsProvider);
          ref.invalidate(myEventPaymentsProvider);
        },
      );
    }
    if (!events.hasValue || !payments.hasValue) return const LoadingView();

    final list = events.requireValue;
    final mine = payments.requireValue;
    if (list.isEmpty) {
      return const EmptyView(
        icon: Icons.event_outlined,
        message: '등록된 이벤트가 없습니다.',
      );
    }

    final unpaidCount = list.where((e) => mine[e.id]?.isPaid == false).length;

    return ScrollPageBody(
      maxWidth: 800,
      children: [
        if (unpaidCount > 0) ...[
          Text(
            '미납 이벤트 $unpaidCount건 · 이벤트마다 안내된 금액과 입금자명으로 따로 송금해 주세요.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 12),
        ],
        for (final e in list) ...[
          _EventCard(event: e, payment: mine[e.id]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, required this.payment});

  final Event event;
  final EventPayment? payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paidAt = payment?.paidAt;
    final profile = ref.watch(currentProfileProvider).value;
    final p = payment;
    final needsPayment = p != null && !p.isPaid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PaymentBadge(payment: payment),
              ],
            ),
            const SizedBox(height: 6),
            EventMetaLine(event: event, payment: payment),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(event.description, style: theme.textTheme.bodyMedium),
            ],
            if (needsPayment) ...[
              const SizedBox(height: 16),
              BankAccountCard(
                embedded: true,
                title: '이 이벤트 송금 안내',
                amount: p.amountFor(event),
                depositName: profile == null
                    ? null
                    : event.depositNameFor(
                        name: profile.name,
                        studentId: profile.studentId,
                      ),
              ),
            ],
            if (paidAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '송금 확인 ${formatDateTime(paidAt)}',
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
